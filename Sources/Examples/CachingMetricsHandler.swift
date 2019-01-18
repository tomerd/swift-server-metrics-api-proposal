#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#else
import Glibc
#endif

@testable import CoreMetrics // because we need Locks
import Foundation
import protocol CoreMetrics.Timer // since otherwise conflicts with Foundation's

/// Not serious example; in reality implementations would themselves rather decide if they need to cache metric values or not.
// FIXME: proposing to remove this example, implementations should perform caching themselfes if they need to since they know their exact types.
public final class CachingMetricsHandler: MetricsHandler {
    private let wrapped: MetricsHandler
    private var counters = Cache<LabelledCounter>()
    private var recorders = Cache<LabelledRecorder>()
    private var timers = Cache<LabelledTimer>()

    public static func wrap(_ handler: MetricsHandler) -> CachingMetricsHandler {
        if let caching = handler as? CachingMetricsHandler {
            return caching
        } else {
            return CachingMetricsHandler(handler)
        }
    }

    private init(_ wrapped: MetricsHandler) {
        self.wrapped = wrapped
    }

    public func makeCounter(label: String, dimensions: [(String, String)]) -> Counter {
        let make = { (label: String, dimensions: [(String, String)]) -> LabelledCounter in
            let inner = self.wrapped.makeCounter(label: label, dimensions: dimensions)
            return LabelledCounter(label: label, counter: inner)
        }
        return self.counters.getOrSet(label: label, dimensions: dimensions, maker: make)
    }

    public func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> Recorder {
        let make  = { (label: String, dimensions: [(String, String)]) -> LabelledRecorder in
            let recorder = self.wrapped.makeRecorder(label: label, dimensions: dimensions, aggregate: aggregate)
            return LabelledRecorder(label: label, recorder: recorder)
        }
        return self.recorders.getOrSet(label: label, dimensions: dimensions, maker: make)
    }

    public func makeTimer(label: String, dimensions: [(String, String)]) -> Timer {
        let make = { (label: String, dimensions: [(String, String)]) -> LabelledTimer in
            let timer = self.wrapped.makeTimer(label: label, dimensions: dimensions)
            return LabelledTimer(label: label, timer: timer)
        }
        return self.timers.getOrSet(label: label, dimensions: dimensions, maker: make)
    }

    public func release<M: Metric>(metric: M) {
        print("release \(metric)")
        // in our caching implementation releasing means removing a metrics from the cache
        switch metric {
        case let m as LabelledCounter: self.counters.remove(label: m.label)
        case let m as LabelledRecorder : self.recorders.remove(label: m.label)
        case let m as LabelledTimer: self.timers.remove(label: m.label)
        default: break // others, if they existed, are not cached
        }
    }


    private class Cache<T> {
        private var items = [String: T]()
        // using a mutex is never ideal, we will need to explore optimization options
        // once we see how real life workloads behaves
        // for example, for short operations like hashmap lookup mutexes are worst than r/w locks in 99% reads, but better than them in mixed r/w mode
        private let lock = Lock()

        func getOrSet(label: String, dimensions: [(String, String)], maker: (String, [(String, String)]) -> T) -> T {
            let key = self.fqn(label: label, dimensions: dimensions)
            return self.lock.withLock {
                if let item = items[key] {
                    return item
                } else {
                    // since we need to be able to handle unregister we wrap using the label
                    // not the best way to deal with this, but we want to showcase how we could wrap/delegate
                    let item = maker(label, dimensions)
                    items[key] = item
                    return item
                }
            }
        }

        @discardableResult
        func remove(label: String) -> Bool {
            return self.lock.withLock {
                return self.items.removeValue(forKey: label) != nil
            }
        }

        private func fqn(label: String, dimensions: [(String, String)]) -> String {
            return [[label], dimensions.compactMap { "\($0.0).\($0.1)" }].flatMap { $0 }.joined(separator: ".")
        }
    }
}


/// An example of how a library may want to mark all of its `Metric` types in order to be able to suppose register/unregister-ing them.
internal protocol LabelledMetric: Metric {
    var label: String { get }
}

internal class LabelledCounter: LabelledMetric, Counter { // TODO: if we need wrappers then it would be useful to allow being a struct
    let _label: String
    let counter: Counter

    init(label: String, counter: Counter) {
        self._label = label
        self.counter = counter
    }

    var label: String {
        return self._label
    }

    func increment<DataType: BinaryInteger>(_ value: DataType) {
        self.counter.increment(value)
    }
}
internal class LabelledRecorder: LabelledMetric, Recorder {
    let _label: String
    let recorder: Recorder

    init(label: String, recorder: Recorder) {
        self._label = label
        self.recorder = recorder
    }

    var label: String {
        return self._label
    }

    func record<DataType: BinaryInteger>(_ value: DataType) {
        self.recorder.record(value)
    }

    func record<DataType: BinaryFloatingPoint>(_ value: DataType) {
        self.recorder.record(value)
    }
}
internal class LabelledTimer: LabelledMetric, Timer {
    let _label: String
    let timer: Timer

    init(label: String, timer: Timer) {
        self._label = label
        self.timer = timer
    }

    var label: String {
        return self._label
    }

    func recordNanoseconds(_ duration: Int64) {
        self.timer.recordNanoseconds(duration)
    }
}
