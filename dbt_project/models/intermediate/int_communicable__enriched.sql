/*
    Intermediate: Communicable Disease Enriched

    Enriches CNDSS staging data with:
    - Year-over-year changes
    - 5-year central moving average and standard deviation
    - Outbreak signal detection (rate > mean + 2×SD)
    - Outbreak z-score (how many SDs above normal)
    - National benchmark comparison
    - Disease burden ranking within year
    - Suppression flag

    National data (CA) spans 2000-2023 with continuous time series.
    Provincial data has snapshots for 2019, 2021, 2023 only.
*/

with staged as (
    select * from {{ ref('stg_phac__cndss') }}
),

-- Separate national and provincial
national as (
    select * from staged where prov_code = 'CA'
),

provincial as (
    select * from staged where prov_code != 'CA'
),

-- ══════════════════════════════════════════════════════════
-- National enrichment: full time series analytics
-- ══════════════════════════════════════════════════════════
national_enriched as (
    select
        n.disease,
        n.ref_year,
        n.prov_code,
        n.region_name,
        n.total_cases,
        n.rate_per_100k,
        n.data_source,
        n.year_type,

        -- Year-over-year change
        lag(n.rate_per_100k) over (
            partition by n.disease
            order by n.ref_year
        ) as prev_year_rate,

        n.rate_per_100k - lag(n.rate_per_100k) over (
            partition by n.disease
            order by n.ref_year
        ) as yoy_change,

        round((
            ((n.rate_per_100k - lag(n.rate_per_100k) over (
                partition by n.disease
                order by n.ref_year
            )) / nullif(lag(n.rate_per_100k) over (
                partition by n.disease
                order by n.ref_year
            ), 0)) * 100
        )::numeric, 1) as yoy_pct_change,

        -- 5-year central moving average (matches Yukon HSR methodology)
        round((avg(n.rate_per_100k) over (
            partition by n.disease
            order by n.ref_year
            rows between 2 preceding and 2 following
        ))::numeric, 2) as rolling_avg_5yr_central,

        -- 5-year central standard deviation (for outbreak detection)
        stddev_pop(n.rate_per_100k) over (
            partition by n.disease
            order by n.ref_year
            rows between 2 preceding and 2 following
        ) as rolling_stddev_5yr,

        -- Outbreak signal: rate > (5yr_mean + 2 × 5yr_stddev)
        case when {{ outbreak_signal('n.rate_per_100k', ['n.disease'], 'n.ref_year', 5, 2) }}
            then true else false
        end as is_outbreak_signal,

        -- Outbreak z-score: how many SDs above the rolling mean
        case
            when stddev_pop(n.rate_per_100k) over (
                partition by n.disease
                order by n.ref_year
                rows between 2 preceding and 2 following
            ) > 0
            then round((
                (n.rate_per_100k - avg(n.rate_per_100k) over (
                    partition by n.disease
                    order by n.ref_year
                    rows between 2 preceding and 2 following
                )) / stddev_pop(n.rate_per_100k) over (
                    partition by n.disease
                    order by n.ref_year
                    rows between 2 preceding and 2 following
                ))::numeric, 2)
            else 0
        end as outbreak_z_score,

        -- Disease burden rank within year (highest rate = 1 = most cases)
        rank() over (
            partition by n.ref_year
            order by n.rate_per_100k desc
        ) as disease_rank_by_rate,

        -- Suppression flag
        case
            when n.total_cases is not null and n.total_cases < 5 then true
            when n.rate_per_100k is null then true
            else false
        end as is_suppressed

    from national n
),

-- ══════════════════════════════════════════════════════════
-- Provincial enrichment: snapshot comparison to national
-- ══════════════════════════════════════════════════════════
provincial_enriched as (
    select
        p.disease,
        p.ref_year,
        p.prov_code,
        p.region_name,
        p.total_cases,
        p.rate_per_100k,
        p.data_source,
        p.year_type,

        -- No YoY for provincial (sparse snapshots)
        null::double precision as prev_year_rate,
        null::double precision as yoy_change,
        null::double precision as yoy_pct_change,
        null::double precision as rolling_avg_5yr_central,
        null::double precision as rolling_stddev_5yr,
        false as is_outbreak_signal,
        null::double precision as outbreak_z_score,

        -- Provincial rank within same year and disease
        rank() over (
            partition by p.disease, p.ref_year
            order by p.rate_per_100k desc
        ) as disease_rank_by_rate,

        -- Suppression
        case
            when p.total_cases is not null and p.total_cases < 5 then true
            when p.rate_per_100k is null then true
            else false
        end as is_suppressed

    from provincial p
),

-- ══════════════════════════════════════════════════════════
-- Union and add national benchmark for provincial rows
-- ══════════════════════════════════════════════════════════
all_rows as (
    select * from national_enriched
    union all
    select * from provincial_enriched
),

with_national_benchmark as (
    select
        a.*,

        -- National rate for same disease/year (for provincial comparison)
        n.rate_per_100k as national_rate,

        -- Gap to national
        case
            when a.prov_code != 'CA' and n.rate_per_100k is not null
            then round((a.rate_per_100k - n.rate_per_100k)::numeric, 2)
            else null
        end as gap_to_national,

        -- Province-to-national ratio
        case
            when a.prov_code != 'CA' and n.rate_per_100k is not null and n.rate_per_100k > 0
            then round((a.rate_per_100k / n.rate_per_100k)::numeric, 2)
            else null
        end as prov_vs_national_ratio,

        -- National outbreak status for this disease/year
        n.is_outbreak_signal as national_outbreak_active

    from all_rows a
    left join national_enriched n
        on a.disease = n.disease
        and a.ref_year = n.ref_year
        and n.prov_code = 'CA'
)

select * from with_national_benchmark
