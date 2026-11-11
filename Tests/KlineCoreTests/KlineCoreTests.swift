import Testing
@testable import KlineCore

@Suite("K 线聚合")
struct CandleTests {
    @Test("按周期对齐分桶，开高低收和成交量正确")
    func aggregate() {
        let s = Series(capacity: 1000)
        // 时间 100..109，每秒一个点；值 = [1,5,2,3,4 | 6,0,7,8,9]；计数每点 10
        let vals: [Double] = [1, 5, 2, 3, 4, 6, 0, 7, 8, 9]
        for (i, v) in vals.enumerated() { s.append(time: 100 + Double(i), value: v, count: 10) }
        let cs = s.candles(period: 5, maxCount: 10)
        #expect(cs.count == 2)
        #expect(cs[0] == Candle(start: 100, open: 1, high: 5, low: 1, close: 4, volume: 50, sampleCount: 5))
        #expect(cs[1] == Candle(start: 105, open: 6, high: 9, low: 0, close: 9, volume: 50, sampleCount: 5))
    }

    @Test("周期不整除时按绝对时间对齐，最新一根可以是未走完的")
    func partial() {
        let s = Series(capacity: 1000)
        for i in 0..<7 { s.append(time: 98 + Double(i), value: Double(i), count: nil) } // 98..104
        let cs = s.candles(period: 5, maxCount: 10)
        #expect(cs.map(\.start) == [95, 100])
        #expect(cs[0].open == 0 && cs[0].close == 1 && cs[0].sampleCount == 2)
        #expect(cs[1].open == 2 && cs[1].close == 6 && cs[1].sampleCount == 5)
        #expect(cs[1].volume == nil)
    }

    @Test("maxCount 只取最新的几根；中间断档不补空 K 线")
    func gapAndLimit() {
        let s = Series(capacity: 1000)
        for t in [0.0, 1, 2, 20, 21, 40] { s.append(time: t, value: t, count: 1) }
        #expect(s.candles(period: 5, maxCount: 10).map(\.start) == [0, 20, 40])
        #expect(s.candles(period: 5, maxCount: 2).map(\.start) == [20, 40])
    }

    @Test("时间不递增的点被丢弃；超容量会删掉最旧的点")
    func capacity() {
        let s = Series(capacity: 100)
        s.append(time: 5, value: 1, count: nil)
        s.append(time: 5, value: 2, count: nil)
        #expect(s.values == [1])
        for i in 0..<500 { s.append(time: 10 + Double(i), value: Double(i), count: nil) }
        #expect(s.values.count <= 100 + 64)
        #expect(s.values.last == 499)
    }

    @Test("按时间查历史值")
    func lookup() {
        let s = Series(capacity: 100)
        for i in 0..<10 { s.append(time: Double(i * 2), value: Double(i), count: nil) } // t=0,2,...,18
        #expect(s.value(atOrBefore: 7) == 3)
        #expect(s.value(atOrBefore: 8) == 4)
        #expect(s.value(atOrBefore: -5) == 0)
        #expect(s.value(atOrBefore: 100) == 9)
    }
}

@Suite("均线")
struct MATests {
    @Test("MA3 手算对照")
    func ma() {
        let r = movingAverage([1, 2, 3, 4, 5, 6], 3)
        #expect(r[0] == nil && r[1] == nil)
        #expect(r[2] == 2 && r[3] == 3 && r[4] == 4 && r[5] == 5)
    }
}

@Suite("进程解析")
struct PSTests {
    @Test("ps 时间格式")
    func time() {
        #expect(ProcessSampler.parseCPUTime("0:01.75") == 1.75)
        #expect(ProcessSampler.parseCPUTime("744:17.53")! - (744 * 60 + 17.53) < 1e-9)
        #expect(ProcessSampler.parseCPUTime("1:02:03.50") == 3723.5)
        #expect(ProcessSampler.parseCPUTime("2-01:00:00.00") == 176_400.0)
        #expect(ProcessSampler.parseCPUTime("abc") == nil)
    }

    @Test("路径含空格时取最后一段做名字")
    func parse() {
        let text = """
          123   0:01.00 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper (Renderer)
            1  10:00.00 /sbin/launchd
          bad line
        """
        let rows = ProcessSampler.parse(text)
        #expect(rows.count == 2)
        #expect(rows[0].pid == 123 && rows[0].name == "Google Chrome Helper (Renderer)" && rows[0].cpuSeconds == 1)
        #expect(rows[1].name == "launchd" && rows[1].cpuSeconds == 600)
    }
}

@Suite("格式与目录")
struct MiscTests {
    @Test("涨跌符号用减号，四舍五入后为 0 不带符号")
    func fmt() {
        #expect(Fmt.signed(2.345, 1, "pt") == "+2.3pt")
        #expect(Fmt.signed(-0.04, 1) == "0.0")
        #expect(Fmt.signed(-1.25, 2, "°C") == "−1.25°C")
        #expect(Fmt.value(-3, 0) == "−3")
        #expect(Fmt.value(-0.01, 1) == "0.0")
        #expect(Fmt.count(123456) == "12.3万")
    }

    @Test("芯片代数识别")
    func chip() {
        #expect(SMCReader.generation(fromBrand: "Apple M4 Pro") == "M4")
        #expect(SMCReader.generation(fromBrand: "Apple M1") == "M1")
        #expect(SMCReader.generation(fromBrand: "Apple A18 Pro") == "A18")
        #expect(SMCReader.generation(fromBrand: "Intel(R) Core(TM) i9") == nil)
    }

    @Test("指标目录：性能核在前、代码不重复")
    func catalog() {
        let kinds: [CoreKind] = [.efficiency, .efficiency, .performance, .performance, .performance]
        let c = Catalog.build(cores: kinds, hasCPUTemp: false, hasGPUTemp: true, hasPower: true)
        let cores = c.filter { $0.group == .cores }
        #expect(cores.map(\.name) == ["性能核 1", "性能核 2", "性能核 3", "能效核 1", "能效核 2"])
        #expect(cores.map(\.id) == ["core.2", "core.3", "core.4", "core.0", "core.1"])
        #expect(Set(c.map(\.code)).count == c.count)
        #expect(!c.contains { $0.id == MetricID.cpuTemp })
    }

    @Test("异动事件：超过阈值才记，冷却期内不重复")
    func tape() {
        let m = Catalog.build(cores: [], hasCPUTemp: false, hasGPUTemp: false, hasPower: false).filter { $0.id == MetricID.cpu }
        let s = Series(capacity: 100)
        let eng = TapeEngine()
        for t in 0..<6 { s.append(time: Double(t), value: 10, count: nil) }
        #expect(eng.metricEvents(time: 5, metrics: m, series: [MetricID.cpu: s]).isEmpty)
        s.append(time: 6, value: 25, count: nil)
        let e = eng.metricEvents(time: 6, metrics: m, series: [MetricID.cpu: s])
        #expect(e.count == 1)
        #expect(e.first?.parts.first?.text == "CPU 占用拉升 +15.0pt → 25.0%")
        s.append(time: 7, value: 40, count: nil)
        #expect(eng.metricEvents(time: 7, metrics: m, series: [MetricID.cpu: s]).isEmpty)
    }
}
