# Changelog

## Unreleased

- Added the W3C `traceparent` and `tracestate` wire codec and native tests.
- Added the W3C Baggage wire codec and native tests.
- Added decoding and validation for `OTEL_RESOURCE_ATTRIBUTES`.
- Added shared typed attributes and versioned semantic-convention metadata.
- Added explicit histogram bucket layouts and boundary validation.
- Added tagged integer and double metric measurements.
- Added endpoint resolution for OTLP/HTTP trace and metric export.
- Added immutable resources, default attributes, environment detection, and merge.
- Added scoped span lifecycle, span contexts, IDs, and named tracers.
- Added span attributes, timestamped events, links, and status.
- Added synchronous start and end hooks for tracer-provider span processors.
- Added UTF-8 baggage value decoding and percent-encoded serialization.
- Added validated integer and double counter summation.
- Added W3C carrier injection and extraction, baggage binding, and remote-parent continuation.
- Added named meters, counter registration, and cumulative counter snapshots.
