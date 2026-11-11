import SwiftUI
import KlineCore

struct MainView: View {
    @Bindable var store: Store
    @State private var chartWidth: CGFloat = 800

    var body: some View {
        VStack(spacing: 0) {
            TitleBar(store: store)
            IndexStrip(store: store)
            HStack(spacing: 0) {
                WatchList(store: store).frame(width: 300)
                Rectangle().fill(Theme.line).frame(width: 1)
                VStack(spacing: 0) {
                    let _ = store.revision
                    QuoteHeader(store: store, visible: store.chartData(width: chartWidth).visible)
                    KlineChart(store: store)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { chartWidth = $0 }
                }
                Rectangle().fill(Theme.line).frame(width: 1)
                RightPanel(store: store).frame(width: 320)
            }
            .frame(maxHeight: .infinity)
            StatusBar(store: store)
        }
        .foregroundStyle(Theme.text)
        .background(Theme.bg)
        .ignoresSafeArea()
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { store.selectNext(-1); return .handled }
        .onKeyPress(.downArrow) { store.selectNext(1); return .handled }
        .onKeyPress(.leftArrow) { store.chartScrollBack += 5; store.clampScroll(width: chartWidth); return .handled }
        .onKeyPress(.rightArrow) { store.chartScrollBack = max(0, store.chartScrollBack - 5); return .handled }
        .onKeyPress(.space) { store.paused.toggle(); return .handled }
        .onKeyPress(characters: .init(charactersIn: "12345")) { press in
            if let d = Int(press.characters), d >= 1, d <= Store.periods.count {
                let p = Store.periods[d - 1]
                if p >= store.interval { store.period = p }
            }
            return .handled
        }
    }
}
