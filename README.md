# otel

OpenTelemetry (tracing + metrics) for [Zap](https://github.com/zaplang-io/zap) — an official **non-core** package.

- Tracking issue: [zaplang-io/zap#329](https://github.com/zaplang-io/zap/issues/329)
- Contributor & agent conventions: [AGENTS.md](AGENTS.md)
- Design decisions: [DECISIONS.md](DECISIONS.md)

> **Status: docs-first.** No implementation yet — the planned surface is tracked in the [issues](https://github.com/zaplang-io/otel/issues) (see the Tier-1 scope epic).

## Goals

A typed Zap OpenTelemetry library whose public API mirrors Python's [**opentelemetry-python**](https://opentelemetry-python.readthedocs.io/) as closely as Zap's static typing allows, with Go's [`go.opentelemetry.io/otel`](https://pkg.go.dev/go.opentelemetry.io/otel) as a secondary design reference. API-parity with the popular Python library is a project rule — see [AGENTS.md](AGENTS.md).

Planned scope (first cut):

- **Tracing API + SDK** — tracer, spans, span context, attributes, events, status.
- **Metrics API + SDK** — counter, histogram, and gauge instruments with a meter provider.
- **W3C trace-context propagation** — `traceparent` / `tracestate` inject and extract.
- **OTLP exporter** — export spans and metrics over OTLP (HTTP first; gRPC a later decision).
- **Resource + semantic conventions** — resource attributes and the common semantic-convention keys.

## Usage (planned — illustrative only)

```zap
import otel

tracer = otel.tracer("my-service")

with tracer.start_as_current_span("handle-request") as span:
    span.set_attribute("http.method", "GET")
    span.add_event("cache-miss")
    # ... work ...

meter = otel.meter("my-service")
requests = meter.create_counter("http.server.requests")
requests.add(1, {"http.route": "/health"})
```

The exact signatures (keyword vs positional, defaults, return shapes) are not final. Any ambiguity is escalated to the maintainer with Python/Go examples and recorded in [DECISIONS.md](DECISIONS.md) rather than decided unilaterally.

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

## Development

Read **[AGENTS.md](AGENTS.md)** before contributing — it covers the opentelemetry-python-parity rule, the one-issue-one-PR flow, how design decisions are recorded in **[DECISIONS.md](DECISIONS.md)**, and the rule for reporting core Zap language/stdlib defects upstream in `zaplang-io/zap` (rather than working around them here).
