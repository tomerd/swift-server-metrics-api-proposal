//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Metrics API open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Metrics API project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Metrics API project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

public protocol MetricHandler: AnyObject {
}

/// This is the Counter protocol a metrics library implements. It must have reference semantics
public protocol CounterHandler: MetricHandler {
    func increment<DataType: BinaryInteger>(_ value: DataType)
}

// This is the user facing Counter API. It must have reference semantics, and its behavior depend ons the `CounterHandler` implementation
public class Counter: CounterHandler {
    @usableFromInline
    var handler: CounterHandler
    public let label: String
    public let dimensions: [(String, String)]

    // this method is public to provide an escape hatch for situations one must use a custom factory instead of the gloabl one
    // we do not expect this API to be used in normal circumstances, so if you find yourself using it make sure its for a good reason
    public init(label: String, dimensions: [(String, String)], handler: CounterHandler) {
        self.label = label
        self.dimensions = dimensions
        self.handler = handler
    }

    @inlinable
    public func increment<DataType: BinaryInteger>(_ value: DataType) {
        self.handler.increment(value)
    }

    @inlinable
    public func increment() {
        self.increment(1)
    }
}

public extension Counter {
    public convenience init(label: String, dimensions: [(String, String)] = []) {
        let handler = MetricsSystem.factory.makeCounter(label: label, dimensions: dimensions)
        self.init(label: label, dimensions: dimensions, handler: handler)
    }
}

/// This is the Recorder protocol a metrics library implements. It must have reference semantics
public protocol RecorderHandler: MetricHandler {
    func record<DataType: BinaryInteger>(_ value: DataType)
    func record<DataType: BinaryFloatingPoint>(_ value: DataType)
}

// This is the user facing Recorder API. It must have reference semantics, and its behavior depend ons the `RecorderHandler` implementation
public class Recorder: RecorderHandler {
    @usableFromInline
    var handler: RecorderHandler
    public let label: String
    public let dimensions: [(String, String)]
    public let aggregate: Bool

    // this method is public to provide an escape hatch for situations one must use a custom factory instead of the gloabl one
    // we do not expect this API to be used in normal circumstances, so if you find yourself using it make sure its for a good reason
    public init(label: String, dimensions: [(String, String)], aggregate: Bool, handler: RecorderHandler) {
        self.label = label
        self.dimensions = dimensions
        self.aggregate = aggregate
        self.handler = handler
    }

    @inlinable
    public func record<DataType: BinaryInteger>(_ value: DataType) {
        self.handler.record(value)
    }

    @inlinable
    public func record<DataType: BinaryFloatingPoint>(_ value: DataType) {
        self.handler.record(value)
    }
}

public extension Recorder {
    public convenience init(label: String, dimensions: [(String, String)] = [], aggregate: Bool = true) {
        let handler = MetricsSystem.factory.makeRecorder(label: label, dimensions: dimensions, aggregate: aggregate)
        self.init(label: label, dimensions: dimensions, aggregate: aggregate, handler: handler)
    }
}

// A Gauge is a convenience for non-aggregating Recorder
public class Gauge: Recorder {
    public convenience init(label: String, dimensions: [(String, String)] = []) {
        self.init(label: label, dimensions: dimensions, aggregate: false)
    }
}

// This is the Timer protocol a metrics library implements. It must have reference semantics
public protocol TimerHandler: MetricHandler {
    func recordNanoseconds(_ duration: Int64)
}

// This is the user facing Timer API. It must have reference semantics, and its behavior depend ons the `RecorderHandler` implementation
public class Timer: TimerHandler {
    @usableFromInline
    var handler: TimerHandler
    public let label: String
    public let dimensions: [(String, String)]

    // this method is public to provide an escape hatch for situations one must use a custom factory instead of the global one
    // we do not expect this API to be used in normal circumstances, so if you find yourself using it make sure its for a good reason
    public init(label: String, dimensions: [(String, String)], handler: TimerHandler) {
        self.label = label
        self.dimensions = dimensions
        self.handler = handler
    }

    @inlinable
    public func recordNanoseconds(_ duration: Int64) {
        self.handler.recordNanoseconds(duration)
    }

    @inlinable
    public func recordMicroseconds<DataType: BinaryInteger>(_ duration: DataType) {
        self.recordNanoseconds(Int64(duration) * 1000)
    }

    @inlinable
    public func recordMicroseconds<DataType: BinaryFloatingPoint>(_ duration: DataType) {
        self.recordNanoseconds(Int64(duration * 1000))
    }

    @inlinable
    public func recordMilliseconds<DataType: BinaryInteger>(_ duration: DataType) {
        self.recordNanoseconds(Int64(duration) * 1_000_000)
    }

    @inlinable
    public func recordMilliseconds<DataType: BinaryFloatingPoint>(_ duration: DataType) {
        self.recordNanoseconds(Int64(duration * 1_000_000))
    }

    @inlinable
    public func recordSeconds<DataType: BinaryInteger>(_ duration: DataType) {
        self.recordNanoseconds(Int64(duration) * 1_000_000_000)
    }

    @inlinable
    public func recordSeconds<DataType: BinaryFloatingPoint>(_ duration: DataType) {
        self.recordNanoseconds(Int64(duration * 1_000_000_000))
    }
}

public extension Timer {
    public convenience init(label: String, dimensions: [(String, String)] = []) {
        let handler = MetricsSystem.factory.makeTimer(label: label, dimensions: dimensions)
        self.init(label: label, dimensions: dimensions, handler: handler)
    }
}

public protocol MetricsFactory {
    func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler
    func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> RecorderHandler
    func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler

