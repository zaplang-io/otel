import baggage_wire as wire
import url

struct BaggageProperty:
    str key
    str value
    bool has_value

struct BaggageEntry:
    str key
    str value
    list[BaggageProperty] properties

def decode_header(str header) -> list[BaggageEntry]:
    "Decode a validated W3C baggage header, preserving member and property order."
    list[BaggageEntry] values = []
    for member in wire.parse_baggage(header):
        list[BaggageProperty] properties = []
        for property in member.properties:
            auto value = url.unquote(property.encoded_value, errors="replace")
            properties.append(BaggageProperty(property.key, value, property.has_value))
        auto value = url.unquote(member.encoded_value, errors="replace")
        values.append(BaggageEntry(member.key, value, properties))
    return values

def encode_header(list[BaggageEntry] baggage) -> str:
    "Encode baggage values and properties as a validated W3C header."
    list[wire.BaggageMember] members = []
    for entry in baggage:
        list[wire.BaggageProperty] properties = []
        for property in entry.properties:
            str value = ""
            if property.has_value:
                value = url.quote(property.value)
            properties.append(
                wire.BaggageProperty(property.key, value, property.has_value),
            )
        members.append(
            wire.BaggageMember(entry.key, url.quote(entry.value), properties),
        )
    return wire.format_baggage(members)
