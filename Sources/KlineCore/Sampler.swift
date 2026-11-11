import Foundation

/// 一次采样：各指标的值，以及与上一次采样之间的事件次数（成交量）。
public struct Sample: Sendable {
    public var time: Double
    public var values: [String: Double]
    public var counts: [String: Double]
}

/// 把所有读取器组合起来。只能在同一个线程（串行队列）上调用。
public final class SystemSampler {
    public let coreKinds: [CoreKind]
    public let catalog: [MetricInfo]
    public let chip: String
    private let smc = SMCReader()
    private let cpu = CPUReader()
    private let mem = MemoryReader()
    private let net = NetworkReader()
    private let disk = DiskReader()
    private var lastTime: Double?

    public init() {
        coreKinds = CPUReader.coreKinds()
        chip = smc.chip
        catalog = Catalog.build(cores: coreKinds,
                                hasCPUTemp: !smc.cpuKeys.isEmpty,
                                hasGPUTemp: !smc.gpuKeys.isEmpty,
                                hasPower: smc.hasPower)
    }

    /// 温度读数用到的 SMC 键（给自检和 README 用）。
    public var temperatureKeys: (cpu: [String], gpu: [String]) { (smc.cpuKeys, smc.gpuKeys) }

    /// 采一次。第一次调用只记录基准，返回 nil。
    public func sample(now: Double = Date().timeIntervalSince1970) -> Sample? {
        let c = cpu.read()
        let m = mem.read()
        let n = net.read()
        let d = disk.read()
        defer { lastTime = now }
        guard let lt = lastTime, now > lt else { return nil }
        let dt = now - lt
        var v: [String: Double] = [:]
        var k: [String: Double] = [:]
        if let c {
            v[MetricID.cpu] = c.total
            k[MetricID.cpu] = c.interruptsTotal
            for (i, u) in c.perCore.enumerated() {
                v[MetricID.core(i)] = u
                if i < c.interruptsPerCore.count { k[MetricID.core(i)] = c.interruptsPerCore[i] }
            }
        }
        if let m {
            v[MetricID.mem] = m.percent
            if let f = m.faults { k[MetricID.mem] = f }
        }
        if let g = GPUReader.read() { v[MetricID.gpu] = g }
        if let n {
            v[MetricID.netIn] = n.bytesIn / dt / 1e6
            v[MetricID.netOut] = n.bytesOut / dt / 1e6
            k[MetricID.netIn] = n.packetsIn
            k[MetricID.netOut] = n.packetsOut
        }
        if let d {
            v[MetricID.diskRead] = d.bytesRead / dt / 1e6
            v[MetricID.diskWrite] = d.bytesWritten / dt / 1e6
            k[MetricID.diskRead] = d.opsRead
            k[MetricID.diskWrite] = d.opsWritten
        }
        if let t = smc.cpuTemperature { v[MetricID.cpuTemp] = t }
        if let t = smc.gpuTemperature { v[MetricID.gpuTemp] = t }
        if let p = smc.systemPower { v[MetricID.power] = p }
        if let pc = SystemReader.processCount() { v[MetricID.procs] = Double(pc) }
        if let l = SystemReader.loadAverage() { v[MetricID.load] = l }
        return Sample(time: now, values: v, counts: k)
    }
}
