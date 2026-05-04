/*
    Intermediate: Substance Use Harms — Enriched

    Enriches PHAC substance harms data with year-over-year changes,
    rolling averages, Yukon-vs-Canada ratio, and emergency period flag.
    Joins with StatsCan population for context.

    Note: Crude rates are pre-calculated by PHAC. We use them directly
    rather than recalculating from counts, as PHAC applies age adjustments
    and suppression rules at source.

    Yukon declared a Substance Use Health Emergency on January 20, 2022.
*/

with harms as (
    select * from {{ ref('stg_phac__substance_harms') }}
    where not is_partial_year  -- exclude partial years for trend analysis
),

pop as (
    select * from {{ ref('stg_statscan__population') }}
),

-- Separate provincial and national rows
provincial as (
    select
        h.prov_code,
        h.region_name,
        h.ref_year,
        h.year_label,
        h.substance,
        h.harm_type,
        h.harm_type_label,
        h.crude_rate_per_100k,
        h.is_partial_year,
        p.population as statscan_population
    from harms h
    left join pop p
        on h.prov_code = p.prov_code
        and h.ref_year = p.ref_year
    where h.prov_code != 'CA'
),

national as (
    select
        ref_year,
        substance,
        harm_type,
        crude_rate_per_100k as national_rate
    from harms
    where prov_code = 'CA'
),

-- Join provincial with national benchmark
with_national as (
    select
        p.*,
        n.national_rate,
        p.crude_rate_per_100k - n.national_rate as gap_to_national,

        -- Yukon-to-Canada ratio (>1.0 = Yukon worse than national)
        case
            when n.national_rate > 0
            then round((p.crude_rate_per_100k / n.national_rate)::numeric, 2)
            else null
        end as yukon_vs_canada_ratio
    from provincial p
    left join national n
        on p.ref_year = n.ref_year
        and p.substance = n.substance
        and p.harm_type = n.harm_type
),

-- Add year-over-year and rolling calculations
with_analytics as (
    select
        *,

        -- Year-over-year change
        crude_rate_per_100k - lag(crude_rate_per_100k) over (
            partition by prov_code, substance, harm_type
            order by ref_year
        ) as yoy_change,

        -- Year-over-year % change
        case
            when lag(crude_rate_per_100k) over (
                partition by prov_code, substance, harm_type order by ref_year
            ) > 0
            then round(((crude_rate_per_100k - lag(crude_rate_per_100k) over (
                partition by prov_code, substance, harm_type order by ref_year
            )) / lag(crude_rate_per_100k) over (
                partition by prov_code, substance, harm_type order by ref_year
            ) * 100)::numeric, 1)
            else null
        end as yoy_pct_change,

        -- 3-year rolling average (trailing — only ~9 years of data, central would lose edges)
        round(avg(crude_rate_per_100k) over (
            partition by prov_code, substance, harm_type
            order by ref_year
            rows between 2 preceding and current row
        )::numeric, 1) as rolling_avg_3yr,

        -- Provincial rank (highest rate = rank 1 = worst)
        rank() over (
            partition by ref_year, substance, harm_type
            order by crude_rate_per_100k desc
        ) as rate_rank_desc,

        -- Yukon Substance Use Health Emergency flag (declared Jan 20, 2022)
        case
            when ref_year >= 2022 then true
            else false
        end as is_emergency_period,

        -- Suppression: PHAC suppresses when deaths < 5
        case
            when crude_rate_per_100k is null then true
            else false
        end as is_suppressed

    from with_national
)

select * from with_analytics
order by substance, harm_type, ref_year, prov_code
