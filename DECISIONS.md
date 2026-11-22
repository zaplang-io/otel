# otel package decisions

Design decisions for the Zap `otel` library, keyed to issues. Each records a
choice that could not be read straight off Python's
[opentelemetry-python](https://opentelemetry-python.readthedocs.io/) or Go's
[`go.opentelemetry.io/otel`](https://pkg.go.dev/go.opentelemetry.io/otel), with
the reference it follows or departs from. Signature ambiguities are resolved with
the maintainer (with Python/Go examples) before being recorded here.

## Parity target: opentelemetry-python

The package tracks [**opentelemetry-python**](https://opentelemetry-python.readthedocs.io/)
as its primary API reference, with Go's `go.opentelemetry.io/otel` as a secondary
reference. Both follow the language-neutral OpenTelemetry specification, which is
the tie-breaker when the two SDKs differ. Deviations are recorded below, keyed to
the issue that introduces them.

## Decisions (2026-11-21)

### W3C wire validation ([#4](https://github.com/zaplang-io/otel/issues/4))

The wire codec operates on header text and defers carrier and span binding to
the propagation layer. It reads the known prefix of `traceparent` versions
above `00` and emits version `00` with only the sampled flag. It preserves the
order of `tracestate` entries, moves updated entries to the front, and drops
the rightmost entry when an insert would exceed the 32-member limit.

The input caps are 8,192 bytes for `traceparent` and 32,768 bytes for
`tracestate`. The latter allows a full list of maximum-width members plus
optional whitespace. See [W3C Trace Context](https://www.w3.org/TR/trace-context/).

Tier 1 uses a `dict[str, str]` carrier. The caller combines repeated HTTP
values for the same header in wire order before passing the carrier. This
keeps the default Python mapping shape. Go's `TextMapCarrier` abstracts the
carrier behind accessor methods.

Tier 1 includes [W3C Baggage](https://www.w3.org/TR/baggage/). The wire layer
retains member order, duplicate keys, properties, and percent-encoded values.
The codec accepts up to 64 members and 8,192 bytes. Value decoding requires
UTF-8 replacement support from
[zaplang-io/zap#1242](https://github.com/zaplang-io/zap/issues/1242).

### Environment resource attributes ([#6](https://github.com/zaplang-io/otel/issues/6))

Follow the [OpenTelemetry Resource SDK](https://opentelemetry.io/docs/specs/otel/resource/sdk/)
for `OTEL_RESOURCE_ATTRIBUTES`. Split assignments before percent decoding,
keep values as strings, and reject the whole input on a malformed assignment or
escape. Detect duplicate keys after decoding. The decoder raises `ValueError`
and includes no attribute data in the diagnostic.

### Shared attribute values and semantic conventions ([#6](https://github.com/zaplang-io/otel/issues/6))

Resources, metrics, and spans use `dict[str, AttributeValue]`. `AttributeValue`
is a tagged enum with Boolean, signed 64-bit integer, double, and string
variants, plus a homogeneous array variant for each scalar type. The tags
retain the original value type, as Go's typed attribute constructors do, while
allowing a Python-style heterogeneous mapping.

Stable convention keys live in one `otel.semconv` module. `SCHEMA_VERSION`
and `SCHEMA_URL` identify the published semantic-convention release. The first
set follows [v1.45.0](https://github.com/open-telemetry/semantic-conventions/releases/tag/v1.45.0).

### Immutable resources and detection precedence ([#6](https://github.com/zaplang-io/otel/issues/6))

Use `resource.create(attributes, schema_url=...)` to construct a `Resource`.
The module factory follows Python's `Resource.create` and applies SDK defaults,
`OTEL_RESOURCE_ATTRIBUTES`, `OTEL_SERVICE_NAME`, and explicit attributes in
increasing priority. An empty service name falls back to the other sources.
If the environment attribute list is malformed, emit a warning and retain the
other sources.

Resource attributes are snapshots, including array values. `merge` gives the
updating resource's attributes priority. An empty schema URL is unspecified.
If both schema URLs are specified and differ, emit a warning and return the
original resource, matching Python's behavior.

### Explicit histogram buckets ([#3](https://github.com/zaplang-io/otel/issues/3))

Use the default boundaries and inclusive upper bounds from the
[OpenTelemetry Metrics SDK](https://opentelemetry.io/docs/specs/otel/metrics/sdk/#explicit-bucket-histogram-aggregation).
Custom boundaries are finite, strictly increasing, and copied at construction.
An empty boundary list yields one bucket. A nonfinite floating-point
measurement raises `ValueError` before bucket selection.

### Measurements and observable callbacks ([#3](https://github.com/zaplang-io/otel/issues/3))

Use Python's `create_counter` and `create_histogram` names. Measurements use
one `MetricNumber` sum type with signed 64-bit integer and double variants.
This retains the source precision in the tagged value. Go makes the numeric
type part of the factory name, for example `Int64Counter`.

Observable gauge callbacks receive `CallbackOptions` (including the collection
timeout) and return a `list[Observation]`. An observation carries a
`MetricNumber` and its attribute mapping. This follows Python's returned
observations. Go invokes callbacks with an observer that accepts measurements.

### OTLP/HTTP endpoint resolution ([#5](https://github.com/zaplang-io/otel/issues/5))

Follow the [OTLP Exporter specification](https://opentelemetry.io/docs/specs/otel/protocol/exporter/#endpoint-urls-for-otlphttp).
Signals use their explicit HTTP or HTTPS endpoint when set, with `/` supplied
when the URL has no path. Otherwise, append the signal path to the general
endpoint. Preserve the configured scheme spelling, authority, path escapes,
query, and fragment during resolution. Invalid URLs raise `ValueError`.

Wire encoding depends on the Protocol Buffers implementation tracked in
[zaplang-io/zap#524](https://github.com/zaplang-io/zap/issues/524).

### Tracing scope and current span ([#2](https://github.com/zaplang-io/otel/issues/2))

The tracing API follows Python's `start_as_current_span` context manager. Use
`with tracer.start_as_current_span("request") as span:` to bind the current
span in the running coroutine. Calls made within that scope can read the
current span without passing it through each function. A nested span uses the
current span as its parent. Leaving the scope ends the span and restores the
previous binding on both normal exit and exception unwinding.

Go's `Tracer.Start(ctx, name)` returns an updated context that callers pass
explicitly, and the caller ends the span with `Span.End()`. The maintainer
approved Python-style scoping and coroutine-local context for Zap.

Zap's [context-manager protocol](https://github.com/zaplang-io/zap/blob/3138b083c489713902eeb150643f002041885af5/DECISIONS.md#d-0069--context-manager-protocol--with-i185)
provides scope cleanup. `ContextVar[Span]` and its reset token bind the span
in the current coroutine. A spawned child inherits the binding at spawn time.
See [zaplang-io/zap#1237](https://github.com/zaplang-io/zap/issues/1237).

Imported tracing methods use the compiler fix in
[zaplang-io/zap#1273](https://github.com/zaplang-io/zap/pull/1273).

### Recorded span data ([#2](https://github.com/zaplang-io/otel/issues/2))

Attributes use the shared tagged values. Spans copy attributes at insertion
and on read, including array payloads. Events and links retain insertion order.
Event timestamps are Unix nanoseconds. An explicit timestamp of zero is valid.
Links require a valid span context and keep a copy of it. Both `start_span`
and `start_as_current_span` accept initial attributes and links.

Status follows the OpenTelemetry precedence `Ok > Error > Unset`. Only `Error`
retains a description. Span mutations after the first `end()` are ignored.
