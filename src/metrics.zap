import attributes as attr
import math
import metric_buckets as buckets
import metric_number as number
import metric_sum as sums
import resource

struct CounterPoint:
    str meter_name
    str name
    str unit
    str description
    number.MetricNumber value
    dict[str, attr.AttributeValue] attributes

struct MetricsData:
    resource.Resource resource
    list[CounterPoint] counters
    list[HistogramPoint] histograms
    list[GaugePoint] gauges

struct HistogramPoint:
    str meter_name
    str name
    str unit
    str description
    int64 count
    float64 sum
    list[float64] boundaries
    list[int64] bucket_counts
    dict[str, attr.AttributeValue] attributes

struct GaugePoint:
    str meter_name
    str name
    str unit
    str description
    number.MetricNumber value
    dict[str, attr.AttributeValue] attributes

struct CallbackOptions:
    float64 timeout_millis = 10000.0

struct Observation:
    number.MetricNumber value
    dict[str, attr.AttributeValue] attributes = {}

struct _CounterSeries:
    dict[str, attr.AttributeValue] attributes
    number.MetricNumber total

struct _HistogramSeries:
    dict[str, attr.AttributeValue] attributes
    list[int64] bucket_counts
    int64 count = 0
    float64 sum = 0.0

    def record(self, int64 bucket, float64 measurement):
        auto total = self.sum + measurement
        if self.count == 9223372036854775807 or math.isinf(total):
            raise ValueError("histogram aggregate exceeds its numeric range")
        self.bucket_counts[bucket] = self.bucket_counts[bucket] + 1
        self.count = self.count + 1
        self.sum = total

def _snapshot_attributes(
    dict[str, attr.AttributeValue] attributes,
) -> dict[str, attr.AttributeValue]:
    dict[str, attr.AttributeValue] copied = {}
    for key, value in attributes.items():
        if key == "":
            raise ValueError("metric attribute key must not be empty")
        copied[key] = value.snapshot()
    return copied

struct Counter:
    str _name
    str _unit
    str _description
    Lock _lock = threading.Lock()
    list[_CounterSeries] _series = []

    def add(
        self,
        number.MetricNumber amount,
        dict[str, attr.AttributeValue] attributes = {},
    ):
        "Record a value in the cumulative counter series for these attributes."
        with self._lock:
            for series in self._series:
                if series.attributes == attributes:
                    series.total = sums.add_counter(series.total, amount)
                    return
            auto total = sums.add_counter(number.MetricNumber.Int(0), amount)
            self._series.append(_CounterSeries(_snapshot_attributes(attributes), total))

    def _collect(self, str meter_name, list[CounterPoint] points):
        with self._lock:
            for series in self._series:
                points.append(
                    CounterPoint(
                        meter_name,
                        self._name,
                        self._unit,
                        self._description,
                        series.total,
                        _snapshot_attributes(series.attributes),
                    ),
                )

struct Histogram:
    str _name
    str _unit
    str _description
    buckets.HistogramBuckets _layout
    Lock _lock = threading.Lock()
    list[_HistogramSeries] _series = []

    def record(
        self,
        number.MetricNumber amount,
        dict[str, attr.AttributeValue] attributes = {},
    ):
        "Record a measurement against the histogram's explicit bucket boundaries."
        int64 bucket = 0
        float64 measurement = 0.0
        match amount:
            case number.MetricNumber.Int(value):
                bucket = self._layout.integer_bucket_index(value)
                measurement = float64(value)
            case number.MetricNumber.Double(value):
                bucket = self._layout.bucket_index(value)
                measurement = value
        with self._lock:
            for series in self._series:
                if series.attributes == attributes:
                    series.record(bucket, measurement)
                    return
            list[int64] counts = []
            for index in range(self._layout.bucket_count()):
                counts.append(0)
            auto series = _HistogramSeries(_snapshot_attributes(attributes), counts)
            series.record(bucket, measurement)
            self._series.append(series)

    def _collect(self, str meter_name, list[HistogramPoint] points):
        with self._lock:
            for series in self._series:
                list[int64] counts = []
                for count in series.bucket_counts:
                    counts.append(count)
                points.append(
                    HistogramPoint(
                        meter_name,
                        self._name,
                        self._unit,
                        self._description,
                        series.count,
                        series.sum,
                        self._layout.boundaries(),
                        counts,
                        _snapshot_attributes(series.attributes),
                    ),
                )

struct ObservableGauge:
    str _name
    str _unit
    str _description
    list[fn(CallbackOptions) -> list[Observation]] _callbacks

    def _collect(
        self,
        str meter_name,
        CallbackOptions options,
        list[GaugePoint] points,
    ):
        list[GaugePoint] readings = []
        for callback in self._callbacks:
            try:
                auto observations = callback(CallbackOptions(options.timeout_millis))
                for observation in observations:
                    self._record_observation(meter_name, observation, readings)
            except Exception:
                logging.warning("OpenTelemetry gauge collection callback failed")
        for point in readings:
            points.append(point)

    def _record_observation(
        self,
        str meter_name,
        Observation observation,
        list[GaugePoint] readings,
    ):
        match observation.value:
            case number.MetricNumber.Double(value):
                if math.isnan(value) or math.isinf(value):
                    return
            case number.MetricNumber.Int(value):
                pass
        for point in readings:
            if point.attributes == observation.attributes:
                point.value = observation.value
                return
        readings.append(
            GaugePoint(
                meter_name,
                self._name,
                self._unit,
                self._description,
                observation.value,
                _snapshot_attributes(observation.attributes),
            ),
        )

