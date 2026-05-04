/*
    Staging model: PHAC Canadian Notifiable Disease Surveillance System (CNDSS)

    Combines two source tables:
    1. National time series (1991-2023): Male + Female aggregated to total
    2. Provincial snapshots (2019, 2021, 2023): Already total rates

    Diseases: Chlamydia, Gonorrhea, Infectious Syphilis, Giardiasis, Salmonellosis
    Uses calendar years (Jan–Dec).
*/

with national_raw as (
    select * from {{ source('raw', 'phac_cndss_national') }}
),

provincial_raw as (
    select * from {{ source('raw', 'phac_cndss_provincial') }}
),

-- Aggregate Male + Female counts to total for national data
-- Then recalculate combined rate using StatsCan national population
national_combined as (
    select
        year as ref_year,
        trim(disease) as disease,
        sum(number_of_reported_cases) as total_cases,
        -- We'll join population separately; for now use weighted average of rates
        -- Male rate × male_share + Female rate × female_share ≈ total rate
        -- But simpler: sum cases is exact; we'll calculate rate from population join
        count(*) as sex_count
    from national_raw
    where trim(age_group) = 'All'
    group by year, trim(disease)
),

-- Join with StatsCan national population for combined rate calculation
national_with_pop as (
    select
        n.ref_year,
        n.disease,
        n.total_cases,

        -- Standardize disease names to match provincial data
        case n.disease
            when 'Syphilis' then 'Infectious Syphilis'
            else n.disease
        end as disease_standard,

        p.population as statscan_population,
        round(((n.total_cases::double precision / nullif(p.population, 0)) * 100000)::numeric, 2) as rate_per_100k,
        'CA' as prov_code,
        'Canada' as region_name,
        'national_time_series' as data_source

    from national_combined n
    left join {{ ref('stg_statscan__population') }} p
        on n.ref_year = p.ref_year
        and p.prov_code = 'CA'
    where n.ref_year >= 2000  -- Focus on 2000+ for analytical relevance
),

-- Provincial data already has rates calculated by PHAC
provincial_cleaned as (
    select
        cast(year as integer) as ref_year,
        trim(disease) as disease_standard,
        cast(cases as double precision) as total_cases,
        cast(rate_per_100k as double precision) as rate_per_100k,
        trim(prov_code) as prov_code,
        trim(region) as region_name,
        'provincial_snapshot' as data_source
    from provincial_raw
    where rate_per_100k is not null
      and trim(prov_code) != ''
),

-- Union both sources, preferring provincial data when both exist
-- (provincial data has PHAC-calculated rates which are authoritative)
combined as (
    -- National time series (excludes years where provincial data exists for CA)
    select
        ref_year,
        disease_standard as disease,
        total_cases,
        rate_per_100k,
        prov_code,
        region_name,
        data_source,
        'calendar' as year_type
    from national_with_pop
    where rate_per_100k is not null

    union all

    -- Provincial data (includes CA national rows from reports)
    select
        ref_year,
        disease_standard as disease,
        total_cases,
        rate_per_100k,
        prov_code,
        region_name,
        data_source,
        'calendar' as year_type
    from provincial_cleaned
    where prov_code != 'CA'  -- Avoid duplicate CA rows; national series covers these
),

-- Deduplicate: keep one row per (disease, ref_year, prov_code)
-- Priority: provincial_snapshot over national_time_series
deduplicated as (
    select
        *,
        row_number() over (
            partition by disease, ref_year, prov_code
            order by
                case data_source
                    when 'provincial_snapshot' then 1
                    else 2
                end
        ) as rn
    from combined
)

select
    disease,
    ref_year,
    prov_code,
    region_name,
    total_cases,
    rate_per_100k,
    data_source,
    year_type
from deduplicated
where rn = 1
  and ref_year is not null
  and rate_per_100k is not null
