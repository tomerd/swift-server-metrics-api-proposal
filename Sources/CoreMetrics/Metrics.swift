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

public protocol CounterHandler: AnyObject {
    func increment<DataType: BinaryInteger>(_ value: DataType)
}

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
        let handler = MetricsSystem.handler.makeCounter(label: label, dimensions: dimensions)
        self.init(label: label, dimensions: dimensions, handler: handler)
    }
}

public extension Counter {
    @inlinable
    public static func `do`(label: String, dimensions: [(String, String)] = [], body: (Counter) -> Void) {
        body(Counter(label: label, dimensions: dimensions))
    }
}

public protocol RecorderHandler: AnyObject {
    func record<DataType: BinaryInteger>(_ value: DataType)
    func record<DataType: BinaryFloatingPoint>(_ value: DataType)
}

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
        let handler = MetricsSystem.handler.makeRecorder(label: label, dimensions: dimensions, aggregate: aggregate)
        self.init(label: label, dimensions: dimensions, aggregate: aggregate, handler: handler)
    }
}

public extension Recorder {
    @inlinable
    public static func `do`(label: String, dimensions: [(String, String)] = [], aggregate: Bool = true, body: (Recorder) -> Void) {
        body(Recorder(label: label, dimensions: dimensions, aggregate: aggregate))
    }
}

public class Gauge: Recorder {
    public convenience init(label: String, dimensions: [(String, String)] = []) {
        self.init(label: label, dimensions: dimensions, aggregate: false)
    }
}

public extension Gauge {
    @inlinable
    static func `do`(label: String, dimensions: [(String, String)] = [], body: (Gauge) -> Void) {
        body(Gauge(label: label, dimensions: dimensions))
    }
}

public protocol TimerHandler: AnyObject {
    func recordNanoseconds(_ duration: Int64)
}

public class Timer: TimerHandler {
    @usableFromInline
    var handler: TimerHandler
    public let label: String
    public let dimensions: [(String, String)]

    // this method is public to provide an escape hatch for situations one must use a custom factory instead of the gloabl one
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
        let handler = MetricsSystem.handler.makeTimer(label: label, dimensions: dimensions)
        self.init(label: label, dimensions: dimensions, handler: handler)
    }
}

public extension Timer {
    @inlinable
    public static func `do`(label: String, dimensions: [(String, String)] = [], body: (Timer) -> Void) {
        body(Timer(label: label, dimensions: dimensions))
    }
}

public protocol MetricsHandler {
    func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler
    func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> RecorderHandler
    func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler
}

// This is the metrics system itself, it's mostly used set the type of the `MetricsHandler` implementation.
public enum MetricsSystem {
    fileprivate static let lock = ReadWriteLock()
    fileprivate static var _handler: MetricsHandler = NOOPMetricsHandler.instance
    fileprivate static var initialized = false

    // Configures which `LogHandler` to use in the application.
    public static func bootstrap(_ handler: MetricsHandler) {
        self.lock.withWriterLock {
            precondition(!self.initialized, "metrics system can only be initialized once per process. currently used factory: \(self._handler)")
            self._handler = handler
            self.initialized = true
        }
    }

    // for our testing we want to allow multiple bootstraping
    internal static func bootstrapInternal(_ handler: MetricsHandler) {
        self.lock.withWriterLock {
            self._handler = handler
        }
    }

    internal static var handler: MetricsHandler {
        return self.lock.withReaderLock { self._handler }
    }
}

/// Ships with the metrics module, used to multiplex to multiple metrics handlers
public final class MultiplexMetricsHandler: MetricsHandler {
    private let handlers: [MetricsHandler]
    public init(handlers: [MetricsHandler]) {
        self.handlers = handlers
    }

    public func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler {
        return MuxCounter(handlers: self.handlers, label: label, dimensions: dimensions)
    }

    public func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> RecorderHandler {
        return MuxRecorder(handlers: self.handlers, label: label, dimensions: dimensions, aggregate: aggregate)
    }

    public func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler {
        return MuxTimer(handlers: self.handlers, label: label, dimensions: dimensions)
    }

    private class MuxCounter: CounterHandler {
        let counters: [CounterHandler]
        public init(handlers: [MetricsHandler], label: String, dimensions: [(String, String)]) {
            self.counters = handlers.map { $0.makeCounter(label: label, dimensions: dimensions) }
        }

        func increment<DataType: BinaryInteger>(_ value: DataType) {
            self.counters.forEach { $0.increment(value) }
        }
    }

    private class MuxRecorder: RecorderHandler {
        let recorders: [RecorderHandler]
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

    private class MuxTimer: TimerHandler {
        let timers: [TimerHandler]
        public init(handlers: [MetricsHandler], label: String, dimensions: [(String, String)]) {
            self.timers = handlers.map { $0.makeTimer(label: label, dimensions: dimensions) }
        }

        func recordNanoseconds(_ duration: Int64) {
            self.timers.forEach { $0.recordNanoseconds(duration) }
        }
    }
}

public final class NOOPMetricsHandler: MetricsHandler, CounterHandler, RecorderHandler, TimerHandler {
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
