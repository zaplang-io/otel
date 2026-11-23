import otel.attributes as attr
import otel.trace as trace

struct Recorder:
    str label
    list[str] calls
    bool fail = False

    def on_start(self, trace.Span span, Optional[trace.SpanContext] parent_context):
        assert span.is_recording()
        str parent = "root"
        match parent_context:
            case Optional.Some(context):
                assert context.is_valid()
                assert context.trace_id == span.get_span_context().trace_id
                parent = "child"
            case Optional.None:
                pass
        self.calls.append(self.label + ":start:" + span.name() + ":" + parent)
        span.set_attribute(self.label, attr.AttributeValue.Str("recorded"))
        if self.fail:
            raise ValueError("processor start failure")

    def on_end(self, trace.ReadableSpan span):
        assert span.end_time().is_some()
        assert self.label in span.attributes()
        assert span.get_span_context().is_valid()
        self.calls.append(self.label + ":end:" + span.name())
        if self.fail:
            raise ValueError("processor end failure")

@test
def processors_observe_nested_lifetimes_and_run_in_registration_order():
    list[str] calls = []
    auto provider = trace.TracerProvider()
    auto tracer = provider.get_tracer("processors")
    provider.add_span_processor(Recorder("first", calls))
    provider.add_span_processor(Recorder("second", calls))
    with tracer.start_as_current_span("root") as root:
        auto child = tracer.start_span("child")
        child.end()
        child.end()
        assert root.is_recording()
    assert calls == ["first:start:root:root", "second:start:root:root", "first:start:child:child", "second:start:child:child", "first:end:child", "second:end:child", "first:end:root", "second:end:root"]

@test
def processors_keep_registration_isolated_and_pair_start_with_end():
    list[str] initial = []
    list[str] late = []
    auto first = trace.TracerProvider()
    auto second = trace.TracerProvider()
    first.add_span_processor(Recorder("first", initial))
    second.add_span_processor(Recorder("second", late))
    auto tracer = first.get_tracer("first")
    auto span = tracer.start_span("old")
    first.add_span_processor(Recorder("late", late))
    span.end()
    assert initial == ["first:start:old:root", "first:end:old"]
    assert len(late) == 0
    tracer.start_span("new").end()
    assert late == ["late:start:new:root", "late:end:new"]
    second.get_tracer("second").start_span("independent").end()
    assert late == ["late:start:new:root", "late:end:new", "second:start:independent:root", "second:end:independent"]
    assert trace.get_tracer_provider().get_tracer("default").name() == "default"

@test
def processor_errors_do_not_break_later_callbacks_or_scope_cleanup():
    list[str] calls = []
    auto provider = trace.TracerProvider()
    provider.add_span_processor(Recorder("raising", calls, True))
    provider.add_span_processor(Recorder("healthy", calls))
    auto tracer = provider.get_tracer("test.errors")
    with expect_raises(ValueError):
        with tracer.start_as_current_span("throws") as span:
            assert span.is_recording()
            raise ValueError("body failure")
    assert trace.get_current_span().is_none()
    assert calls == ["raising:start:throws:root", "healthy:start:throws:root", "raising:end:throws", "healthy:end:throws"]
