/*
    Mart: Provincial Comparison Dashboard

    All provinces/territories side-by-side for the interactive
    comparison page. Unions three indicators into a single table
    with an indicator_name column for dashboard filtering.
    Includes region grouping, rankings, and Yukon highlight flags.
*/

with acsc as (
    select
        prov_code,
        province_name,
        fiscal_year,
        'ACSC Hospitalizations' as indicator_name,
        'per 100,000' as rate_unit,
        'fiscal' as year_type,
        age_standardized_rate as rate_value,
        national_rate,
        national_ci_lower,
        national_ci_upper,
        gap_to_national,
        yoy_change,
        yoy_pct_change,
        rolling_avg_5yr_central,
        rate_rank_desc as national_rank,
        is_suppressed,
        statscan_population as population
    from {{ ref('int_health__year_over_year') }}
),

mh as (
    select
        prov_code,
        province_name,
        fiscal_year,
        'Mental Health Readmissions' as indicator_name,
        '%' as rate_unit,
        'fiscal' as year_type,
        risk_adjusted_rate as rate_value,
        national_rate,
        national_ci_lower,
        national_ci_upper,
        gap_to_national,
        yoy_change,
        yoy_pct_change,
        rolling_avg_5yr_central,
        rate_rank_desc as national_rank,
        is_suppressed,
        statscan_population as population
    from {{ ref('int_mental_health__enriched') }}
),

diabetes as (
    select
        prov_code,
        province_name,
        fiscal_year,
        'Diabetes Incidence' as indicator_name,
        'per 100,000' as rate_unit,
        'calendar' as year_type,
        age_standardized_rate as rate_value,
        national_rate,
        national_ci_lower,
        national_ci_upper,
        gap_to_national,
        yoy_change,
        yoy_pct_change,
        rolling_avg_5yr_central,
        rate_rank_desc as national_rank,
        is_suppressed,
        statscan_population as population
    from {{ ref('int_diabetes__enriched') }}
),

combined as (
    select * from acsc
    union all
    select * from mh
    union all
    select * from diabetes
),

with_flags as (
    select
        c.*,

        -- Geographic grouping for dashboard filters
        case
            when c.prov_code in ('YT', 'NT', 'NU') then 'Territories'
            when c.prov_code in ('BC', 'AB', 'SK', 'MB') then 'Western'
            when c.prov_code in ('ON', 'QC') then 'Central'
            when c.prov_code in ('NB', 'NS', 'PE', 'NL') then 'Atlantic'
            else 'National'
        end as region_group,

        -- CI-based national comparison (A-2)
        case
            when c.rate_value > c.national_ci_upper then 'Significantly Above National'
            when c.rate_value > c.national_rate      then 'Above National'
            when c.rate_value < c.national_ci_lower  then 'Significantly Below National'
            when c.rate_value < c.national_rate      then 'Below National'
            else 'At National Rate'
        end as national_comparison,

        case when c.prov_code = 'YT' then true else false end as is_yukon,
        case when c.prov_code in ('YT', 'NT', 'NU') then true else false end as is_territory

    from combined c
)

select * from with_flags
order by indicator_name, fiscal_year, national_rank
