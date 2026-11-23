import metric_number as number
import metric_sum as sums
import resource

struct CounterPoint:
    str meter_name
    str name
    str unit
    str description
    number.MetricNumber value

struct MetricsData:
    resource.Resource resource
    list[CounterPoint] counters

struct Counter:
    str _name
    str _unit
    str _description
    Lock _lock = threading.Lock()
    number.MetricNumber _total = number.MetricNumber.Int(0)
    bool _has_measurement = False

    def add(self, number.MetricNumber amount):
        "Record a value in the counter's unattributed series."
        with self._lock:
            self._total = sums.add_counter(self._total, amount)
            self._has_measurement = True

    def _collect(self, str meter_name) -> Optional[CounterPoint]:
        with self._lock:
            if not self._has_measurement:
                return None
            return Optional.Some(
                CounterPoint(
                    meter_name,
                    self._name,
                    self._unit,
                    self._description,
                    self._total,
                ),
            )

struct Meter:
    str _name
    Lock _lock = threading.Lock()
    list[Counter] _counters = []

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

    def _collect_counters(self, list[CounterPoint] points):
        with self._lock:
            for counter in self._counters:
                match counter._collect(self._name):
                    case Optional.Some(point):
                        points.append(point)
                    case Optional.None:
                        pass

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

    def _collect(self) -> MetricsData:
        list[CounterPoint] counters = []
        with self._lock:
            for meter in self._meters:
                meter._collect_counters(counters)
        return MetricsData(self._resource, counters)

struct InMemoryMetricReader:
    MeterProvider _provider

    def get_metrics_data(self) -> MetricsData:
        "Collect a cumulative snapshot from this reader's provider."
        return self._provider._collect()

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
