@testable import CoreMetrics
@testable import protocol CoreMetrics.Timer
import Foundation

internal class TestMetrics: MetricsHandler {

    private let lock = NSLock() // TODO: consider lock per cache?
    private var _counters = Cache<TestCounter>()
    private var _recorders = Cache<TestRecorder>()
    private var _timers = Cache<TestTimer>()

    public func makeCounter(label: String, dimensions: [(String, String)]) -> Counter {
        return self._counters.getOrSet(label: label, dimensions: dimensions, maker: TestCounter.init)
    }

    public func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> Recorder {
        return self._recorders.getOrSet(label: label, dimensions: dimensions, maker: { l, dim in
            TestRecorder(label: l, dimensions: dim, aggregate: aggregate)
        })
    }

    public func makeTimer(label: String, dimensions: [(String, String)]) -> Timer {
        return self._timers.getOrSet(label: label, dimensions: dimensions, maker: TestTimer.init)
    }

    public func release<M: Metric>(metric: M) {
        // in our caching implementation releasing means removing a metrics from the cache
        switch metric {
        case let m as TestCounter: self._counters.remove(label: m.label)
        case let m as TestRecorder : self._recorders.remove(label: m.label)
        case let m as TestTimer: self._timers.remove(label: m.label)
        default: break // others, if they existed, are not cached
        }
    }
    
    subscript(counter label: String) -> Counter? {
        return self._counters.get(label: label, dimensions: [])
    }
    subscript(recorder label: String) -> Recorder? {
        return self._recorders.get(label: label, dimensions: [])
    }
    subscript(timer label: String) -> Timer? {
        return self._timers.get(label: label, dimensions: [])
    }

    private class Cache<T> {
        private var items = [String: T]()
        // using a mutex is never ideal, we will need to explore optimization options
        // once we see how real life workloads behaves
        // for example, for short operations like hashmap lookup mutexes are worst than r/w locks in 99% reads, but better than them in mixed r/w mode
        private let lock = Lock()


        func get(label: String, dimensions: [(String, String)]) -> T? {
            let key = self.fqn(label: label, dimensions: dimensions)
            return self.lock.withLock {
                return items[key]
            }
        }

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

internal class TestCounter: Counter, Equatable {
    let id: String
    let label: String
    let dimensions: [(String, String)]

    let lock = NSLock()
    var values = [(Date, Int64)]()

    init(label: String, dimensions: [(String, String)]) {
        self.id = NSUUID().uuidString
        self.label = label
        self.dimensions = dimensions
    }

    func increment<DataType: BinaryInteger>(_ value: DataType) {
        self.lock.withLock {
            self.values.append((Date(), Int64(value)))
        }
        print("adding \(value) to \(self.label)")
    }

    public static func == (lhs: TestCounter, rhs: TestCounter) -> Bool {
        return lhs.id == rhs.id
    }
}

internal class TestRecorder: Recorder, Equatable {
    let id: String
    let label: String
    let dimensions: [(String, String)]
    let aggregate: Bool

    let lock = NSLock()
    var values = [(Date, Double)]()

    init(label: String, dimensions: [(String, String)], aggregate: Bool) {
        self.id = NSUUID().uuidString
        self.label = label
        self.dimensions = dimensions
        self.aggregate = aggregate
    }

    func record<DataType: BinaryInteger>(_ value: DataType) {
        self.record(Double(value))
    }

    func record<DataType: BinaryFloatingPoint>(_ value: DataType) {
        self.lock.withLock {
            // this may loose percision but good enough as an example
            values.append((Date(), Double(value)))
        }
        print("recoding \(value) in \(self.label)")
    }

    public static func == (lhs: TestRecorder, rhs: TestRecorder) -> Bool {
        return lhs.id == rhs.id
    }
}

internal class TestTimer: Timer, Equatable {
    let id: String
    let label: String
    let dimensions: [(String, String)]

    let lock = NSLock()
    var values = [(Date, Int64)]()

    init(label: String, dimensions: [(String, String)]) {
        self.id = NSUUID().uuidString
        self.label = label
        self.dimensions = dimensions
    }

    func recordNanoseconds(_ duration: Int64) {
        self.lock.withLock {
            values.append((Date(), duration))
        }
        print("recoding \(duration) \(self.label)")
    }

    public static func == (lhs: TestTimer, rhs: TestTimer) -> Bool {
        return lhs.id == rhs.id
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        self.lock()
        defer {
            self.unlock()
        }
        return body()
    }
}
