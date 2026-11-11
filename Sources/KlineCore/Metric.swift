import Foundation

/// 自选行情里的分组（显示顺序即声明顺序）。
public enum MetricGroup: String, CaseIterable, Sendable {
    case market = "大盘"
    case cores = "处理器 · 逐核占用"
    case thermal = "温度 · 功耗"
    case io = "网络 · 磁盘"
    case system = "系统"
}

/// 一只“股票”：一个可采样的系统指标。
public struct MetricInfo: Identifiable, Hashable, Sendable {
    public let id: String
    /// 仿股票代码，只用于显示。
    public let code: String
    public let name: String
    /// 单位："%"、"°C"、"W"、"MB/s"、""。
    public let unit: String
    public let decimals: Int
    public let group: MetricGroup
    /// 成交量的含义（nil 表示这个指标没有对应的计数）。
    public let volumeName: String?
    /// 值域下限，画图时纵轴不低于它。
    public let floor: Double?
    /// 值域上限（百分比类为 100）。
    public let ceiling: Double?

    public init(id: String, code: String, name: String, unit: String, decimals: Int,
                group: MetricGroup, volumeName: String?, floor: Double? = 0, ceiling: Double? = nil) {
        self.id = id; self.code = code; self.name = name; self.unit = unit
        self.decimals = decimals; self.group = group; self.volumeName = volumeName
        self.floor = floor; self.ceiling = ceiling
    }

    public var isPercent: Bool { unit == "%" }

    /// 涨跌的单位：百分比指标的涨跌用“个百分点”(pt)，避免和相对涨幅的 % 混淆。
    public var changeUnit: String { isPercent ? "pt" : unit }
}

public enum MetricID {
    public static let cpu = "cpu"
    public static let gpu = "gpu"
    public static let mem = "mem"
    public static let cpuTemp = "cpuTemp"
    public static let gpuTemp = "gpuTemp"
    public static let power = "power"
    public static let netIn = "netIn"
    public static let netOut = "netOut"
    public static let diskRead = "diskRead"
    public static let diskWrite = "diskWrite"
    public static let procs = "procs"
    public static let load = "load"
    public static func core(_ i: Int) -> String { "core.\(i)" }
}

/// 核心类型：能效核 / 性能核。
public enum CoreKind: Sendable { case efficiency, performance }

public enum Catalog {
    /// 根据本机实际能读到的数据生成指标列表。
    public static func build(cores: [CoreKind], hasCPUTemp: Bool, hasGPUTemp: Bool, hasPower: Bool) -> [MetricInfo] {
        var list: [MetricInfo] = [
            MetricInfo(id: MetricID.cpu, code: "600001", name: "CPU 占用", unit: "%", decimals: 1,
                       group: .market, volumeName: "中断次数", ceiling: 100),
            MetricInfo(id: MetricID.gpu, code: "600002", name: "GPU 占用", unit: "%", decimals: 1,
                       group: .market, volumeName: nil, ceiling: 100),
            MetricInfo(id: MetricID.mem, code: "600003", name: "内存占用", unit: "%", decimals: 1,
                       group: .market, volumeName: "缺页次数", ceiling: 100),
        ]
        // 显示顺序：性能核在前（和设计稿一致），能效核在后；代码按显示顺序编号。
        let perf = cores.indices.filter { cores[$0] == .performance }
        let eff = cores.indices.filter { cores[$0] == .efficiency }
        var code = 600101
        for (n, i) in perf.enumerated() {
            list.append(MetricInfo(id: MetricID.core(i), code: String(code), name: "性能核 \(n + 1)", unit: "%",
                                   decimals: 1, group: .cores, volumeName: "中断次数", ceiling: 100))
            code += 1
        }
        for (n, i) in eff.enumerated() {
            list.append(MetricInfo(id: MetricID.core(i), code: String(code), name: "能效核 \(n + 1)", unit: "%",
                                   decimals: 1, group: .cores, volumeName: "中断次数", ceiling: 100))
            code += 1
        }
        if hasCPUTemp {
            list.append(MetricInfo(id: MetricID.cpuTemp, code: "600011", name: "CPU 温度", unit: "°C", decimals: 1,
                                   group: .thermal, volumeName: nil, floor: nil))
        }
        if hasGPUTemp {
            list.append(MetricInfo(id: MetricID.gpuTemp, code: "600012", name: "GPU 温度", unit: "°C", decimals: 1,
                                   group: .thermal, volumeName: nil, floor: nil))
        }
        if hasPower {
            list.append(MetricInfo(id: MetricID.power, code: "600013", name: "整机功耗", unit: "W", decimals: 1,
                                   group: .thermal, volumeName: nil))
        }
        list += [
            MetricInfo(id: MetricID.netIn, code: "600021", name: "网络下行", unit: "MB/s", decimals: 2,
                       group: .io, volumeName: "收包数"),
            MetricInfo(id: MetricID.netOut, code: "600022", name: "网络上行", unit: "MB/s", decimals: 2,
                       group: .io, volumeName: "发包数"),
            MetricInfo(id: MetricID.diskRead, code: "600023", name: "磁盘读取", unit: "MB/s", decimals: 2,
                       group: .io, volumeName: "读操作次数"),
            MetricInfo(id: MetricID.diskWrite, code: "600024", name: "磁盘写入", unit: "MB/s", decimals: 2,
                       group: .io, volumeName: "写操作次数"),
            MetricInfo(id: MetricID.procs, code: "600031", name: "进程数", unit: "", decimals: 0,
                       group: .system, volumeName: nil, floor: nil),
            MetricInfo(id: MetricID.load, code: "600032", name: "系统负载", unit: "", decimals: 2,
                       group: .system, volumeName: nil),
        ]
        return list
    }
}
