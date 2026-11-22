import otel.attributes as attr
import otel.resource as resource
import otel.semconv as semconv

def _text(dict[str, attr.AttributeValue] values, str key) -> str:
    match values[key]:
        case attr.AttributeValue.Str(value):
            return value
        case _:
            raise ValueError("attribute must be text")

@test
def resource_defaults_and_explicit_attributes_have_standard_keys():
    auto previous_env = os.getenv("OTEL_RESOURCE_ATTRIBUTES")
    auto previous_name = os.getenv("OTEL_SERVICE_NAME")
    try:
        os.setenv("OTEL_RESOURCE_ATTRIBUTES", "")
        os.setenv("OTEL_SERVICE_NAME", "")
        auto defaults = resource.create().attributes()
        assert _text(defaults, semconv.SERVICE_NAME) == "unknown_service"
        assert _text(defaults, semconv.TELEMETRY_SDK_NAME) == "opentelemetry"
        assert _text(defaults, semconv.TELEMETRY_SDK_LANGUAGE) == "zap"
        assert _text(defaults, semconv.TELEMETRY_SDK_VERSION) == "0.1.0"
        auto explicit = resource.create(
            {"service.name": attr.AttributeValue.Str("checkout")},
        )
        assert _text(explicit.attributes(), semconv.SERVICE_NAME) == "checkout"
    finally:
        os.setenv("OTEL_RESOURCE_ATTRIBUTES", previous_env)
        os.setenv("OTEL_SERVICE_NAME", previous_name)

@test
def resource_environment_precedence_and_malformed_input_are_atomic():
    auto previous_env = os.getenv("OTEL_RESOURCE_ATTRIBUTES")
    auto previous_name = os.getenv("OTEL_SERVICE_NAME")
    try:
        os.setenv("OTEL_SERVICE_NAME", "")
        os.setenv("OTEL_RESOURCE_ATTRIBUTES", "service.name=blob,custom.path=a%2Cb")
        assert _text(resource.create().attributes(), semconv.SERVICE_NAME) == "blob"
        os.setenv("OTEL_SERVICE_NAME", "dedicated")
        auto detected = resource.create().attributes()
        assert _text(detected, semconv.SERVICE_NAME) == "dedicated"
        assert _text(detected, "custom.path") == "a,b"
        auto explicit = resource.create(
            {"service.name": attr.AttributeValue.Str("explicit")},
        )
        assert _text(explicit.attributes(), semconv.SERVICE_NAME) == "explicit"
        for malformed in ["custom.path=x,bad", "custom.path=x,custom.path=y"]:
            os.setenv("OTEL_RESOURCE_ATTRIBUTES", malformed)
            auto fallback = resource.create().attributes()
            assert _text(fallback, semconv.SERVICE_NAME) == "dedicated"
            assert "custom.path" not in fallback
    finally:
        os.setenv("OTEL_RESOURCE_ATTRIBUTES", previous_env)
        os.setenv("OTEL_SERVICE_NAME", previous_name)

@test
def resource_snapshots_keep_input_and_returned_boolean_arrays_independent():
    list[bool] flags = [True, False]
    dict[str, attr.AttributeValue] input = {
        "test.flags": attr.AttributeValue.BoolArray(flags),
    }
    auto created = resource.create(input)
    flags[0] = False
    input["test.flags"] = attr.AttributeValue.Str("changed")
    auto snapshot = created.attributes()
    match snapshot["test.flags"]:
        case attr.AttributeValue.BoolArray(values):
            assert values == [True, False]
            values[1] = True
        case _:
            assert False
    snapshot["test.flags"] = attr.AttributeValue.Str("changed")
    auto next_snapshot = created.attributes()
    match next_snapshot["test.flags"]:
        case attr.AttributeValue.BoolArray(values):
            assert values == [True, False]
        case _:
            assert False

@test
def resource_merge_uses_updating_attributes_and_schema_precedence():
    auto old = resource.create(
        {
            "test.left": attr.AttributeValue.Str("left"),
            "test.shared": attr.AttributeValue.Str("old"),
        },
    )
    auto update = resource.create(
        {
            "test.shared": attr.AttributeValue.Str("new"),
            "test.right": attr.AttributeValue.Str("right"),
        },
        schema_url=semconv.SCHEMA_URL,
    )
    auto merged = old.merge(update)
    assert merged.schema_url() == semconv.SCHEMA_URL
    assert _text(merged.attributes(), "test.left") == "left"
    assert _text(merged.attributes(), "test.shared") == "new"
    assert _text(merged.attributes(), "test.right") == "right"
    assert _text(old.attributes(), "test.shared") == "old"
    assert update.merge(old).schema_url() == semconv.SCHEMA_URL
    assert update.merge(update).schema_url() == semconv.SCHEMA_URL
    assert old.merge(old).schema_url() == ""
    auto conflict = resource.create(
        {"test.shared": attr.AttributeValue.Str("conflict")},
        schema_url="schema:other",
    )
    auto retained = update.merge(conflict)
    assert retained.schema_url() == semconv.SCHEMA_URL
    assert _text(retained.attributes(), "test.shared") == "new"

@test
def resource_rejects_empty_or_whitespace_only_explicit_keys():
    for key in ["", " ", "\t"]:
        with expect_raises(ValueError):
            resource.create({key: attr.AttributeValue.Str("value")})
