import Foundation
import Darwin
import IOKit

// 本文件的读取器都只用公开接口，不需要管理员权限。
// 每个读取器记住上一次的累计计数，返回两次之间的差值；第一次调用没有“上一次”，返回 nil。

// MARK: - CPU 占用与中断

public struct CPUReading {
    /// 全部核心合计占用（0–100）。
    public var total: Double
    /// 每个逻辑核心的占用（下标 = 逻辑核编号）。
    public var perCore: [Double]
    /// 两次读取之间全部核心的中断次数。
    public var interruptsTotal: Double
    public var interruptsPerCore: [Double]
}

public final class CPUReader {
    private var lastTicks: [[UInt32]] = []   // 每核 [user, system, idle, nice]
    private var lastIRQ: [UInt64] = []

    public init() {}

    /// 每个逻辑核心的类型。读 IODeviceTree 里 cpu 节点的 cluster-type（E / P）和 logical-cpu-id；
    /// 读不到时按 sysctl hw.perflevel1.logicalcpu 的数量把前几个当能效核（苹果芯片上能效核编号在前）。
    public static func coreKinds() -> [CoreKind] {
        let n = Int(sysctlInt("hw.ncpu") ?? 0)
        var kinds = [CoreKind?](repeating: nil, count: n)
        var it: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPlatformDevice"), &it) == KERN_SUCCESS {
            while case let s = IOIteratorNext(it), s != 0 {
                defer { IOObjectRelease(s) }
                guard let ct = IORegistryEntryCreateCFProperty(s, "cluster-type" as CFString, nil, 0)?.takeRetainedValue() as? Data,
                      let idData = IORegistryEntryCreateCFProperty(s, "logical-cpu-id" as CFString, nil, 0)?.takeRetainedValue()
                else { continue }
                var id = -1
                if let num = idData as? NSNumber { id = num.intValue }
                else if let d = idData as? Data, d.count >= 4 { id = Int(d.withUnsafeBytes { $0.load(as: UInt32.self) }) }
                guard id >= 0, id < n else { continue }
                kinds[id] = ct.first == UInt8(ascii: "E") ? .efficiency : .performance
            }
            IOObjectRelease(it)
        }
        if kinds.allSatisfy({ $0 != nil }) { return kinds.map { $0! } }
        let e = Int(sysctlInt("hw.perflevel1.logicalcpu") ?? 0)
        return (0..<n).map { $0 < e ? .efficiency : .performance }
    }

    public func read() -> CPUReading? {
        var n: natural_t = 0
        var info: processor_info_array_t?
        var cnt: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &n, &info, &cnt) == KERN_SUCCESS,
              let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(cnt) * MemoryLayout<integer_t>.stride)) }
        let cores = Int(n)
        var ticks: [[UInt32]] = []
        for c in 0..<cores {
            let base = c * Int(CPU_STATE_MAX)
            ticks.append((0..<Int(CPU_STATE_MAX)).map { UInt32(bitPattern: info[base + $0]) })
        }

        var irq: [UInt64] = []
        var n2: natural_t = 0
        var info2: processor_info_array_t?
        var cnt2: mach_msg_type_number_t = 0
        if host_processor_info(mach_host_self(), PROCESSOR_CPU_STAT64, &n2, &info2, &cnt2) == KERN_SUCCESS, let info2 {
            let per = Int(cnt2) / max(1, Int(n2))
            for c in 0..<Int(n2) {
                let p = UnsafeRawPointer(info2 + c * per).loadUnaligned(as: processor_cpu_stat64.self)
                irq.append(p.irq_ex_cnt)
            }
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info2), vm_size_t(Int(cnt2) * MemoryLayout<integer_t>.stride))
        }

        defer { lastTicks = ticks; lastIRQ = irq }
        guard lastTicks.count == cores else { return nil }

        var perCore: [Double] = []
        var busyAll = 0.0, totalAll = 0.0
        for c in 0..<cores {
            // 计数器是 32 位，用回绕减法（&-）处理溢出。
            let d = (0..<Int(CPU_STATE_MAX)).map { Double(ticks[c][$0] &- lastTicks[c][$0]) }
            let busy = d[Int(CPU_STATE_USER)] + d[Int(CPU_STATE_SYSTEM)] + d[Int(CPU_STATE_NICE)]
            let total = busy + d[Int(CPU_STATE_IDLE)]
            perCore.append(total > 0 ? busy / total * 100 : 0)
            busyAll += busy; totalAll += total
        }
        var irqPer = [Double](repeating: 0, count: cores)
        if irq.count == cores && lastIRQ.count == cores {
            for c in 0..<cores { irqPer[c] = irq[c] >= lastIRQ[c] ? Double(irq[c] - lastIRQ[c]) : 0 }
        }
        return CPUReading(total: totalAll > 0 ? busyAll / totalAll * 100 : 0, perCore: perCore,
                          interruptsTotal: irqPer.reduce(0, +), interruptsPerCore: irqPer)
    }
}

// MARK: - 内存

public final class MemoryReader {
    private var lastFaults: UInt64?
    private let totalBytes = Double(sysctlInt("hw.memsize") ?? 1)

    public init() {}

