/*
    Intermediate model: Year-over-year change analysis

    Calculates YoY change, rolling averages, and gap-to-national
    for each province and fiscal year.
*/

with indicators as (
    select * from {{ ref('int_health__indicators_with_population') }}
    where age_standardized_rate is not null
),

-- Get national rate + CI for each year (A-2: needed for CI-based comparison)
national_rates as (
    select
        fiscal_year,
        age_standardized_rate as national_rate,
        ci_lower as national_ci_lower,
        ci_upper as national_ci_upper
    from indicators
    where prov_code = 'CA'
),

-- Calculate YoY changes and national gap
with_changes as (
    select
        i.prov_code,
        i.province_name,
        i.fiscal_year,
        i.age_standardized_rate,
        i.statscan_population,
        i.geo_level,

        -- Year-over-year change
        lag(i.age_standardized_rate) over (
            partition by i.prov_code
            order by i.fiscal_year
        ) as prev_year_rate,

        round(
            (i.age_standardized_rate - lag(i.age_standardized_rate) over (
                partition by i.prov_code order by i.fiscal_year
            ))::numeric,
            1
        ) as yoy_change,

        -- Percent change
        case
            when lag(i.age_standardized_rate) over (
                partition by i.prov_code order by i.fiscal_year
            ) > 0
            then round(
                ((i.age_standardized_rate - lag(i.age_standardized_rate) over (
                    partition by i.prov_code order by i.fiscal_year
                )) / lag(i.age_standardized_rate) over (
                    partition by i.prov_code order by i.fiscal_year
                ) * 100)::numeric,
                1
            )
            else null
        end as yoy_pct_change,

        -- 5-year central moving average (matches Yukon HSR methodology)
        round(
            avg(i.age_standardized_rate) over (
                partition by i.prov_code
                order by i.fiscal_year
                rows between 2 preceding and 2 following
            )::numeric,
            1
        ) as rolling_avg_5yr_central,

        -- Gap to national average
        n.national_rate,
        n.national_ci_lower,
        n.national_ci_upper,
        round((i.age_standardized_rate - coalesce(n.national_rate, 0))::numeric, 1) as gap_to_national,

        -- Unified suppression flag (C-6)
        i.is_suppressed,

        -- Rank among provinces for this year
        rank() over (
            partition by i.fiscal_year
            order by i.age_standardized_rate desc
        ) as rate_rank_desc

    from indicators i
    left join national_rates n
        on i.fiscal_year = n.fiscal_year
    where i.geo_level = 'province'
)

select * from with_changes
