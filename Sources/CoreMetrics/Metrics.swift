
public protocol Metric: AnyObject {
}

// FIXME this would NOT be in the proposal, a library would identify its metrics however it wants.
// This is needed to showcase how releasing generally works; NOT a full real implementation thereof and I'm not proposing adding this type.
internal protocol NamedMetric: Metric {
    var label: String { get }
}

public protocol Counter: Metric {
    func increment<DataType: BinaryInteger>(_ value: DataType)
}

public extension Counter {
    @inlinable
    func increment() {
        self.increment(1)
    }
}

public protocol Recorder: Metric {
    func record<DataType: BinaryInteger>(_ value: DataType)
    func record<DataType: BinaryFloatingPoint>(_ value: DataType)
}

public protocol Timer: Metric {
    func recordNanoseconds(_ duration: Int64)
}

public extension Timer {
    @inlinable
    func recordMicroseconds<DataType: BinaryInteger>(_ duration: DataType) {
        self.recordNanoseconds(Int64(duration) * 1000)
    }

    @inlinable
    func recordMicroseconds<DataType: BinaryFloatingPoint>(_ duration: DataType) {
        self.recordNanoseconds(Int64(duration * 1000))
    }

    @inlinable
    func recordMilliseconds<DataType: BinaryInteger>(_ duration: DataType) {
        self.recordNanoseconds(Int64(duration) * 1_000_000)
    }

    @inlinable
    func recordMilliseconds<DataType: BinaryFloatingPoint>(_ duration: DataType) {
        self.recordNanoseconds(Int64(duration * 1_000_000))
    }

    @inlinable
    func recordSeconds<DataType: BinaryInteger>(_ duration: DataType) {
        self.recordNanoseconds(Int64(duration) * 1_000_000_000)
    }

    @inlinable
    func recordSeconds<DataType: BinaryFloatingPoint>(_ duration: DataType) {
        self.recordNanoseconds(Int64(duration * 1_000_000_000))
    }
}

public protocol MetricsHandler {
    func makeCounter(label: String, dimensions: [(String, String)]) -> Counter
    func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> Recorder
    func makeTimer(label: String, dimensions: [(String, String)]) -> Timer

    /// Signal to the `MetricsHandler` that the passed in metric will no longer be updated.
    /// The handler MAY release some resources associated with this metric in response to this information.
    /// It is not required to act on this information immediately (or at all).
    ///
    /// Implementing `release` is optional, and one should refer to the underlying MetricsHandler for details (e.g. if releasing is a noop).
    ///
    /// Libraries instrumenting their own codebase with metrics should, as a best practice, call `release()` on metrics
    /// whenever sure that a given `Metric` will never be updated again, for example when the library can determine that a given metric
    /// will never be updated again (e.g. since the lifecycle of the resource the metric is concerned about has completed).
    /// It is expected and normal that certain kinds of metrics do not experience such lifecycle bound and remain alive for
    /// the entire lifetime of an application (e.g. global throughput metrics or similar).
    func release<M: Metric>(metric: M)
}
public extension MetricsHandler {
    func release<M: Metric>(metric: M) {
        // intentionally left empty, some metrics systems have no need to implement releasing
        // e.g. if they immediately send metrics off to another storage then they are stateless and don't need to "shut down"
    }
}

public extension MetricsHandler {
    @inlinable
    func makeCounter(label: String) -> Counter {
        return self.makeCounter(label: label, dimensions: [])
    }

    @inlinable
    func makeRecorder(label: String, aggregate: Bool = true) -> Recorder {
        return self.makeRecorder(label: label, dimensions: [], aggregate: aggregate)
    }

    @inlinable
    func makeTimer(label: String) -> Timer {
        return self.makeTimer(label: label, dimensions: [])
    }
}

public extension MetricsHandler {
    @inlinable
    func makeGauge(label: String, dimensions: [(String, String)] = []) -> Recorder {
        return self.makeRecorder(label: label, dimensions: dimensions, aggregate: false)
    }
}

public extension MetricsHandler {
    @inlinable
    func withCounter(label: String, dimensions: [(String, String)] = [], then: (Counter) -> Void) {
        then(self.makeCounter(label: label, dimensions: dimensions))
    }

    @inlinable
    func withRecorder(label: String, dimensions: [(String, String)] = [], aggregate: Bool = true, then: (Recorder) -> Void) {
        then(self.makeRecorder(label: label, dimensions: dimensions, aggregate: aggregate))
    }

    @inlinable
    func withTimer(label: String, dimensions: [(String, String)] = [], then: (Timer) -> Void) {
        then(self.makeTimer(label: label, dimensions: dimensions))
    }

    @inlinable
    func withGauge(label: String, dimensions: [(String, String)] = [], then: (Recorder) -> Void) {
        then(self.makeGauge(label: label, dimensions: dimensions))
    }
}

public enum Metrics {
    private static let lock = ReadWriteLock()
    private static var _handler: MetricsHandler = NOOPMetricsHandler.instance