    /// 返回（占用百分比，两次之间的缺页次数）。
    /// 占用 = App 内存 + 联动内存 + 被压缩内存，与“活动监视器”的“已使用内存”同口径；
    /// App 内存 = internal − purgeable（与 Stats 的算法一致，见 README 查证记录）。
    public func read() -> (percent: Double, faults: Double?)? {
        var vm = vm_statistics64()
        var c = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(c)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &c) }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let page = Double(vm_kernel_page_size)
        let app = Double(vm.internal_page_count) - Double(vm.purgeable_count)
        let used = (app + Double(vm.wire_count) + Double(vm.compressor_page_count)) * page
        defer { lastFaults = vm.faults }
        let faults = lastFaults.map { vm.faults >= $0 ? Double(vm.faults - $0) : 0 }
        return (min(100, max(0, used / totalBytes * 100)), faults)
    }
}

// MARK: - GPU

public enum GPUReader {
    /// IOAccelerator 的 PerformanceStatistics["Device Utilization %"]（0–100）。读不到返回 nil。
    public static func read() -> Double? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var best: Double?
        while case let s = IOIteratorNext(it), s != 0 {
            defer { IOObjectRelease(s) }
            if let d = IORegistryEntryCreateCFProperty(s, "PerformanceStatistics" as CFString, nil, 0)?.takeRetainedValue() as? [String: Any],
               let u = (d["Device Utilization %"] as? NSNumber)?.doubleValue {
                best = max(best ?? 0, u)
            }
        }
        return best
    }
}

// MARK: - 网络

public struct NetReading { public var bytesIn, bytesOut, packetsIn, packetsOut: Double }

public final class NetworkReader {
    private var last: [String: (UInt32, UInt32, UInt32, UInt32)] = [:]
    public init() {}

    /// 只统计 en* 接口（Wi‑Fi / 有线）。VPN 的 utun 接口会把同一份流量再算一遍，所以不计入。
    /// if_data 的计数是 32 位，用回绕减法处理溢出（一个采样间隔内不会超过 4 GB）。
    public func read() -> NetReading? {
        var ifa: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifa) == 0 else { return nil }
        defer { freeifaddrs(ifa) }
        var now: [String: (UInt32, UInt32, UInt32, UInt32)] = [:]
        var p = ifa
        while let a = p {
            defer { p = a.pointee.ifa_next }
            guard let addr = a.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = a.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            let name = String(cString: a.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            let d = data.pointee
            now[name] = (d.ifi_ibytes, d.ifi_obytes, d.ifi_ipackets, d.ifi_opackets)
        }
        defer { last = now }
        guard !last.isEmpty else { return nil }
        var r = NetReading(bytesIn: 0, bytesOut: 0, packetsIn: 0, packetsOut: 0)
        for (k, v) in now {
            guard let o = last[k] else { continue }
            r.bytesIn += Double(v.0 &- o.0); r.bytesOut += Double(v.1 &- o.1)
            r.packetsIn += Double(v.2 &- o.2); r.packetsOut += Double(v.3 &- o.3)
        }
        return r
    }
}

// MARK: - 磁盘

public struct DiskReading { public var bytesRead, bytesWritten, opsRead, opsWritten: Double }

public final class DiskReader {
    private var last: (Double, Double, Double, Double)?
    public init() {}

    /// 累加所有 IOBlockStorageDriver 的 Statistics（与 iostat 同一数据源）。
    public func read() -> DiskReading? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var br = 0.0, bw = 0.0, orr = 0.0, ow = 0.0
        while case let s = IOIteratorNext(it), s != 0 {
            defer { IOObjectRelease(s) }
            guard let d = IORegistryEntryCreateCFProperty(s, "Statistics" as CFString, nil, 0)?.takeRetainedValue() as? [String: Any] else { continue }
            br += (d["Bytes (Read)"] as? NSNumber)?.doubleValue ?? 0
            bw += (d["Bytes (Write)"] as? NSNumber)?.doubleValue ?? 0
            orr += (d["Operations (Read)"] as? NSNumber)?.doubleValue ?? 0
            ow += (d["Operations (Write)"] as? NSNumber)?.doubleValue ?? 0
        }
        defer { last = (br, bw, orr, ow) }
        guard let l = last else { return nil }
        // 磁盘被推出时累计值会变小，此时记 0。
        return DiskReading(bytesRead: max(0, br - l.0), bytesWritten: max(0, bw - l.1),
                           opsRead: max(0, orr - l.2), opsWritten: max(0, ow - l.3))
    }
}

// MARK: - 进程数、负载

public enum SystemReader {
    /// 当前进程总数（proc_listallpids，包括其他用户的进程）。
    public static func processCount() -> Int? {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(n) + 64)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return got > 0 ? Int(got) : nil
    }

    /// 1 分钟平均负载（与 uptime / top 的 Load Avg 第一项相同）。
    public static func loadAverage() -> Double? {
        var l = [Double](repeating: 0, count: 3)
        return getloadavg(&l, 3) >= 1 ? l[0] : nil
    }
}

func sysctlInt(_ name: String) -> Int64? {
    var v: Int64 = 0
    var size = MemoryLayout<Int64>.size
    guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
    if size == 4 { return Int64(Int32(truncatingIfNeeded: v)) }
    return v
}
