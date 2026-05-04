/*
    Singular test: MH readmission rate must be a valid percentage (D-2)

    Risk-adjusted 30-day readmission rate is a percentage (0–100).
    A value outside this range indicates a unit error (e.g., per 100k
    value loaded into a % column) or a calculation bug.

    Returns rows (fails) if any MH readmission rate is outside [0, 100].
*/

select
    prov_code,
    fiscal_year,
    mh_readmission_rate,
    'MH readmission rate outside valid percentage range [0, 100]' as failure_reason
from {{ ref('mart_dashboard__yukon_overview') }}
where mh_readmission_rate is not null
  and (mh_readmission_rate < 0 or mh_readmission_rate > 100)
