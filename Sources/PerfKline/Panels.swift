import SwiftUI
import KlineCore

// MARK: - 标题栏

struct TitleBar: View {
    @Bindable var store: Store

    var body: some View {
        let _ = store.revision
        HStack(spacing: 14) {
            Text("性能行情").font(.system(size: 14, weight: .bold)).kerning(0.5)
            HStack(spacing: 6) {
                Circle().fill(store.paused ? Theme.muted : store.colors.up).frame(width: 6, height: 6)
                Text(store.paused ? "已暂停" : "实时采样 \(intervalLabel(store.interval).replacingOccurrences(of: "秒", with: " 秒"))")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Text(store.chip).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Spacer(minLength: 10)
            Text("采样").font(.system(size: 12)).foregroundStyle(Theme.muted)
            Seg(options: Store.intervals, label: intervalLabel, selection: Binding(
                get: { store.interval },
                set: { v in
                    store.interval = v
                    if store.period < v { store.period = Store.periods.first { $0 >= v } ?? 60 }
                }))
            BarButton(title: store.paused ? "继续" : "暂停", on: store.paused) { store.paused.toggle() }
                .help("暂停采样（空格）")
            BarButton(title: "置顶", on: store.pinned) { store.pinned.toggle() }
                .help("窗口保持在最前面")
            BarButton(title: store.redUp ? "红涨绿跌" : "绿涨红跌") { store.redUp.toggle() }
                .help("切换涨跌配色")
            Text(Fmt.clock(store.lastSampleTime)).num(15, .semibold)
        }
        .padding(.leading, 84)
        .padding(.trailing, 14)
        .frame(height: 38)
        .background(WindowDragArea())
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

// MARK: - 指数条

struct IndexStrip: View {
    @Bindable var store: Store
    static let ids = [MetricID.cpu, MetricID.gpu, MetricID.mem, MetricID.cpuTemp, MetricID.netIn, MetricID.power, MetricID.procs]

    var body: some View {
        let _ = store.revision
        let ids = Array(Self.ids.filter { store.byID[$0] != nil }.prefix(6))
        HStack(spacing: 0) {
            ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                tile(store.byID[id]!)
                if i < ids.count - 1 { Rectangle().fill(Theme.line2).frame(width: 1) }
            }
        }
        .frame(height: 78)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    func tile(_ m: MetricInfo) -> some View {
        IndexTile(model: store.rowModel(m, candles: 18), onTap: { store.selected = m.id }).equatable()
    }
}

/// 一行 / 一块要显示的内容。做成可比较的值：和上一秒完全一样时 SwiftUI 跳过重画（省 CPU）。
struct RowModel: Equatable {
    var metric: MetricInfo
    var value: String
    var change: String
    var changeLong: String
    var sign: Int
    var candles: [Candle]
    var selected: Bool
    var redUp: Bool
}

extension Store {
    func rowModel(_ m: MetricInfo, candles n: Int) -> RowModel {
        let v = latest[m.id]
        let ch = change(m.id) ?? 0
        let shown = Fmt.signed(ch, m.decimals)
        let sign = shown.hasPrefix("+") ? 1 : (shown.hasPrefix("−") ? -1 : 0)
        return RowModel(metric: m, value: v.map { Fmt.value($0, m.decimals) } ?? "—",
                        change: v == nil ? "" : shown,
                        changeLong: v == nil ? " " : Fmt.signed(ch, m.decimals, m.changeUnit),
                        sign: sign, candles: candles(m.id, count: n), selected: selected == m.id, redUp: redUp)
    }
}

extension RowModel {
    var colors: Colors { Colors(redUp: redUp) }
    var tone: Color { colors.tone(Double(sign)) }
}

struct IndexTile: View, Equatable {
    var model: RowModel
    var onTap: () -> Void
    static func == (a: Self, b: Self) -> Bool { a.model == b.model }

    var body: some View {
        let m = model.metric
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(m.name).font(.system(size: 12)).foregroundStyle(Theme.muted)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(model.value).num(21, .bold).foregroundStyle(model.tone)
                    Text(m.unit).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Text(model.changeLong).num(12).foregroundStyle(model.tone)
            }
            .fixedSize()
            Spacer(minLength: 0)
            MiniCandles(candles: model.candles, slots: 18, colors: model.colors)
                .frame(width: 92, height: 46)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(model.selected ? Theme.sel : Color.clear, ignoresSafeAreaEdges: [])
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .help("\(m.name)：涨跌是和 10 分钟前相比")
    }
}

struct WatchRow: View, Equatable {
    var model: RowModel
    var onTap: () -> Void
    static func == (a: Self, b: Self) -> Bool { a.model == b.model }

    var body: some View {
        let m = model.metric
        HStack(spacing: 4) {
            Text(m.code).num(11).foregroundStyle(Theme.muted).frame(width: 48, alignment: .leading)
            Text(m.name).font(.system(size: 13)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            MiniCandles(candles: model.candles, slots: 12, colors: model.colors)
                .frame(width: 44, height: 18)
            Text(model.value).num(13).foregroundStyle(model.tone)
                .frame(width: 52, alignment: .trailing)
            Text(model.change).num(12).foregroundStyle(model.tone)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 29)
        .background(model.selected ? Theme.sel : Color.clear, ignoresSafeAreaEdges: [])
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - 自选行情

struct WatchList: View {
    @Bindable var store: Store

    var body: some View {
        let _ = store.revision
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("自选行情").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(store.catalog.count) 项").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line2).frame(height: 1) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(MetricGroup.allCases, id: \.self) { g in
                            let rows = store.catalog.filter { $0.group == g }
                            if !rows.isEmpty {
                                HStack {
                                    Text(g.rawValue)
                                    Spacer()
                                    Text("\(rows.count)")
                                }
                                .font(.system(size: 11)).foregroundStyle(Theme.muted)
                                .padding(.horizontal, 14).padding(.top, 7).padding(.bottom, 4)
                                ForEach(rows) { m in row(m).id(m.id) }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.never)
                .onChange(of: store.selected) { _, id in withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
            }
        }
    }

    func row(_ m: MetricInfo) -> some View {
        WatchRow(model: store.rowModel(m, candles: 12), onTap: { store.selected = m.id }).equatable()
    }
}

// MARK: - 品种头

struct QuoteHeader: View {
    @Bindable var store: Store
    var visible: [Candle]

    var body: some View {
        let _ = store.revision
        let m = store.selectedMetric
        let v = store.latest[m.id]
        let ref = store.reference(m.id)
        let ch = (v != nil && ref != nil) ? v! - ref! : 0
        let tone = store.colors.tone(ch)
        let hi = visible.map(\.high).max(), lo = visible.map(\.low).min()
        let avg = visible.isEmpty ? nil : visible.map(\.close).reduce(0, +) / Double(visible.count)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 18) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(m.name).font(.system(size: 17, weight: .bold))
                    Text(m.code).num(12).foregroundStyle(Theme.muted)
                }
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(v.map { Fmt.value($0, m.decimals) } ?? "—").num(36, .bold).foregroundStyle(tone)
                    Text(m.unit).font(.system(size: 14)).foregroundStyle(Theme.muted)
                }
                if v != nil, let ref {
                    HStack(spacing: 14) {
                        Text(Fmt.signed(ch, m.decimals, m.changeUnit))
                        if abs(ref) > 1e-9 { Text(Fmt.signed(ch / abs(ref) * 100, 2, "%")) }
                    }
                    .num(14).foregroundStyle(tone)
                }
                Spacer()
                Seg(options: Store.periods, label: periodLabel, selection: $store.period,
                    disabled: { $0 < store.interval })
                    .alignmentGuide(.lastTextBaseline) { $0[.bottom] - 4 }
            }
            HStack(spacing: 26) {
                stat("10分钟前", ref.map { Fmt.value($0, m.decimals) })
                stat("最高", hi.map { Fmt.value($0, m.decimals) }, store.colors.up)
                stat("最低", lo.map { Fmt.value($0, m.decimals) }, store.colors.down)
                stat("均值", avg.map { Fmt.value($0, m.decimals) })
                stat("振幅", (hi != nil && lo != nil) ? Fmt.value(hi! - lo!, m.decimals) + m.changeUnit : nil)
                stat("成交量", m.volumeName.map { "\($0) / 根" } ?? "无")
            }
            .font(.system(size: 12))
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line2).frame(height: 1) }
    }

    func stat(_ k: String, _ v: String?, _ color: Color = Theme.text) -> some View {
        HStack(spacing: 6) {
            Text(k).foregroundStyle(Theme.muted)
            Text(v ?? "—").monospacedDigit().fontWeight(.medium).foregroundStyle(color)
        }
        .help(k == "10分钟前" ? "涨跌的参考值：10 分钟前的读数（运行不足 10 分钟时用第一次读数）" :
              k == "成交量" ? "每根 K 线时间段内发生的次数" : "图上可见范围内")
    }
}

