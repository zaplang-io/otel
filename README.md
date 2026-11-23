# otel

OpenTelemetry (tracing + metrics) for [Zap](https://github.com/zaplang-io/zap) — an official **non-core** package.

- Tracking issue: [zaplang-io/zap#329](https://github.com/zaplang-io/zap/issues/329)
- Contributor & agent conventions: [AGENTS.md](AGENTS.md)
- Design decisions: [DECISIONS.md](DECISIONS.md)

> **Status: in development.** The [Tier-1 scope epic](https://github.com/zaplang-io/otel/issues/1)
> tracks the planned public API.

## Goals

A typed Zap OpenTelemetry library whose public API mirrors Python's [**opentelemetry-python**](https://opentelemetry-python.readthedocs.io/) as closely as Zap's static typing allows, with Go's [`go.opentelemetry.io/otel`](https://pkg.go.dev/go.opentelemetry.io/otel) as a secondary design reference. API-parity with the popular Python library is a project rule — see [AGENTS.md](AGENTS.md).

Planned scope (first cut):

- **Tracing API + SDK** — tracer, spans, span context, attributes, events, status.
- **Metrics API + SDK** — counter, histogram, and gauge instruments with a meter provider.
- **W3C propagation** — `traceparent`, `tracestate`, and `baggage` inject and extract.
- **OTLP exporter** — export spans and metrics over OTLP (HTTP first; gRPC a later decision).
- **Resource + semantic conventions** — resource attributes and the common semantic-convention keys.

## Usage (planned — illustrative only)

```zap
import otel.trace as trace
import otel.metrics as metrics
import otel.attributes as attr

tracer = trace.get_tracer("my-service")

with tracer.start_as_current_span("handle-request") as span:
    span.set_attribute("http.request.method", attr.AttributeValue.Str("GET"))
    span.add_event("cache-miss")
    # ... work ...

meter = metrics.get_meter("my-service")
requests = meter.create_counter("http.server.requests")
requests.add(1, {"http.route": "/health"})
```

Scoped spans use Zap's `with` statement. On scope exit, the span ends and the
coroutine's previous current span is restored, including during exception
unwinding. See [DECISIONS.md](DECISIONS.md) for the design and language dependency.
The remaining signatures are provisional.

Spans accept typed attributes and links at creation. During recording, use
`set_attribute`, `set_attributes`, `add_event`, `add_link`, and `set_status`.
Events use the current Unix nanosecond timestamp unless supplied explicitly.
Attribute, event, link, and status accessors return snapshots. Mutations after
`end()` leave the recorded span unchanged.

Register span processors with `TracerProvider.add_span_processor`. The start
hook receives the recording span and its optional parent context. The end
hook receives a read-only view of the finished span.

## Build and test

The test project installs this checkout as an `otel` path dependency. Run the
native suites from the repository root:

```sh
(cd tools/test_project && zap zenv create --no-venv)
ZAP_ZENV="$PWD/tools/test_project/zenv" zap test tests/
```

GitHub Actions runs the suite on pull requests and pushes inside the
`ghcr.io/zaplang-io/zap:latest` container. CI stays pinned to `zap:latest`
until this module reaches a 1.0 release.

## Trace context

The W3C wire codec treats incoming trace headers as untrusted metadata. It
validates `traceparent` up to 8,192 bytes and `tracestate` up to 32,768 bytes
with at most 32 entries. An invalid field raises `ValueError` at the codec
boundary. Carrier integration and extraction into a span context are tracked
in [#4](https://github.com/zaplang-io/otel/issues/4).

The baggage wire codec accepts up to 64 members and 8,192 bytes per combined
header. The planned carrier is a `dict[str, str]` with repeated HTTP header
values combined in wire order.

The baggage value codec percent-decodes UTF-8 with replacement for malformed
sequences. It preserves entry order and property metadata.

## Resource configuration

The resource SDK reads `OTEL_RESOURCE_ATTRIBUTES` as a comma-separated list of
assignments. Use percent escapes for literal `,` and `=` in keys and values.
Values are strings. A malformed assignment or duplicate decoded key invalidates
the entire variable.

Use `otel.attributes.AttributeValue` for scalar and homogeneous array
attributes. The `otel.semconv` module exposes stable service, SDK, HTTP,
server, and network keys along with their schema version and URL.

```zap
import otel.attributes as attr
import otel.resource as resource
import otel.semconv as semconv

auto app = resource.create({semconv.SERVICE_NAME: attr.AttributeValue.Str("checkout")})
auto attributes = app.attributes()
```

`resource.create` applies SDK defaults, `OTEL_RESOURCE_ATTRIBUTES`,
`OTEL_SERVICE_NAME`, then explicit attributes. With no service name it uses
`unknown_service`. `attributes()` returns a copy, including arrays, and
`merge(other)` returns a resource with `other`'s attributes taking precedence.
Conflicting nonempty schema URLs leave the original resource in place and emit
a warning.

## Histogram buckets

The metrics SDK uses the OpenTelemetry default explicit bucket boundaries
unless the caller supplies a layout. Custom boundaries must be finite and
strictly increasing. Each upper bound belongs to its bucket. The metric
instruments and reader are tracked in [#3](https://github.com/zaplang-io/otel/issues/3).

Counters and histograms use `MetricNumber.Int` or `MetricNumber.Double`.
Observable gauge callbacks will return a list of observations to the reader.

## OTLP endpoints

OTLP/HTTP uses the signal-specific endpoint when configured. Otherwise, it
appends `v1/traces` or `v1/metrics` to the general endpoint, which defaults to
`http://localhost:4318`. Endpoint resolution is implemented. Export and wire
encoding are tracked in [#5](https://github.com/zaplang-io/otel/issues/5).

## Development

Read **[AGENTS.md](AGENTS.md)** before contributing — it covers the opentelemetry-python-parity rule, the one-issue-one-PR flow, how design decisions are recorded in **[DECISIONS.md](DECISIONS.md)**, and the rule for reporting core Zap language/stdlib defects upstream in `zaplang-io/zap` (rather than working around them here).
