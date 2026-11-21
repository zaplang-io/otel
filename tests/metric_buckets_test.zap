import math
import otel.metric_buckets as histogram

@test
def histogram_has_the_sdk_default_boundaries():
    auto buckets = histogram.default_histogram_buckets()
    auto boundaries = buckets.boundaries()
    assert boundaries == [0.0, 5.0, 10.0, 25.0, 50.0, 75.0, 100.0, 250.0, 500.0, 750.0, 1000.0, 2500.0, 5000.0, 7500.0, 10000.0]
    for index in range(len(boundaries)):
        assert buckets.bucket_index(boundaries[index]) == index
    assert buckets.bucket_index(10000.01) == 15

@test
def histogram_uses_inclusive_upper_bounds():
    auto buckets = histogram.make_histogram_buckets([-5.0, 0.0, 5.0])
    assert buckets.bucket_index(-5.5) == 0
    assert buckets.bucket_index(-5.0) == 0
    assert buckets.bucket_index(-4.5) == 1
    assert buckets.bucket_index(-0.0) == 1
    assert buckets.bucket_index(0.0) == 1
    assert buckets.bucket_index(0.5) == 2
    assert buckets.bucket_index(5.0) == 2
    assert buckets.bucket_index(5.5) == 3
    auto single = histogram.make_histogram_buckets([])
    assert single.bucket_index(-100.0) == 0
    assert single.bucket_index(100.0) == 0

@test
def histogram_layout_copies_boundaries_at_both_edges():
    list[float64] input = [0.0, 1.0]
    auto buckets = histogram.make_histogram_buckets(input)
    input[0] = -42.0
    auto output = buckets.boundaries()
    output[0] = 42.0
    assert buckets.boundaries() == [0.0, 1.0]
    assert buckets.bucket_index(0.0) == 0
    assert buckets.bucket_index(0.5) == 1

@test
def histogram_rejects_nonfinite_and_unordered_boundaries():
    list[list[float64]] invalid = [
        [0.0, -1.0],
        [1.0, 1.0],
        [-0.0, 0.0],
        [math.nan],
        [math.inf],
        [-math.inf],
        [0.0, math.nan],
    ]
    for boundaries in invalid:
        with expect_raises(ValueError):
            histogram.make_histogram_buckets(boundaries)

@test
def histogram_rejects_nonfinite_measurements():
    auto buckets = histogram.make_histogram_buckets([0.0])
    for measurement in [math.nan, math.inf, -math.inf]:
        with expect_raises(ValueError):
            buckets.bucket_index(measurement)
