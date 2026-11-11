# 性能行情 perf-kline

把 Mac 的系统占用画成炒股软件那样的 K 线行情：CPU、每个核、GPU、内存、温度、功耗、网络、磁盘……每一项都是一只“股票”，有 K 线、均线、成交量、涨跌，还有按 CPU 排的“主力动向”和记录系统异动的“逐笔成交”。完整窗口 + 菜单栏小行情。

- 原生 macOS App（Swift + SwiftUI + AppKit），只用苹果系统自带的框架，没有第三方依赖。
- 只支持苹果芯片的 Mac，macOS 14 及以上。在 M4 Pro / macOS 27.2 上开发和验证过，其他机型没测过。
- 不需要管理员权限，不联网，数据只在内存里（最多保留 4 小时），退出即清空。
- 深色外观用“石墨”配色，浅色外观自动换成浅色配色；默认红涨绿跌，可一键切换为绿涨红跌。

灵感来自 Windows 上的 [PerfTicker](https://github.com/QiuSui1145/PerfTicker)（GPL-3.0）。本项目只借用了“把性能指标当股票看”的思路，代码全部重新写，没有用它的代码。

## 功能

- **指数条**：CPU、GPU、内存、CPU 温度、网络下行、整机功耗，带小 K 线。
- **自选行情**：所有指标按“大盘 / 处理器逐核 / 温度功耗 / 网络磁盘 / 系统”分组，点一行就在中间看它的 K 线。
- **K 线主图**：2 秒 / 5 秒 / 10 秒 / 30 秒 / 1 分钟周期；MA5 / MA10 / MA20；成交量；十字光标显示开高低收、涨跌、成交量。
- **主力动向**：CPU 占用前 10 的进程（包括系统进程）。
- **逐笔成交**：指标急涨急跌、进程启动 / 退出、主力进程占用明显变化时记一条。
- **菜单栏小行情**：12 根小 K 线 + 当前读数，可选显示哪一项；关掉窗口后继续在菜单栏运行。

几个约定：

- **涨跌**是和 **10 分钟前**的读数相比（运行不足 10 分钟时和第一次读数比）。百分比类指标的涨跌单位是“个百分点”（pt）。
- **成交量**是每根 K 线时间段内真实发生的次数，每个指标用和它相关的计数：CPU / 各核 = 中断次数，内存 = 缺页次数，网络 = 收 / 发包数，磁盘 = 读 / 写操作次数。GPU、温度、功耗、进程数、负载没有对应的计数，图上会写明，不硬凑。
- 逐笔成交的触发规则和阈值是本项目自定的，集中在 `Sources/KlineCore/Tape.swift` 顶部。

## 操作

| 操作 | 作用 |
|---|---|
| 点指数块 / 自选行情的一行，或 `↑` `↓` | 切换主图显示的指标 |
| 数字键 `1`–`5` | 切换 K 线周期（不能短于采样间隔） |
| 上下滚动、双指捏合 | 缩放 K 线 |
| 左右滑动、按住拖动、`←` `→` | 翻看历史 |
| 双击图表 | 回到最新 |
| 空格 | 暂停 / 继续采样 |
| 标题栏按钮 | 采样间隔 0.5 / 1 / 2 / 5 秒、暂停、窗口置顶、切换涨跌配色 |

## 安装

目前没有发布编译好的版本，需要自己构建（要装 Xcode 16 或更新版本）：

```sh
git clone https://github.com/chang0220/perf-kline.git
cd perf-kline
scripts/build-app.sh            # 生成 dist/性能行情.app
open dist/性能行情.app
```

App 是本机自签名的，没有经过苹果公证；如果系统拦下，右键 → 打开。

## 开发

```sh
swift test                      # 单元测试（K 线聚合、均线、ps 解析、格式、事件规则等）
scripts/build-app.sh [目录]     # 打包到 dist/，给了目录就再复制一份过去
.build/release/PerfKline --selftest 10   # 每秒打印一行原始读数，用来和 top / netstat / iostat 对照
.build/release/PerfKline --snapshot 图.png --after 60 --appearance dark --hover 150,250   # 离屏截图（不需要录屏权限）
.build/release/PerfKline --snapshot 图.png --after 50 --threads --real-visibility [--close-window]   # 按线程统计 App 自身 CPU
.build/release/PerfKline --snapshot 图.png --after 60 --scroll-test   # 向 K 线图发滚轮事件，检查缩放和翻历史的限位
```

代码结构：`Sources/KlineCore`（采样、K 线聚合、事件，带测试）+ `Sources/PerfKline`（界面）。开发状态、设计决定和问题记录见 [docs/开发记录.md](docs/开发记录.md)。

## 已知问题

- **窗口开着时 App 自身约占 4% 单核 CPU**（1 秒采样，M4 Pro 实测），没达到 3% 的目标；窗口关掉只剩菜单栏时约 0.5%。原因和测量方法见开发记录。
- 键盘操作、触控板捏合 / 拖动、置顶、菜单栏下拉菜单还没有系统地测过。
- 苹果芯片不向普通程序公开逐核实时频率，所以只画占用率；全系统的上下文切换次数也读不到，所以 CPU 的成交量用中断次数。

## 数据来源与查证（2026-11-10，M4 Pro / macOS 27.2，不需要管理员权限）

| 指标 | 来源 | 说明 |
|---|---|---|
| CPU 总占用、逐核占用 | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` 两次 tick 相减 | 核心类型读 IODeviceTree 的 `cluster-type` + `logical-cpu-id`；本机 0–3 号是能效核 |
| CPU 中断次数（成交量） | `host_processor_info(PROCESSOR_CPU_STAT64)` 的 `irq_ex_cnt` | 全系统上下文切换次数普通程序读不到（`ps` 的 nvcsw 字段在 macOS 上是空的），所以用中断 |
| 内存占用 | `host_statistics64`：(internal − purgeable + wired + compressor) × 页大小 ÷ 物理内存 | 与“活动监视器”的“已使用内存”同口径（App 内存 + 联动 + 被压缩） |
| GPU 占用 | IOKit `IOAccelerator` → `PerformanceStatistics["Device Utilization %"]` | 整数百分比 |
| CPU / GPU 温度、整机功耗 | SMC（AppleSMC 用户客户端）| 键名和口径照 Stats（见下）；CPU 温度 = 各核传感器平均；功耗 = `PSTR`。按芯片代数（M1–M6、A18）选键，认不出的芯片不显示温度 |
| 网络 | `getifaddrs` 的 `if_data`，只算 `en*` 接口 | VPN 的 `utun` 会把同一份流量再算一遍，所以不算 |
| 磁盘 | IOKit `IOBlockStorageDriver` 的 `Statistics` | 与 `iostat` 同一数据源 |
| 进程排行 | `/bin/ps -axo pid=,time=,comm=` 两次相减，每 2 秒一次 | `proc_pidinfo` 读不到其他用户的进程（本机 881 个里 299 个读不到）；`ps` 带 setuid 能读全，单次约 26 毫秒。`top` 也能读全但单次 0.35 秒 CPU，会把 CPU 占用本身抬高，不用 |
| 进程数、负载 | `proc_listallpids`、`getloadavg` | |

**读不到、所以不做的**：苹果芯片的逐核实时频率（系统不向普通程序公开）、全系统上下文切换次数。

### 和系统工具对照（通过线在看数据前定好）

| 项目 | 本 App 采样器 | 标准工具 | 差距 | 通过线 | 结果 |
|---|---|---|---|---|---|
| CPU 10 秒平均 | 14.55% | `top` 13.61% | 0.94 个百分点 | ≤ 5 个百分点 | 过 |
| 网络下行总量（下载 80 MB） | 83.879 MB | `netstat -ib` 83.883 MB | 0.005% | ≤ 5% | 过 |
| 磁盘读写总量（写 300 MB） | 334.2 MB | `iostat` 316.2 MB | 5.7% | ≤ 10% | 过 |
| 4 个满载 `yes` 进程 | 每个约 100% | 理论 100% | — | 接近 100% | 过 |
| App 自身 CPU（窗口可见） | 4.12% / 4.12% | — | — | ≤ 3% | **没过**，见已知问题 |
| App 自身 CPU（只剩菜单栏） | 0.45% / 0.64% | — | — | ≤ 1.5% | 过 |

过程中出过两次量具问题，都是对照脚本的错、不是采样器的错：第一次磁盘差 23% 是两边计时窗口没对齐（同窗口重测差 5%）；网络头两次没测到是下载命令本身没成功（静默参数把错误吞了）。

满载时的旁证：CPU 从 11.5% 升到 38%（4 个满核 ÷ 14 核 ≈ 28.6 个百分点，对得上）；功耗 9 W → 31.5 W，比负载变化晚约 2 秒（SMC 本身有平滑）；CPU 温度 45 → 50°C。功耗和温度没有能在本机不用管理员权限对照的标准工具（`powermetrics` 要 sudo），只验证了方向和量级。

## 灵感来源、借鉴与许可证

- 原版 **PerfTicker**：https://github.com/QiuSui1145/PerfTicker ，C# / Windows 专用，**GPL-3.0**。只学公开思路（指标当“个股”、K 线、主力动向、逐笔成交），**没有看或抄它的代码和数值**（包括它的“营收”公式参数）。
- 跨平台重写 **perfticker-mcpp**：https://github.com/ztuqfvy/perfticker-mcpp ，没有许可证文件（不能合法拿来改）、没有发布包、没人验证过 Mac 上能跑，所以没用。
- **Stats**：https://github.com/exelban/stats ，**MIT**。只借用了“各代芯片的 SMC 温度键名”这一事实（2026-11-10 从 `Modules/Sensors/values.swift` 原文逐条核对），以及内存占用和温度平均的口径；读 SMC 的代码是本项目自己按接口写的。
- 本项目全部代码为本项目自写，没有打包第三方库，只用苹果系统自带的框架。
- 许可证：[MIT](LICENSE)。
- K 线（开高低收）和简单移动平均 MA(n) 用的是行情软件的通行定义：MA(n) = 最近 n 根收盘价的算术平均。
