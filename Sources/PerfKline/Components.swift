import AppKit
import SwiftUI
import KlineCore

/// 小 K 线（自选行情、指数条里用）。纵轴按这几根 K 线自身的高低点缩放。
struct MiniCandles: View {
    var candles: [Candle]
    /// 预定的根数；数据不够时靠右排，新 K 线总出现在右端。
    var slots: Int
    var colors: Colors

    var body: some View {
        Canvas { ctx, size in
            guard !candles.isEmpty else { return }
            var hi = candles.map(\.high).max()!, lo = candles.map(\.low).min()!
            if hi - lo < 1e-9 { hi += 0.5; lo -= 0.5 } // 完全没波动时画在中间
            let span = hi - lo
            let y = { (v: Double) in size.height - 2 - (v - lo) / span * (size.height - 4) }
            let slots = max(self.slots, candles.count)
            let step = size.width / CGFloat(slots)
            let offset = CGFloat(slots - candles.count)
            for (i, c) in candles.enumerated() {
                let col = c.isUp ? colors.up : colors.down
                let x = (offset + CGFloat(i)) * step + step / 2
                var wick = Path()
                wick.move(to: CGPoint(x: x, y: y(c.high)))
                wick.addLine(to: CGPoint(x: x, y: y(c.low)))
                ctx.stroke(wick, with: .color(col), lineWidth: 1)
                let top = y(max(c.open, c.close))
                let h = max(1, abs(y(c.open) - y(c.close)))
                let w = max(1.5, step * 0.62)
                ctx.fill(Path(CGRect(x: x - w / 2, y: top, width: w, height: h)), with: .color(col))
            }
        }
    }
}

/// 分段选择（采样间隔、K 线周期）。选中项用强调色填充。
struct Seg<T: Hashable>: View {
    var options: [T]
    var label: (T) -> String
    @Binding var selection: T
    var disabled: (T) -> Bool = { _ in false }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { o in
                let on = o == selection
                let off = disabled(o)
                Text(label(o))
                    .font(.system(size: 12, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Theme.accentInk : (off ? Theme.muted.opacity(0.4) : Theme.muted))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(on ? Theme.accent : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { if !off { selection = o } }
                    .help(off ? "K 线周期不能短于采样间隔" : "")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
    }
}

/// 标题栏上的文字按钮；on 时用强调色描边和文字。
struct BarButton: View {
    var title: String
    var on = false
    var action: () -> Void

    var body: some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(on ? Theme.accent : Theme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? Theme.accent : Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

/// 让一块区域可以拖动窗口、双击缩放（和系统标题栏行为一致）。
struct WindowDragArea: NSViewRepresentable {
    final class V: NSView {
        override func mouseDown(with e: NSEvent) {
            if e.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: e) }
        }
    }
    func makeNSView(context: Context) -> NSView { V() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

func periodLabel(_ p: Double) -> String { p >= 60 ? "\(Int(p / 60))分K" : "\(Int(p))秒K" }
func intervalLabel(_ i: Double) -> String { i < 1 ? "0.5秒" : "\(Int(i))秒" }
