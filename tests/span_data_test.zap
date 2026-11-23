import otel.attributes as attr
import otel.trace as trace

def _trace_span() -> trace.Span:
    return trace.get_tracer("span.data").start_span("operation")

def _read_text(dict[str, attr.AttributeValue] values, str key) -> str:
    match values[key]:
        case attr.AttributeValue.Str(value):
            return value
        case _:
            raise ValueError("expected text attribute")

@test
def span_supports_all_attribute_types_and_replacement():
    auto span = _trace_span()
    dict[str, attr.AttributeValue] values = {
        "bool": attr.AttributeValue.Bool(False),
        "int": attr.AttributeValue.Int(9007199254740993),
        "double": attr.AttributeValue.Double(1.5),
        "str": attr.AttributeValue.Str("initial"),
        "bools": attr.AttributeValue.BoolArray([True, False]),
        "ints": attr.AttributeValue.IntArray([1, -2]),
        "doubles": attr.AttributeValue.DoubleArray([1.5, -3.0]),
        "strings": attr.AttributeValue.StrArray(["a", "é"]),
    }
    span.set_attributes(values)
    span.set_attribute("str", attr.AttributeValue.Str("replacement"))
    auto read = span.attributes()
    assert len(read) == 8
    assert _read_text(read, "str") == "replacement"
    match read["bool"]:
        case attr.AttributeValue.Bool(value):
            assert not value
        case _:
            assert False
    match read["int"]:
        case attr.AttributeValue.Int(value):
            assert value == 9007199254740993
        case _:
            assert False
    match read["double"]:
        case attr.AttributeValue.Double(value):
            assert value == 1.5
        case _:
            assert False
    match read["bools"]:
        case attr.AttributeValue.BoolArray(value):
            assert value == [True, False]
        case _:
            assert False
    match read["ints"]:
        case attr.AttributeValue.IntArray(value):
            assert value == [1, -2]
        case _:
            assert False
    match read["doubles"]:
        case attr.AttributeValue.DoubleArray(value):
            assert value == [1.5, -3.0]
        case _:
            assert False
    match read["strings"]:
        case attr.AttributeValue.StrArray(value):
            assert value == ["a", "é"]
        case _:
            assert False
    span.end()

@test
def span_snapshots_own_arrays_and_do_not_share_metadata_between_spans():
    auto first = _trace_span()
    auto second = _trace_span()
    list[bool] flags = [True, False]
    first.set_attribute("flags", attr.AttributeValue.BoolArray(flags))
    flags[0] = False
    auto snapshot = first.attributes()
    match snapshot["flags"]:
        case attr.AttributeValue.BoolArray(value):
            assert value == [True, False]
            value[1] = True
        case _:
            assert False
    match first.attributes()["flags"]:
        case attr.AttributeValue.BoolArray(value):
            assert value == [True, False]
        case _:
            assert False
    assert len(second.attributes()) == 0
    assert len(second.events()) == 0
    assert len(second.links()) == 0
    first.end()
    second.end()

@test
def span_events_keep_explicit_timestamps_order_and_independent_attributes():
    auto span = _trace_span()
    dict[str, attr.AttributeValue] attributes = {
        "key": attr.AttributeValue.Str("before"),
    }
    span.add_event("first", attributes=attributes, timestamp=Optional.Some(int64(0)))
    span.add_event("second")
    attributes["key"] = attr.AttributeValue.Str("after")
    auto events = span.events()
    assert len(events) == 2
    assert events[0].name == "first"
    assert events[0].timestamp == 0
    assert events[1].name == "second"
    assert events[1].timestamp >= span.start_time()
    assert _read_text(events[0].attributes, "key") == "before"
    events[0].attributes["key"] = attr.AttributeValue.Str("external mutation")
    assert _read_text(span.events()[0].attributes, "key") == "before"
    span.end()

