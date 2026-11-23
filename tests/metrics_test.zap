import math
import otel.attributes as attr
import otel.metric_number as number
import otel.metrics as metrics
import otel.resource as resource

def _int_value(number.MetricNumber measurement) -> int64:
    match measurement:
        case number.MetricNumber.Int(value):
            return value
        case _:
            raise ValueError("expected an integer measurement")

def _double_value(number.MetricNumber measurement) -> float64:
    match measurement:
        case number.MetricNumber.Double(value):
            return value
        case _:
            raise ValueError("expected a double measurement")

@test
def meters_are_named_and_counters_reuse_the_registered_instrument():
    auto provider = metrics.MeterProvider()
    auto meter = provider.get_meter("inventory")
    assert meter is provider.get_meter("inventory")
    assert meter is not provider.get_meter("Inventory")
    assert meter.name() == "inventory"
    auto counter = meter.create_counter(
        "Items.Added",
        unit="{item}",
        description="Inventory additions",
    )
    auto alias = meter.create_counter(
        "items.added",
        unit="{item}",
        description="Inventory additions",
    )
    assert alias is counter
    auto different = meter.create_counter(
        "items.added",
        unit="{crate}",
        description="Inventory additions",
    )
    assert counter is not different
    assert metrics.get_meter("default") is metrics.get_meter_provider().get_meter("default")

@test
def native_reader_collects_cumulative_counter_values_and_independent_snapshots():
    auto custom = resource.create(
        {"service.name": attr.AttributeValue.Str("warehouse")},
    )
    auto provider = metrics.MeterProvider(custom)
    auto reader = metrics.InMemoryMetricReader(provider)
    auto counter = provider.get_meter("inventory").create_counter(
        "items.added",
        unit="{item}",
        description="Inventory additions",
    )
    assert len(reader.get_metrics_data().counters) == 0
    counter.add(number.MetricNumber.Int(9007199254740993))
    auto first = reader.get_metrics_data()
    assert len(first.counters) == 1
    assert first.counters[0].meter_name == "inventory"
    assert first.counters[0].name == "items.added"
    assert first.counters[0].unit == "{item}"
    assert first.counters[0].description == "Inventory additions"
    assert _int_value(first.counters[0].value) == 9007199254740993
    assert "service.name" in first.resource.attributes()
    counter.add(number.MetricNumber.Int(2))
    auto second = reader.get_metrics_data()
    assert _int_value(second.counters[0].value) == 9007199254740995
    assert _int_value(first.counters[0].value) == 9007199254740993
    second.counters[0].name = "mutation"
    assert reader.get_metrics_data().counters[0].name == "items.added"

@test
def counter_collection_ignores_instruments_from_other_providers():
    auto provider = metrics.MeterProvider()
    auto unrelated = metrics.MeterProvider()
    auto local_counter = provider.get_meter("test").create_counter("jobs")
    auto foreign_counter = unrelated.get_meter("test").create_counter("jobs")
    foreign_counter.add(number.MetricNumber.Int(22))
    auto reader = metrics.InMemoryMetricReader(provider)
    assert len(reader.get_metrics_data().counters) == 0
    local_counter.add(number.MetricNumber.Int(1))
    local_counter.add(number.MetricNumber.Double(0.5))
    assert _double_value(reader.get_metrics_data().counters[0].value) == 1.5

@test
def counters_reject_invalid_values_without_changing_collection():
    auto provider = metrics.MeterProvider()
    auto counter = provider.get_meter("test").create_counter("jobs")
    auto reader = metrics.InMemoryMetricReader(provider)
    with expect_raises(ValueError):
        counter.add(number.MetricNumber.Int(-1))
    assert len(reader.get_metrics_data().counters) == 0
    counter.add(number.MetricNumber.Int(9223372036854775807))
    for invalid in [number.MetricNumber.Int(1), number.MetricNumber.Double(-1.0), number.MetricNumber.Double(math.nan), number.MetricNumber.Double(math.inf), number.MetricNumber.Double(-math.inf)]:
        with expect_raises(ValueError):
            counter.add(invalid)
    assert _int_value(reader.get_metrics_data().counters[0].value) == 9223372036854775807

@test
def meters_and_instruments_validate_names():
    auto provider = metrics.MeterProvider()
    for invalid in ["", " ", "\t"]:
        with expect_raises(ValueError):
            provider.get_meter(invalid)
    auto meter = provider.get_meter("test")
    for invalid in ["", "1start", ".start", "white space", "slash\\wrong", "métric", "name:"]:
        with expect_raises(ValueError):
            meter.create_counter(invalid)
    list[str] characters = []
    for index in range(255):
        characters.append("x")
    auto maximum = "".join(characters)
    meter.create_counter(maximum)
    meter.create_counter("Jobs.Active-v2_1/per_second")
    with expect_raises(ValueError):
        meter.create_counter(maximum + "x")
