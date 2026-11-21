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

The immutable `Resource` API depends on copying Boolean arrays. Zap's
list iteration regression is tracked in
[zaplang-io/zap#1241](https://github.com/zaplang-io/zap/issues/1241).

### Explicit histogram buckets ([#3](https://github.com/zaplang-io/otel/issues/3))

Use the default boundaries and inclusive upper bounds from the
[OpenTelemetry Metrics SDK](https://opentelemetry.io/docs/specs/otel/metrics/sdk/#explicit-bucket-histogram-aggregation).
Custom boundaries are finite, strictly increasing, and copied at construction.
An empty boundary list yields one bucket. A nonfinite floating-point
measurement raises `ValueError` before bucket selection.