    public static func bootstrap(_ handler: MetricsHandler) {
        self.lock.withWriterLockVoid {
            // using a wrapper to avoid redundant and potentially expensive factory calls
            self._handler = CachingMetricsHandler.wrap(handler) // TODO: I'd argue this is up to the handler implementation, some may not want this OR they can implement it better than a generic impl like we do here
        }
    }

    public static var global: MetricsHandler {
        return self.lock.withReaderLock { self._handler }
    }
}

public extension Metrics {
    @inlinable
    func makeCounter(label: String, dimensions: [(String, String)]) -> Counter {
        return Metrics.global.makeCounter(label: label, dimensions: dimensions)
    }
    @inlinable
    func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> Recorder {
        return Metrics.global.makeRecorder(label: label, dimensions: dimensions, aggregate: aggregate)
    }
    @inlinable
    func makeTimer(label: String, dimensions: [(String, String)]) -> Timer {
        return Metrics.global.makeTimer(label: label, dimensions: dimensions)
    }
}

private final class CachingMetricsHandler: MetricsHandler {
    private let wrapped: MetricsHandler
    private var counters = Cache<Counter>()
    private var recorders = Cache<Recorder>()
    private var timers = Cache<Timer>()

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
        return self.counters.getOrSet(label: label, dimensions: dimensions, maker: self.wrapped.makeCounter)
    }

    public func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> Recorder {
        let maker = { (label: String, dimensions: [(String, String)]) -> Recorder in
            self.wrapped.makeRecorder(label: label, dimensions: dimensions, aggregate: aggregate)
        }
        return self.recorders.getOrSet(label: label, dimensions: dimensions, maker: maker)
    }

    public func makeTimer(label: String, dimensions: [(String, String)]) -> Timer {
        return self.timers.getOrSet(label: label, dimensions: dimensions, maker: self.wrapped.makeTimer)
    }

    func release<M: Metric>(metric: M) {
        print("release \(metric)")
        // in our caching implementation releasing means removing a metrics from the cache
        // FIXME: just an example, I'd argue a metrics lib would have its own types and those would carry ID if they needed to release()
        switch metric {
        case let m as Counter & NamedMetric: self.counters.remove(label: m.label)
        case let m as Recorder & NamedMetric: self.recorders.remove(label: m.label)
        case let m as Timer & NamedMetric: self.timers.remove(label: m.label)
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

public final class MultiplexMetricsHandler: MetricsHandler {
    private let handlers: [MetricsHandler]
    public init(handlers: [MetricsHandler]) {
        self.handlers = handlers
    }

    public func makeCounter(label: String, dimensions: [(String, String)]) -> Counter {
        return MuxCounter(handlers: self.handlers, label: label, dimensions: dimensions)
    }

    public func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> Recorder {
        return MuxRecorder(handlers: self.handlers, label: label, dimensions: dimensions, aggregate: aggregate)
    }

    public func makeTimer(label: String, dimensions: [(String, String)]) -> Timer {
        return MuxTimer(handlers: self.handlers, label: label, dimensions: dimensions)
    }

    private class MuxCounter: Counter {
        let counters: [Counter]
        public init(handlers: [MetricsHandler], label: String, dimensions: [(String, String)]) {
            self.counters = handlers.map { $0.makeCounter(label: label, dimensions: dimensions) }
        }

        func increment<DataType: BinaryInteger>(_ value: DataType) {
            self.counters.forEach { $0.increment(value) }
        }
    }

    private class MuxRecorder: Recorder {
        let recorders: [Recorder]
        public init(handlers: [MetricsHandler], label: String, dimensions: [(String, String)], aggregate: Bool) {
            self.recorders = handlers.map { $0.makeRecorder(label: label, dimensions: dimensions, aggregate: aggregate) }
        }

        func record<DataType: BinaryInteger>(_ value: DataType) {
            self.recorders.forEach { $0.record(value) }
        }

        func record<DataType: BinaryFloatingPoint>(_ value: DataType) {
            self.recorders.forEach { $0.record(value) }
        }
    }

    private class MuxTimer: Timer {
        let timers: [Timer]
        public init(handlers: [MetricsHandler], label: String, dimensions: [(String, String)]) {
            self.timers = handlers.map { $0.makeTimer(label: label, dimensions: dimensions) }
        }

        func recordNanoseconds(_ duration: Int64) {
            self.timers.forEach { $0.recordNanoseconds(duration) }
        }
    }
}

public final class NOOPMetricsHandler: MetricsHandler, Counter, Recorder, Timer {
    public static let instance = NOOPMetricsHandler()

    private init() {}

    public func makeCounter(label: String, dimensions: [(String, String)]) -> Counter {
        return self
    }

    public func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> Recorder {
        return self
    }

    public func makeTimer(label: String, dimensions: [(String, String)]) -> Timer {
        return self
    }

    public func increment<DataType: BinaryInteger>(_: DataType) {}
    public func record<DataType: BinaryInteger>(_: DataType) {}
    public func record<DataType: BinaryFloatingPoint>(_: DataType) {}
    public func recordNanoseconds(_: Int64) {}
}
