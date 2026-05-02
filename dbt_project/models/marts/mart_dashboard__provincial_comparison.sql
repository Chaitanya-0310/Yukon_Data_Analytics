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
        age_standardized_rate as rate_value,
        national_rate,
        gap_to_national,
        yoy_change,
        yoy_pct_change,
        rolling_avg_3yr,
        rate_rank_desc as national_rank,
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
        risk_adjusted_rate as rate_value,
        national_rate,
        gap_to_national,
        yoy_change,
        yoy_pct_change,
        rolling_avg_3yr,
        rate_rank_desc as national_rank,
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
        age_standardized_rate as rate_value,
        national_rate,
        gap_to_national,
        yoy_change,
        yoy_pct_change,
        rolling_avg_3yr,
        rate_rank_desc as national_rank,
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

        case when c.prov_code = 'YT' then true else false end as is_yukon,
        case when c.prov_code in ('YT', 'NT', 'NU') then true else false end as is_territory

    from combined c
)

select * from with_flags
order by indicator_name, fiscal_year, national_rank
