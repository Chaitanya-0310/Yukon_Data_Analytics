/*
    Intermediate: Diabetes Incidence — Enriched

    Enriches PHAC CCDSS diabetes data with StatsCan population,
    year-over-year changes, gap to national average,
    3-year rolling average, and provincial ranking.

    Note: Uses PHAC's own population column for case counts context,
    but links StatsCan population for consistency with other indicators.
*/

with diabetes as (
    select * from {{ ref('stg_phac__ccdss_diabetes') }}
),

pop as (
    select * from {{ ref('stg_statscan__population') }}
),

-- Separate provincial and national rows
provincial as (
    select
        d.prov_code,
        d.province_name,
        d.fiscal_year,
        d.fiscal_year_label,
        d.indicator_name,
        d.age_standardized_rate,
        d.ci_lower,
        d.ci_upper,
        d.case_counts,
        d.phac_population,
        pop.population as statscan_population
    from diabetes d
    left join pop
        on d.prov_code = pop.prov_code
        and d.fiscal_year = pop.ref_year
    where d.prov_code != 'CA'
),

national as (
    select
        fiscal_year,
        age_standardized_rate as national_rate,
        ci_lower as national_ci_lower,
        ci_upper as national_ci_upper
    from diabetes
    where prov_code = 'CA'
),

-- Join provincial with national benchmark
with_national as (
    select
        p.*,
        n.national_rate,
        n.national_ci_lower,
        n.national_ci_upper,
        p.age_standardized_rate - n.national_rate as gap_to_national
    from provincial p
    left join national n on p.fiscal_year = n.fiscal_year
),

-- Add year-over-year and rolling calculations
with_analytics as (
    select
        *,
        age_standardized_rate - lag(age_standardized_rate) over (
            partition by prov_code order by fiscal_year
        ) as yoy_change,

        case
            when lag(age_standardized_rate) over (partition by prov_code order by fiscal_year) > 0
            then ((age_standardized_rate - lag(age_standardized_rate) over (
                partition by prov_code order by fiscal_year
            )) / lag(age_standardized_rate) over (
                partition by prov_code order by fiscal_year
            )) * 100
            else null
        end as yoy_pct_change,

        avg(age_standardized_rate) over (
            partition by prov_code
            order by fiscal_year
            rows between 2 preceding and 2 following
        ) as rolling_avg_5yr_central,

        -- Rank: highest incidence = rank 1 (worst)
        rank() over (
            partition by fiscal_year
            order by age_standardized_rate desc
        ) as rate_rank_desc,

        -- Unified suppression flag (C-6)
        case
            when age_standardized_rate is null then true
            when case_counts is not null and case_counts < 10 then true  -- PHAC threshold is <10
            else false
        end as is_suppressed

    from with_national
)

select * from with_analytics
order by fiscal_year, prov_code
