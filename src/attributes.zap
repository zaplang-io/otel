# Attribute values shared by resources, metrics, and tracing.
enum AttributeValue:
    Bool(bool value)
    Int(int64 value)
    Double(float64 value)
    Str(str value)
    BoolArray(list[bool] values)
    IntArray(list[int64] values)
    DoubleArray(list[float64] values)
    StrArray(list[str] values)

    def snapshot(self) -> AttributeValue:
        "Return an attribute with independent storage for any array payload."
        match self:
            case AttributeValue.BoolArray(values):
                return AttributeValue.BoolArray(_copy_array(values))
            case AttributeValue.IntArray(values):
                return AttributeValue.IntArray(_copy_array(values))
            case AttributeValue.DoubleArray(values):
                return AttributeValue.DoubleArray(_copy_array(values))
            case AttributeValue.StrArray(values):
                return AttributeValue.StrArray(_copy_array(values))
            case _:
                return self

def _copy_array[T](list[T] values) -> list[T]:
    list[T] copied = []
    for value in values:
        copied.append(value)
    return copied
