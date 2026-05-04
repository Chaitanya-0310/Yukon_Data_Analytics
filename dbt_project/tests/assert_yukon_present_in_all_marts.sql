/*
    Singular test: Assert Yukon rows are never accidentally dropped.

    This test returns rows (fails) if Yukon is missing from any mart table.
    Critical for a Yukon-focused project — a filter or join bug that drops
    YT rows would silently produce an empty dashboard.
*/

with yukon_check as (
    select 'yukon_overview' as mart, count(*) as yukon_rows
    from {{ ref('mart_dashboard__yukon_overview') }}

    union all

    select 'provincial_comparison', count(*)
    from {{ ref('mart_dashboard__provincial_comparison') }}
    where prov_code = 'YT'

    union all

    select 'trend_analysis', count(*)
    from {{ ref('mart_dashboard__trend_analysis') }}
    where series_name = 'Yukon'
)

-- Returns failing rows where Yukon has zero rows in a mart
select * from yukon_check where yukon_rows = 0
