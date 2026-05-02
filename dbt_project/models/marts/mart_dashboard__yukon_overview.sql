/*
    Mart: Yukon Overview Dashboard

    Headline KPIs and trend data for the Yukon-focused dashboard.
    Combines three indicators: ACSC, Mental Health Readmissions, and Diabetes.
    Includes current rates, national comparison, trend direction,
    and historical context for each indicator.
*/

with acsc as (
    select * from {{ ref('int_health__year_over_year') }}
    where prov_code = 'YT'
),

mh as (
    select * from {{ ref('int_mental_health__enriched') }}
    where prov_code = 'YT'
),

diabetes as (
    select * from {{ ref('int_diabetes__enriched') }}
    where prov_code = 'YT'
),

-- Build Yukon overview joining all three indicators by fiscal year
combined as (
    select
        a.prov_code,
        a.province_name,
        a.fiscal_year,

        -- ACSC indicator
        a.age_standardized_rate as acsc_rate,
        a.national_rate as acsc_national_rate,
        a.gap_to_national as acsc_gap_to_national,
        a.yoy_change as acsc_yoy_change,
        a.yoy_pct_change as acsc_yoy_pct_change,
        a.rolling_avg_3yr as acsc_rolling_avg_3yr,
        a.rate_rank_desc as acsc_national_rank,

        case
            when a.yoy_change > 0 then 'Increasing'
            when a.yoy_change < 0 then 'Decreasing'
            else 'Stable'
        end as acsc_trend_direction,

        case
            when a.gap_to_national > 50 then 'Significantly Above National'
            when a.gap_to_national > 0 then 'Above National'
            when a.gap_to_national < -50 then 'Significantly Below National'
            when a.gap_to_national < 0 then 'Below National'
            else 'At National Average'
        end as acsc_national_comparison,

        -- Mental Health Readmissions indicator
        m.risk_adjusted_rate as mh_readmission_rate,
        m.national_rate as mh_national_rate,
        m.gap_to_national as mh_gap_to_national,
        m.yoy_change as mh_yoy_change,
        m.yoy_pct_change as mh_yoy_pct_change,
        m.rolling_avg_3yr as mh_rolling_avg_3yr,
        m.rate_rank_desc as mh_national_rank,

        case
            when m.yoy_change > 0 then 'Increasing'
            when m.yoy_change < 0 then 'Decreasing'
            else 'Stable'
        end as mh_trend_direction,

        -- Diabetes Incidence indicator
        d.age_standardized_rate as diabetes_incidence_rate,
        d.national_rate as diabetes_national_rate,
        d.gap_to_national as diabetes_gap_to_national,
        d.yoy_change as diabetes_yoy_change,
        d.yoy_pct_change as diabetes_yoy_pct_change,
        d.rolling_avg_3yr as diabetes_rolling_avg_3yr,
        d.rate_rank_desc as diabetes_national_rank,

        case
            when d.yoy_change > 0 then 'Increasing'
            when d.yoy_change < 0 then 'Decreasing'
            else 'Stable'
        end as diabetes_trend_direction,

        -- Population
        a.statscan_population as population

    from acsc a
    left join mh m
        on a.fiscal_year = m.fiscal_year
    left join diabetes d
        on a.fiscal_year = d.fiscal_year
),

with_latest as (
    select
        *,
        max(fiscal_year) over () as latest_data_year,
        case
            when fiscal_year = max(fiscal_year) over () then true
            else false
        end as is_latest
    from combined
)

select * from with_latest
order by fiscal_year
