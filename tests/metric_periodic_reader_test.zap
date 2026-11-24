import time
import otel.metric_number as number
import otel.metrics as metrics

struct RecordingExporter:
    channel[int64] delivered
    Atomic[int64] calls
    bool fail_first = False

    def export(
        self,
        metrics.MetricsData data,
        int64 timeout_millis,
    ) -> metrics.MetricExportResult:
        assert timeout_millis == 1000
        assert len(data.counters) == 1
        assert data.counters[0].name == "jobs"
        auto index = self.calls.add(1)
        if self.fail_first and index == 1:
            raise ValueError("transient exporter failure")
        self.delivered <- index
        return metrics.MetricExportResult.Success

struct SlowExporter:
    Atomic[int64] cleaned

    def export(
        self,
        metrics.MetricsData data,
        int64 timeout_millis,
    ) -> metrics.MetricExportResult:
        assert timeout_millis == 25
        try:
            time.sleep_for(time.seconds(60))
            return metrics.MetricExportResult.Success
        finally:
            self.cleaned.add(1)

struct FailingExporter:
    def export(
        self,
        metrics.MetricsData data,
        int64 timeout_millis,
    ) -> metrics.MetricExportResult:
        return metrics.MetricExportResult.Failure

def _provider_with_measurement() -> metrics.MeterProvider:
    auto provider = metrics.MeterProvider()
    auto counter = provider.get_meter("service").create_counter("jobs")
    counter.add(number.MetricNumber.Int(1))
    return provider

def _observe_periodic_exports(channel[int64] delivered):
    assert <-delivered == 2
    assert <-delivered == 3
    raise ValueError("stop after two exports")

def _run_and_note_cleanup(
    metrics.PeriodicExportingMetricReader reader,
    channel[int64] entered,
    Atomic[int64] cleaned,
):
    try:
        entered <- 1
        reader.run()
    finally:
        cleaned.add(1)

def _cancel_waiting_reader(channel[int64] entered):
    assert <-entered == 1
    time.sleep_for(time.millis(15))
    raise ValueError("stop before the next interval")

def _verify_export_deadline(
    metrics.PeriodicExportingMetricReader reader,
    Atomic[int64] finished,
):
    assert reader.collect_once() == metrics.MetricExportResult.Failure
    finished.add(1)

@test
def periodic_reader_exports_at_intervals_and_continues_after_an_exporter_error():
    auto delivered = channel[int64]()
    Atomic[int64] calls = Atomic(0)
    auto exporter = RecordingExporter(delivered, calls, True)
    auto reader = metrics.PeriodicExportingMetricReader(
        _provider_with_measurement(),
        exporter,
        export_interval_millis=10,
        export_timeout_millis=1000,
    )
    with expect_raises(ValueError):
        scope(timeout=3000, grace=500):
            spawn reader.run()
            spawn _observe_periodic_exports(delivered)
    assert calls.load() >= 3

@test
def periodic_reader_drains_on_scope_cancellation_during_a_long_interval():
    auto delivered = channel[int64]()
    auto entered = channel[int64]()
    Atomic[int64] calls = Atomic(0)
    Atomic[int64] cleaned = Atomic(0)
    auto exporter = RecordingExporter(delivered, calls)
    auto reader = metrics.PeriodicExportingMetricReader(
        _provider_with_measurement(),
        exporter,
        export_interval_millis=60000,
        export_timeout_millis=1000,
    )
    for attempt in range(2):
        with expect_raises(ValueError):
            scope(timeout=3000, grace=500):
                spawn _run_and_note_cleanup(reader, entered, cleaned)
                spawn _cancel_waiting_reader(entered)
        assert cleaned.load() == attempt + 1
        assert calls.load() == 0

@test
def periodic_reader_passes_a_deadline_and_reports_failed_export():
    Atomic[int64] cleaned = Atomic(0)
    Atomic[int64] finished = Atomic(0)
    auto reader = metrics.PeriodicExportingMetricReader(
        metrics.MeterProvider(),
        SlowExporter(cleaned),
        export_timeout_millis=25,
    )
    scope(timeout=3000, grace=500):
        spawn _verify_export_deadline(reader, finished)
    assert cleaned.load() == 1
    assert finished.load() == 1
    auto failing = metrics.PeriodicExportingMetricReader(
        metrics.MeterProvider(),
        FailingExporter(),
    )
    assert failing.collect_once() == metrics.MetricExportResult.Failure

@test
def periodic_reader_rejects_invalid_intervals_and_timeouts():
    for duration in [0, -1, 9223372036855]:
        auto invalid_interval = metrics.PeriodicExportingMetricReader(
            metrics.MeterProvider(),
            FailingExporter(),
            export_interval_millis=duration,
        )
        with expect_raises(ValueError):
            invalid_interval.run()
        auto invalid_timeout = metrics.PeriodicExportingMetricReader(
            metrics.MeterProvider(),
            FailingExporter(),
            export_timeout_millis=duration,
        )
        with expect_raises(ValueError):
            invalid_timeout.collect_once()
        with expect_raises(ValueError):
            invalid_timeout.run()
