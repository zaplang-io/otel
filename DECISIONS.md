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
