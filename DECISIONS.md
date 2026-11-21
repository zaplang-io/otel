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

_No decisions recorded yet. Add one section per decision as issues are implemented._
