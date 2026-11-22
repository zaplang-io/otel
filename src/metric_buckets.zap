import math

# Internal explicit bucket layout for the OpenTelemetry Metrics SDK.
struct HistogramBuckets:
    list[float64] _boundaries

    def boundaries(self) -> list[float64]:
        list[float64] result = []
        for boundary in self._boundaries:
            result.append(boundary)
        return result

    def bucket_index(self, float64 measurement) -> int64:
        if math.isnan(measurement) or math.isinf(measurement):
            raise ValueError("histogram measurement must be finite")
        auto lower = 0
        auto upper = len(self._boundaries)
        while lower < upper:
            auto middle = lower + (upper - lower) // 2
            if measurement <= self._boundaries[middle]:
                upper = middle
            else:
                lower = middle + 1
        return lower

def make_histogram_buckets(list[float64] boundaries) -> HistogramBuckets:
    list[float64] validated = []
    for boundary in boundaries:
        if math.isnan(boundary) or math.isinf(boundary):
            raise ValueError("histogram boundaries must be finite")
        auto count = len(validated)
        if count > 0 and boundary <= validated[count - 1]:
            raise ValueError("histogram boundaries must be strictly increasing")
        validated.append(boundary)
    return HistogramBuckets(validated)

def default_histogram_buckets() -> HistogramBuckets:
    # OpenTelemetry Metrics SDK, "Explicit Bucket Histogram Aggregation".
    return make_histogram_buckets(
        [
            0.0,
            5.0,
            10.0,
            25.0,
            50.0,
            75.0,
            100.0,
            250.0,
            500.0,
            750.0,
            1000.0,
            2500.0,
            5000.0,
            7500.0,
            10000.0,
        ],
    )
