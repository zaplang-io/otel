# Preserve integer precision until the chosen aggregation requires a double.
enum MetricNumber:
    Int(int64 value)
    Double(float64 value)
