import Foundation

public enum Tone: Sendable { case up, down, plain, muted }

public struct TapePart: Equatable, Sendable {
    public var text: String
    public var tone: Tone
    public init(_ text: String, _ tone: Tone) { self.text = text; self.tone = tone }
}

/// “逐笔成交”里的一条系统事件。
public struct TapeEvent: Identifiable, Equatable, Sendable {
    public var id: Int
    public var time: Double
    public var parts: [TapePart]
}

/// 从指标和进程变化里生成“逐笔成交”事件。
///
/// 规则和阈值是本项目自定的（行情软件没有对应标准可抄），写在这里集中管理：
/// - 指标异动：最新值和 5 秒前相比变化超过阈值，就记一条“拉升 / 回落”；同一指标 15 秒内只记一次。
/// - 进程：新出现 / 退出的进程各记一条，每次最多 3 条，其余合并成“另有 N 个”。
/// - 主力（CPU 前 10 的进程）：占用比上一次变化 ≥ 3 个百分点记一条。
public final class TapeEngine {
    public static let window = 5.0
    public static let cooldown = 15.0
    public static let thresholds: [String: Double] = [
        MetricID.cpu: 10, MetricID.gpu: 10, MetricID.mem: 2,
        MetricID.cpuTemp: 3, MetricID.gpuTemp: 3, MetricID.power: 5,
        MetricID.netIn: 2, MetricID.netOut: 2, MetricID.diskRead: 5, MetricID.diskWrite: 5,
    ]
    public static let processMove = 3.0
    public static let maxListed = 3

    private var lastFired: [String: Double] = [:]
    private var lastTop: [Int32: Double] = [:]
    private var nextID = 0

    public init() {}

    private func make(_ time: Double, _ parts: [TapePart]) -> TapeEvent {
        nextID += 1
        return TapeEvent(id: nextID, time: time, parts: parts)
    }

    public func metricEvents(time: Double, metrics: [MetricInfo], series: [String: Series]) -> [TapeEvent] {
        var out: [TapeEvent] = []
        for m in metrics {
            guard let th = Self.thresholds[m.id], let s = series[m.id], let now = s.last,
                  let before = s.value(atOrBefore: time - Self.window),
                  let t0 = s.times.first, time - t0 >= Self.window else { continue }
            let d = now - before
            guard abs(d) >= th else { continue }
            if let f = lastFired[m.id], time - f < Self.cooldown { continue }
            lastFired[m.id] = time
            let up = d > 0
            let verb: String
            switch m.unit {
            case "MB/s": verb = up ? "放量" : "缩量"
            case "°C": verb = up ? "升温" : "降温"
            default: verb = up ? "拉升" : "回落"
            }
            let text = "\(m.name)\(verb) \(Fmt.signed(d, m.decimals, m.changeUnit)) → \(Fmt.value(now, m.decimals))\(m.unit)"
            out.append(make(time, [TapePart(text, up ? .up : .down)]))
        }
        return out
    }

    public func processEvents(time: Double, snapshot: ProcessSnapshot) -> [TapeEvent] {
        var out: [TapeEvent] = []
        for (label, list) in [("新进", snapshot.started), ("退出", snapshot.exited)] where !list.isEmpty {
            for p in list.prefix(Self.maxListed) {
                out.append(make(time, [TapePart(label, .muted), TapePart(" \(p.name) · \(p.pid)", .plain)]))
            }
            if list.count > Self.maxListed {
                out.append(make(time, [TapePart(label, .muted), TapePart(" 另有 \(list.count - Self.maxListed) 个进程", .plain)]))
            }
        }
        for p in snapshot.top {
            if let before = lastTop[p.pid] {
                let d = p.cpu - before
                if abs(d) >= Self.processMove {
                    out.append(make(time, [TapePart("\(p.name) \(Fmt.value(p.cpu, 1))% ", .plain),
                                           TapePart((d > 0 ? "▲" : "▼") + Fmt.value(abs(d), 1), d > 0 ? .up : .down)]))
                }
            }
        }
        lastTop = Dictionary(uniqueKeysWithValues: snapshot.top.map { ($0.pid, $0.cpu) })
        return out
    }
}

/// 数字格式。负号用真正的减号 “−”（U+2212），和行情软件一致、与加号等宽。
public enum Fmt {
    public static func value(_ v: Double, _ decimals: Int) -> String {
        let s = String(format: "%.\(decimals)f", v)
        guard s.hasPrefix("-") else { return s }
        // 四舍五入后是 0 的负数（如 −0.0）显示成 0
        if Double(s) == 0 { return String(s.dropFirst()) }
        return "−" + s.dropFirst()
    }

    public static func signed(_ v: Double, _ decimals: Int, _ unit: String = "") -> String {
        let r = (v * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals))
        let sign = r > 0 ? "+" : (r < 0 ? "−" : "")
        return sign + String(format: "%.\(decimals)f", abs(r)) + unit
    }

    /// 成交量这类大数：1.2万、3.4亿。
    public static func count(_ v: Double) -> String {
        if v >= 1e8 { return String(format: "%.2f亿", v / 1e8) }
        if v >= 1e4 { return String(format: "%.1f万", v / 1e4) }
        return String(format: "%.0f", v)
    }

    private static let hms: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()
    private static let hm: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    public static func clock(_ t: Double, seconds: Bool = true) -> String {
        (seconds ? hms : hm).string(from: Date(timeIntervalSince1970: t))
    }

    public static func duration(_ s: Double) -> String {
        let n = Int(max(0, s))
        return String(format: "%02d:%02d:%02d", n / 3600, n / 60 % 60, n % 60)
    }
}
