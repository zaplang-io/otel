# Internal W3C Trace Context wire codec. Carrier and span bindings live above it.

struct TraceParent:
    str trace_id
    str parent_id
    int64 flags

struct TraceStateMember:
    str key
    str value

def _hex_digit(int64 octet) -> int64:
    if octet >= 48 and octet <= 57:
        return octet - 48
    if octet >= 97 and octet <= 102:
        return octet - 87
    return -1

def _hex_byte(bytes raw, int64 offset) -> int64:
    auto high = _hex_digit(raw[offset])
    auto low = _hex_digit(raw[offset + 1])
    if high < 0 or low < 0:
        raise ValueError("traceparent must use lowercase hexadecimal fields")
    return high * 16 + low

def _validate_id(bytes raw, int64 width):
    if len(raw) != width:
        raise ValueError("traceparent ID has the wrong width")
    bool nonzero = False
    for index in range(width):
        auto digit = _hex_digit(raw[index])
        if digit < 0:
            raise ValueError("traceparent ID must use lowercase hexadecimal")
        if digit != 0:
            nonzero = True
    if not nonzero:
        raise ValueError("traceparent ID must be nonzero")

def parse_traceparent(str value) -> TraceParent:
    if len(value) > 8192:
        raise ValueError("traceparent exceeds the header size limit")
    auto raw = bytes(value)
    auto size = len(raw)
    if size < 55 or size > 8192:
        raise ValueError("invalid traceparent length")
    if raw[2] != 45 or raw[35] != 45 or raw[52] != 45:
        raise ValueError("invalid traceparent separators")
    auto version = _hex_byte(raw, 0)
    if version == 255:
        raise ValueError("reserved traceparent version")
    if size > 55 and (version == 0 or raw[55] != 45 or size == 56):
        raise ValueError("invalid traceparent extension")
    auto trace_id = raw[3:35]
    auto parent_id = raw[36:52]
    _validate_id(trace_id, 32)
    _validate_id(parent_id, 16)
    return TraceParent(str(trace_id), str(parent_id), _hex_byte(raw, 53))

def format_traceparent(TraceParent fields) -> str:
    _validate_id(bytes(fields.trace_id), 32)
    _validate_id(bytes(fields.parent_id), 16)
    if fields.flags < 0 or fields.flags > 255:
        raise ValueError("traceparent flags must fit in one byte")
    # Version 00 assigns only the low (sampled) bit.
    return "00-" + fields.trace_id + "-" + fields.parent_id + "-" + hex.encode(bytes([fields.flags & 1]))

def _lower_ascii(int64 octet) -> bool:
    return octet >= 97 and octet <= 122

def _digit_ascii(int64 octet) -> bool:
    return octet >= 48 and octet <= 57

def _valid_state_key_part(bytes part, int64 maximum, bool tenant) -> bool:
    if len(part) == 0 or len(part) > maximum:
        return False
    if not (_lower_ascii(part[0]) or tenant and _digit_ascii(part[0])):
        return False
    for index in range(len(part)):
        auto octet = part[index]
        if not (_lower_ascii(octet) or _digit_ascii(octet) or octet == 95 or octet == 45 or octet == 42 or octet == 47):
            return False
    return True

def _validate_state_member(TraceStateMember member):
    if len(member.key) > 256 or len(member.value) > 256:
        raise ValueError("tracestate key or value exceeds 256 characters")
    auto key = member.key.split("@")
    bool valid_key = False
    if len(key) == 1:
        valid_key = _valid_state_key_part(bytes(key[0]), 256, False)
    elif len(key) == 2:
        valid_key = _valid_state_key_part(bytes(key[0]), 241, True) and _valid_state_key_part(bytes(key[1]), 14, False)
    if not valid_key:
        raise ValueError("invalid tracestate key")
    auto value = bytes(member.value)
    if len(value) == 0 or value[len(value) - 1] == 32:
        raise ValueError("tracestate value must end with a non-space character")
    for index in range(len(value)):
        auto octet = value[index]
        if octet < 32 or octet > 126 or octet == 44 or octet == 61:
            raise ValueError("invalid tracestate value")

def parse_tracestate(str header) -> list[TraceStateMember]:
    # A canonical list of 32 maximum-sized members fits in 16,447 bytes.
    # Allow additional space for optional HTTP whitespace.
    if len(header) > 32768 or len(bytes(header)) > 32768:
        raise ValueError("tracestate exceeds the header size limit")
    auto entries = header.split(",")
    if len(entries) > 32:
        raise ValueError("tracestate has more than 32 members")
    auto seen = set[str]()
    list[TraceStateMember] members = []
    for entry in entries:
        auto trimmed = entry.strip(" \t")
        if len(trimmed) == 0:
            continue
        auto pair = trimmed.split("=")
        if len(pair) != 2:
            raise ValueError("tracestate member must contain one equals sign")
        auto member = TraceStateMember(pair[0], pair[1])
        _validate_state_member(member)
        if member.key in seen:
            raise ValueError("duplicate tracestate key")
        seen.add(member.key)
        members.append(member)
    return members

def format_tracestate(list[TraceStateMember] members) -> str:
    list[str] entries = []
    for member in members:
        entries.append(member.key + "=" + member.value)
    return ",".join(entries)

def update_tracestate(
    list[TraceStateMember] members,
    TraceStateMember update,
) -> list[TraceStateMember]:
    _validate_state_member(update)
    list[TraceStateMember] updated = [update]
    for member in members:
        if member.key != update.key and len(updated) < 32:
            updated.append(member)
    return updated
