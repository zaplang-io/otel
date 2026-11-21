import otel.baggage_wire as baggage

@test
def baggage_round_trips_w3c_examples():
    auto header = "userId=Am%C3%A9lie,serverNode=DF%2028,isProduction=false"
    auto members = baggage.parse_baggage(header)
    assert len(members) == 3
    assert members[0].key == "userId"
    assert members[0].encoded_value == "Am%C3%A9lie"
    assert members[1].encoded_value == "DF%2028"
    assert members[2].encoded_value == "false"
    assert baggage.format_baggage(members) == header

@test
def baggage_preserves_properties_duplicate_members_and_equal_signs():
    auto members = baggage.parse_baggage(
        " key = a=b=c ; public ; note = x%3By, key= ;present=\t",
    )
    assert len(members) == 2
    assert members[0].encoded_value == "a=b=c"
    assert len(members[0].properties) == 2
    assert members[0].properties[0].has_value == False
    assert members[0].properties[1].encoded_value == "x%3By"
    assert members[1].key == "key"
    assert members[1].encoded_value == ""
    assert members[1].properties[0].has_value == True
    assert baggage.format_baggage(members) == "key=a=b=c;public;note=x%3By,key=;present="

@test
def baggage_retains_encoded_bytes_for_the_value_decoder():
    auto members = baggage.parse_baggage("a=%FF%25%0D%0A,b=+")
    assert members[0].encoded_value == "%FF%25%0D%0A"
    assert baggage.format_baggage(members) == "a=%FF%25%0D%0A,b=+"
    assert len(baggage.parse_baggage(" \t")) == 0
    assert baggage.format_baggage([]) == ""

@test
def baggage_rejects_invalid_keys_values_and_properties():
    list[str] invalid = [
        "key",
        "=value",
        "bad key=value",
        "foo@bar=x",
        "a=x y",
        "a=é",
        "a=x\ry",
        "a=x\ny",
        "a=x\ty",
        "a=\"x\"",
        "a=x\\y",
        "a=%",
        "a=%0",
        "a=%xz",
        "a=b,",
        "a=b;",
        "a=b;=x",
        "a=b;tag=%yy",
    ]
    for header in invalid:
        with expect_raises(ValueError):
            baggage.parse_baggage(header)
    with expect_raises(ValueError):
        baggage.format_baggage([baggage.BaggageMember("a", "x,y", [])])
    with expect_raises(ValueError):
        baggage.format_baggage(
            [
                baggage.BaggageMember(
                    "a",
                    "x",
                    [baggage.BaggageProperty("bad key", "", False)],
                ),
            ],
        )

@test
def baggage_enforces_member_and_byte_limits():
    list[str] fields = []
    for index in range(64):
        fields.append("a" + str(index) + "=x")
    auto header = ",".join(fields)
    auto members = baggage.parse_baggage(header)
    assert len(members) == 64
    assert baggage.format_baggage(members) == header
    with expect_raises(ValueError):
        baggage.parse_baggage(header + ",extra=x")
    members.append(baggage.BaggageMember("extra", "x", []))
    with expect_raises(ValueError):
        baggage.format_baggage(members)

    list[str] payload = []
    for index in range(8190):
        payload.append("x")
    auto value = "".join(payload)
    auto size_boundary = "a=" + value
    assert baggage.format_baggage(baggage.parse_baggage(size_boundary)) == size_boundary
    with expect_raises(ValueError):
        baggage.parse_baggage(size_boundary + "x")
    with expect_raises(ValueError):
        baggage.format_baggage([baggage.BaggageMember("a", value + "x", [])])
