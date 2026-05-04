/*
    Singular test: ACSC rate domain-anchored reasonableness check (D-2)

    Yukon ACSC rate has historically ranged ~350–700 per 100,000.
    Guard rails: 150 (floor) to 1000 (ceiling) flag data loading errors
    or unit mismatches before they reach the dashboard.

    Returns rows (fails) if any Yukon ACSC rate falls outside plausible range.
*/

select
    prov_code,
    fiscal_year,
    acsc_rate,
    'ACSC rate outside plausible range [150, 1000] per 100k' as failure_reason
from {{ ref('mart_dashboard__yukon_overview') }}
where prov_code = 'YT'
  and acsc_rate is not null
  and (acsc_rate < 150 or acsc_rate > 1000)
