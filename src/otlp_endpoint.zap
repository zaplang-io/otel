import url

# Internal endpoint resolver for OTLP/HTTP. It does not open connections.
enum OtlpSignal:
    Traces
    Metrics

def _validate_endpoint(str endpoint) -> UrlParts:
    for character in endpoint:
        auto code = ord(character)
        if code <= 32 or code == 127:
            raise ValueError("OTLP endpoint contains whitespace or a control character")
    auto parts = url.split(endpoint)
    if parts.scheme != "http" and parts.scheme != "https" or not parts.has_authority or parts.host == "":
        raise ValueError("OTLP endpoint must be an absolute HTTP or HTTPS URL")
    return parts

def _path_end(str endpoint) -> int64:
    auto index = 0
    for character in endpoint:
        auto code = ord(character)
        if code == 63 or code == 35:
            break
        index = index + 1
    return index

def resolve_http_endpoint(
    OtlpSignal signal,
    str general_endpoint,
    str signal_endpoint,
) -> str:
    if signal_endpoint != "":
        auto parts = _validate_endpoint(signal_endpoint)
        if parts.path != "":
            return signal_endpoint
        auto path_end = _path_end(signal_endpoint)
        return signal_endpoint[:path_end] + "/" + signal_endpoint[path_end:]

    str base = general_endpoint
    if base == "":
        base = "http://localhost:4318"
    _validate_endpoint(base)
    auto path_end = _path_end(base)
    auto prefix = base[:path_end]
    if not prefix.endswith("/"):
        prefix = prefix + "/"
    str signal_path = "v1/traces"
    if signal == OtlpSignal.Metrics:
        signal_path = "v1/metrics"
    return prefix + signal_path + base[path_end:]
