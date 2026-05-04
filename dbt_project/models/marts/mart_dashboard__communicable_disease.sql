/*
    Mart: Communicable Disease Surveillance Dashboard

    Dashboard-ready table for communicable disease monitoring.
    Combines national time series (2000-2023) with provincial
    snapshots (2019, 2021, 2023) for chlamydia, gonorrhea, and
    infectious syphilis.

    Key features:
    - Outbreak detection via statistical alarm (mean + 2×SD)
    - National trend with rolling averages
    - Provincial comparison with Yukon highlight
    - Disease burden ranking
*/

with enriched as (
    select * from {{ ref('int_communicable__enriched') }}
),

dashboard_rows as (
    select
        disease,
        ref_year,
        prov_code,
        region_name,
        total_cases,
        rate_per_100k,
        data_source,
        year_type,

        -- Trend analytics (national only; null for provincial snapshots)
        yoy_change,
        yoy_pct_change,
        rolling_avg_5yr_central,
        rolling_stddev_5yr,

        -- Outbreak detection
        is_outbreak_signal,
        outbreak_z_score,
        national_outbreak_active,

        -- Benchmarking
        national_rate,
        gap_to_national,
        prov_vs_national_ratio,
        disease_rank_by_rate,

        -- Suppression
        is_suppressed,

        -- Trend direction (national rows only)
        case
            when yoy_change > 0 then 'Increasing'
            when yoy_change < 0 then 'Decreasing'
            else 'Stable'
        end as trend_direction,

        -- Outbreak severity label
        case
            when is_outbreak_signal = true and outbreak_z_score >= 3.0
                then 'Severe Outbreak'
            when is_outbreak_signal = true
                then 'Outbreak Detected'
            when outbreak_z_score is not null and outbreak_z_score >= 1.0
                then 'Elevated'
            else 'Normal Range'
        end as outbreak_status_label,

        -- Disease category grouping
        case
            when disease in ('Chlamydia', 'Gonorrhea', 'Infectious Syphilis')
                then 'Sexually Transmitted Infection'
            when disease in ('Giardiasis', 'Salmonellosis')
                then 'Enteric / Foodborne'
            else 'Other'
        end as disease_category,

        -- Yukon highlight flags
        case when prov_code = 'YT' then true else false end as is_yukon,
        case when prov_code in ('YT', 'NT', 'NU') then true else false end as is_territory,

        -- Severity vs national (for provincial rows)
        case
            when prov_vs_national_ratio >= 5.0 then 'Extreme'
            when prov_vs_national_ratio >= 2.0 then 'Crisis Level'
            when prov_vs_national_ratio >= 1.5 then 'Severely Elevated'
            when prov_vs_national_ratio >= 1.0 then 'Above National'
            when prov_vs_national_ratio < 1.0 then 'Below National'
            else null
        end as severity_vs_national

    from enriched
    where not is_suppressed
),

-- Add summary statistics per disease per region
with_stats as (
    select
        d.*,
        -- Summary stats (per disease per prov_code)
        avg(d.rate_per_100k) over (
            partition by d.prov_code, d.disease
        ) as mean_rate,
        min(d.rate_per_100k) over (
            partition by d.prov_code, d.disease
        ) as min_rate,
        max(d.rate_per_100k) over (
            partition by d.prov_code, d.disease
        ) as max_rate,
        count(*) over (
            partition by d.prov_code, d.disease
        ) as data_points,
        -- Peak year for this disease in this region
        first_value(d.ref_year) over (
            partition by d.prov_code, d.disease
            order by d.rate_per_100k desc
        ) as peak_year
    from dashboard_rows d
)

select * from with_stats
order by disease, prov_code, ref_year