@test
def span_links_reject_invalid_contexts_and_snapshot_valid_links():
    auto span = _trace_span()
    auto linked = _trace_span()
    auto context = linked.get_span_context()
    auto expected_id = context.span_id
    dict[str, attr.AttributeValue] link_attributes = {
        "relation": attr.AttributeValue.Str("request"),
    }
    span.add_link(context, attributes=link_attributes)
    context.span_id = "invalid"
    link_attributes["relation"] = attr.AttributeValue.Str("changed")
    with expect_raises(ValueError):
        span.add_link(context)
    auto links = span.links()
    assert len(links) == 1
    assert links[0].context.span_id == expected_id
    assert _read_text(links[0].attributes, "relation") == "request"
    links[0].context.span_id = "external mutation"
    assert span.links()[0].context.span_id == expected_id
    span.end()
    linked.end()

@test
def span_status_honors_precedence_and_only_keeps_error_descriptions():
    auto span = _trace_span()
    assert span.status().status_code == trace.StatusCode.Unset
    auto error = trace.Status(trace.StatusCode.Error, "failed")
    span.set_status(error)
    error.description = "changed"
    assert span.status().status_code == trace.StatusCode.Error
    assert span.status().description == "failed"
    span.set_status(trace.Status(trace.StatusCode.Unset))
    assert span.status().description == "failed"
    span.set_status(trace.Status(trace.StatusCode.Ok, "ignored"))
    assert span.status().status_code == trace.StatusCode.Ok
    assert span.status().description == ""
    span.set_status(error)
    assert span.status().status_code == trace.StatusCode.Ok
    span.end()

@test
def span_rejects_invalid_keys_and_ignores_all_changes_after_end():
    auto span = _trace_span()
    with expect_raises(ValueError):
        span.set_attribute("", attr.AttributeValue.Str("invalid"))
    with expect_raises(ValueError):
        span.set_attributes(
            {
                "ok": attr.AttributeValue.Str("first"),
                "": attr.AttributeValue.Str("invalid"),
            },
        )
    assert len(span.attributes()) == 0
    span.set_attribute("ok", attr.AttributeValue.Str("saved"))
    auto valid_context = span.get_span_context()
    span.end()
    span.set_attribute("ok", attr.AttributeValue.Str("discarded"))
    span.set_attributes({"other": attr.AttributeValue.Str("discarded")})
    span.add_event("discarded")
    span.add_link(valid_context)
    span.set_status(trace.Status(trace.StatusCode.Error, "discarded"))
    assert len(span.attributes()) == 1
    assert _read_text(span.attributes(), "ok") == "saved"
    assert len(span.events()) == 0
    assert len(span.links()) == 0
    assert span.status().status_code == trace.StatusCode.Unset

@test
def span_starts_with_attributes_and_links_in_both_lifecycle_forms():
    auto tracer = trace.get_tracer("span.creation")
    auto linked = tracer.start_span("linked")
    auto context = linked.get_span_context()
    dict[str, attr.AttributeValue] attributes = {
        "initial": attr.AttributeValue.Str("yes"),
    }
    dict[str, attr.AttributeValue] link_attributes = {
        "relationship": attr.AttributeValue.Str("follows"),
    }
    list[trace.Link] links = [trace.Link(context, link_attributes)]
    auto explicit = tracer.start_span("explicit", attributes=attributes, links=links)
    assert _read_text(explicit.attributes(), "initial") == "yes"
    assert explicit.links()[0].context.span_id == context.span_id
    assert _read_text(explicit.links()[0].attributes, "relationship") == "follows"
    with tracer.start_as_current_span("scoped", attributes=attributes, links=links) as scoped:
        assert _read_text(scoped.attributes(), "initial") == "yes"
        assert scoped.links()[0].context.span_id == context.span_id
    with expect_raises(ValueError):
        tracer.start_span(
            "invalid",
            attributes={"": attr.AttributeValue.Str("invalid")},
        )
    context.span_id = "invalid"
    with expect_raises(ValueError):
        tracer.start_span("invalid", links=links)
    assert trace.get_current_span().is_none()
    explicit.end()
    linked.end()
