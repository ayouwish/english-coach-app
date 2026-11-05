import Foundation

/// 通用图表点（趋势/自定义曲线）。与网络 DTO 解耦：页面把业务数据映射成它。
struct ChartPoint: Identifiable, Hashable, Sendable {
    let id: Int
    /// 横轴（时间戳/序号/任意标量）。
    let x: Double
    /// 纵轴（通常 0...100 的分数）。
    let y: Double
    /// 横轴展示标签（如 "11-04"）。
    let label: String?

    init(id: Int, x: Double, y: Double, label: String? = nil) {
        self.id = id
        self.x = x
        self.y = y
        self.label = label
    }

    /// 按序号生成：x = index。
    init(index: Int, y: Double, label: String? = nil) {
        self.init(id: index, x: Double(index), y: y, label: label)
    }
}

/// 音高曲线整形结果（用户 / 示范两组，已按上限降采样）。
struct IntonationSeries: Hashable, Sendable {
    let user: [PitchPoint]
    let reference: [PitchPoint]

    init(user: [PitchPoint], reference: [PitchPoint]) {
        self.user = user
        self.reference = reference
    }

    var isEmpty: Bool {
        user.allSatisfy { $0.hz == nil } && reference.allSatisfy { $0.hz == nil }
    }
}

/// 图表数据整形工具：把业务数据（数组/元组）映射为 Core 图表组件的输入模型，
/// 并提供降采样、归一化、滑动平均等纯函数。**不 import 任何 DTO / Networking 类型**。
enum ChartsData {

    /// 音高曲线最多点数（与 `IntonationChart` 内部上限一致）。
    static let maxIntonationPoints = 200

    // MARK: - 音高

    /// 两组时间序列 → 音高曲线数据（自动配对、降采样）。
    static func intonationSeries(
        user: [(timeMs: Double, hz: Double?)],
        reference: [(timeMs: Double, hz: Double?)],
        limit: Int = 200
    ) -> IntonationSeries {
        IntonationSeries(
            user: pitchPoints(user, limit: limit),
            reference: pitchPoints(reference, limit: limit)
        )
    }

    /// [时间, 频率] 元组 → `PitchPoint`（id 为原始序号，保证唯一）。
    static func pitchPoints(_ pairs: [(timeMs: Double, hz: Double?)], limit: Int = 200) -> [PitchPoint] {
        let points = pairs.enumerated().map { index, pair in
            PitchPoint(id: index, timeMs: pair.timeMs, hz: normalizedHz(pair.hz))
        }
        return downsample(points, limit: limit)
    }

    /// 两个平行数组 → `PitchPoint`（长度以短的一侧为准，越界忽略）。
    static func pitchPoints(timesMs: [Double], hz: [Double?], limit: Int = 200) -> [PitchPoint] {
        let count = min(timesMs.count, hz.count)
        guard count > 0 else { return [] }
        let points = (0..<count).map { index in
            PitchPoint(id: index, timeMs: timesMs[index], hz: normalizedHz(hz[index]))
        }
        return downsample(points, limit: limit)
    }

    // MARK: - 趋势 / 雷达 / 柱状

    /// 平行数组 → 趋势点（标签可为空串）。
    static func trendPoints(labels: [String], values: [Double]) -> [TrendPoint] {
        let count = min(labels.count, values.count)
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            TrendPoint(id: index, label: labels[index], value: clampPercent(values[index]))
        }
    }

    /// 平行数组 → 雷达轴（nil 保留为「无数据」，不落 0）。
    static func radarMetrics(labels: [String], values: [Double?]) -> [RadarMetric] {
        let count = min(labels.count, values.count)
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            RadarMetric(id: index, label: labels[index], value: normalizedPercent(values[index]))
        }
    }

    /// 平行数组 → 柱状项（可选 tint 逐项指定语义色）。
    static func barValues(labels: [String], values: [Double], tints: [BarTint?] = []) -> [BarValue] {
        let count = min(labels.count, values.count)
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            BarValue(
                id: index,
                label: labels[index],
                value: clampPercent(values[index]),
                tint: index < tints.count ? tints[index] : nil
            )
        }
    }

    /// 单条分数序列 → 趋势点；`labels` 可省略（自动 1...N）。
    static func trendPoints(scores: [Double], labels: [String] = []) -> [TrendPoint] {
        let count = scores.count
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let label = index < labels.count ? labels[index] : "第 \(index + 1) 次"
            return TrendPoint(id: index, label: label, value: clampPercent(scores[index]))
        }
    }

    // MARK: - 转换

    /// 通用点 → 趋势点（取 y 值，x 丢弃；标签缺失时用序号）。
    static func trendPoints(from points: [ChartPoint]) -> [TrendPoint] {
        points.enumerated().map { index, point in
            TrendPoint(id: index, label: point.label ?? "\(index + 1)", value: clampPercent(point.y))
        }
    }

    /// 音高曲线 → 通用点（只保留有频率的点，用于自定义绘制/调试）。
    static func chartPoints(from series: [PitchPoint]) -> [ChartPoint] {
        var result: [ChartPoint] = []
        for point in series {
            guard let hz = point.hz, hz.isFinite else { continue }
            result.append(ChartPoint(id: result.count, x: point.timeMs, y: hz))
        }
        return result
    }

    // MARK: - 整形工具

    /// 均匀降采样（保留首尾），最多 `limit` 个。
    static func downsample<T>(_ items: [T], limit: Int = 200) -> [T] {
        guard limit > 1, items.count > limit else { return items }
        let step = Double(items.count - 1) / Double(limit - 1)
        return (0..<limit).map { index in
            items[min(items.count - 1, Int((Double(index) * step).rounded()))]
        }
    }

    /// 只取最后 `limit` 条（「最近 N 次」语义），再降采样。
    static func recent<T>(_ items: [T], limit: Int = 30) -> [T] {
        guard limit > 0, items.count > limit else { return items }
        return Array(items.suffix(limit))
    }

    /// min-max 归一化到 0...100；全等值返回 50，nil 保持 nil。
    static func normalize(_ values: [Double?]) -> [Double?] {
        let valid = values.compactMap { $0 }.filter { $0.isFinite }
        guard let lower = valid.min(), let upper = valid.max() else { return values.map { _ in nil } }
        guard upper > lower else { return values.map { value in value == nil ? nil : 50 } }
        return values.map { value in
            guard let value, value.isFinite else { return nil }
            return (value - lower) / (upper - lower) * 100
        }
    }

    /// 有效值平均（跳过 nil/NaN）。
    static func average(_ values: [Double?]) -> Double? {
        let valid = values.compactMap { $0 }.filter { $0.isFinite }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    /// 简单滑动平均（窗口不足时按实际数量平均）。
    static func movingAverage(_ values: [Double], window: Int = 3) -> [Double] {
        guard window > 1, values.count > 1 else { return values }
        let safeWindow = min(window, values.count)
        return values.indices.map { index in
            let lower = max(0, index - safeWindow + 1)
            let slice = values[lower...index]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    /// 0...100 夹取；非有限值落 0。
    static func clampPercent(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 100)
    }

    /// 0...100 夹取，nil 保持 nil。
    static func normalizedPercent(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return clampPercent(value)
    }

    /// 频率兜底：<=0 / 非有限值视为清音段（nil）。
    static func normalizedHz(_ hz: Double?) -> Double? {
        guard let hz, hz.isFinite, hz > 0 else { return nil }
        return hz
    }
}
