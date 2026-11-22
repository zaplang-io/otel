import otel.metric_number as metric_number

@test
def metric_number_preserves_integers_beyond_double_precision():
    auto number = metric_number.MetricNumber.Int(9007199254740993)
    match number:
        case metric_number.MetricNumber.Int(value):
            assert value == 9007199254740993
        case _:
            assert False

@test
def metric_number_preserves_fractional_measurements():
    auto number = metric_number.MetricNumber.Double(-0.125)
    match number:
        case metric_number.MetricNumber.Double(value):
            assert value == -0.125
        case _:
            assert False
