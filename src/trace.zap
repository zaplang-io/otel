import trace_context_wire as wire

enum SpanKind:
    Internal
    Server
    Client
    Producer
    Consumer

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

struct Span:
    str _name
    SpanKind _kind
    SpanContext _context
    Optional[SpanContext] _parent
    Lock _lock
    int64 _start_time
    Optional[int64] _end_time = None

    def get_span_context(self) -> SpanContext:
        "Return a copy of the span's propagation context."
        auto span = self._context
        return SpanContext(
            span.trace_id,
            span.span_id,
            span.trace_flags,
            span.trace_state,
            span.is_remote,
        )

    def parent_context(self) -> Optional[SpanContext]:
        "Return a copy of the parent context when present."
        match self._parent:
            case Optional.Some(parent):
                return Optional.Some(
                    SpanContext(
                        parent.trace_id,
                        parent.span_id,
                        parent.trace_flags,
                        parent.trace_state,
                        parent.is_remote,
                    ),
                )
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

    def start_span(self, str name, SpanKind kind = SpanKind.Internal) -> Span:
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
        return Span(name, kind, context, parent, threading.Lock(), time.time_ns())

    def start_as_current_span(
        self,
        str name,
        SpanKind kind = SpanKind.Internal,
    ) -> CurrentSpan:
        "Create a context manager that activates the span for the scope."
        return CurrentSpan(self, name, kind)

struct CurrentSpan:
    Tracer _tracer
    str _name
    SpanKind _kind
    Optional[Span] _span = None
    Optional[ContextToken] _token = None

    def __enter__(self) -> Span:
        if not self._token.is_none():
            raise ValueError("span scope is already active")
        auto span = self._tracer.start_span(self._name, kind=self._kind)
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
