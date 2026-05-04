/*
    Singular test: is_latest must be true for exactly one row per indicator (D-3)

    The yukon_overview mart has an is_latest flag marking the most recent
    data year. If a de-duplication bug or duplicate data load creates
    multiple "latest" rows, the dashboard KPI cards will show incorrect values.

    Returns rows (fails) if more than one row has is_latest = true.
    There should be exactly one "latest" row (one overall latest year).
*/

with latest_count as (
    select count(*) as n_latest
    from {{ ref('mart_dashboard__yukon_overview') }}
    where is_latest = true
)

select
    n_latest,
    'Expected exactly 1 is_latest=true row, found ' || n_latest::text as failure_reason
from latest_count
where n_latest != 1
