import Foundation

public struct ProcessRow: Identifiable, Equatable, Sendable {
    public var id: Int32 { pid }
    public var pid: Int32
    public var name: String
    /// 两次采样之间的 CPU 占用（单核 = 100%，多线程进程可以超过 100%，和“活动监视器”一致）。
    public var cpu: Double
}

public struct ProcessSnapshot: Sendable {
    public var top: [ProcessRow]
    public var started: [ProcessRow]
    public var exited: [ProcessRow]
}

/// 用系统自带的 /bin/ps 读全部进程的累计 CPU 时间，两次相减得到这段时间的占用。
///
/// 为什么用 ps：普通程序用 proc_pidinfo 读不到其他用户（root、_windowserver 等）的进程，
/// 本机实测 881 个进程里有 299 个读不到；/bin/ps 带 setuid，可以读到全部，单次耗时约 26 毫秒。
/// （/usr/bin/top 也能读到，但单次要 0.35 秒 CPU，会把 CPU 占用本身抬高，所以不用。）
public final class ProcessSampler {
    private var last: [Int32: (name: String, cpuSeconds: Double)] = [:]
    private var lastTime: Double?

    public init() {}

    public func sample(now: Double = Date().timeIntervalSince1970, topCount: Int = 10) -> ProcessSnapshot? {
        guard let (rows, psPid) = Self.runPS() else { return nil }
        var cur: [Int32: (name: String, cpuSeconds: Double)] = [:]
        // 名字带括号的是正在退出的进程（ps 显示为 "(ps)" 这类），不计入。
        for r in rows where r.pid != psPid && !r.name.hasPrefix("(") { cur[r.pid] = (r.name, r.cpuSeconds) }
        defer { last = cur; lastTime = now }
        guard let lt = lastTime, now > lt else { return nil }
        let dt = now - lt
        var all: [ProcessRow] = []
        var started: [ProcessRow] = []
        for (pid, v) in cur {
            if let o = last[pid], o.name == v.name {
                all.append(ProcessRow(pid: pid, name: v.name, cpu: max(0, v.cpuSeconds - o.cpuSeconds) / dt * 100))
            } else {
                started.append(ProcessRow(pid: pid, name: v.name, cpu: 0))
            }
        }
        let exited = last.compactMap { pid, v in cur[pid] == nil ? ProcessRow(pid: pid, name: v.name, cpu: 0) : nil }
        all.sort { $0.cpu != $1.cpu ? $0.cpu > $1.cpu : $0.pid < $1.pid }
        return ProcessSnapshot(top: Array(all.prefix(topCount)),
                               started: started.sorted { $0.pid < $1.pid },
                               exited: exited.sorted { $0.pid < $1.pid })
    }

    struct PSRow { var pid: Int32; var cpuSeconds: Double; var name: String }

    static func runPS() -> ([PSRow], Int32)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pid=,time=,comm="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return nil }
        return (parse(text), p.processIdentifier)
    }

    /// 解析 `ps -axo pid=,time=,comm=` 的输出。comm 是可执行文件完整路径（可能含空格），只取最后一段。
    static func parse(_ text: String) -> [PSRow] {
        var out: [PSRow] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int32(parts[0]), let t = parseCPUTime(String(parts[1])) else { continue }
            let path = String(parts[2]).trimmingCharacters(in: .whitespaces)
            let name = (path as NSString).lastPathComponent
            out.append(PSRow(pid: pid, cpuSeconds: t, name: name.isEmpty ? path : name))
        }
        return out
    }

    /// ps 的 time 字段："分:秒.百分秒"，时间长了是 "时:分:秒.百分秒"，也可能带 "天-" 前缀。
    static func parseCPUTime(_ s: String) -> Double? {
        var rest = Substring(s)
        var days = 0.0
        if let dash = rest.firstIndex(of: "-") {
            guard let d = Double(rest[..<dash]) else { return nil }
            days = d
            rest = rest[rest.index(after: dash)...]
        }
        let comps = rest.split(separator: ":")
        guard !comps.isEmpty, comps.count <= 3 else { return nil }
        var total = 0.0
        for c in comps {
            guard let v = Double(c) else { return nil }
            total = total * 60 + v
        }
        return days * 86400 + total
    }
}
