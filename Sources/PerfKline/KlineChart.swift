import AppKit
import SwiftUI
import KlineCore

/// 主图要画的数据：可见的 K 线和对应的均线。
struct ChartData {
    var visible: [Candle]
    var ma: [(n: Int, values: [Double?])]
    var slots: Int
}

enum ChartLayout {
    static let padL: CGFloat = 10
    static let padR: CGFloat = 62
    static let top: CGFloat = 26
    static let maPeriods = [5, 10, 20]
    static let minStep = 3.0, maxStep = 40.0
}

extension Store {
    func chartData(width: CGFloat) -> ChartData {
        let pw = max(50, width - ChartLayout.padL - ChartLayout.padR)
        let n = max(5, Int(pw / chartStep))
        let back = max(0, Int(chartScrollBack.rounded()))
        let extra = ChartLayout.maPeriods.max()! - 1
        let all = candles(selected, count: n + back + extra)
        var end = all.count - back
        if end < min(n, all.count) { end = min(n, all.count) } // 翻过头时停在最早的数据
        let start = max(0, end - n)
        let closes = all.map(\.close)
        let ma = ChartLayout.maPeriods.map { p in (p, Array(movingAverage(closes, p)[start..<end])) }
        return ChartData(visible: Array(all[start..<end]), ma: ma, slots: n)
    }

    /// 往回翻的根数不超过历史数据。
    func clampScroll(width: CGFloat) {
        let pw = max(50, width - ChartLayout.padL - ChartLayout.padR)
        let n = max(5, Int(pw / chartStep))
        let total = series[selected]?.candles(period: period, maxCount: Int.max).count ?? 0
        chartScrollBack = min(max(0, chartScrollBack), Double(max(0, total - n)))
    }
}

struct KlineChart: View {
    @Bindable var store: Store
    @State private var hover: CGPoint?

