import otel.resource_environment as environment

@test
def resource_environment_keeps_all_values_as_text():
    auto attributes = environment.parse_resource_attributes(
        " count = 123 ,ready=false,empty=,enabled=True ",
    )
    assert len(attributes) == 4
    assert attributes["count"] == "123"
    assert attributes["ready"] == "false"
    assert attributes["empty"] == ""
    assert attributes["enabled"] == "True"
    assert len(environment.parse_resource_attributes("")) == 0
    assert len(environment.parse_resource_attributes("  \t")) == 0

@test
def resource_environment_decodes_delimiters_utf8_and_literal_plus():
    auto attributes = environment.parse_resource_attributes(
        "a%2cb%3Dc=v%2Cw%3dz,utf8=caf%c3%a9,pct=100%25,plus=a+b,decoded-space=%20x%20",
    )
    assert attributes["a,b=c"] == "v,w=z"
    assert attributes["utf8"] == "café"
    assert attributes["pct"] == "100%"
    assert attributes["plus"] == "a+b"
    assert attributes["decoded-space"] == " x "

@test
def resource_environment_rejects_invalid_utf8_in_keys_and_values():
    for raw in ["%ff=a", "a=%ff", "a=%c3", "a=%c0%af", "a=%ed%a0%80"]:
        with expect_raises(ValueError):
            environment.parse_resource_attributes(raw)

@test
def resource_environment_rejects_ambiguous_or_malformed_assignments():
    list[str] invalid = [
        "a",
        "a=b=c",
        "=x",
        " \t =x",
        "%20%09=x",
        "a=1,a=2",
        "a=1,%61=2",
        "a=1,",
        ",a=1",
        "a=1,,b=2",
        "a=1,b=%",
        "a=1,b=%a",
        "a=1,b=%xz",
        "%xz=a",
    ]
    for raw in invalid:
        with expect_raises(ValueError):
            environment.parse_resource_attributes(raw)