struct Meter:
    str _name
    Lock _lock = threading.Lock()
    list[Counter] _counters = []
    list[Histogram] _histograms = []
    list[ObservableGauge] _gauges = []

    def name(self) -> str:
        "Return the instrumentation scope name."
        return self._name

    def create_counter(self, str name, str unit = "", str description = "") -> Counter:
        "Get or register a named monotonic counter."
        _validate_instrument_name(name)
        auto canonical = name.lower()
        with self._lock:
            for counter in self._counters:
                if counter._name.lower() == canonical and counter._unit == unit and counter._description == description:
                    return counter
            auto counter = Counter(name, unit, description)
            self._counters.append(counter)
            return counter

    def create_histogram(
        self,
        str name,
        str unit = "",
        str description = "",
        Optional[list[float64]] explicit_bucket_boundaries_advisory = None,
    ) -> Histogram:
        "Get or register a histogram with default or explicit bucket boundaries."
        _validate_instrument_name(name)
        auto canonical = name.lower()
        auto layout = buckets.default_histogram_buckets()
        match explicit_bucket_boundaries_advisory:
            case Optional.Some(boundaries):
                layout = buckets.make_histogram_buckets(boundaries)
            case Optional.None:
                pass
        with self._lock:
            for histogram in self._histograms:
                if histogram._name.lower() == canonical and histogram._unit == unit and histogram._description == description:
                    return histogram
            auto histogram = Histogram(name, unit, description, layout)
            self._histograms.append(histogram)
            return histogram

    def create_observable_gauge(
        self,
        str name,
        list[fn(CallbackOptions) -> list[Observation]] callbacks = [],
        str unit = "",
        str description = "",
    ) -> ObservableGauge:
        "Get or register a gauge whose callbacks return observations at collection."
        _validate_instrument_name(name)
        auto canonical = name.lower()
        list[fn(CallbackOptions) -> list[Observation]] registered = []
        for callback in callbacks:
            registered.append(callback)
        with self._lock:
            for gauge in self._gauges:
                if gauge._name.lower() == canonical and gauge._unit == unit and gauge._description == description:
                    return gauge
            auto gauge = ObservableGauge(name, unit, description, registered)
            self._gauges.append(gauge)
            return gauge

    def _collect(self, MetricsData data, CallbackOptions options):
        list[ObservableGauge] gauges = []
        with self._lock:
            for counter in self._counters:
                counter._collect(self._name, data.counters)
            for histogram in self._histograms:
                histogram._collect(self._name, data.histograms)
            for gauge in self._gauges:
                gauges.append(gauge)
        for gauge in gauges:
            gauge._collect(self._name, options, data.gauges)

struct MeterProvider:
    resource.Resource _resource = resource.create()
    Lock _lock = threading.Lock()
    list[Meter] _meters = []

    def get_meter(self, str name) -> Meter:
        "Get or create a meter for the named instrumentation scope."
        if name.strip() == "":
            raise ValueError("meter name must not be empty")
        with self._lock:
            for meter in self._meters:
                if meter.name() == name:
                    return meter
            auto meter = Meter(name)
            self._meters.append(meter)
            return meter

    def _collect(self, CallbackOptions options) -> MetricsData:
        list[Meter] meters = []
        with self._lock:
            for meter in self._meters:
                meters.append(meter)
        auto data = MetricsData(self._resource, [], [], [])
        for meter in meters:
            meter._collect(data, options)
        return data

struct InMemoryMetricReader:
    MeterProvider _provider

    def get_metrics_data(self, float64 timeout_millis = 10000.0) -> MetricsData:
        "Collect a cumulative snapshot from this reader's provider."
        if timeout_millis <= 0.0 or math.isnan(timeout_millis) or math.isinf(timeout_millis):
            raise ValueError("collection timeout must be finite and positive")
        return self._provider._collect(CallbackOptions(timeout_millis))

const MeterProvider _default_provider = MeterProvider()

def get_meter_provider() -> MeterProvider:
    "Return the default meter provider."
    return _default_provider

def get_meter(str name) -> Meter:
    "Get a meter from the default provider."
    return _default_provider.get_meter(name)

def _validate_instrument_name(str name):
    if len(name) == 0 or len(name) > 255:
        raise ValueError("metric instrument name must contain 1 to 255 characters")
    auto first = ord(name[0])
    if not _ascii_letter(first):
        raise ValueError("metric instrument name must start with an ASCII letter")
    for character in name:
        auto code = ord(character)
        if not (_ascii_letter(code) or code >= 48 and code <= 57 or code == 95 or code == 46 or code == 45 or code == 47):
            raise ValueError("invalid character in metric instrument name")

def _ascii_letter(int64 code) -> bool:
    return code >= 65 and code <= 90 or code >= 97 and code <= 122
