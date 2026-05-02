/*
    Intermediate: Mental Health Readmissions — Enriched

    Joins CIHI mental health readmission data with StatsCan population.
    Calculates year-over-year changes, gap to national average,
    3-year rolling average, and provincial ranking.

    Note: Mental health uses risk-adjusted rate (%) not per-100k rate.
*/

with mh as (
    select * from {{ ref('stg_cihi__mental_health_readmissions') }}
),

pop as (
    select * from {{ ref('stg_statscan__population') }}
),

-- Separate provincial and national rows
provincial as (
    select
        mh.prov_code,
        mh.province_name,
        mh.fiscal_year,
        mh.fiscal_year_label,
        mh.indicator_name,
        mh.risk_adjusted_rate,
        mh.ci_lower,
        mh.ci_upper,
        mh.numerator,
        mh.denominator,
        mh.crude_rate,
        pop.population as statscan_population
    from mh
    left join pop
        on mh.prov_code = pop.prov_code
        and mh.fiscal_year = pop.ref_year
    where mh.reporting_level = 'Province/territory'
),

national as (
    select
        fiscal_year,
        risk_adjusted_rate as national_rate
    from mh
    where prov_code = 'CA'
),

-- Join provincial with national benchmark
with_national as (
    select
        p.*,
        n.national_rate,
        p.risk_adjusted_rate - n.national_rate as gap_to_national
    from provincial p
    left join national n on p.fiscal_year = n.fiscal_year
),

-- Add year-over-year and rolling calculations
with_analytics as (
    select
        *,
        risk_adjusted_rate - lag(risk_adjusted_rate) over (
            partition by prov_code order by fiscal_year
        ) as yoy_change,

        case
            when lag(risk_adjusted_rate) over (partition by prov_code order by fiscal_year) > 0
            then ((risk_adjusted_rate - lag(risk_adjusted_rate) over (
                partition by prov_code order by fiscal_year
            )) / lag(risk_adjusted_rate) over (
                partition by prov_code order by fiscal_year
            )) * 100
            else null
        end as yoy_pct_change,

        avg(risk_adjusted_rate) over (
            partition by prov_code
            order by fiscal_year
            rows between 2 preceding and current row
        ) as rolling_avg_3yr,

        -- Rank: highest readmission rate = rank 1 (worst)
        rank() over (
            partition by fiscal_year
            order by risk_adjusted_rate desc
        ) as rate_rank_desc

    from with_national
)

select * from with_analytics
order by fiscal_year, prov_code
