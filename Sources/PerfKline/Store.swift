import Foundation
import Observation
import KlineCore

/// 全局状态：采样循环、历史数据、界面设置。只在主线程读写；采样在后台串行队列做。
@MainActor @Observable
final class Store {
    static let intervals: [Double] = [0.5, 1, 2, 5]
    static let periods: [Double] = [2, 5, 10, 30, 60]
    /// 保留 4 小时原始采样（按最快 0.5 秒算）。
    static let historySeconds = 4 * 3600.0
    /// 涨跌的参考点：10 分钟前的值。
    static let referenceSeconds = 600.0

    let catalog: [MetricInfo]
    let byID: [String: MetricInfo]
    let chip: String
    @ObservationIgnored let series: [String: Series]

    /// 每采样一次加 1，界面靠它刷新。
    private(set) var revision = 0
    private(set) var latest: [String: Double] = [:]
    private(set) var rank: [ProcessRow] = []
    private(set) var tape: [TapeEvent] = []
    private(set) var lastSampleTime = Date().timeIntervalSince1970
    let startTime = Date().timeIntervalSince1970

    var selected: String { didSet { UserDefaults.standard.set(selected, forKey: "selected"); chartScrollBack = 0 } }
    var period: Double { didSet { UserDefaults.standard.set(period, forKey: "period"); chartScrollBack = 0 } }
    var interval: Double { didSet { UserDefaults.standard.set(interval, forKey: "interval"); restartTimer() } }
    var redUp: Bool { didSet { UserDefaults.standard.set(redUp, forKey: "redUp"); onChange?() } }
    var pinned: Bool { didSet { UserDefaults.standard.set(pinned, forKey: "pinned"); onPinChange?(pinned) } }
    var menubarMetric: String { didSet { UserDefaults.standard.set(menubarMetric, forKey: "menubarMetric"); onChange?() } }
    var paused = false { didSet { restartTimer() } }

    /// K 线图：每根 K 线占的宽度（像素）和往回翻了多少根。
    var chartStep: Double = 9
    var chartScrollBack: Double = 0
    /// 只给 --snapshot 自检用：模拟鼠标悬停位置。
    var debugHover: CGPoint?

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onPinChange: ((Bool) -> Void)?

    @ObservationIgnored private let sampler: SystemSampler
    @ObservationIgnored private let procSampler = ProcessSampler()
    @ObservationIgnored private let tapeEngine = TapeEngine()
    @ObservationIgnored private let queue = DispatchQueue(label: "perfkline.sampler", qos: .utility)
    @ObservationIgnored private var timer: DispatchSourceTimer?

    init() {
        sampler = SystemSampler()
        catalog = sampler.catalog
        chip = sampler.chip
        byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        var s: [String: Series] = [:]
        for m in catalog { s[m.id] = Series(capacity: Int(Self.historySeconds / Self.intervals[0])) }
        series = s

        let d = UserDefaults.standard
        let sel = d.string(forKey: "selected") ?? MetricID.cpu
        selected = byID[sel] != nil ? sel : MetricID.cpu
        let p = d.double(forKey: "period")
        period = Self.periods.contains(p) ? p : 5
        let iv = d.double(forKey: "interval")
        interval = Self.intervals.contains(iv) ? iv : 1
        redUp = d.object(forKey: "redUp") as? Bool ?? true
        pinned = d.bool(forKey: "pinned")
        let mb = d.string(forKey: "menubarMetric") ?? MetricID.cpu
        menubarMetric = byID[mb] != nil ? mb : MetricID.cpu
        if period < interval { period = Self.periods.first { $0 >= interval } ?? 60 }
    }

    var colors: Colors { Colors(redUp: redUp) }
    var selectedMetric: MetricInfo { byID[selected] ?? catalog[0] }

    // MARK: 采样循环

    func start() { restartTimer() }

    private func restartTimer() {
        timer?.cancel()
        timer = nil
        guard !paused else { return }
        let sampler = self.sampler
        let procSampler = self.procSampler
        let interval = self.interval
        // 暂停或改间隔后，第一次采样只当基准，不然会把整段暂停时间平均成一根。
        queue.async { _ = sampler.sample() }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(20))
        // 进程排行每 2 秒刷新一次就够了（每次调用 ps 约 26 毫秒，太频繁会抬高 CPU 占用本身）。
        let procEvery = max(2.0, interval)
        var lastProc = 0.0
        t.setEventHandler { [weak self] in
            let now = Date().timeIntervalSince1970
            let sample = sampler.sample(now: now)
            var procs: ProcessSnapshot?
            if now - lastProc >= procEvery - 0.05 {
                procs = procSampler.sample(now: now)
                lastProc = now
            }
            DispatchQueue.main.async { self?.ingest(sample, procs) }
        }
        timer = t
        t.resume()
    }

    private func ingest(_ sample: Sample?, _ procs: ProcessSnapshot?) {
        var events: [TapeEvent] = []
        if let sample {
            for m in catalog {
                guard let v = sample.values[m.id] else { continue }
                series[m.id]?.append(time: sample.time, value: v, count: sample.counts[m.id])
                latest[m.id] = v
            }
            lastSampleTime = sample.time
            events += tapeEngine.metricEvents(time: sample.time, metrics: catalog, series: series)
        }
        if let procs {
            rank = procs.top
            events += tapeEngine.processEvents(time: Date().timeIntervalSince1970, snapshot: procs)
        }
        if !events.isEmpty {
            tape.insert(contentsOf: events.reversed(), at: 0)
            if tape.count > 300 { tape.removeLast(tape.count - 300) }
        }
        revision += 1
        onChange?()
    }

    // MARK: 读数

    /// 涨跌参考值：10 分钟前的采样（不足 10 分钟时用最早的采样）。
    func reference(_ id: String) -> Double? {
        series[id]?.value(atOrBefore: lastSampleTime - Self.referenceSeconds)
    }

    func change(_ id: String) -> Double? {
        guard let v = latest[id], let r = reference(id) else { return nil }
        return v - r
    }

    func candles(_ id: String, count: Int, period: Double? = nil) -> [Candle] {
        series[id]?.candles(period: period ?? self.period, maxCount: count) ?? []
    }

    func selectNext(_ delta: Int) {
        guard let i = catalog.firstIndex(where: { $0.id == selected }) else { return }
        let ordered = displayOrder
        guard let j = ordered.firstIndex(of: catalog[i].id) else { return }
        let k = min(max(0, j + delta), ordered.count - 1)
        selected = ordered[k]
    }

    /// 自选列表的显示顺序（按分组）。
    var displayOrder: [String] {
        MetricGroup.allCases.flatMap { g in catalog.filter { $0.group == g }.map(\.id) }
    }
}
