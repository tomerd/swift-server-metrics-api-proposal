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
//
// THIS IS NOT PART OF THE PITCH, JUST AN EXAMPLE
//

import Metrics

class SimpleMetricsLibrary: MetricsFactory {
    init() {}

    func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler {
        return ExampleCounter(label, dimensions)
    }

    func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> RecorderHandler {
        let maker: (String, [(String, String)]) -> RecorderHandler = aggregate ? ExampleRecorder.init : ExampleGauge.init
        return maker(label, dimensions)
    }

    func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler {
        return ExampleTimer(label, dimensions)
    }

    private class ExampleCounter: CounterHandler {
        init(_: String, _: [(String, String)]) {}

        let lock = NSLock()
        var value: Int64 = 0
        func increment(_ value: Int64) {
            self.lock.withLock {
                self.value += value
            }
        }

        func reset() {
            self.lock.withLock {
                self.value = 0
            }
        }
    }

    private class ExampleRecorder: RecorderHandler {
        init(_: String, _: [(String, String)]) {}

        private let lock = NSLock()
        var values = [(Int64, Double)]()
        func record(_ value: Int64) {
            self.record(Double(value))
        }

        func record(_ value: Double) {
            // TODO: sliding window
            self.lock.withLock {
                values.append((Date().nanoSince1970, value))
                self._count += 1
                self._sum += value
                self._min = Swift.min(self._min, value)
                self._max = Swift.max(self._max, value)
            }
        }

        var _sum: Double = 0
        var sum: Double {
            return self.lock.withLock { _sum }
        }

        private var _count: Int = 0
        var count: Int {
            return self.lock.withLock { _count }
        }

        private var _min: Double = 0
        var min: Double {
            return self.lock.withLock { _min }
        }

        private var _max: Double = 0
        var max: Double {
            return self.lock.withLock { _max }
        }
    }

    private class ExampleGauge: RecorderHandler {
        init(_: String, _: [(String, String)]) {}

        let lock = NSLock()
        var _value: Double = 0
        func record(_ value: Int64) {
            self.record(Double(value))
        }

        func record(_ value: Double) {
            self.lock.withLock { _value = value }
        }
    }

    private class ExampleTimer: ExampleRecorder, TimerHandler {
        func recordNanoseconds(_ duration: Int64) {
            super.record(duration)
        }
    }
}

private extension Foundation.Date {
    var nanoSince1970: Int64 {
        return Int64(self.timeIntervalSince1970 * 1_000_000_000)
    }
}

private extension Foundation.NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        self.lock()
        defer {
            self.unlock()
        }
        return body()
    }
}
