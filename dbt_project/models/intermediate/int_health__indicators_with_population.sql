/*
    Intermediate model: Join CIHI indicators with StatsCan population

    Links CIHI health indicators to population estimates by province + year.
    This is the core data linkage step — deterministic join on prov_code + year.
    Calculates crude rates where raw numerators are available.
*/

with acsc as (
    select * from {{ ref('stg_cihi__acsc') }}
    where lower(reporting_level) = 'province/territory'
),

national as (
    select * from {{ ref('stg_cihi__acsc') }}
    where lower(reporting_level) = 'national'
),

population as (
    select * from {{ ref('stg_statscan__population') }}
),

-- Join province-level CIHI data with population
provincial_with_pop as (
    select
        a.prov_code,
        a.province_name,
        a.fiscal_year,
        a.fiscal_year_label,
        a.indicator_name,
        a.age_standardized_rate,
        a.ci_lower,
        a.ci_upper,
        a.numerator,
        a.denominator as cihi_denominator,
        a.crude_rate,
        p.population as statscan_population,
        'province' as geo_level
    from acsc a
    left join population p
        on a.prov_code = p.prov_code
        and a.fiscal_year = p.ref_year
),

-- Add national averages for comparison
national_rates as (
    select
        'CA' as prov_code,
        'Canada' as province_name,
        n.fiscal_year,
        n.fiscal_year_label,
        n.indicator_name,
        n.age_standardized_rate,
        n.ci_lower,
        n.ci_upper,
        n.numerator,
        n.denominator as cihi_denominator,
        n.crude_rate,
        p.population as statscan_population,
        'national' as geo_level
    from national n
    left join population p
        on p.prov_code = 'CA'
        and n.fiscal_year = p.ref_year
),

combined as (
    select * from provincial_with_pop
    union all
    select * from national_rates
)

select
    *,
    -- Calculate population-adjusted rate where we have numerator
    case
        when numerator is not null and statscan_population > 0
        then round((numerator / statscan_population * 100000)::numeric, 1)
        else null
    end as calculated_rate_per_100k,

    -- Flag: is the CIHI rate available or was it suppressed?
    case
        when age_standardized_rate is not null then false
        else true
    end as rate_suppressed,

    -- Flag: did population join succeed?
    case
        when statscan_population is not null then true
        else false
    end as population_linked

from combined
