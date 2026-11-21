import otel.otlp_endpoint as otlp

@test
def otlp_endpoint_defaults_to_localhost_per_signal():
    assert otlp.resolve_http_endpoint(otlp.OtlpSignal.Traces, "", "") == "http://localhost:4318/v1/traces"
    assert otlp.resolve_http_endpoint(otlp.OtlpSignal.Metrics, "", "") == "http://localhost:4318/v1/metrics"

@test
def otlp_endpoint_appends_paths_to_the_base_url():
    for base in ["http://collector:4318", "http://collector:4318/"]:
        assert otlp.resolve_http_endpoint(otlp.OtlpSignal.Traces, base, "") == "http://collector:4318/v1/traces"
        assert otlp.resolve_http_endpoint(otlp.OtlpSignal.Metrics, base, "") == "http://collector:4318/v1/metrics"
    for base in ["https://collector/team", "https://collector/team/"]:
        assert otlp.resolve_http_endpoint(otlp.OtlpSignal.Traces, base, "") == "https://collector/team/v1/traces"
    assert otlp.resolve_http_endpoint(otlp.OtlpSignal.Metrics, "http://[::1]:4318/a%2Fb?tenant=x#label", "") == "http://[::1]:4318/a%2Fb/v1/metrics?tenant=x#label"
    assert otlp.resolve_http_endpoint(otlp.OtlpSignal.Traces, "https://collector/café?q=1", "") == "https://collector/café/v1/traces?q=1"

@test
def otlp_endpoint_signal_override_takes_precedence_and_preserves_the_path():
    auto traces = otlp.resolve_http_endpoint(
        otlp.OtlpSignal.Traces,
        "invalid base",
        "http://trace-collector:4318",
    )
    assert traces == "http://trace-collector:4318/"
    auto metrics = otlp.resolve_http_endpoint(
        otlp.OtlpSignal.Metrics,
        "http://fallback",
        "HTTPS://Collector/custom/%2F/?x=1#label",
    )
    assert metrics == "HTTPS://Collector/custom/%2F/?x=1#label"
    assert otlp.resolve_http_endpoint(otlp.OtlpSignal.Traces, "", "https://collector?x=1") == "https://collector/?x=1"
    assert otlp.resolve_http_endpoint(otlp.OtlpSignal.Traces, "", "https://collector#label") == "https://collector/#label"
    assert otlp.resolve_http_endpoint(otlp.OtlpSignal.Traces, "", "https://collector/") == "https://collector/"

@test
def otlp_endpoint_rejects_malformed_or_unsupported_urls():
    list[str] invalid = [
        "collector:4318",
        "/local",
        "//collector",
        "ftp://collector",
        "https:///path",
        "http://",
        "http://collector:x",
        "https://collector:65536",
        "https://coll ector",
        "https://collector\n/path",
        " https://collector",
    ]
    for endpoint in invalid:
        with expect_raises(ValueError):
            otlp.resolve_http_endpoint(otlp.OtlpSignal.Traces, endpoint, "")
        with expect_raises(ValueError):
            otlp.resolve_http_endpoint(
                otlp.OtlpSignal.Metrics,
                "https://fallback",
                endpoint,
            )
