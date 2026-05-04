/*
    Mart: Substance Use Harms Dashboard

    Dashboard-ready table for the substance harms page.
    Focuses on Yukon, territories, and national benchmark.
    Combines opioid and stimulant data across harm types
    (deaths, ED visits, hospitalizations) with trend analysis
    and emergency period context.

    Yukon declared a Substance Use Health Emergency on Jan 20, 2022.
*/

with enriched as (
    select * from {{ ref('int_substance__enriched') }}
),

-- Focus on Yukon, territories, and national for dashboard
dashboard_rows as (
    select
        prov_code,
        region_name,
        ref_year,
        year_label,
        substance,
        harm_type,
        harm_type_label,
        crude_rate_per_100k,
        national_rate,
        gap_to_national,
        yukon_vs_canada_ratio,
        yoy_change,
        yoy_pct_change,
        rolling_avg_3yr,
        rate_rank_desc as national_rank,
        is_emergency_period,
        is_suppressed,
        statscan_population,

        -- Construct indicator label: "Opioid — Apparent Toxicity Deaths"
        substance || ' — ' || harm_type_label as indicator_label,

        -- Trend direction
        case
            when yoy_change > 0 then 'Increasing'
            when yoy_change < 0 then 'Decreasing'
            else 'Stable'
        end as trend_direction,

        -- Severity classification based on Yukon-to-Canada ratio
        case
            when yukon_vs_canada_ratio >= 2.0 then 'Crisis Level'
            when yukon_vs_canada_ratio >= 1.5 then 'Severely Elevated'
            when yukon_vs_canada_ratio >= 1.0 then 'Above National'
            when yukon_vs_canada_ratio < 1.0 then 'Below National'
            else null
        end as severity_vs_national,

        -- Pre/post emergency comparison flag
        case
            when ref_year between 2019 and 2021 then 'Pre-Emergency'
            when ref_year >= 2022 then 'Post-Emergency'
            else 'Baseline'
        end as emergency_period_label,

        'calendar' as year_type

    from enriched
),

-- Add summary stats per indicator per province
with_stats as (
    select
        d.*,
        avg(d.crude_rate_per_100k) over (
            partition by d.prov_code, d.substance, d.harm_type
        ) as mean_rate,
        min(d.crude_rate_per_100k) over (
            partition by d.prov_code, d.substance, d.harm_type
        ) as min_rate,
        max(d.crude_rate_per_100k) over (
            partition by d.prov_code, d.substance, d.harm_type
        ) as max_rate,
        count(*) over (
            partition by d.prov_code, d.substance, d.harm_type
        ) as data_points
    from dashboard_rows d
)

select * from with_stats
order by substance, harm_type, prov_code, ref_year