    /// Signals the `MetricsFactory` that the passed in `MetricHandler` will no longer be updated.
    /// Implementing this functionality is _optional_, and depends on the semantics of the concrete `MetricsFactory`.
    ///
    /// In response to this call, the factory _may_ release resources associated with this metric,
    /// e.g. in case the metric contains references to "heavy" resources, such as file handles, connections,
    /// or large in-memory data structures.
    ///
    /// **Intended usage:**
    ///
    /// Metrics library implementations are _not_ required to act on this signal immediately (or at all).
    /// However, the presence of this API allows middle-ware libraries wanting to emit metrics for resources with
    /// well-defined life-cycles to behave pro-actively, and signal when a given metric is known to not be used anymore,
    /// which can make an positive impact with regards to resource utilization in case of metrics libraries which keep
    /// references to "heavy" resources.
    ///
    /// It is expected that some metrics libraries, may choose to omit implementing this functionality.
    /// One such example may be a library which directly emits recorded values to some underlying shared storage engine,
    /// which means that the `MetricHandler` objects themselves are light-weight by nature, and thus no lifecycle
    /// management and releasing of such metrics handlers is necessary.
    ///
    /// **Concurrency:**
    ///
    /// This function MAY be invoked concurrently, and implementations should take care to use appropriate
    /// synchronization mechanisms where necessary.
    func release<M: MetricHandler>(metric: M)
}

extension MetricsFactory {
    public func release<M: MetricHandler>(metric: M) {
        // no-op by default.
        // Libraries which do maintain metric lifecycle should implement this method.
    }
}

// This is the metrics system itself, it's mostly used set the type of the `MetricsFactory` implementation
public enum MetricsSystem {
    fileprivate static let lock = ReadWriteLock()
    fileprivate static var _factory: MetricsFactory = NOOPMetricsHandler.instance
    fileprivate static var initialized = false

    // Configures which `LogHandler` to use in the application.
    public static func bootstrap(_ factory: MetricsFactory) {
        self.lock.withWriterLock {
            precondition(!self.initialized, "metrics system can only be initialized once per process. currently used factory: \(self.factory)")
            self._factory = factory
            self.initialized = true
        }
    }

    // for our testing we want to allow multiple bootstraping
    internal static func bootstrapInternal(_ factory: MetricsFactory) {
        self.lock.withWriterLock {
            self._factory = factory
        }
    }

    /// Signals the underlying `MetricsFactory` that the passed in `MetricHandler` will no longer be updated.
    /// Implementing this functionality by metrics factories is _optional_, and depends on the underlying semantics of the factory.
    ///
    /// - Parameter metric: metric object to be released by underlying metrics factory
    /// - SeeAlso: `MetricsFactory.release` for more details.
    public static func release<M: MetricHandler>(metric: M) {
        self.lock.withReaderLockVoid {
            self._factory.release(metric: metric)
        }
    }

    public static var factory: MetricsFactory {
        return self.lock.withReaderLock { self._factory }
    }
}

/// Ships with the metrics module, used to multiplex to multiple metrics handlers
public final class MultiplexMetricsHandler: MetricsFactory {
    private let factories: [MetricsFactory]
    public init(factories: [MetricsFactory]) {
        self.factories = factories
    }

    public func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler {
        return MuxCounter(factories: self.factories, label: label, dimensions: dimensions)
    }

    public func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> RecorderHandler {
        return MuxRecorder(factories: self.factories, label: label, dimensions: dimensions, aggregate: aggregate)
    }

    public func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler {
        return MuxTimer(factories: self.factories, label: label, dimensions: dimensions)
    }


    public func release<M: MetricHandler>(metric: M) {
        self.factories.forEach { factory in
            factory.release(metric: metric)
        }
    }

    private class MuxCounter: CounterHandler {
        let counters: [CounterHandler]
        public init(factories: [MetricsFactory], label: String, dimensions: [(String, String)]) {
            self.counters = factories.map { $0.makeCounter(label: label, dimensions: dimensions) }
        }

        func increment<DataType: BinaryInteger>(_ value: DataType) {
            self.counters.forEach { $0.increment(value) }
        }
    }

    private class MuxRecorder: RecorderHandler {
        let recorders: [RecorderHandler]
        public init(factories: [MetricsFactory], label: String, dimensions: [(String, String)], aggregate: Bool) {
            self.recorders = factories.map { $0.makeRecorder(label: label, dimensions: dimensions, aggregate: aggregate) }
        }

        func record<DataType: BinaryInteger>(_ value: DataType) {
            self.recorders.forEach { $0.record(value) }
        }

        func record<DataType: BinaryFloatingPoint>(_ value: DataType) {
            self.recorders.forEach { $0.record(value) }
        }
    }

    private class MuxTimer: TimerHandler {
        let timers: [TimerHandler]
        public init(factories: [MetricsFactory], label: String, dimensions: [(String, String)]) {
            self.timers = factories.map { $0.makeTimer(label: label, dimensions: dimensions) }
        }

        func recordNanoseconds(_ duration: Int64) {
            self.timers.forEach { $0.recordNanoseconds(duration) }
        }
    }
}

public final class NOOPMetricsHandler: MetricsFactory, CounterHandler, RecorderHandler, TimerHandler {
    public static let instance = NOOPMetricsHandler()

    private init() {}

    public func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler {
        return self
    }

    public func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> RecorderHandler {
        return self
    }

    public func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler {
        return self
    }

    public func increment<DataType: BinaryInteger>(_: DataType) {}
    public func record<DataType: BinaryInteger>(_: DataType) {}
    public func record<DataType: BinaryFloatingPoint>(_: DataType) {}
    public func recordNanoseconds(_: Int64) {}
}
