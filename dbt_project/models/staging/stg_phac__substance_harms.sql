/*
    Staging model: PHAC Opioid- and Stimulant-related Harms

    Cleans and standardizes the PHAC Health Infobase substance harms data.
    Filters to: overall numbers (no demographic breakdowns), crude rates,
    annual data only. Maps region names to standard 2-letter province codes.

    Terminology note: Uses "apparent opioid toxicity death" per PHAC/Yukon
    Coroner convention — not "overdose".
*/

with source as (
    select * from {{ source('raw', 'phac_substance_harms') }}
),

-- Filter to core analytical rows: overall numbers, crude rate, annual
filtered as (
    select *
    from source
    where trim(specific_measure) = 'Overall numbers'
      and trim(unit) = 'Crude rate'
      and trim(time_period) = 'By year'
      -- Exclude sub-provincial regions (Whitehorse, Winnipeg, etc.)
      and trim(region) not in (
          'Whitehorse, Yukon',
          'Yellowknife, Northwest Territories',
          'Northern and rural Manitoba',
          'Winnipeg, Manitoba',
          'Territories'
      )
),

cleaned as (
    select
        trim(substance) as substance,
        trim(source) as harm_type,

        -- Standardize harm type names
        case trim(source)
            when 'Deaths' then 'Apparent Toxicity Deaths'
            when 'Emergency Department (ED) Visits' then 'ED Visits'
            when 'Hospitalizations' then 'Hospitalizations'
            when 'Emergency Medical Services (EMS)' then 'EMS Responses'
        end as harm_type_label,

        trim(region) as region_name,

        -- Map region names to standard 2-letter codes
        case trim(region)
            when 'Canada' then 'CA'
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
            else null
        end as prov_code,

        -- Extract year from year_quarter (handles "2025 (Jan to Sep)" partial years)
        cast(left(trim(year_quarter), 4) as integer) as ref_year,

        -- Flag partial-year data
        case
            when trim(year_quarter) like '%(%)%' then true
            else false
        end as is_partial_year,

        trim(year_quarter) as year_label,

        -- Cast to numeric; handle PHAC suppression marker "Suppr."
        case
            when trim(value) in ('Suppr.', 'Suppressed', '-', '', 'N/A') or value is null then null
            else cast(value as double precision)
        end as crude_rate_per_100k,

        'calendar' as year_type  -- PHAC substance harms uses calendar years

    from filtered
)

select *
from cleaned
where prov_code is not null
  and ref_year is not null
  and crude_rate_per_100k is not null
