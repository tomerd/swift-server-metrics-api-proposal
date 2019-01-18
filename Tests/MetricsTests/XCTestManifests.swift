import XCTest

extension MetricsExtensionsTests {
    static let __allTests = [
        ("testTimerBlock", testTimerBlock),
        ("testTimerWithDispatchTime", testTimerWithDispatchTime),
        ("testTimerWithTimeInterval", testTimerWithTimeInterval),
    ]
}

extension MetricsTests {
    static let __allTests = [
        ("testCaching", testCaching),
        ("testCachingWithDimensions", testCachingWithDimensions),
        ("testCounterBlock", testCounterBlock),
        ("testCounters", testCounters),
        ("testGauge", testGauge),
        ("testGaugeBlock", testGaugeBlock),
        ("testMUX", testMUX),
        ("testRecorderBlock", testRecorderBlock),
        ("testRecorders", testRecorders),
        ("testRecordersFloat", testRecordersFloat),
        ("testRecordersInt", testRecordersInt),
        ("testReleasingMetrics", testReleasingMetrics),
        ("testTimerBlock", testTimerBlock),
        ("testTimers", testTimers),
        ("testTimerVariants", testTimerVariants),
    ]
}

#if !os(macOS)
public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(MetricsExtensionsTests.__allTests),
        testCase(MetricsTests.__allTests),
    ]
}
#endif
