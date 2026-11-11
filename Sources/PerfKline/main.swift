import AppKit

let args = CommandLine.arguments

if let i = args.firstIndex(of: "--selftest") {
    let n = args.count > i + 1 ? Int(args[i + 1]) ?? 10 : 10
    SelfTest.run(seconds: n)
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate

// 开发用：`PerfKline --snapshot 输出.png [--after 秒] [--appearance dark|light] [--select 指标] [--hover x,y]`
// 采样若干秒后把主窗口和菜单栏小行情画到图片里，用来检查界面，不需要录屏权限。
if let i = args.firstIndex(of: "--snapshot"), args.count > i + 1 {
    MainActor.assumeIsolated { Snapshot.schedule(delegate: delegate, path: args[i + 1], args: args) }
}

app.run()
