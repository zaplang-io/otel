import otel.trace as trace

def _active_span() -> trace.Span:
    match trace.get_current_span():
        case Optional.Some(span):
            return span
        case Optional.None:
            raise ValueError("expected an active span")

def _parent(trace.Span span) -> trace.SpanContext:
    match span.parent_context():
        case Optional.Some(parent):
            return parent
        case Optional.None:
            raise ValueError("expected a parent context")

@test
def tracing_nested_scopes_link_and_restore_parent_spans():
    auto tracer = trace.get_tracer("app")
    assert tracer.name() == "app"
    assert trace.get_current_span().is_none()
    list[trace.Span] spans = []
    with tracer.start_as_current_span("root", kind=trace.SpanKind.Server) as root:
        spans.append(root)
        assert _active_span() is root
        assert root.parent_context().is_none()
        assert root.name() == "root"
        assert root.kind() == trace.SpanKind.Server
        auto root_context = root.get_span_context()
        assert root_context.is_valid()
        assert root_context.is_sampled()
        assert not root_context.is_remote
        with tracer.start_as_current_span("child", kind=trace.SpanKind.Client) as child:
            spans.append(child)
            assert _active_span() is child
            auto child_context = child.get_span_context()
            assert child_context.trace_id == root_context.trace_id
            assert child_context.span_id != root_context.span_id
            assert child_context.trace_flags == root_context.trace_flags
            assert _parent(child).span_id == root_context.span_id
        assert not spans[1].is_recording()
        assert _active_span() is root
        assert root.is_recording()
    assert not spans[0].is_recording()
    assert trace.get_current_span().is_none()

@test
def tracing_unwind_ends_the_inner_span_and_restores_the_outer_binding():
    auto tracer = trace.get_tracer("test.unwind")
    with tracer.start_as_current_span("outer") as outer:
        list[trace.Span] failed = []
        with expect_raises(ValueError):
            with tracer.start_as_current_span("failing") as inner:
                failed.append(inner)
                raise ValueError("body failed")
        assert len(failed) == 1
        assert not failed[0].is_recording()
        assert _active_span() is outer
    assert trace.get_current_span().is_none()

def _child_context(trace.Tracer tracer, channel[str] output):
    output <- _active_span().name()
    with tracer.start_as_current_span("child") as child:
        output <- _active_span().name()
    output <- _active_span().name()

@test
def tracing_coroutine_inherits_and_restores_its_own_binding():
    auto tracer = trace.get_tracer("test.coroutines")
    auto output = channel[str](3)
    with tracer.start_as_current_span("parent") as parent:
        scope:
            spawn _child_context(tracer, output)
        assert <-output == "parent"
        assert <-output == "child"
        assert <-output == "parent"
        assert _active_span() is parent
    assert trace.get_current_span().is_none()

@test
def tracing_detached_spans_keep_the_current_binding_and_end_once():
    auto tracer = trace.TracerProvider().get_tracer("test.detached")
    with tracer.start_as_current_span("parent", kind=trace.SpanKind.Producer) as parent:
        auto detached = tracer.start_span("detached", kind=trace.SpanKind.Consumer)
        assert _active_span() is parent
        assert _parent(detached).span_id == parent.get_span_context().span_id
        assert detached.kind() == trace.SpanKind.Consumer
        assert detached.start_time() > 0
        assert detached.end_time().is_none()
        detached.end()
        auto first_time = detached.end_time().unwrap()
        assert first_time >= detached.start_time()
        detached.end()
        assert detached.end_time().unwrap() == first_time
        assert _active_span() is parent
        assert tracer.start_span("default kind").kind() == trace.SpanKind.Internal

@test
def tracing_rejects_missing_tracer_names_and_detects_invalid_contexts():
    for name in ["", "  ", "\t"]:
        with expect_raises(ValueError):
            trace.get_tracer(name)
    auto valid = trace.get_tracer("test.context").start_span("span")
    auto context = valid.get_span_context()
    assert context.is_valid()
    assert not trace.SpanContext("", context.span_id, 1, "", False).is_valid()
    assert not trace.SpanContext(context.trace_id, "0000000000000000", 1, "", False).is_valid()
    assert not trace.SpanContext(context.trace_id, context.span_id, 256, "", False).is_valid()
    assert not trace.SpanContext(context.trace_id, context.span_id, 1, "a=1,a=2", False).is_valid()
    assert trace.SpanContext(context.trace_id, context.span_id, 0, "a=1", True).is_valid()
    assert not trace.SpanContext(context.trace_id, context.span_id, 0, "", True).is_sampled()
    valid.end()
