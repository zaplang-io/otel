import metric_number as number
import math

# Sum a monotonic counter series. The caller associates the series with its
# instrument and attributes and stores the result only after this succeeds.
def add_counter(
    number.MetricNumber current,
    number.MetricNumber measurement,
) -> number.MetricNumber:
    _validate_counter_value(current)
    _validate_counter_value(measurement)
    match current:
        case number.MetricNumber.Int(previous):
            match measurement:
                case number.MetricNumber.Int(value):
                    if value > 9223372036854775807 - previous:
                        raise ValueError("integer counter sum exceeds int64")
                    return number.MetricNumber.Int(previous + value)
                case number.MetricNumber.Double(value):
                    return _add_double(float64(previous), value)
        case number.MetricNumber.Double(previous):
            match measurement:
                case number.MetricNumber.Int(value):
                    return _add_double(previous, float64(value))
                case number.MetricNumber.Double(value):
                    return _add_double(previous, value)

def _add_double(float64 left, float64 right) -> number.MetricNumber:
    auto total = left + right
    if math.isinf(total):
        raise ValueError("double counter sum exceeds float64")
    return number.MetricNumber.Double(total)

def _validate_counter_value(number.MetricNumber measurement):
    match measurement:
        case number.MetricNumber.Int(value):
            if value < 0:
                raise ValueError("counter value must be nonnegative")
        case number.MetricNumber.Double(value):
            if value < 0.0 or math.isnan(value) or math.isinf(value):
                raise ValueError("counter value must be finite and nonnegative")
