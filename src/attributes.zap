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

    def __eq__(self, AttributeValue other) -> bool:
        match (self, other):
            case (AttributeValue.Bool(left), AttributeValue.Bool(right)):
                return left == right
            case (AttributeValue.Int(left), AttributeValue.Int(right)):
                return left == right
            case (AttributeValue.Double(left), AttributeValue.Double(right)):
                return left == right
            case (AttributeValue.Str(left), AttributeValue.Str(right)):
                return left == right
            case (AttributeValue.BoolArray(left), AttributeValue.BoolArray(right)):
                return left == right
            case (AttributeValue.IntArray(left), AttributeValue.IntArray(right)):
                return left == right
            case (AttributeValue.DoubleArray(left), AttributeValue.DoubleArray(right)):
                return left == right
            case (AttributeValue.StrArray(left), AttributeValue.StrArray(right)):
                return left == right
            case _:
                return False

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
