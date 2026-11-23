import otel.attributes as attr
import otel.propagate as propagate
import otel.trace as trace

const str TRACE_ID = "4bf92f3577b34da6a3ce929d0e0e4736"
const str PARENT_ID = "00f067aa0ba902b7"
const str TRACEPARENT = "00-" + TRACE_ID + "-" + PARENT_ID + "-01"

@test
def propagation_continues_the_remote_parent_and_preserves_ambient_baggage():
    dict[str, str] inbound = {
        "Traceparent": TRACEPARENT,
        "TraceState": "rojo=one,congo=two",
        "Baggage": "tenant=Am%C3%A9lie;flag,tenant=backup",
    }
    auto extracted = propagate.extract(inbound)
    auto remote = extracted.span_context().unwrap()
    assert remote.is_remote
    assert remote.trace_id == TRACE_ID
    assert remote.span_id == PARENT_ID
    assert remote.trace_state == "rojo=one,congo=two"
    assert len(extracted.baggage()) == 2
    assert trace.get_current_span().is_none()
    auto token = propagate.attach(extracted)
    try:
        auto active = trace.get_current_span().unwrap()
        assert not active.is_recording()
        assert active.end_time().is_none()
        active.set_attribute("ignored", attr.AttributeValue.Str("value"))
        assert len(active.attributes()) == 0
        active.end()
        assert active.end_time().is_none()
        auto tracer = trace.get_tracer("receiver")
        with tracer.start_as_current_span("receive", kind=trace.SpanKind.Server) as server:
            auto parent = server.parent_context().unwrap()
            assert parent.is_remote
            assert parent.span_id == PARENT_ID
            auto local = server.get_span_context()
            assert local.trace_id == TRACE_ID
            assert local.span_id != PARENT_ID
            assert not local.is_remote
            dict[str, str] outbound = {
                "TraceParent": "stale",
                "TRACESTATE": "stale",
                "BAGGAGE": "stale",
                "authorization": "untouched",
            }
            propagate.inject(outbound)
            assert outbound["traceparent"] == "00-" + TRACE_ID + "-" + local.span_id + "-01"
            assert outbound["tracestate"] == "rojo=one,congo=two"
            assert outbound["baggage"] == "tenant=Am%C3%A9lie;flag,tenant=backup"
            assert outbound["authorization"] == "untouched"
            assert len(outbound) == 4
        assert trace.get_current_span().unwrap() is active
    finally:
        propagate.detach(token)
    assert trace.get_current_span().is_none()
    assert len(propagate.get_current().baggage()) == 0

@test
def propagation_bad_fields_do_not_replace_valid_base_components():
    auto base = propagate.extract(
        {"traceparent": TRACEPARENT, "baggage": "existing=one"},
    )
    for invalid in ["ff-" + TRACE_ID + "-" + PARENT_ID + "-01", "00-00000000000000000000000000000000-" + PARENT_ID + "-01", "00-" + TRACE_ID + "-0000000000000000-01", "00-" + TRACE_ID + "-" + PARENT_ID + "-GG"]:
        auto context = propagate.extract(
            {"traceparent": invalid, "baggage": "bad=%QZ"},
            context=Optional.Some(base),
        )
        assert context.span_context().unwrap().span_id == PARENT_ID
        assert context.baggage()[0].key == "existing"
        assert propagate.extract({"traceparent": invalid}).span_context().is_none()
    auto ambiguous = propagate.extract(
        {
            "traceparent": TRACEPARENT,
            "TraceParent": TRACEPARENT,
            "baggage": "tenant=valid",
        },
    )
    assert ambiguous.span_context().is_none()
    assert ambiguous.baggage()[0].value == "valid"
    auto absent = propagate.extract({"tracestate": "valid=yes"})
    assert absent.span_context().is_none()

@test
def propagation_discards_invalid_trace_state_without_discarding_the_parent():
    auto context = propagate.extract(
        {"traceparent": TRACEPARENT, "tracestate": "vendor=one,vendor=two"},
    )
    assert context.span_context().unwrap().trace_state == ""
    dict[str, str] outbound = {"TraceState": "old=leave"}
    propagate.inject(outbound, context=Optional.Some(context))
    assert outbound["traceparent"] == TRACEPARENT
    assert len(outbound) == 1
    auto unsampled = propagate.extract(
        {"traceparent": "00-" + TRACE_ID + "-" + PARENT_ID + "-00"},
    )
    assert not unsampled.span_context().unwrap().is_sampled()

@test
def propagation_context_scope_restores_the_recording_span_and_ignores_extraction_by_default():
    auto tracer = trace.get_tracer("scope")
    with tracer.start_as_current_span("outer") as outer:
        auto base = propagate.get_current()
        auto empty = propagate.extract({})
        assert empty.span_context().is_none()
        auto empty_token = propagate.attach(empty)
        try:
            assert trace.get_current_span().is_none()
        finally:
            propagate.detach(empty_token)
        assert trace.get_current_span().unwrap() is outer
        auto derived = propagate.set_baggage(
            "tenant",
            "shop",
            context=Optional.Some(base),
        )
        auto token = propagate.attach(derived)
        try:
            assert trace.get_current_span().unwrap() is outer
            assert propagate.get_current().baggage()[0].value == "shop"
            auto copied = derived.baggage()
            copied[0].value = "mutation"
            assert derived.baggage()[0].value == "shop"
        finally:
            propagate.detach(token)
        assert len(propagate.get_current().baggage()) == 0
        assert outer.is_recording()

@test
def propagation_can_update_baggage_independently_of_the_trace():
    auto source = propagate.extract(
        {"baggage": "tenant=old;flag,other=keep,tenant=duplicate"},
    )
    auto with_value = propagate.set_baggage(
        "tenant",
        "east;west",
        context=Optional.Some(source),
    )
    assert len(source.baggage()) == 3
    assert len(with_value.baggage()) == 2
    dict[str, str] outgoing = {}
    propagate.inject(outgoing, context=Optional.Some(with_value))
    assert "traceparent" not in outgoing
    assert outgoing["baggage"] == "tenant=east%3Bwest,other=keep"
    assert propagate.fields() == ["traceparent", "tracestate", "baggage"]
    with expect_raises(ValueError):
        propagate.set_baggage("invalid,key", "value")
