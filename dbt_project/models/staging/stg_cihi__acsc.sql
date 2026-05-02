/*
    Staging model: CIHI Ambulatory Care Sensitive Conditions (ACSC)

    Cleans and standardizes the raw CIHI ACSC indicator data.
    Filters to province/territory level, maps province names to codes,
    extracts fiscal year, and casts rate columns to numeric.
*/

with source as (
    select * from {{ source('raw', 'cihi_acsc') }}
),

filtered as (
    select *
    from source
    where lower(trim(reporting_level)) in ('province/territory', 'national')
),

cleaned as (
    select
        trim(province_territory) as province_name,

        -- Map province names to standard 2-letter codes
        case trim(province_territory)
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
            when '-' then 'CA'
            else null
        end as prov_code,

        -- Extract fiscal year start from formats like '2022–2023' or '2022-2023'
        cast(left(regexp_replace(time_frame, '[^0-9]', '', 'g'), 4) as integer) as fiscal_year,

        trim(time_frame) as fiscal_year_label,
        trim(reporting_level) as reporting_level,
        trim(indicator) as indicator_name,

        -- Cast numeric columns (CIHI uses '-' for suppressed values)
        case
            when trim(age_standardized_rate) in ('-', 'Suppressed', '') or age_standardized_rate is null then null
            else cast(replace(age_standardized_rate, ',', '') as double precision)
        end as age_standardized_rate,

        case
            when trim(confidence_interval_lower_limit) in ('-', 'Suppressed', '') or confidence_interval_lower_limit is null then null
            else cast(replace(confidence_interval_lower_limit, ',', '') as double precision)
        end as ci_lower,

        case
            when trim(confidence_interval_upper_limit) in ('-', 'Suppressed', '') or confidence_interval_upper_limit is null then null
            else cast(replace(confidence_interval_upper_limit, ',', '') as double precision)
        end as ci_upper,

        case
            when trim(numerator) in ('-', 'Suppressed', '') or numerator is null then null
            else cast(replace(numerator, ',', '') as double precision)
        end as numerator,

        case
            when trim(denominator) in ('-', 'Suppressed', '') or denominator is null then null
            else cast(replace(denominator, ',', '') as double precision)
        end as denominator,

        case
            when trim(crude_rate) in ('-', 'Suppressed', '') or crude_rate is null then null
            else cast(replace(crude_rate, ',', '') as double precision)
        end as crude_rate,

        'fiscal' as year_type  -- CIHI uses fiscal years (Apr 1 – Mar 31)

    from filtered
)

select *
from cleaned
where prov_code is not null
  and fiscal_year is not null
