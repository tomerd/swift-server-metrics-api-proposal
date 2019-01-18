
public protocol Metric: AnyObject {
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

public extension MetricsHandler {
    func release<M: Metric>(metric: M) {
        // intentionally left empty, some metrics systems have no need to implement releasing
        // e.g. if they immediately send metrics off to another storage then they are stateless and don't need to "shut down"
    }
}

public enum Metrics {
    private static let lock = ReadWriteLock()
    private static var _handler: MetricsHandler = NOOPMetricsHandler.instance

    public static func bootstrap(_ handler: MetricsHandler) {
        self.lock.withWriterLockVoid {
            self._handler = handler
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
