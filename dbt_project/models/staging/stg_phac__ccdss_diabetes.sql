/*
    Staging model: PHAC CCDSS Diabetes Incidence

    Cleans and standardizes the PHAC Canadian Chronic Disease Surveillance System
    diabetes mellitus (types combined) data. Filters to valid provinces/territories,
    both sexes, total age group. Handles footnote rows, COVID-era asterisks,
    and suppressed values.
*/

with source as (
    select * from {{ source('raw', 'phac_ccdss_diabetes') }}
),

-- Filter to valid provinces/territories only (exclude footnote rows)
-- and restrict to "Both sexes" + total age group for the main rate
filtered as (
    select *
    from source
    where trim(geography) in (
        'Canada',
        'Newfoundland and Labrador', 'Prince Edward Island', 'Nova Scotia',
        'New Brunswick', 'Quebec', 'Ontario', 'Manitoba', 'Saskatchewan',
        'Alberta', 'British Columbia', 'Yukon', 'Northwest Territories', 'Nunavut'
    )
    and trim(sex) = 'Both sexes'
    and trim(age_group_type) = 'Total'
),

cleaned as (
    select
        trim(geography) as province_name,

        -- Map province names to standard 2-letter codes
        case trim(geography)
            when 'Newfoundland and Labrador' then 'NL'
            when 'Prince Edward Island' then 'PE'
            when 'Nova Scotia' then 'NS'
            when 'New Brunswick' then 'NB'
            when 'Quebec' then 'QC'
            when 'Ontario' then 'ON'
            when 'Manitoba' then 'MB'
            when 'Saskatchewan' then 'SK'
            when 'Alberta' then 'AB'
            when 'British Columbia' then 'BC'
            when 'Yukon' then 'YT'
            when 'Northwest Territories' then 'NT'
            when 'Nunavut' then 'NU'
            when 'Canada' then 'CA'
            else null
        end as prov_code,

        -- Extract fiscal year start: strip COVID asterisk and non-numeric chars
        -- Format is '20222023' or '20202021*'
        cast(
            left(
                regexp_replace(
                    replace(fiscal_year, '*', ''),
                    '[^0-9]', '', 'g'
                ),
                4
            ) as integer
        ) as fiscal_year,

        -- Keep original label (with asterisk for COVID years)
        trim(fiscal_year) as fiscal_year_label,

        'Diabetes Incidence' as indicator_name,

        -- Already numeric from source — just pass through
        rate_per_100000 as age_standardized_rate,
        lower_95pct_ci as ci_lower,
        upper_95pct_ci as ci_upper,
        standard_error,
        case_counts,
        population as phac_population,

        'calendar' as year_type  -- PHAC CCDSS uses calendar years (Jan–Dec)

    from filtered
)

select *
from cleaned
where prov_code is not null
  and fiscal_year is not null
  and age_standardized_rate is not null
