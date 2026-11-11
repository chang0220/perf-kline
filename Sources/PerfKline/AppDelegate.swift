import AppKit
import SwiftUI
import KlineCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let store = Store()
    var window: NSWindow!
    var statusItem: NSStatusItem!
    let statusMenu = NSMenu()

    func applicationDidFinishLaunching(_ n: Notification) {
        buildMainMenu()
        buildWindow()
        buildStatusItem()
        store.onChange = { [weak self] in self?.updateStatusItem() }
        store.onPinChange = { [weak self] on in self?.window.level = on ? .floating : .normal }
        store.start()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // 关掉窗口后继续在菜单栏运行。
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow()
        return true
    }

    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: 主窗口

    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "性能行情"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // 加一个空工具栏，把标题栏撑到 38 点高，让红绿灯按钮和我们自己的标题栏垂直居中。
        let tb = NSToolbar(identifier: "main")
        tb.showsBaselineSeparator = false
        window.toolbar = tb
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1180, height: 720)
        window.contentView = NSHostingView(rootView: MainView(store: store))
        window.setFrameAutosaveName("main")
        if !window.setFrameUsingName("main") { window.center() }
        window.level = store.pinned ? .floating : .normal
        window.delegate = self
    }

    func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu()
        app.addItem(withTitle: "关于性能行情", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "隐藏性能行情", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: "退出性能行情", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        main.addItem(appItem)

        let winItem = NSMenuItem()
        let win = NSMenu(title: "窗口")
        win.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        win.addItem(.separator())
        win.addItem(withTitle: "显示主窗口", action: #selector(showWindow), keyEquivalent: "0")
        winItem.submenu = win
        main.addItem(winItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = win
    }

    // MARK: 菜单栏小行情

    func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeft
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        updateStatusItem()
    }

    private var lastStatusKey: String?
    private var lastStatusCandles: [Candle] = []

    func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let m = store.byID[store.menubarMetric] ?? store.catalog[0]
        let candles = store.candles(m.id, count: 12)
        // 内容和上次一样就不重设，省得菜单栏每秒重画。
        let key = "\(m.id)|\(store.latest[m.id].map { Fmt.value($0, m.decimals) } ?? "")|\(Fmt.signed(store.change(m.id) ?? 0, m.decimals))|\(store.redUp)"
        if key == lastStatusKey && candles == lastStatusCandles { return }
        lastStatusKey = key
        lastStatusCandles = candles
        button.image = StatusImage.candles(candles, up: store.colors.upNS, down: store.colors.downNS)
        let v = store.latest[m.id].map { Fmt.value($0, m.decimals) } ?? "—"
        let ch = store.change(m.id) ?? 0
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let title = NSMutableAttributedString(string: " \(StatusImage.shortName(m)) \(v)\(m.unit)", attributes: [.font: font])
        if store.latest[m.id] != nil {
            title.append(NSAttributedString(string: " " + Fmt.signed(ch, m.decimals), attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: ch > 0 ? store.colors.upNS : (ch < 0 ? store.colors.downNS : NSColor.secondaryLabelColor),
                .baselineOffset: 1,
            ]))
        }
        button.attributedTitle = title
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let para = NSMutableParagraphStyle()
        para.tabStops = [NSTextTab(textAlignment: .right, location: 170), NSTextTab(textAlignment: .right, location: 240)]
        let quick = [MetricID.cpu, MetricID.gpu, MetricID.mem, MetricID.cpuTemp, MetricID.power, MetricID.netIn, MetricID.diskRead]
        for id in quick {
            guard let m = store.byID[id] else { continue }
            let v = store.latest[id].map { Fmt.value($0, m.decimals) + m.unit } ?? "—"
            let ch = store.change(id) ?? 0
            let s = NSMutableAttributedString(string: "\(m.name)\t\(v)\t", attributes: [.font: font, .paragraphStyle: para])
            s.append(NSAttributedString(string: Fmt.signed(ch, m.decimals, m.changeUnit), attributes: [
                .font: font, .paragraphStyle: para,
                .foregroundColor: ch > 0 ? store.colors.upNS : (ch < 0 ? store.colors.downNS : NSColor.secondaryLabelColor),
            ]))
            let item = NSMenuItem(title: m.name, action: #selector(selectFromMenu(_:)), keyEquivalent: "")
            item.attributedTitle = s
            item.representedObject = id
            item.target = self
            menu.addItem(item)
        }
        let note = NSMenuItem(title: "涨跌：和 10 分钟前相比", action: nil, keyEquivalent: "")
        note.isEnabled = false
        menu.addItem(note)
        menu.addItem(.separator())
        menu.addItem(withTitle: "打开性能行情", action: #selector(showWindow), keyEquivalent: "o").target = self

        let pick = NSMenuItem(title: "菜单栏显示", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for m in store.catalog where m.group != .cores {
            let it = NSMenuItem(title: m.name, action: #selector(pickMenubar(_:)), keyEquivalent: "")
            it.representedObject = m.id
            it.target = self
            it.state = m.id == store.menubarMetric ? .on : .off
            sub.addItem(it)
        }
        pick.submenu = sub
        menu.addItem(pick)
        let pause = NSMenuItem(title: store.paused ? "继续采样" : "暂停采样", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc func selectFromMenu(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { store.selected = id }
        showWindow()
    }

    @objc func pickMenubar(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { store.menubarMetric = id }
    }

    @objc func togglePause() { store.paused.toggle() }
}

enum StatusImage {
    /// 菜单栏里的名字尽量短，省菜单栏空间。
    static func shortName(_ m: MetricInfo) -> String {
        switch m.id {
        case MetricID.cpu: "CPU"
        case MetricID.gpu: "GPU"
        case MetricID.mem: "内存"
        case MetricID.cpuTemp: "CPU"
        case MetricID.gpuTemp: "GPU"
        case MetricID.power: "功耗"
        case MetricID.netIn: "↓"
        case MetricID.netOut: "↑"
        case MetricID.diskRead: "读"
        case MetricID.diskWrite: "写"
        default: m.name
        }
    }

    /// 菜单栏的 12 根小 K 线（40×16 点）。
    static func candles(_ cs: [Candle], up: NSColor, down: NSColor) -> NSImage {
        let size = NSSize(width: 40, height: 16)
        return NSImage(size: size, flipped: false) { rect in
            guard !cs.isEmpty else { return true }
            var hi = cs.map(\.high).max()!, lo = cs.map(\.low).min()!
            if hi - lo < 1e-9 { hi += 0.5; lo -= 0.5 }
            let y = { (v: Double) in 1 + CGFloat((v - lo) / (hi - lo)) * (rect.height - 2) }
            let slots = 12
            let step = rect.width / CGFloat(slots)
            let off = CGFloat(slots - cs.count)
            for (i, c) in cs.enumerated() {
                (c.isUp ? up : down).setFill()
                let x = (off + CGFloat(i)) * step + step / 2
                NSRect(x: x - 0.5, y: y(c.low), width: 1, height: max(1, y(c.high) - y(c.low))).fill()
                let w = max(1.5, step * 0.62)
                let b = y(min(c.open, c.close))
                NSRect(x: x - w / 2, y: b, width: w, height: max(1, y(max(c.open, c.close)) - b)).fill()
            }
            return true
        }
    }
}
