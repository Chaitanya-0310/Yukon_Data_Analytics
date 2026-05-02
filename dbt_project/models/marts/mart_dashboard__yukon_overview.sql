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
        a.rolling_avg_5yr_central as acsc_rolling_avg_5yr,
        a.rate_rank_desc as acsc_national_rank,
        a.is_suppressed as acsc_is_suppressed,

        case
            when a.yoy_change > 0 then 'Increasing'
            when a.yoy_change < 0 then 'Decreasing'
            else 'Stable'
        end as acsc_trend_direction,

        -- CI-based national comparison (A-2: replaces hardcoded ±50 threshold)
        case
            when a.age_standardized_rate > a.national_ci_upper then 'Significantly Above National'
            when a.age_standardized_rate > a.national_rate      then 'Above National'
            when a.age_standardized_rate < a.national_ci_lower  then 'Significantly Below National'
            when a.age_standardized_rate < a.national_rate      then 'Below National'
            else 'At National Rate'
        end as acsc_national_comparison,

        -- Mental Health Readmissions indicator
        m.risk_adjusted_rate as mh_readmission_rate,
        m.national_rate as mh_national_rate,
        m.gap_to_national as mh_gap_to_national,
        m.yoy_change as mh_yoy_change,
        m.yoy_pct_change as mh_yoy_pct_change,
        m.rolling_avg_5yr_central as mh_rolling_avg_5yr,
        m.rate_rank_desc as mh_national_rank,
        m.is_suppressed as mh_is_suppressed,

        case
            when m.yoy_change > 0 then 'Increasing'
            when m.yoy_change < 0 then 'Decreasing'
            else 'Stable'
        end as mh_trend_direction,

        -- CI-based national comparison for MH
        case
            when m.risk_adjusted_rate > m.national_ci_upper then 'Significantly Above National'
            when m.risk_adjusted_rate > m.national_rate      then 'Above National'
            when m.risk_adjusted_rate < m.national_ci_lower  then 'Significantly Below National'
            when m.risk_adjusted_rate < m.national_rate      then 'Below National'
            else 'At National Rate'
        end as mh_national_comparison,

        -- Diabetes Incidence indicator
        d.age_standardized_rate as diabetes_incidence_rate,
        d.national_rate as diabetes_national_rate,
        d.gap_to_national as diabetes_gap_to_national,
        d.yoy_change as diabetes_yoy_change,
        d.yoy_pct_change as diabetes_yoy_pct_change,
        d.rolling_avg_5yr_central as diabetes_rolling_avg_5yr,
        d.rate_rank_desc as diabetes_national_rank,
        d.is_suppressed as diabetes_is_suppressed,

        case
            when d.yoy_change > 0 then 'Increasing'
            when d.yoy_change < 0 then 'Decreasing'
            else 'Stable'
        end as diabetes_trend_direction,

        -- CI-based national comparison for Diabetes
        case
            when d.age_standardized_rate > d.national_ci_upper then 'Significantly Above National'
            when d.age_standardized_rate > d.national_rate      then 'Above National'
            when d.age_standardized_rate < d.national_ci_lower  then 'Significantly Below National'
            when d.age_standardized_rate < d.national_rate      then 'Below National'
            else 'At National Rate'
        end as diabetes_national_comparison,

        -- Population
        a.statscan_population as population,

        -- A-4: Flag that CIHI (fiscal) and PHAC (calendar) years are mixed
        true as cross_year_type_join_flag

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
