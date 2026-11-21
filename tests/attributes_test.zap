import otel.attributes as attr

@test
def attribute_scalars_retain_their_types():
    auto flag = attr.AttributeValue.Bool(False)
    auto count = attr.AttributeValue.Int(9007199254740993)
    auto ratio = attr.AttributeValue.Double(1.25)
    auto text = attr.AttributeValue.Str("café")
    match flag:
        case attr.AttributeValue.Bool(value):
            assert value == False
        case _:
            assert False
    match count:
        case attr.AttributeValue.Int(value):
            assert value == 9007199254740993
        case _:
            assert False
    match ratio:
        case attr.AttributeValue.Double(value):
            assert value == 1.25
        case _:
            assert False
    match text:
        case attr.AttributeValue.Str(value):
            assert value == "café"
        case _:
            assert False

@test
def attribute_arrays_retain_their_element_types():
    auto flags = attr.AttributeValue.BoolArray([True, False])
    auto counts = attr.AttributeValue.IntArray([9007199254740993, -1])
    auto ratios = attr.AttributeValue.DoubleArray([1.25, -2.5])
    auto texts = attr.AttributeValue.StrArray([])
    match flags:
        case attr.AttributeValue.BoolArray(values):
            assert len(values) == 2
            assert values[0] == True
            assert values[1] == False
        case _:
            assert False
    match counts:
        case attr.AttributeValue.IntArray(values):
            assert values[0] == 9007199254740993
            assert values[1] == -1
        case _:
            assert False
    match ratios:
        case attr.AttributeValue.DoubleArray(values):
            assert values[0] == 1.25
            assert values[1] == -2.5
        case _:
            assert False
    match texts:
        case attr.AttributeValue.StrArray(values):
            assert len(values) == 0
        case _:
            assert False
