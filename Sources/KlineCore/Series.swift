import Foundation

/// 一根 K 线：一个时间段内所有采样的 开 / 高 / 低 / 收，以及这段时间内的计数总和（成交量）。
public struct Candle: Equatable, Sendable {
    /// 时间段起点（Unix 秒，是周期的整数倍）。
    public var start: Double
    public var open: Double
    public var high: Double
    public var low: Double
    public var close: Double
    /// 这段时间内发生的事件次数之和；指标没有计数时为 nil。
    public var volume: Double?
    public var sampleCount: Int

    public init(start: Double, open: Double, high: Double, low: Double, close: Double, volume: Double?, sampleCount: Int) {
        self.start = start; self.open = open; self.high = high; self.low = low
        self.close = close; self.volume = volume; self.sampleCount = sampleCount
    }

    public var isUp: Bool { close >= open }
}

/// 一个指标的原始采样序列（按时间递增），保留最近一段时间。
public final class Series {
    public private(set) var times: [Double] = []
    public private(set) var values: [Double] = []
    /// 与上一个采样之间发生的事件次数；nil 表示没有计数。
    public private(set) var counts: [Double?] = []
    public let capacity: Int

    public init(capacity: Int) { self.capacity = capacity }

    public var isEmpty: Bool { values.isEmpty }
    public var last: Double? { values.last }

    public func append(time: Double, value: Double, count: Double?) {
        if let t = times.last, time <= t { return } // 时间必须递增
        times.append(time); values.append(value); counts.append(count)
        // 超出容量时成块删除，避免每次都整体搬移数组。
        let slack = max(64, capacity / 10)
        if times.count > capacity + slack {
            let drop = times.count - capacity
            times.removeFirst(drop); values.removeFirst(drop); counts.removeFirst(drop)
        }
    }

    /// 把采样按 `period` 秒对齐分桶，从最新往回取最多 `maxCount` 根 K 线（返回顺序：旧 → 新）。
    /// 没有采样的时间段（比如暂停期间）不生成空 K 线，和股票停牌时不画 K 线一样。
    public func candles(period: Double, maxCount: Int) -> [Candle] {
        precondition(period > 0)
        guard maxCount > 0, !values.isEmpty else { return [] }
        var out: [Candle] = []
        // 预留空间不能直接用 maxCount：调用方可能传 Int.max 表示“全部”（2026-11-10 因此崩过一次）。
        out.reserveCapacity(min(maxCount, values.count))
        var i = values.count - 1
        while i >= 0 && out.count < maxCount {
            let bucket = (times[i] / period).rounded(.down)
            var hi = values[i], lo = values[i]
            let close = values[i]
            var vol: Double? = nil
            var n = 0
            var j = i
            while j >= 0 && (times[j] / period).rounded(.down) == bucket {
                let v = values[j]
                if v > hi { hi = v }
                if v < lo { lo = v }
                if let c = counts[j] { vol = (vol ?? 0) + c }
                n += 1
                j -= 1
            }
            out.append(Candle(start: bucket * period, open: values[j + 1], high: hi, low: lo, close: close,
                              volume: vol, sampleCount: n))
            i = j
        }
        return out.reversed()
    }

    /// 按 `period` 秒分桶后一共有多少根 K 线（只数不生成，给滚动范围检查用）。
    public func candleCount(period: Double) -> Int {
        precondition(period > 0)
        var n = 0
        var last: Double?
        for t in times {
            let b = (t / period).rounded(.down)
            if b != last { n += 1; last = b }
        }
        return n
    }

    /// 时间 `t` 时（或之前最近一次）的采样值；比最早的采样还早时返回最早的值。
    public func value(atOrBefore t: Double) -> Double? {
        guard !times.isEmpty else { return nil }
        var lo = 0, hi = times.count - 1
        if times[0] > t { return values[0] }
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if times[mid] <= t { lo = mid } else { hi = mid - 1 }
        }
        return values[lo]
    }
}

/// 简单移动平均（收盘价），和行情软件的 MA 定义相同：MA(n) = 最近 n 根收盘价的算术平均。
/// 不足 n 根时为 nil。
public func movingAverage(_ closes: [Double], _ n: Int) -> [Double?] {
    guard n > 0 else { return closes.map { _ in nil } }
    var out = [Double?](repeating: nil, count: closes.count)
    var sum = 0.0
    for i in closes.indices {
        sum += closes[i]
        if i >= n { sum -= closes[i - n] }
        if i >= n - 1 { out[i] = sum / Double(n) }
    }
    return out
}
