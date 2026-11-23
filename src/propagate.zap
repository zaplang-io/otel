import baggage_values as bag
import trace
import trace_context_wire as wire

struct Context:
    Optional[trace.Span] _span
    list[bag.BaggageEntry] _baggage

    def span_context(self) -> Optional[trace.SpanContext]:
        "Return a copy of the span context carried by this context."
        match self._span:
            case Optional.Some(span):
                return Optional.Some(span.get_span_context())
            case Optional.None:
                return None

    def baggage(self) -> list[bag.BaggageEntry]:
        "Return baggage entries and metadata in wire order."
        return _copy_baggage(self._baggage)

struct _BaggageBinding:
    list[bag.BaggageEntry] entries

struct Token:
    ContextToken _span
    ContextToken _baggage

ContextVar[_BaggageBinding] _current_baggage = ContextVar[_BaggageBinding](
    "otel.baggage",
)

def _copy_baggage(list[bag.BaggageEntry] source) -> list[bag.BaggageEntry]:
    list[bag.BaggageEntry] result = []
    for entry in source:
        list[bag.BaggageProperty] properties = []
        for property in entry.properties:
            properties.append(
                bag.BaggageProperty(property.key, property.value, property.has_value),
            )
        result.append(bag.BaggageEntry(entry.key, entry.value, properties))
    return result

def get_current() -> Context:
    "Capture the active span and baggage without changing either binding."
    list[bag.BaggageEntry] entries = []
    try:
        entries = _copy_baggage(_current_baggage.get().entries)
    except LookupError:
        pass
    return Context(trace.get_current_span(), entries)

def attach(Context context) -> Token:
    "Activate a context in the current coroutine. Detach in reverse attachment order."
    auto entries = _copy_baggage(context._baggage)
    auto span_token = trace.attach_span(context._span)
    auto baggage_token = _current_baggage.set(_BaggageBinding(entries))
    return Token(span_token, baggage_token)

def detach(Token token):
    "Restore the previous context."
    _current_baggage.reset(token._baggage)
    trace.detach_span(token._span)

def _read_header(dict[str, str] carrier, str name) -> str:
    bool found = False
    str value = ""
    for key, header in carrier.items():
        if key.lower() == name:
            if found:
                raise ValueError(
                    "ambiguous propagation header, combine repeated values in wire order",
                )
            found = True
            value = header
    return value

def _extract_span(
    dict[str, str] carrier,
    Optional[trace.Span] fallback,
) -> Optional[trace.Span]:
    try:
        auto header = _read_header(carrier, "traceparent")
        if header == "":
            return fallback
        auto parent = wire.parse_traceparent(header)
        str state = ""
        try:
            state = wire.format_tracestate(
                wire.parse_tracestate(_read_header(carrier, "tracestate")),
            )
        except ValueError:
            pass
        auto remote = trace.SpanContext(
            parent.trace_id,
            parent.parent_id,
            parent.flags,
            state,
            True,
        )
        return Optional.Some(trace.non_recording_span(remote))
    except ValueError:
        return fallback

def extract(dict[str, str] carrier, Optional[Context] context = None) -> Context:
    "Extract W3C trace context and baggage, using an empty context by default."
    auto base = context.unwrap_or(Context(None, []))
    auto entries = base.baggage()
    try:
        auto header = _read_header(carrier, "baggage")
        if header.strip(" \t") != "":
            entries = bag.decode_header(header)
    except ValueError:
        pass
    return Context(_extract_span(carrier, base._span), entries)

def fields() -> list[str]:
    "Return the managed W3C field names."
    return ["traceparent", "tracestate", "baggage"]

def _clear_field(dict[str, str] carrier, str name):
    list[str] matching = []
    for key in carrier.keys():
        if key.lower() == name:
            matching.append(key)
    for key in matching:
        del carrier[key]

def inject(dict[str, str] carrier, Optional[Context] context = None):
    "Inject the supplied context, or the current context when omitted."
    auto source = get_current()
    match context:
        case Optional.Some(explicit):
            source = explicit
        case Optional.None:
            pass
    auto baggage_header = bag.encode_header(source._baggage)
    match source.span_context():
        case Optional.Some(span):
            if span.is_valid():
                auto parent = wire.format_traceparent(
                    wire.TraceParent(span.trace_id, span.span_id, span.trace_flags),
                )
                _clear_field(carrier, "traceparent")
                _clear_field(carrier, "tracestate")
                carrier["traceparent"] = parent
                if span.trace_state != "":
                    carrier["tracestate"] = span.trace_state
        case Optional.None:
            pass
    if baggage_header != "":
        _clear_field(carrier, "baggage")
        carrier["baggage"] = baggage_header

def set_baggage(str name, str value, Optional[Context] context = None) -> Context:
    "Return a context with the named baggage value set."
    auto base = get_current()
    match context:
        case Optional.Some(explicit):
            base = explicit
        case Optional.None:
            pass
    list[bag.BaggageEntry] entries = [bag.BaggageEntry(name, value, [])]
    for entry in base.baggage():
        if entry.key != name:
            entries.append(entry)
    bag.encode_header(entries)
    return Context(base._span, entries)
