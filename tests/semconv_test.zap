import otel.semconv as semconv

@test
def semantic_conventions_report_version_and_stable_keys():
    assert semconv.SCHEMA_VERSION == "1.45.0"
    assert semconv.SCHEMA_URL == "https://opentelemetry.io/schemas/" + semconv.SCHEMA_VERSION
    assert semconv.SERVICE_NAME == "service.name"
    assert semconv.SERVICE_NAMESPACE == "service.namespace"
    assert semconv.SERVICE_VERSION == "service.version"
    assert semconv.SERVICE_INSTANCE_ID == "service.instance.id"
    assert semconv.TELEMETRY_SDK_NAME == "telemetry.sdk.name"
    assert semconv.TELEMETRY_SDK_LANGUAGE == "telemetry.sdk.language"
    assert semconv.TELEMETRY_SDK_VERSION == "telemetry.sdk.version"
    assert semconv.HTTP_REQUEST_METHOD == "http.request.method"
    assert semconv.HTTP_RESPONSE_STATUS_CODE == "http.response.status_code"
    assert semconv.HTTP_ROUTE == "http.route"
    assert semconv.SERVER_ADDRESS == "server.address"
    assert semconv.SERVER_PORT == "server.port"
    assert semconv.NETWORK_PROTOCOL_NAME == "network.protocol.name"
    assert semconv.NETWORK_PROTOCOL_VERSION == "network.protocol.version"
    assert semconv.NETWORK_TRANSPORT == "network.transport"