    var body: some View {
        let _ = store.revision
        GeometryReader { geo in
            let data = store.chartData(width: geo.size.width)
            let m = store.selectedMetric
            ZStack(alignment: .topTrailing) {
                Canvas { ctx, size in draw(ctx, size, data, m) }
                ChartInteraction(
                    onHover: { hover = $0 },
                    onPan: { dx in
                        store.chartScrollBack += Double(dx) / store.chartStep
                        store.clampScroll(width: geo.size.width)
                    },
                    onZoom: { factor in
                        store.chartStep = min(ChartLayout.maxStep, max(ChartLayout.minStep, store.chartStep * factor))
                        store.clampScroll(width: geo.size.width)
                    },
                    onReset: { store.chartScrollBack = 0 })
                if store.chartScrollBack >= 1 {
                    Text("回到最新 ›")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.accentInk)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 5))
                        .padding(.trailing, ChartLayout.padR + 6).padding(.top, 4)
                        .onTapGesture { store.chartScrollBack = 0 }
                }
            }
        }
    }

    // MARK: 绘制

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ d: ChartData, _ m: MetricInfo) {
        let L = ChartLayout.self
        let W = size.width, H = size.height
        let mainH = (H - L.top) * 0.68
        let volTop = L.top + mainH + 26
        let volH = max(20, H - volTop - 24)
        let step = CGFloat(store.chartStep)
        let colors = store.colors
        let grid = Theme.line2, muted = Theme.muted
        let numFont = Font.system(size: 11).monospacedDigit()
        let hover = self.hover ?? store.debugHover

        guard !d.visible.isEmpty else {
            ctx.draw(Text("正在采集数据…").font(.system(size: 13)).foregroundColor(muted),
                     at: CGPoint(x: W / 2, y: H / 2))
            return
        }

        // 纵轴范围：可见 K 线和均线的高低点，上下留 6%；不超出指标的值域。
        var hi = d.visible.map(\.high).max()!, lo = d.visible.map(\.low).min()!
        for (_, vals) in d.ma { for v in vals.compactMap({ $0 }) { hi = max(hi, v); lo = min(lo, v) } }
        let minSpan = max(abs(hi) * 0.02, pow(10, -Double(m.decimals)) * 5)
        if hi - lo < minSpan { let mid = (hi + lo) / 2; hi = mid + minSpan / 2; lo = mid - minSpan / 2 }
        let pad = (hi - lo) * 0.06
        hi += pad; lo -= pad
        if let f = m.floor, lo < f { lo = f }
        if let c = m.ceiling, hi > c { hi = c }
        let y = { (v: Double) -> CGFloat in L.top + mainH - CGFloat((v - lo) / (hi - lo)) * mainH }
        let xAt = { (i: Int) -> CGFloat in L.padL + CGFloat(i) * step + step / 2 }

        // 网格和纵轴刻度
        for k in 0...4 {
            let v = lo + (hi - lo) * Double(k) / 4
            let yy = y(v)
            var p = Path(); p.move(to: CGPoint(x: L.padL, y: yy)); p.addLine(to: CGPoint(x: W - L.padR, y: yy))
            ctx.stroke(p, with: .color(grid), lineWidth: 1)
            ctx.draw(Text(Fmt.value(v, m.decimals)).font(numFont).foregroundColor(muted),
                     at: CGPoint(x: W - L.padR + 8, y: yy), anchor: .leading)
        }

        // K 线和成交量
        let vols = d.visible.map { $0.volume ?? 0 }
        let vmax = max(vols.max() ?? 0, 1)
        let bw = max(1, step * 0.66)
        for (i, c) in d.visible.enumerated() {
            let col = c.isUp ? colors.up : colors.down
            let x = xAt(i)
            var wick = Path(); wick.move(to: CGPoint(x: x, y: y(c.high))); wick.addLine(to: CGPoint(x: x, y: y(c.low)))
            ctx.stroke(wick, with: .color(col), lineWidth: 1)
            let t = y(max(c.open, c.close))
            let bh = max(1, abs(y(c.open) - y(c.close)))
            ctx.fill(Path(CGRect(x: x - bw / 2, y: t, width: bw, height: bh)), with: .color(col))
            if m.volumeName != nil, let v = c.volume {
                let vh = CGFloat(v / vmax) * volH
                ctx.fill(Path(CGRect(x: x - bw / 2, y: volTop + volH - vh, width: bw, height: vh)),
                         with: .color(col.opacity(0.55)))
            }
        }

        // 均线
        let maColors = [Theme.ma5, Theme.ma10, Theme.ma20]
        for (k, (_, vals)) in d.ma.enumerated() {
            var p = Path(); var started = false
            for (i, v) in vals.enumerated() {
                guard let v else { continue }
                let pt = CGPoint(x: xAt(i), y: y(v))
                if started { p.addLine(to: pt) } else { p.move(to: pt); started = true }
            }
            ctx.stroke(p, with: .color(maColors[k]), lineWidth: 1.2)
        }

        // 十字光标对准的 K 线（没有悬停时用最新一根）
        var hoverIndex: Int?
        if let h = hover, h.x >= L.padL, h.x <= W - L.padR, h.y >= L.top, h.y <= volTop + volH {
            let i = Int((h.x - L.padL) / step)
            if i >= 0 && i < d.visible.count { hoverIndex = i }
        }
        let shown = hoverIndex ?? d.visible.count - 1

        // 均线图例
        var legend = Text("")
        for (k, (n, vals)) in d.ma.enumerated() {
            let v = vals[shown].map { Fmt.value($0, m.decimals) } ?? "—"
            legend = legend + Text((k > 0 ? "　" : "") + "MA\(n) \(v)").foregroundColor(maColors[k])
        }
        ctx.draw(legend.font(.system(size: 12).monospacedDigit()), at: CGPoint(x: L.padL + 4, y: 14), anchor: .leading)

        // 最新值标签
        if store.chartScrollBack < 1, let last = d.visible.last {
            let ly = y(last.close)
            let lc = last.isUp ? colors.up : colors.down
            var p = Path(); p.move(to: CGPoint(x: L.padL, y: ly)); p.addLine(to: CGPoint(x: W - L.padR, y: ly))
            ctx.stroke(p, with: .color(lc.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ctx.fill(Path(roundedRect: CGRect(x: W - L.padR + 2, y: ly - 9, width: L.padR - 6, height: 18), cornerRadius: 3),
                     with: .color(lc))
            ctx.draw(Text(Fmt.value(last.close, m.decimals)).font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundColor(.white),
                     at: CGPoint(x: W - L.padR + 8, y: ly), anchor: .leading)
        }

        // 成交量标题
        let volTitle: Text
        if let name = m.volumeName {
            let v = d.visible[shown].volume.map { Fmt.count($0) } ?? "—"
            volTitle = Text("成交量（\(name)）") + Text("  \(v)").foregroundColor(Theme.text)
        } else {
            volTitle = Text("成交量：这个指标没有对应的计数")
        }
        ctx.draw(volTitle.font(.system(size: 11).monospacedDigit()).foregroundColor(muted),
                 at: CGPoint(x: L.padL + 4, y: volTop - 10), anchor: .leading)
        var sep = Path(); sep.move(to: CGPoint(x: L.padL, y: volTop - 20)); sep.addLine(to: CGPoint(x: W - L.padR, y: volTop - 20))
        ctx.stroke(sep, with: .color(grid), lineWidth: 1)

        // 时间轴：大约每 120 像素一个标签
        let every = max(1, Int(120 / step))
        var i = d.visible.count - 1
        while i >= 0 {
            let x = xAt(i)
            if x > L.padL + 30 && x < W - L.padR - 10 {
                ctx.draw(Text(Fmt.clock(d.visible[i].start)).font(numFont).foregroundColor(muted),
                         at: CGPoint(x: x, y: H - 10))
            }
            i -= every
        }

        // 十字光标和信息框
        if let hx = hoverIndex, let h = hover {
            let c = d.visible[hx]
            let cx = xAt(hx)
            let dash = StrokeStyle(lineWidth: 0.8, dash: [2, 2])
            var v = Path(); v.move(to: CGPoint(x: cx, y: L.top)); v.addLine(to: CGPoint(x: cx, y: volTop + volH))
            ctx.stroke(v, with: .color(muted), style: dash)
            if h.y <= L.top + mainH {
                var hl = Path(); hl.move(to: CGPoint(x: L.padL, y: h.y)); hl.addLine(to: CGPoint(x: W - L.padR, y: h.y))
                ctx.stroke(hl, with: .color(muted), style: dash)
                let price = lo + Double((L.top + mainH - h.y) / mainH) * (hi - lo)
                ctx.fill(Path(roundedRect: CGRect(x: W - L.padR + 2, y: h.y - 9, width: L.padR - 6, height: 18), cornerRadius: 3),
                         with: .color(Theme.tag))
                ctx.draw(Text(Fmt.value(price, m.decimals)).font(numFont).foregroundColor(Theme.text),
                         at: CGPoint(x: W - L.padR + 8, y: h.y), anchor: .leading)
            }
            let prevClose = hx > 0 ? d.visible[hx - 1].close : nil
            var rows: [(String, String, Color)] = [
                ("时间", Fmt.clock(c.start), Theme.text),
                ("开", Fmt.value(c.open, m.decimals), Theme.text),
                ("高", Fmt.value(c.high, m.decimals), Theme.text),
                ("低", Fmt.value(c.low, m.decimals), Theme.text),
                ("收", Fmt.value(c.close, m.decimals), Theme.text),
            ]
            if let pc = prevClose {
                rows.append(("涨跌", Fmt.signed(c.close - pc, m.decimals, m.changeUnit), colors.tone(c.close - pc)))
            }
            if m.volumeName != nil { rows.append(("成交量", c.volume.map { Fmt.count($0) } ?? "—", Theme.text)) }
            rows.append(("采样数", "\(c.sampleCount)", muted))
            let bwid: CGFloat = 132, bh = CGFloat(rows.count) * 16 + 12
            var bx = cx + 14
            if bx + bwid > W - L.padR { bx = cx - 14 - bwid }
            let box = CGRect(x: bx, y: L.top + 10, width: bwid, height: bh)
            ctx.fill(Path(roundedRect: box, cornerRadius: 5), with: .color(Theme.panel2))
            ctx.stroke(Path(roundedRect: box, cornerRadius: 5), with: .color(Theme.line), lineWidth: 1)
            for (j, r) in rows.enumerated() {
                let yy = box.minY + 14 + CGFloat(j) * 16
                ctx.draw(Text(r.0).font(.system(size: 11)).foregroundColor(muted), at: CGPoint(x: box.minX + 10, y: yy), anchor: .leading)
                ctx.draw(Text(r.1).font(numFont).foregroundColor(r.2), at: CGPoint(x: box.maxX - 10, y: yy), anchor: .trailing)
            }
        }
    }
}

/// 透明的 AppKit 层，接收鼠标悬停、滚轮 / 触控板、拖动和双击。
/// - 上下滚动 / 双指捏合：缩放 K 线宽度
/// - 左右滑动 / 按住拖动：往回翻看历史
/// - 双击：回到最新
struct ChartInteraction: NSViewRepresentable {
    var onHover: (CGPoint?) -> Void
    var onPan: (CGFloat) -> Void
    var onZoom: (Double) -> Void
    var onReset: () -> Void

    final class V: NSView {
        var parent: ChartInteraction!
        override var isFlipped: Bool { true }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                           owner: self))
        }
        private func local(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }
        override func mouseMoved(with e: NSEvent) { parent.onHover(local(e)) }
        override func mouseExited(with e: NSEvent) { parent.onHover(nil) }
        override func mouseDown(with e: NSEvent) { if e.clickCount == 2 { parent.onReset() } }
        override func mouseDragged(with e: NSEvent) { parent.onPan(e.deltaX); parent.onHover(local(e)) }
        override func scrollWheel(with e: NSEvent) {
            let dx = e.scrollingDeltaX, dy = e.scrollingDeltaY
            if abs(dx) > abs(dy) {
                parent.onPan(e.hasPreciseScrollingDeltas ? dx : dx * 8)
            } else if dy != 0 {
                let k = e.hasPreciseScrollingDeltas ? 0.01 : 0.1
                parent.onZoom(1 + Double(dy) * k)
            }
            parent.onHover(local(e))
        }
        override func magnify(with e: NSEvent) { parent.onZoom(1 + Double(e.magnification)) }
    }

    func makeNSView(context: Context) -> V { let v = V(); v.parent = self; return v }
    func updateNSView(_ v: V, context: Context) { v.parent = self }
}
