import otel.baggage_values as baggage

@test
def baggage_values_decode_utf8_literals_and_encoded_delimiters():
    auto values = baggage.decode_header(
        "a=Am%C3%A9lie;flag;note=left%3Bright%3Dend,a=+%2B%2C%25",
    )
    assert len(values) == 2
    assert values[0].key == "a"
    assert values[0].value == "Amélie"
    assert values[0].properties[0].has_value == False
    assert values[0].properties[1].value == "left;right=end"
    assert values[1].key == "a"
    assert values[1].value == "++,%"
    assert baggage.encode_header(values) == "a=Am%C3%A9lie;flag;note=left%3Bright%3Dend,a=%2B%2B%2C%25"

@test
def baggage_values_replace_invalid_utf8_in_values_and_metadata():
    auto values = baggage.decode_header("a=A%FFB;metadata=%E2%82,b=%C3%A9%FE%21")
    assert values[0].value == "A�B"
    assert values[0].properties[0].value == "�"
    assert values[1].value == "é�!"
    assert baggage.encode_header(values) == "a=A%EF%BF%BDB;metadata=%EF%BF%BD,b=%C3%A9%EF%BF%BD%21"

@test
def baggage_values_distinguish_bare_and_empty_properties_and_encode_injection_bytes():
    auto entries = baggage.decode_header("a=;bare;empty=")
    assert entries[0].value == ""
    assert entries[0].properties[0].has_value == False
    assert entries[0].properties[1].has_value == True
    assert baggage.encode_header(entries) == "a=;bare;empty="
    list[baggage.BaggageEntry] custom = [
        baggage.BaggageEntry("trace", "a\r\nb; x=1", []),
    ]
    assert baggage.encode_header(custom) == "trace=a%0D%0Ab%3B%20x%3D1"
    assert baggage.decode_header(baggage.encode_header(custom))[0].value == "a\r\nb; x=1"

@test
def baggage_values_reject_invalid_wire_syntax_and_keys():
    assert len(baggage.decode_header("")) == 0
    assert baggage.encode_header([]) == ""
    with expect_raises(ValueError):
        baggage.decode_header("a=%q1")
    with expect_raises(ValueError):
        baggage.encode_header([baggage.BaggageEntry("bad,key", "value", [])])
    with expect_raises(ValueError):
        baggage.encode_header(
            [
                baggage.BaggageEntry(
                    "ok",
                    "x",
                    [baggage.BaggageProperty("bad;key", "", False)],
                ),
            ],
        )
