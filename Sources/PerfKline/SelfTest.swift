import Foundation
import KlineCore

/// `PerfKline --selftest 秒数`：每秒打印一行原始读数，用来和 top / netstat / iostat 对照。
enum SelfTest {
    static func run(seconds: Int) {
        let s = SystemSampler()
        let ps = ProcessSampler()
        print("chip=\(s.chip) cores=\(s.coreKinds.map { $0 == .efficiency ? "E" : "P" }.joined()) cpuKeys=\(s.temperatureKeys.cpu) gpuKeys=\(s.temperatureKeys.gpu)")
        print("metrics=\(s.catalog.map(\.name).joined(separator: ","))")
        _ = s.sample()
        _ = ps.sample()
        print("READY \(Fmt.clock(Date().timeIntervalSince1970))")
        var sumCPU = 0.0, sumNet = 0.0, sumDisk = 0.0, n = 0
        var prev = Date().timeIntervalSince1970
        for _ in 0..<seconds {
            Thread.sleep(forTimeInterval: 1)
            let now = Date().timeIntervalSince1970
            guard let x = s.sample(now: now) else { continue }
            let v = x.values
            func f(_ k: String, _ d: Int = 1) -> String { v[k].map { String(format: "%.\(d)f", $0) } ?? "-" }
            let top = ps.sample(now: now)?.top.prefix(3).map { "\($0.name)=\(String(format: "%.0f", $0.cpu))" }.joined(separator: " ") ?? ""
            print("\(Fmt.clock(now)) cpu=\(f(MetricID.cpu)) irq=\(Int(x.counts[MetricID.cpu] ?? 0)) gpu=\(f(MetricID.gpu)) mem=\(f(MetricID.mem)) faults=\(Int(x.counts[MetricID.mem] ?? 0)) net=\(f(MetricID.netIn, 3))/\(f(MetricID.netOut, 3)) disk=\(f(MetricID.diskRead, 3))/\(f(MetricID.diskWrite, 3)) T=\(f(MetricID.cpuTemp))/\(f(MetricID.gpuTemp)) P=\(f(MetricID.power)) procs=\(f(MetricID.procs, 0)) load=\(f(MetricID.load, 2)) | \(top)")
            let dt = now - prev; prev = now
            sumCPU += v[MetricID.cpu] ?? 0; n += 1
            sumNet += (v[MetricID.netIn] ?? 0) * dt
            sumDisk += ((v[MetricID.diskRead] ?? 0) + (v[MetricID.diskWrite] ?? 0)) * dt
        }
        print(String(format: "AVG cpu=%.2f  netIn总量=%.3fMB  磁盘读写总量=%.3fMB  (n=%d)", sumCPU / Double(n), sumNet, sumDisk, n))
    }
}
