# W3C Baggage wire members retain percent-encoded values until decoding.
struct BaggageProperty:
    str key
    str encoded_value
    bool has_value

struct BaggageMember:
    str key
    str encoded_value
    list[BaggageProperty] properties

const int64 MAX_HEADER_BYTES = 8192
const int64 MAX_MEMBERS = 64

def _validate_key(str key):
    if key == "":
        raise ValueError("empty baggage key")
    for character in key:
        auto code = ord(character)
        if code >= 48 and code <= 57 or code >= 65 and code <= 90 or code >= 97 and code <= 122:
            continue
        if not "!#$%&'*+-.^_`|~".contains(str(character)):
            raise ValueError("invalid baggage key")

def _is_hex(int64 code) -> bool:
    return code >= 48 and code <= 57 or code >= 65 and code <= 70 or code >= 97 and code <= 102

def _validate_encoded_value(str value):
    auto raw = bytes(value)
    auto index = 0
    while index < len(raw):
        auto code = raw[index]
        if code == 37:
            if len(raw) - index < 3 or not _is_hex(raw[index + 1]) or not _is_hex(raw[index + 2]):
                raise ValueError("invalid percent escape in baggage value")
            index = index + 3
        else:
            if code <= 32 or code >= 127 or code == 34 or code == 44 or code == 59 or code == 92:
                raise ValueError("invalid baggage value")
            index = index + 1

def _parse_property(str raw) -> BaggageProperty:
    # The ASCII check on the full header makes the byte offset a string index.
    auto delimiter = raw.find("=")
    if delimiter < 0:
        auto key = raw.strip(" \t")
        _validate_key(key)
        return BaggageProperty(key, "", False)
    auto key = raw[:delimiter].strip(" \t")
    auto value = raw[delimiter + 1:].strip(" \t")
    _validate_key(key)
    _validate_encoded_value(value)
    return BaggageProperty(key, value, True)

def parse_baggage(str header) -> list[BaggageMember]:
    if len(header) > MAX_HEADER_BYTES:
        raise ValueError("baggage exceeds the header size limit")
    for character in header:
        auto code = ord(character)
        if code < 32 and code != 9 or code >= 127:
            raise ValueError(
                "baggage header must use printable ASCII and horizontal tabs",
            )
    list[BaggageMember] members = []
    if header.strip(" \t") == "":
        return members
    auto items = header.split(",")
    if len(items) > MAX_MEMBERS:
        raise ValueError("baggage has more than 64 members")
    for item in items:
        auto fields = item.split(";")
        auto entry = _parse_property(fields[0])
        if not entry.has_value:
            raise ValueError("baggage member must have a value")
        list[BaggageProperty] properties = []
        for index in range(1, len(fields)):
            properties.append(_parse_property(fields[index]))
        members.append(BaggageMember(entry.key, entry.encoded_value, properties))
    return members

def format_baggage(list[BaggageMember] members) -> str:
    if len(members) > MAX_MEMBERS:
        raise ValueError("baggage has more than 64 members")
    list[str] fields = []
    auto size = 0
    for member in members:
        _validate_key(member.key)
        _validate_encoded_value(member.encoded_value)
        auto field = member.key + "=" + member.encoded_value
        for property in member.properties:
            _validate_key(property.key)
            field = field + ";" + property.key
            if property.has_value:
                _validate_encoded_value(property.encoded_value)
                field = field + "=" + property.encoded_value
            if len(field) > MAX_HEADER_BYTES:
                raise ValueError("baggage exceeds the header size limit")
        if len(fields) > 0:
            size = size + 1
        if len(field) > MAX_HEADER_BYTES - size:
            raise ValueError("baggage exceeds the header size limit")
        size = size + len(field)
        fields.append(field)
    return ",".join(fields)
