import math
import otel.metric_number as number
import otel.metric_sum as sums

def _assert_integer(number.MetricNumber actual, int64 expected):
    match actual:
        case number.MetricNumber.Int(value):
            assert value == expected
        case _:
            assert False

def _assert_double(number.MetricNumber actual, float64 expected):
    match actual:
        case number.MetricNumber.Double(value):
            assert value == expected
        case _:
            assert False

@test
def counter_sum_retains_exact_integer_values_and_zero():
    auto zero = number.MetricNumber.Int(0)
    auto high = number.MetricNumber.Int(9007199254740993)
    _assert_integer(sums.add_counter(zero, zero), 0)
    _assert_integer(sums.add_counter(zero, high), 9007199254740993)
    _assert_integer(
        sums.add_counter(high, number.MetricNumber.Int(2)),
        9007199254740995,
    )
    _assert_integer(
        sums.add_counter(
            number.MetricNumber.Int(9223372036854775806),
            number.MetricNumber.Int(1),
        ),
        9223372036854775807,
    )

@test
def counter_sum_combines_mixed_values_and_keeps_double_totals():
    auto integer = number.MetricNumber.Int(2)
    auto fractional = number.MetricNumber.Double(1.25)
    _assert_double(sums.add_counter(integer, fractional), 3.25)
    _assert_double(sums.add_counter(fractional, integer), 3.25)
    _assert_double(sums.add_counter(fractional, fractional), 2.5)
    _assert_double(sums.add_counter(integer, number.MetricNumber.Double(-0.0)), 2.0)

@test
def counter_sum_rejects_negative_or_nonfinite_values():
    auto zero = number.MetricNumber.Int(0)
    for invalid in [number.MetricNumber.Int(-1), number.MetricNumber.Double(-0.25), number.MetricNumber.Double(math.nan), number.MetricNumber.Double(math.inf), number.MetricNumber.Double(-math.inf)]:
        with expect_raises(ValueError):
            sums.add_counter(zero, invalid)
        with expect_raises(ValueError):
            sums.add_counter(invalid, zero)

@test
def counter_sum_reports_integer_and_double_overflow():
    auto maximum = number.MetricNumber.Int(9223372036854775807)
    with expect_raises(ValueError):
        sums.add_counter(maximum, number.MetricNumber.Int(1))
    auto huge = number.MetricNumber.Double(1.0e308)
    with expect_raises(ValueError):
        sums.add_counter(huge, huge)
