# Internal decoder for OTEL_RESOURCE_ATTRIBUTES. A malformed assignment
# invalidates the whole value, so callers can use their other resource sources.

def _hex_value(int64 octet) -> int64:
    if octet >= 48 and octet <= 57:
        return octet - 48
    if octet >= 65 and octet <= 70:
        return octet - 55
    if octet >= 97 and octet <= 102:
        return octet - 87
    return -1

def _decode_resource_component(str component) -> str:
    auto raw = bytes(component)
    list[int64] decoded = []
    auto index = 0
    while index < len(raw):
        auto octet = int64(raw[index])
        if octet == 37:
            if len(raw) - index < 3:
                raise ValueError("truncated escape in OTEL_RESOURCE_ATTRIBUTES")
            auto high = _hex_value(raw[index + 1])
            auto low = _hex_value(raw[index + 2])
            if high < 0 or low < 0:
                raise ValueError("invalid escape in OTEL_RESOURCE_ATTRIBUTES")
            decoded.append(high * 16 + low)
            index = index + 3
        else:
            decoded.append(octet)
            index = index + 1
    auto octets = bytes(decoded)
    try:
        return str(octets)
    except Exception:
        raise ValueError("invalid UTF-8 in OTEL_RESOURCE_ATTRIBUTES")

def parse_resource_attributes(str raw) -> dict[str, str]:
    # OpenTelemetry Resource SDK, "Specifying resource information via an
    # environment variable": split before unescaping and keep values as text.
    dict[str, str] attributes = {}
    if raw.strip() == "":
        return attributes
    for assignment in raw.split(","):
        auto pair = assignment.split("=")
        if len(pair) != 2:
            raise ValueError("invalid assignment in OTEL_RESOURCE_ATTRIBUTES")
        auto key = _decode_resource_component(pair[0].strip())
        if key.strip() == "":
            raise ValueError("empty key in OTEL_RESOURCE_ATTRIBUTES")
        if key in attributes:
            raise ValueError("duplicate key in OTEL_RESOURCE_ATTRIBUTES")
        attributes[key] = _decode_resource_component(pair[1].strip())
    return attributes
