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
