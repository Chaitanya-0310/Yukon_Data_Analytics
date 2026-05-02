/*
    Staging model: CIHI 30-Day Readmission for Mental Health and Substance Use

    Cleans and standardizes the raw CIHI mental health readmissions data.
    Filters to province/territory and national level with overall rates only
    (excludes age/sex/urban breakdowns). Maps province names to codes,
    extracts fiscal year, and casts rate columns to numeric.
*/

with source as (
    select * from {{ source('raw', 'cihi_mental_health_readmissions') }}
),

-- Filter to province/territory + national, overall rates only (no demographic breakdowns)
filtered as (
    select *
    from source
    where lower(trim(reporting_level)) in ('province/territory', 'national')
      and trim(level_1_breakdown) = 'Not applicable'
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
            when 'N/A' then 'CA'  -- National rows use 'N/A' for province
            else null
        end as prov_code,

        -- Extract fiscal year start from formats like '2022–2023' or '2022-2023'
        cast(left(regexp_replace(time_frame, '[^0-9]', '', 'g'), 4) as integer) as fiscal_year,

        trim(time_frame) as fiscal_year_label,
        trim(reporting_level) as reporting_level,
        trim(indicator) as indicator_name,

        -- Risk-adjusted rate (percentage, not per 100k)
        case
            when trim(risk_adjusted_rate) in ('-', '–', 'Suppressed', '') or risk_adjusted_rate is null then null
            else cast(replace(risk_adjusted_rate, ',', '') as double precision)
        end as risk_adjusted_rate,

        -- Confidence intervals
        case
            when trim("risk_adjusted_rate:_confidence_interval_lower_limit") in ('-', '–', 'Suppressed', '')
                 or "risk_adjusted_rate:_confidence_interval_lower_limit" is null then null
            else cast(replace("risk_adjusted_rate:_confidence_interval_lower_limit", ',', '') as double precision)
        end as ci_lower,

        case
            when trim("risk_adjusted_rate:_confidence_interval_upper_limit") in ('-', '–', 'Suppressed', '')
                 or "risk_adjusted_rate:_confidence_interval_upper_limit" is null then null
            else cast(replace("risk_adjusted_rate:_confidence_interval_upper_limit", ',', '') as double precision)
        end as ci_upper,

        -- Numerator and denominator
        case
            when trim(numerator) in ('-', '–', 'Suppressed', '') or numerator is null then null
            else cast(replace(numerator, ',', '') as double precision)
        end as numerator,

        case
            when trim(denominator) in ('-', '–', 'Suppressed', '') or denominator is null then null
            else cast(replace(denominator, ',', '') as double precision)
        end as denominator,

        -- Crude rate
        case
            when trim(crude_rate) in ('-', '–', 'Suppressed', '') or crude_rate is null then null
            else cast(replace(crude_rate, ',', '') as double precision)
        end as crude_rate,

        'fiscal' as year_type  -- CIHI uses fiscal years (Apr 1 – Mar 31)

    from filtered
)

select *
from cleaned
where prov_code is not null
  and fiscal_year is not null
