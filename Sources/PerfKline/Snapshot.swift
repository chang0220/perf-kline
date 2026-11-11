import AppKit
import KlineCore

/// 开发自检用：把主窗口和菜单栏小行情渲染成 PNG（不需要录屏权限）。
@MainActor
enum Snapshot {
    static func schedule(delegate: AppDelegate, path: String, args: [String]) {
        func arg(_ k: String) -> String? { args.firstIndex(of: k).flatMap { args.count > $0 + 1 ? args[$0 + 1] : nil } }
        let after = arg("--after").flatMap(Double.init) ?? 15
        delegate.store.alwaysRender = !args.contains("--real-visibility")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let a = arg("--appearance") {
                NSApp.appearance = NSAppearance(named: a == "light" ? .aqua : .darkAqua)
            }
            if args.contains("--close-window") { delegate.window.performClose(nil) }
            if let s = arg("--select") { delegate.store.selected = s }
            if let iv = arg("--interval").flatMap(Double.init) { delegate.store.interval = iv }
            if let p = arg("--period").flatMap(Double.init) { delegate.store.period = p }
            if let h = arg("--hover") {
                let xy = h.split(separator: ",").compactMap { Double($0) }
                if xy.count == 2 { delegate.store.debugHover = CGPoint(x: xy[0], y: xy[1]) }
            }
        }
        // 截图前 30 秒到截图时，按线程统计本进程的 CPU 时间（诊断 App 自身开销用）
        var before: [UInt64: (String, Double)] = [:]
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.5, after - 30)) { before = threadTimes() }
        DispatchQueue.main.asyncAfter(deadline: .now() + after) {
            if args.contains("--threads") {
                let span = min(30, after - 0.5)
                let now = threadTimes()
                var rows: [(String, Double)] = []
                for (id, v) in now { rows.append((v.0, (v.1 - (before[id]?.1 ?? 0)) / span * 100)) }
                rows.sort { $0.1 > $1.1 }
                print(String(format: "合计 %.2f%%", rows.map(\.1).reduce(0, +)))
                for r in rows.prefix(8) { print(String(format: "  %6.2f%%  %@", r.1, r.0)) }
            }
            guard let v = delegate.window.contentView,
                  let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { exit(1) }
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            // 菜单栏小行情：按钮内容单独画一张
            if let b = delegate.statusItem.button {
                b.appearance = NSApp.effectiveAppearance
                if let r2 = b.bitmapImageRepForCachingDisplay(in: b.bounds) {
                    b.cacheDisplay(in: b.bounds, to: r2)
                    let p2 = (path as NSString).deletingPathExtension + "-menubar.png"
                    try? r2.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: p2))
                }
            }
            print("snapshot written: \(path)")
            exit(0)
        }
    }
}

/// 本进程每个线程累计的 CPU 时间（用户态 + 内核态），键是系统给的稳定线程编号。
func threadTimes() -> [UInt64: (String, Double)] {
    var list: thread_act_array_t?
    var count: mach_msg_type_number_t = 0
    guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS, let list else { return [:] }
    var out: [UInt64: (String, Double)] = [:]
    for i in 0..<Int(count) {
        let t = list[i]
        var basic = thread_basic_info()
        var n = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
        let k1 = withUnsafeMutablePointer(to: &basic) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { thread_info(t, thread_flavor_t(THREAD_BASIC_INFO), $0, &n) } }
        var ident = thread_identifier_info()
        var n2 = mach_msg_type_number_t(MemoryLayout<thread_identifier_info>.size / MemoryLayout<integer_t>.size)
        let k2 = withUnsafeMutablePointer(to: &ident) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(n2)) { thread_info(t, thread_flavor_t(THREAD_IDENTIFIER_INFO), $0, &n2) } }
        if k1 == KERN_SUCCESS && k2 == KERN_SUCCESS {
            let secs = Double(basic.user_time.seconds + basic.system_time.seconds)
                + Double(basic.user_time.microseconds + basic.system_time.microseconds) / 1e6
            var name = [CChar](repeating: 0, count: 128)
            if let pt = pthread_from_mach_thread_np(t) { pthread_getname_np(pt, &name, 128) }
            var label = String(cString: name)
            if label.isEmpty { label = (pthread_from_mach_thread_np(t) == pthread_self() ? "主线程 " : "线程 ") + "\(ident.thread_id)" }
            out[ident.thread_id] = (label, secs)
        }
        mach_port_deallocate(mach_task_self_, t)
    }
    vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), vm_size_t(Int(count) * MemoryLayout<thread_act_t>.stride))
    return out
}
