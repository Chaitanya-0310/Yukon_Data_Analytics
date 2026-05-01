/*
    Staging model: Statistics Canada Population Estimates

    Standardizes province names to 2-letter codes, extracts year
    from REF_DATE, and cleans population values.
    Source: Table 17-10-0005-01
*/

with source as (
    select * from {{ source('raw', 'statscan_population') }}
),

cleaned as (
    select
        trim(geo) as province_name,

        case trim(geo)
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

        -- Extract year from REF_DATE (format: '2019-01-01' or '2019')
        cast(left(ref_date, 4) as integer) as ref_year,

        cast(value as double precision) as population

    from source
    where value is not null
)

select *
from cleaned
where prov_code is not null
  and ref_year >= 2000
