import Foundation
import IOKit

/// 读 SMC（系统管理控制器）里的温度和功耗。苹果芯片上普通用户可读，不需要管理员权限。
///
/// 键名来自 Stats（https://github.com/exelban/stats ，MIT 许可证）的 Modules/Sensors/values.swift，
/// 只用了键名这一事实，读写代码是本项目按 AppleSMC 用户客户端的接口自己写的。
/// 口径与 Stats 一致：CPU 温度 = 能效核和性能核传感器的平均值；GPU 温度 = GPU 传感器平均值；
/// 整机功耗 = PSTR（Stats 称为 System Total）。
public final class SMCReader {
    /// 各代芯片的 CPU / GPU 温度键，逐条照抄自 Stats values.swift（2026-11-10 取的 master 版本）。
    /// 同一个键在不同代芯片上含义不同（例如 Tp09 在 M1 是能效核、在 M4 是性能核），所以必须按代数选，不能取并集。
    /// 键表里本机读不到的键（例如 M4 Pro 没有 Tg0G）会在初始化时剔除。
    static let keyTable: [String: (cpu: [String], gpu: [String])] = [
        "M1": (["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"],
               ["Tg05", "Tg0D", "Tg0L", "Tg0T"]),
        "M2": (["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"],
               ["Tg0f", "Tg0j"]),
        "M3": (["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",
                "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"],
               ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"]),
        "M4": (["Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"],
               ["Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"]),
        "M5": (["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U", "Tp0X",
                "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"],
               ["Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg1Y", "Tg1c", "Tg1g"]),
        "M6": (["Tp0j", "Tp0g", "Tp09", "Tp07", "Tp0m", "Tp0L", "Tp0I", "Tp0d", "Tp0E", "Tp0G", "Tp0b", "Tp05",
                "Te07", "Te08", "Te09", "Te0c", "Te0h", "Te0i"],
               ["Tg1e", "Tg0d", "Tg0c", "Tg0b", "Tg1c", "Tg1d", "Tg07", "Tg1f", "Tg09", "Tg0a", "Tg1g", "Tg1h"]),
        "A18": (["Te05", "Te0S", "Tp05", "Tp0D"], ["Tg05", "Tg0D", "Tg0L", "Tg0e"]),
    ]

    /// 从芯片名（如 "Apple M4 Pro"）取出代数（"M4"）；认不出返回 nil。
    public static func generation(fromBrand brand: String) -> String? {
        guard let r = brand.range(of: #"\b(M\d|A18)\b"#, options: .regularExpression) else { return nil }
        return String(brand[r])
    }

    public let chip: String

    private var conn: io_connect_t = 0
    private var infoCache: [UInt32: KeyInfo] = [:]
    public private(set) var cpuKeys: [String] = []
    public private(set) var gpuKeys: [String] = []
    public private(set) var hasPower = false

    public init() {
        chip = cpuBrand()
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return }
        defer { IOObjectRelease(svc) }
        guard IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { conn = 0; return }
        if let gen = Self.generation(fromBrand: chip), let keys = Self.keyTable[gen] {
            cpuKeys = keys.cpu.filter { Self.validTemp(readFloat($0)) }
            gpuKeys = keys.gpu.filter { Self.validTemp(readFloat($0)) }
        }
        hasPower = readFloat("PSTR") != nil
    }

    deinit { if conn != 0 { IOServiceClose(conn) } }

    static func validTemp(_ v: Float?) -> Bool { if let v { return v > 1 && v < 130 } else { return false } }

    public var cpuTemperature: Double? { average(cpuKeys) }
    public var gpuTemperature: Double? { average(gpuKeys) }
    public var systemPower: Double? {
        guard hasPower, let v = readFloat("PSTR"), v >= 0, v < 1000 else { return nil }
        return Double(v)
    }

    private func average(_ keys: [String]) -> Double? {
        let vals = keys.compactMap { readFloat($0) }.filter { Self.validTemp($0) }
        guard !vals.isEmpty else { return nil }
        return Double(vals.reduce(0, +)) / Double(vals.count)
    }

    // MARK: AppleSMC 用户客户端

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
        // C 结构体在这里有 3 字节对齐填充；Swift 不会自动补，所以显式写出，保证整体 80 字节。
        var pad: (UInt8, UInt8, UInt8) = (0, 0, 0)
    }

    struct Param {
        var key: UInt32 = 0
        var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
        var pLimit: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
        var keyInfo = KeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
            = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    static let selectorHandleYPCEvent: UInt32 = 2
    static let cmdReadBytes: UInt8 = 5
    static let cmdReadKeyInfo: UInt8 = 9
    static let typeFlt = fourCC("flt ")

    static func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    private func call(_ input: inout Param) -> Bool {
        var output = Param()
        var size = MemoryLayout<Param>.size
        let kr = IOConnectCallStructMethod(conn, Self.selectorHandleYPCEvent, &input, MemoryLayout<Param>.size, &output, &size)
        guard kr == KERN_SUCCESS, output.result == 0 else { return false }
        input = output
        return true
    }

    /// 读一个 "flt " 类型的键（4 字节小端浮点）。读不到或类型不对返回 nil。
    func readFloat(_ key: String) -> Float? {
        guard conn != 0 else { return nil }
        let k = Self.fourCC(key)
        var info = infoCache[k]
        if info == nil {
            var p = Param()
            p.key = k
            p.data8 = Self.cmdReadKeyInfo
            guard call(&p) else { return nil }
            info = p.keyInfo
            infoCache[k] = info
        }
        guard let info, info.dataType == Self.typeFlt, info.dataSize == 4 else { return nil }
        var p = Param()
        p.key = k
        p.keyInfo.dataSize = info.dataSize
        p.data8 = Self.cmdReadBytes
        guard call(&p) else { return nil }
        let b = p.bytes
        return Float(bitPattern: UInt32(b.0) | UInt32(b.1) << 8 | UInt32(b.2) << 16 | UInt32(b.3) << 24)
    }
}

func cpuBrand() -> String {
    var size = 0
    guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "" }
    var buf = [CChar](repeating: 0, count: size)
    guard sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0) == 0 else { return "" }
    return String(cString: buf)
}
