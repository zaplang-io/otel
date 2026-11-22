import attributes as attr
import trace_context_wire as wire

enum SpanKind:
    Internal
    Server
    Client
    Producer
    Consumer

enum StatusCode:
    Unset
    Error
    Ok

struct Status:
    StatusCode status_code = StatusCode.Unset
    str description = ""

struct Event:
    str name
    int64 timestamp
    dict[str, attr.AttributeValue] attributes

struct Link:
    SpanContext context
    dict[str, attr.AttributeValue] attributes

struct SpanContext:
    str trace_id
    str span_id
    int64 trace_flags
    str trace_state
    bool is_remote

    def is_valid(self) -> bool:
        "Check the trace ID, span ID, flags, and W3C trace state."
        try:
            wire.format_traceparent(
                wire.TraceParent(self.trace_id, self.span_id, self.trace_flags),
            )
            wire.parse_tracestate(self.trace_state)
            return True
        except ValueError:
            return False

    def is_sampled(self) -> bool:
        "Return whether the sampled bit is set."
        return self.trace_flags & 1 != 0

    def _snapshot(self) -> SpanContext:
        return SpanContext(
            self.trace_id,
            self.span_id,
            self.trace_flags,
            self.trace_state,
            self.is_remote,
        )

def _snapshot_attributes(
    dict[str, attr.AttributeValue] values,
) -> dict[str, attr.AttributeValue]:
    dict[str, attr.AttributeValue] result = {}
    for key, value in values.items():
        if key == "":
            raise ValueError("span attribute key must not be empty")
        result[key] = value.snapshot()
    return result

struct Span:
    str _name
    SpanKind _kind
    SpanContext _context
    Optional[SpanContext] _parent
    Lock _lock
    int64 _start_time
    Optional[int64] _end_time = None
    dict[str, attr.AttributeValue] _attributes = {}
    list[Event] _events = []
    list[Link] _links = []
    Status _status = Status()

    def get_span_context(self) -> SpanContext:
        "Return a copy of the span's propagation context."
        return self._context._snapshot()

    def parent_context(self) -> Optional[SpanContext]:
        "Return a copy of the parent context when present."
        match self._parent:
            case Optional.Some(parent):
                return Optional.Some(parent._snapshot())
            case Optional.None:
                return None

    def start_time(self) -> int64:
        "Return the start timestamp in Unix nanoseconds."
        return self._start_time

    def end_time(self) -> Optional[int64]:
        "Return the end timestamp after the span has ended."
        with self._lock:
            return self._end_time

    def name(self) -> str:
        return self._name

    def kind(self) -> SpanKind:
        return self._kind

    def is_recording(self) -> bool:
        "Return whether this span is still recording."
        return self.end_time().is_none()

    def set_attribute(self, str key, attr.AttributeValue value):
        "Set an attribute on a recording span, replacing any previous value."
        with self._lock:
            if not self._end_time.is_none():
                return
            if key == "":
                raise ValueError("span attribute key must not be empty")
            self._attributes[key] = value.snapshot()

    def set_attributes(self, dict[str, attr.AttributeValue] attributes):
        "Set several attributes on a recording span."
        with self._lock:
            if not self._end_time.is_none():
                return
            auto values = _snapshot_attributes(attributes)
            for key, value in values.items():
                self._attributes[key] = value

    def attributes(self) -> dict[str, attr.AttributeValue]:
        "Return a snapshot of the span attributes."
        with self._lock:
            return _snapshot_attributes(self._attributes)

    def add_event(
        self,
        str name,
        dict[str, attr.AttributeValue] attributes = {},
        Optional[int64] timestamp = None,
    ):
        "Append an event, using the current Unix nanosecond time by default."
        with self._lock:
            if not self._end_time.is_none():
                return
            int64 at = 0
            match timestamp:
                case Optional.Some(value):
                    at = value
                case Optional.None:
                    at = time.time_ns()
            self._events.append(Event(name, at, _snapshot_attributes(attributes)))

    def events(self) -> list[Event]:
        "Return a snapshot of the events in insertion order."
        list[Event] result = []
        with self._lock:
            for event in self._events:
                result.append(
                    Event(
                        event.name,
                        event.timestamp,
                        _snapshot_attributes(event.attributes),
                    ),
                )
        return result

    def add_link(
        self,
        SpanContext context,
        dict[str, attr.AttributeValue] attributes = {},
    ):
        "Append a link to a valid span context."
        with self._lock:
            if not self._end_time.is_none():
                return
            if not context.is_valid():
                raise ValueError("span link context must be valid")
            self._links.append(
                Link(context._snapshot(), _snapshot_attributes(attributes)),
            )

    def links(self) -> list[Link]:
        "Return a snapshot of the links in insertion order."
        list[Link] result = []
        with self._lock:
            for link in self._links:
                result.append(
                    Link(
                        link.context._snapshot(),
                        _snapshot_attributes(link.attributes),
                    ),
                )
        return result

    def set_status(self, Status status):
        "Set the span status. Ok is final, and descriptions apply to Error."
        with self._lock:
            if not self._end_time.is_none() or self._status.status_code == StatusCode.Ok or status.status_code == StatusCode.Unset:
                return
            str description = ""
            if status.status_code == StatusCode.Error:
                description = status.description
            self._status = Status(status.status_code, description)

    def status(self) -> Status:
        "Return a copy of the current status."
        with self._lock:
            return Status(self._status.status_code, self._status.description)

    def end(self):
        "Finish recording the span once."
        with self._lock:
            if self._end_time.is_none():
                self._end_time = Optional.Some(time.time_ns())