// MARK: - 主力动向 + 逐笔成交

struct RightPanel: View {
    @Bindable var store: Store

    var body: some View {
        let _ = store.revision
        VStack(spacing: 0) {
            header("主力动向", "按 CPU 占用", "前 \(store.rank.count)")
            VStack(spacing: 0) {
                let top = max(store.rank.first?.cpu ?? 1, 1)
                ForEach(Array(store.rank.enumerated()), id: \.element.pid) { i, p in
                    HStack(spacing: 8) {
                        Text("\(i + 1)").num(11, i < 3 ? .bold : .regular)
                            .foregroundStyle(i < 3 ? Theme.accentInk : Theme.muted)
                            .frame(width: 18, height: 18)
                            .background(i < 3 ? Theme.accent : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(i < 3 ? Theme.accent : Theme.line, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        Text(p.name).font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Fmt.value(p.cpu, 1) + "%").num(13).foregroundStyle(store.colors.up)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 27)
                    .background(alignment: .trailing) {
                        GeometryReader { g in
                            store.colors.up.opacity(0.14)
                                .frame(width: g.size.width * 0.62 * min(1, p.cpu / top))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.vertical, 3)
                        }
                    }
                    .help("PID \(p.pid)")
                }
                if store.rank.isEmpty {
                    Text("正在读取进程…").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(14)
                }
            }
            .padding(.vertical, 4)
            header("逐笔成交", "系统事件", nil)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.tape) { e in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Fmt.clock(e.time)).num(12).foregroundStyle(Theme.muted).frame(width: 62, alignment: .leading)
                            e.parts.reduce(Text("")) { acc, p in acc + Text(p.text).foregroundColor(color(p.tone)) }
                                .font(.system(size: 12)).lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 3)
                    }
                    if store.tape.isEmpty {
                        Text("还没有事件。指标急涨急跌、进程启动或退出时会记在这里。")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(14)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)
        }
    }

    func color(_ t: Tone) -> Color {
        switch t {
        case .up: store.colors.up
        case .down: store.colors.down
        case .plain: Theme.text
        case .muted: Theme.muted
        }
    }

    func header(_ title: String, _ sub: String, _ right: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(sub).font(.system(size: 11)).foregroundStyle(Theme.muted)
            Spacer()
            if let right { Text(right).font(.system(size: 11)).foregroundStyle(Theme.muted) }
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line2).frame(height: 1) }
    }
}

