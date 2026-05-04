/*
    Singular test: Substance harm rates must be non-negative (D-2)

    Crude rates per 100,000 cannot be negative. A negative value indicates
    a calculation error (e.g., subtraction applied to a rate column) or
    a sign convention error in the source data loading step.

    Returns rows (fails) if any substance harm rate is negative.
*/

select
    prov_code,
    ref_year,
    substance,
    harm_type_label,
    crude_rate_per_100k,
    'Substance harm rate is negative — calculation or loading error' as failure_reason
from {{ ref('mart_dashboard__substance_harms') }}
where crude_rate_per_100k < 0
