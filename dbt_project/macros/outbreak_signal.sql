/*
    Macro: outbreak_signal

    Implements statistical outbreak detection used in public health surveillance.
    Returns TRUE when the current rate exceeds the central moving average plus
    a configurable number of standard deviations.

    This is a simplified version of the statistical process control (SPC)
    approach used in communicable disease surveillance systems.

    Parameters:
      - rate_col: the column containing the rate to evaluate
      - partition_cols: list of columns to partition by (e.g., ['disease'])
      - order_col: the column to order by (e.g., 'ref_year')
      - window_size: total window size for the moving average (default: 5)
      - threshold_sd: number of standard deviations above mean (default: 2)

    Usage:
      {{ outbreak_signal('rate_per_100k', ['disease'], 'ref_year', 5, 2) }}
*/

{% macro outbreak_signal(rate_col, partition_cols, order_col, window_size=5, threshold_sd=2) %}
    {{ rate_col }} > (
        avg({{ rate_col }}) over (
            partition by {{ partition_cols | join(', ') }}
            order by {{ order_col }}
            rows between {{ (window_size // 2) }} preceding
                     and {{ (window_size // 2) }} following
        )
        + {{ threshold_sd }} * stddev_pop({{ rate_col }}) over (
            partition by {{ partition_cols | join(', ') }}
            order by {{ order_col }}
            rows between {{ (window_size // 2) }} preceding
                     and {{ (window_size // 2) }} following
        )
    )
{% endmacro %}