ContextVar[Span] _current_span = ContextVar[Span]("otel.current_span")

def get_current_span() -> Optional[Span]:
    "Return the active span for the current coroutine, if there is one."
    try:
        return Optional.Some(_current_span.get())
    except LookupError:
        return None

def _random_id(int64 width, str zero) -> str:
    auto value = hex.encode(crypto.random_bytes(width))
    while value == zero:
        value = hex.encode(crypto.random_bytes(width))
    return value

struct Tracer:
    str _name

    def name(self) -> str:
        return self._name

    def start_span(
        self,
        str name,
        SpanKind kind = SpanKind.Internal,
        dict[str, attr.AttributeValue] attributes = {},
        list[Link] links = [],
    ) -> Span:
        "Start a span with the current parent and leave the current binding in place."
        str trace_id = ""
        int64 flags = 1
        str state = ""
        Optional[SpanContext] parent = None
        match get_current_span():
            case Optional.Some(active):
                auto parent_context = active.get_span_context()
                trace_id = parent_context.trace_id
                flags = parent_context.trace_flags
                state = parent_context.trace_state
                parent = Optional.Some(parent_context)
            case Optional.None:
                trace_id = _random_id(16, "00000000000000000000000000000000")
        auto span_id = _random_id(8, "0000000000000000")
        auto context = SpanContext(trace_id, span_id, flags, state, False)
        auto span = Span(name, kind, context, parent, threading.Lock(), time.time_ns())
        span.set_attributes(attributes)
        for link in links:
            span.add_link(link.context, attributes=link.attributes)
        return span

    def start_as_current_span(
        self,
        str name,
        SpanKind kind = SpanKind.Internal,
        dict[str, attr.AttributeValue] attributes = {},
        list[Link] links = [],
    ) -> CurrentSpan:
        "Create a context manager that activates the span for the scope."
        return CurrentSpan(self, name, kind, attributes, links)

struct CurrentSpan:
    Tracer _tracer
    str _name
    SpanKind _kind
    dict[str, attr.AttributeValue] _attributes = {}
    list[Link] _links = []
    Optional[Span] _span = None
    Optional[ContextToken] _token = None

    def __enter__(self) -> Span:
        if not self._token.is_none():
            raise ValueError("span scope is already active")
        auto span = self._tracer.start_span(
            self._name,
            kind=self._kind,
            attributes=self._attributes,
            links=self._links,
        )
        self._token = Optional.Some(_current_span.set(span))
        self._span = Optional.Some(span)
        return span

    def __exit__(self):
        match self._token:
            case Optional.Some(token):
                _current_span.reset(token)
                self._token = None
            case Optional.None:
                return
        match self._span:
            case Optional.Some(span):
                span.end()
                self._span = None
            case Optional.None:
                pass

struct TracerProvider:
    def get_tracer(self, str name) -> Tracer:
        "Get a tracer for a named instrumentation scope."
        if name.strip() == "":
            raise ValueError("tracer name must not be empty")
        return Tracer(name)

const TracerProvider _default_provider = TracerProvider()

def get_tracer(str name) -> Tracer:
    "Get a tracer from the default provider."
    return _default_provider.get_tracer(name)
