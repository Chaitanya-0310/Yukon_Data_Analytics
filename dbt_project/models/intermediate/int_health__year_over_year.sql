/*
    Intermediate model: Year-over-year change analysis

    Calculates YoY change, rolling averages, and gap-to-national
    for each province and fiscal year.
*/

with indicators as (
    select * from {{ ref('int_health__indicators_with_population') }}
    where age_standardized_rate is not null
),

-- Get national rate for each year
national_rates as (
    select
        fiscal_year,
        age_standardized_rate as national_rate
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

        -- 3-year rolling average
        round(
            avg(i.age_standardized_rate) over (
                partition by i.prov_code
                order by i.fiscal_year
                rows between 2 preceding and current row
            )::numeric,
            1
        ) as rolling_avg_3yr,

        -- Gap to national average
        n.national_rate,
        round((i.age_standardized_rate - coalesce(n.national_rate, 0))::numeric, 1) as gap_to_national,

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
