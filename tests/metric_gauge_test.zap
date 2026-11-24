import math
import otel.attributes as attr
import otel.metric_number as number
import otel.metrics as metrics

def _observe_temperature(metrics.CallbackOptions options) -> list[metrics.Observation]:
    assert options.timeout_millis == 125.0
    return [
        metrics.Observation(
            number.MetricNumber.Double(20.5),
            {
                "room": attr.AttributeValue.Str("office"),
                "floor": attr.AttributeValue.Int(2),
            },
        ),
        metrics.Observation(
            number.MetricNumber.Double(21.5),
            {
                "floor": attr.AttributeValue.Int(2),
                "room": attr.AttributeValue.Str("office"),
            },
        ),
        metrics.Observation(
            number.MetricNumber.Double(-2.0),
            {"room": attr.AttributeValue.Str("outside")},
        ),
    ]

def _observe_invalid(metrics.CallbackOptions options) -> list[metrics.Observation]:
    return [
        metrics.Observation(number.MetricNumber.Double(math.nan)),
        metrics.Observation(number.MetricNumber.Double(math.inf)),
        metrics.Observation(number.MetricNumber.Double(-math.inf)),
    ]

def _raise_from_callback(metrics.CallbackOptions options) -> list[metrics.Observation]:
    raise ValueError("gauge observation failed")

def _observe_count(metrics.CallbackOptions options) -> list[metrics.Observation]:
    return [metrics.Observation(number.MetricNumber.Int(9007199254740993))]

def _double_value(number.MetricNumber measurement) -> float64:
    match measurement:
        case number.MetricNumber.Double(value):
            return value
        case _:
            raise ValueError("expected a double gauge reading")

@test
def gauge_collection_uses_last_observation_per_attribute_set():
    auto provider = metrics.MeterProvider()
    auto meter = provider.get_meter("building")
    auto reader = metrics.InMemoryMetricReader(provider)
    list[fn(metrics.CallbackOptions) -> list[metrics.Observation]] callbacks = [
        _observe_temperature,
    ]
    auto gauge = meter.create_observable_gauge(
        "temperature",
        callbacks=callbacks,
        unit="Cel",
        description="Room temperature",
    )
    assert gauge is meter.create_observable_gauge("Temperature", unit="Cel", description="Room temperature")
    callbacks.append(_raise_from_callback)
    auto data = reader.get_metrics_data(timeout_millis=125.0)
    assert len(data.gauges) == 2
    assert data.gauges[0].name == "temperature"
    assert data.gauges[0].meter_name == "building"
    assert data.gauges[0].unit == "Cel"
    assert data.gauges[0].description == "Room temperature"
    assert _double_value(data.gauges[0].value) == 21.5
    assert _double_value(data.gauges[1].value) == -2.0
    data.gauges[0].attributes["room"] = attr.AttributeValue.Str("external mutation")
    auto later = reader.get_metrics_data(timeout_millis=125.0)
    match later.gauges[0].attributes["room"]:
        case attr.AttributeValue.Str(value):
            assert value == "office"
        case _:
            assert False

@test
def gauge_collection_continues_after_raising_callbacks_and_discards_nonfinite_readings():
    auto provider = metrics.MeterProvider()
    auto meter = provider.get_meter("test")
    meter.create_observable_gauge("unobserved")
    list[fn(metrics.CallbackOptions) -> list[metrics.Observation]] callbacks = [
        _raise_from_callback,
        _observe_invalid,
        _observe_count,
    ]
    meter.create_observable_gauge("observed", callbacks=callbacks)
    auto reader = metrics.InMemoryMetricReader(provider)
    auto data = reader.get_metrics_data()
    assert len(data.gauges) == 1
    assert data.gauges[0].name == "observed"
    assert len(data.gauges[0].attributes) == 0
    match data.gauges[0].value:
        case number.MetricNumber.Int(value):
            assert value == 9007199254740993
        case _:
            assert False

@test
def metric_reader_rejects_invalid_collection_timeouts():
    auto reader = metrics.InMemoryMetricReader(metrics.MeterProvider())
    for timeout in [0.0, -1.0, math.nan, math.inf, -math.inf]:
        with expect_raises(ValueError):
            reader.get_metrics_data(timeout_millis=timeout)
