import AppKit
import KlineCore

/// 开发自检用：把主窗口和菜单栏小行情渲染成 PNG（不需要录屏权限）。
@MainActor
enum Snapshot {
    static func schedule(delegate: AppDelegate, path: String, args: [String]) {
        func arg(_ k: String) -> String? { args.firstIndex(of: k).flatMap { args.count > $0 + 1 ? args[$0 + 1] : nil } }
        let after = arg("--after").flatMap(Double.init) ?? 15
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let a = arg("--appearance") {
                NSApp.appearance = NSAppearance(named: a == "light" ? .aqua : .darkAqua)
            }
            if let s = arg("--select") { delegate.store.selected = s }
            if let iv = arg("--interval").flatMap(Double.init) { delegate.store.interval = iv }
            if let p = arg("--period").flatMap(Double.init) { delegate.store.period = p }
            if let h = arg("--hover") {
                let xy = h.split(separator: ",").compactMap { Double($0) }
                if xy.count == 2 { delegate.store.debugHover = CGPoint(x: xy[0], y: xy[1]) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + after) {
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
