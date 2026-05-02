/*
    Mart: Trend Analysis

    Time series data optimized for the trend analysis and forecasting
    dashboard pages. Includes Yukon, territories, and national benchmarks
    for all three indicators with summary statistics.
*/

-- ACSC trends (Yukon + territories + national)
with acsc_trends as (
    select
        fiscal_year,
        age_standardized_rate as rate_value,
        ci_lower,
        ci_upper,
        statscan_population as population,
        case
            when prov_code = 'YT' then 'Yukon'
            when prov_code = 'CA' then 'Canada (National)'
            else province_name
        end as series_name,
        prov_code,
        'ACSC Hospitalizations' as indicator_name,
        'per 100,000' as rate_unit
    from {{ ref('int_health__indicators_with_population') }}
    where prov_code in ('YT', 'CA', 'NT', 'NU')
      and age_standardized_rate is not null
),

-- Mental Health trends (Yukon + territories + national)
mh_trends as (
    select
        fiscal_year,
        risk_adjusted_rate as rate_value,
        ci_lower,
        ci_upper,
        statscan_population as population,
        case
            when prov_code = 'YT' then 'Yukon'
            else province_name
        end as series_name,
        prov_code,
        'Mental Health Readmissions' as indicator_name,
        '%' as rate_unit
    from {{ ref('int_mental_health__enriched') }}
    where prov_code in ('YT', 'CA', 'NT', 'NU')
      and risk_adjusted_rate is not null
),

-- Diabetes trends (Yukon + territories + national)
diabetes_trends as (
    select
        fiscal_year,
        age_standardized_rate as rate_value,
        ci_lower,
        ci_upper,
        statscan_population as population,
        case
            when prov_code = 'YT' then 'Yukon'
            when prov_code = 'CA' then 'Canada (National)'
            else province_name
        end as series_name,
        prov_code,
        'Diabetes Incidence' as indicator_name,
        'per 100,000' as rate_unit
    from {{ ref('int_diabetes__enriched') }}
    where prov_code in ('YT', 'CA', 'NT', 'NU')
      and age_standardized_rate is not null
),

combined as (
    select * from acsc_trends
    union all
    select * from mh_trends
    union all
    select * from diabetes_trends
),

-- Add summary stats per series per indicator
with_stats as (
    select
        c.*,
        avg(c.rate_value) over (partition by c.indicator_name, c.prov_code) as mean_rate,
        min(c.rate_value) over (partition by c.indicator_name, c.prov_code) as min_rate,
        max(c.rate_value) over (partition by c.indicator_name, c.prov_code) as max_rate,
        count(*) over (partition by c.indicator_name, c.prov_code) as data_points
    from combined c
)

select * from with_stats
order by indicator_name, prov_code, fiscal_year