// MARK: - 状态栏

struct StatusBar: View {
    @Bindable var store: Store

    var body: some View {
        let _ = store.revision
        HStack(spacing: 18) {
            item("采样", intervalLabel(store.interval).replacingOccurrences(of: "秒", with: " 秒"))
            item("运行", Fmt.duration(store.lastSampleTime - store.startTime))
            item("进程", store.latest[MetricID.procs].map { Fmt.value($0, 0) } ?? "—")
            item("负载", store.latest[MetricID.load].map { Fmt.value($0, 2) } ?? "—")
            HStack(spacing: 22) {
                ForEach([MetricID.mem, MetricID.netIn, MetricID.diskRead, MetricID.cpuTemp].compactMap { store.byID[$0] }) { m in
                    let ch = store.change(m.id) ?? 0
                    HStack(spacing: 4) {
                        Text(m.name)
                        Text((store.latest[m.id].map { Fmt.value($0, m.decimals) } ?? "—") + m.unit + " " +
                             (ch > 0 ? "▲" : ch < 0 ? "▼" : ""))
                            .monospacedDigit().foregroundStyle(store.colors.tone(ch))
                    }
                }
            }
            .padding(.leading, 14)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
            Spacer(minLength: 0)
            Text("数据只保存在内存里，退出即清空").foregroundStyle(Theme.muted.opacity(0.7))
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.muted)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 28)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    func item(_ k: String, _ v: String) -> some View {
        HStack(spacing: 4) { Text(k); Text(v).monospacedDigit().fontWeight(.medium).foregroundStyle(Theme.text) }
    }
}
