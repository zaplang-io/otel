import otel.trace_context_wire as wire

# W3C Trace Context §3.2.3 and §3.3.2 provide the canonical wire examples.

def _sample_traceparent() -> str:
    return "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

def _repeat_text(str value, int64 count) -> str:
    list[str] parts = []
    for index in range(count):
        parts.append(value)
    return "".join(parts)

@test
def traceparent_round_trips_sampled_and_unsampled_examples():
    auto example = _sample_traceparent()
    auto sampled = wire.parse_traceparent(example)
    assert sampled.trace_id == "4bf92f3577b34da6a3ce929d0e0e4736"
    assert sampled.parent_id == "00f067aa0ba902b7"
    assert sampled.flags == 1
    assert wire.format_traceparent(sampled) == example
    auto unsampled = example[:54] + "0"
    assert wire.parse_traceparent(unsampled).flags == 0
    assert wire.format_traceparent(wire.parse_traceparent(unsampled)) == unsampled

@test
def traceparent_reads_the_known_prefix_of_a_future_version():
    auto example = _sample_traceparent()
    auto fields = wire.parse_traceparent("01" + example[2:53] + "a1-opaque")
    assert fields.flags == 161
    assert wire.format_traceparent(fields) == example
    assert wire.format_traceparent(wire.parse_traceparent("fe" + example[2:])) == example

@test
def traceparent_rejects_malformed_fields():
    auto example = _sample_traceparent()
    list[str] invalid = [
        "",
        example[0:54],
        "ff" + example[2:],
        "gz" + example[2:],
        "00/" + example[3:],
        example[:35] + "/" + example[36:],
        example[:52] + "/" + example[53:],
        example + "-extra",
        "01" + example[2:] + "extra",
        "01" + example[2:] + "-",
        example[:3] + _repeat_text("0", 32) + example[35:],
        example[:36] + _repeat_text("0", 16) + example[52:],
        example[:3] + "A" + example[4:],
        example[:36] + "g" + example[37:],
        example[:53] + "0G",
        example[:3] + "é" + example[4:],
    ]
    for header in invalid:
        with expect_raises(ValueError):
            wire.parse_traceparent(header)

@test
def traceparent_rejects_oversized_input_and_invalid_output_fields():
    auto example = _sample_traceparent()
    auto prefix = "01" + example[2:] + "-"
    assert wire.format_traceparent(wire.parse_traceparent(prefix + _repeat_text("x", 8192 - len(prefix)))) == example
    with expect_raises(ValueError):
        wire.parse_traceparent(prefix + _repeat_text("x", 8193 - len(prefix)))
    auto fields = wire.parse_traceparent(example)
    with expect_raises(ValueError):
        wire.format_traceparent(wire.TraceParent(fields.trace_id, fields.parent_id, -1))
    with expect_raises(ValueError):
        wire.format_traceparent(
            wire.TraceParent(fields.trace_id, fields.parent_id, 256),
        )
    with expect_raises(ValueError):
        wire.format_traceparent(wire.TraceParent("1234", fields.parent_id, 1))

@test
def tracestate_round_trips_order_and_ignores_empty_members():
    auto state = wire.parse_tracestate(
        " rojo=00f067aa0ba902b7\t, ,\tcongo=t61rcWkgMzE, 2a@sys/v*= a!~ ",
    )
    assert len(state) == 3
    assert state[2].value == " a!~"
    assert wire.format_tracestate(state) == "rojo=00f067aa0ba902b7,congo=t61rcWkgMzE,2a@sys/v*= a!~"
    assert len(wire.parse_tracestate("")) == 0
    assert len(wire.parse_tracestate(", \t, ")) == 0

@test
def tracestate_updates_move_to_front_and_preserve_other_entries():
    auto state = wire.parse_tracestate("a=1,b=2,c=3")
    auto updated = wire.update_tracestate(state, wire.TraceStateMember("b", "4"))
    assert wire.format_tracestate(updated) == "b=4,a=1,c=3"
    assert wire.format_tracestate(state) == "a=1,b=2,c=3"
    assert wire.format_tracestate(wire.update_tracestate(updated, wire.TraceStateMember("d", "5"))) == "d=5,b=4,a=1,c=3"
    with expect_raises(ValueError):
        wire.update_tracestate(state, wire.TraceStateMember("d", "trailing "))

@test
def tracestate_enforces_member_count_and_evicts_the_rightmost_entry_on_insert():
    list[str] entries = []
    for index in range(32):
        entries.append("key" + str(index) + "=value")
    auto full = wire.parse_tracestate(",".join(entries))
    assert len(full) == 32
    assert full[31].key == "key31"
    auto added = wire.update_tracestate(full, wire.TraceStateMember("extra", "value"))
    assert len(added) == 32
    assert added[0].key == "extra"
    assert added[31].key == "key30"
    auto moved = wire.update_tracestate(full, wire.TraceStateMember("key31", "updated"))
    assert len(moved) == 32
    assert moved[0].key == "key31"
    assert moved[31].key == "key30"
    with expect_raises(ValueError):
        wire.parse_tracestate(",".join(entries) + ",extra=value")

@test
def tracestate_enforces_key_value_and_total_size_limits():
    auto key = _repeat_text("k", 256)
    auto value = _repeat_text("v", 256)
    assert wire.format_tracestate(wire.parse_tracestate(key + "=" + value)) == key + "=" + value
    auto tenant = _repeat_text("1", 241) + "@" + _repeat_text("s", 14)
    assert wire.parse_tracestate(tenant + "=a")[0].key == tenant
    list[str] invalid = [
        "a=1,a=2",
        "UP=1",
        "9a=1",
        "a@9b=1",
        "a@@b=1",
        "=1",
        "a=",
        "a==1",
        "a",
        "a =1",
        "a=x\ty",
        "a=x\ny",
        "a=é",
        "a=" + value + "x",
        key + "x=y",
        _repeat_text("a", 242) + "@b=1",
        "a@" + _repeat_text("b", 15) + "=1",
        _repeat_text(" ", 32769),
    ]
    for header in invalid:
        with expect_raises(ValueError):
            wire.parse_tracestate(header)
