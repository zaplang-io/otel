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
