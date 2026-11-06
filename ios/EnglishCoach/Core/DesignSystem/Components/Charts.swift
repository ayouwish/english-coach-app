import Charts
import SwiftUI

// MARK: - 图表输入模型（Core 自包含，Feature 侧用 `Features/Shared/ChartsData` 整形）

/// 音高采样点：`timeMs` 为相对毫秒，`hz == nil` 表示清音段（曲线在此断开）。
struct PitchPoint: Identifiable, Hashable, Sendable {
    let id: Int
    let timeMs: Double
    let hz: Double?

    init(id: Int, timeMs: Double, hz: Double?) {
        self.id = id
        self.timeMs = timeMs
        self.hz = hz
    }
}

/// 趋势点（历次总分 / 掌握度），`value` 为 0...100。
struct TrendPoint: Identifiable, Hashable, Sendable {
    let id: Int
    let label: String
    let value: Double

    init(id: Int, label: String, value: Double) {
        self.id = id
        self.label = label
        self.value = value
    }
}

/// 雷达图单轴：`value == nil` 表示该维度无数据（不参与多边形）。
struct RadarMetric: Identifiable, Hashable, Sendable {
    let id: Int
    let label: String
    let value: Double?

    init(id: Int, label: String, value: Double?) {
        self.id = id
        self.label = label
        self.value = value
    }
}

/// 柱状图语义色（不把 hex 带到页面）。
enum BarTint: String, CaseIterable, Hashable, Sendable {
    case primary
    case success
    case warning
    case danger
    case info
    case child

    var color: Color {
        switch self {
        case .primary: return Tokens.Colors.primary
        case .success: return Tokens.Colors.success
        case .warning: return Tokens.Colors.warning
        case .danger: return Tokens.Colors.danger
        case .info: return Tokens.Colors.info
        case .child: return Tokens.Colors.childAccent
        }
    }
}

/// 柱状图单项，`value` 期望 0...100。
struct BarValue: Identifiable, Hashable, Sendable {
    let id: Int
    let label: String
    let value: Double
    let tint: BarTint?

    init(id: Int, label: String, value: Double, tint: BarTint? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.tint = tint
    }
}

// MARK: - 音高曲线

/// 音高（语调）曲线：user 实线（主色）/ reference 虚线（灰）。
///
/// 实现要点（对齐 HOS `PitchChart` 的真机修复经验）：
/// - **全部用实际点坐标计算**：`Canvas` 的 `size` 是点（pt），所有 Path 坐标都由
///   `plot.minX + 比例 * plot.width` 显式求出，混用比例坐标会导致只画一半；
/// - 空数据 → 占位文案；单点 → 画圆点（不画退化为空的折线）；
/// - 清音段（hz 为 nil）自动断笔，不跨段连线；
/// - 采样点数超过 200 自动降采样。
///
/// 儿童模式由页面决定是否渲染（design-system：语调曲线仅成人显示）。
struct IntonationChart: View {
    let user: [PitchPoint]
    var reference: [PitchPoint] = []
    var height: CGFloat = 160
    var showsLegend: Bool = true

    @Environment(\.roleCapabilities) private var caps

    init(user: [PitchPoint], reference: [PitchPoint] = [], height: CGFloat = 160, showsLegend: Bool = true) {
        self.user = user
        self.reference = reference
        self.height = height
        self.showsLegend = showsLegend
    }

    private var sampledUser: [PitchPoint] { ChartSampling.evenDownsample(user, limit: ChartSampling.maxIntonationPoints) }
    private var sampledReference: [PitchPoint] { ChartSampling.evenDownsample(reference, limit: ChartSampling.maxIntonationPoints) }

    private var hasValidPitch: Bool {
        (sampledUser + sampledReference).contains { point in
            guard let hz = point.hz else { return false }
            return hz.isFinite && hz > 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s8) {
            if hasValidPitch {
                Canvas { context, size in
                    draw(series: sampledReference, color: Tokens.Colors.textTertiary, dashed: true, in: &context, size: size)
                    draw(series: sampledUser, color: Tokens.Colors.primary, dashed: false, in: &context, size: size)
                }
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                        .fill(Tokens.Colors.surfaceSunken)
                )
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous))
                if showsLegend {
                    legend
                }
            } else {
                ChartPlaceholder(text: "暂无音高数据", height: height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("音高曲线"))
        .accessibilityValue(Text(hasValidPitch ? "蓝色是你的音调，灰色是示范音调" : "暂无数据"))
    }

    // MARK: 绘制

    private func plotRect(in size: CGSize) -> CGRect {
        CGRect(
            x: Tokens.Spacing.s8,
            y: Tokens.Spacing.s8,
            width: max(1, size.width - Tokens.Spacing.s8 * 2),
            height: max(1, size.height - Tokens.Spacing.s8 * 2)
        )
    }

    /// 绘制一条曲线。坐标一律由「时间 → x」「频率 → y」显式换算，Path 只用点坐标。
    private func draw(series: [PitchPoint], color: Color, dashed: Bool, in context: inout GraphicsContext, size: CGSize) {
        let plot = plotRect(in: size)
        let times = timeBounds
        let frequencies = hzBounds
        let timeSpan = max(times.upperBound - times.lowerBound, 0.001)
        let hzSpan = max(frequencies.upperBound - frequencies.lowerBound, 0.001)

        var runs: [[CGPoint]] = []
        var currentRun: [CGPoint] = []

        for point in series {
            guard let hz = point.hz, hz.isFinite, hz > 0, point.timeMs.isFinite else {
                if !currentRun.isEmpty {
                    runs.append(currentRun)
                    currentRun = []
                }
                continue
            }
            let xRatio = (point.timeMs - times.lowerBound) / timeSpan
            let yRatio = (hz - frequencies.lowerBound) / hzSpan
            let x = plot.minX + CGFloat(xRatio) * plot.width
            let y = plot.maxY - CGFloat(yRatio) * plot.height
            currentRun.append(CGPoint(x: x, y: y))
        }
        if !currentRun.isEmpty {
            runs.append(currentRun)
        }

        for run in runs {
            if run.count == 1 {
                let center = run[0]
                let dot = Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4))
                context.fill(dot, with: .color(color))
                continue
            }
            var path = Path()
            path.addLines(run)
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(
                    lineWidth: dashed ? 1.5 : 2,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: dashed ? [5, 4] : []
                )
            )
        }
    }

    private var timeBounds: ClosedRange<Double> {
        var lower = Double.greatestFiniteMagnitude
        var upper = -Double.greatestFiniteMagnitude
        for point in sampledUser + sampledReference {
            guard point.timeMs.isFinite, let hz = point.hz, hz.isFinite, hz > 0 else { continue }
            lower = min(lower, point.timeMs)
            upper = max(upper, point.timeMs)
        }
        guard lower.isFinite, upper.isFinite, lower < upper else {
            let anchor = lower.isFinite ? lower : 0
            return (anchor - 1)...(anchor + 1)
        }
        return lower...upper
    }

    private var hzBounds: ClosedRange<Double> {
        var lower = Double.greatestFiniteMagnitude
        var upper = -Double.greatestFiniteMagnitude
        for point in sampledUser + sampledReference {
            guard let hz = point.hz, hz.isFinite, hz > 0 else { continue }
            lower = min(lower, hz)
            upper = max(upper, hz)
        }
        guard lower.isFinite, upper.isFinite else { return 0.0...1.0 }
        if lower >= upper {
            return (lower - 10)...(lower + 10)
        }
        return (lower - 10)...(upper + 10)
    }

    private var legend: some View {
        HStack(spacing: Tokens.Spacing.s12) {
            legendItem(color: Tokens.Colors.primary, text: "你的音调")
            legendItem(color: Tokens.Colors.textTertiary, text: "示范音调")
        }
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: Tokens.Spacing.s4) {
            Capsule(style: .continuous)
                .fill(color)
                .frame(width: 12, height: 3)
            Text(text)
                .font(AppFont.micro(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
        }
    }
}

// MARK: - 趋势折线

/// 历次总分/掌握度趋势。空数据占位、单点只画点、最多 200 点。
struct TrendLineChart: View {
    let points: [TrendPoint]
    var height: CGFloat = 160
    var showsPointLabels: Bool = true

    @Environment(\.roleCapabilities) private var caps

    init(points: [TrendPoint], height: CGFloat = 160, showsPointLabels: Bool = true) {
        self.points = points
        self.height = height
        self.showsPointLabels = showsPointLabels
    }

    private var sampled: [TrendPoint] {
        ChartSampling.evenDownsample(points, limit: ChartSampling.maxIntonationPoints)
    }

    private var showsLabels: Bool {
        showsPointLabels && caps.showsNumericScore && sampled.count <= 8
    }

    var body: some View {
        if sampled.isEmpty {
            ChartPlaceholder(text: "还没有趋势数据", height: height)
        } else {
            Chart(sampled) { point in
                AreaMark(
                    x: .value("时间", point.label),
                    y: .value("分数", clamped(point.value))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Tokens.Colors.primary.opacity(0.18), Tokens.Colors.primary.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("时间", point.label),
                    y: .value("分数", clamped(point.value))
                )
                .foregroundStyle(Tokens.Colors.primary)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("时间", point.label),
                    y: .value("分数", clamped(point.value))
                )
                .foregroundStyle(Tokens.Colors.primary)
                .symbolSize(sampled.count <= 30 ? 36 : 0)
                .annotation(position: .top, alignment: .center) {
                    if showsLabels {
                        Text(String(Int(clamped(point.value).rounded())))
                            .font(AppFont.micro(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                    }
                }
            }
            .chartYScale(domain: 0.0...100.0)
            .chartYAxis(caps.showsNumericScore ? .automatic : .hidden)
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Tokens.Colors.borderSubtle)
                    AxisValueLabel().font(AppFont.micro(caps))
                }
            }
            .frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("分数趋势"))
            .accessibilityValue(Text(accessibilityValue))
        }
    }

    private var accessibilityValue: String {
        guard let first = sampled.first, let last = sampled.last else { return "暂无数据" }
        if caps.showsNumericScore {
            return "共 \(sampled.count) 次，从 \(Int(clamped(first.value).rounded())) 分到 \(Int(clamped(last.value).rounded())) 分"
        }
        return "共 \(sampled.count) 次记录"
    }

    private func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 100)
    }
}

// MARK: - 音素雷达图

/// 发音分项雷达图（自定义 Path，不依赖 Swift Charts 的雷达支持）。
/// 少于 3 个维度或有效值少于 3 个时显示占位，避免画出退化的多边形。
struct PhonemeRadarChart: View {
    let metrics: [RadarMetric]
    var size: CGFloat = 240
    var showsValues: Bool = true

    @Environment(\.roleCapabilities) private var caps

    init(metrics: [RadarMetric], size: CGFloat = 240, showsValues: Bool = true) {
        self.metrics = metrics
        self.size = size
        self.showsValues = showsValues
    }

    private var validCount: Int {
        metrics.compactMap { $0.value }.filter { $0.isFinite }.count
    }

    private var showsNumber: Bool {
        showsValues && caps.showsNumericScore
    }

    var body: some View {
        if metrics.count < 3 || validCount < 3 {
            ChartPlaceholder(text: "数据不足，暂时画不出雷达图", height: size)
        } else {
            GeometryReader { proxy in
                let layout = RadarLayout(
                    center: CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2),
                    radius: min(proxy.size.width, proxy.size.height) * 0.29,
                    count: metrics.count
                )
                ZStack(alignment: .topLeading) {
                    ForEach(RadarLayout.ringRatios, id: \.self) { ratio in
                        polygonPath(layout: layout, ratio: ratio)
                            .stroke(Tokens.Colors.borderSubtle, lineWidth: 1)
                    }
                    ForEach(0..<metrics.count, id: \.self) { index in
                        Path { path in
                            path.move(to: layout.center)
                            path.addLine(to: layout.point(index: index, ratio: 1))
                        }
                        .stroke(Tokens.Colors.borderSubtle, lineWidth: 1)
                    }
                    scorePath(layout: layout)
                        .fill(Tokens.Colors.primary.opacity(0.18))
                    scorePath(layout: layout)
                        .stroke(Tokens.Colors.primary, lineWidth: 2)
                    ForEach(metrics.indices, id: \.self) { index in
                        labelView(
                            for: metrics[index],
                            at: layout.point(index: index, ratio: 1.20)
                        )
                    }
                }
            }
            .frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("发音分项雷达图"))
            .accessibilityValue(Text(accessibilityValue))
        }
    }

    private func polygonPath(layout: RadarLayout, ratio: Double) -> Path {
        Path { path in
            for index in 0..<metrics.count {
                let point = layout.point(index: index, ratio: ratio)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
        }
    }

    private func scorePath(layout: RadarLayout) -> Path {
        Path { path in
            var started = false
            for (index, metric) in metrics.enumerated() {
                guard let value = metric.value, value.isFinite else { continue }
                let ratio = min(max(value, 0), 100) / 100
                let point = layout.point(index: index, ratio: ratio)
                if started {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                    started = true
                }
            }
            if started {
                path.closeSubpath()
            }
        }
    }

    private func labelView(for metric: RadarMetric, at point: CGPoint) -> some View {
        VStack(spacing: 1) {
            Text(metric.label)
                .font(AppFont.micro(caps).weight(.semibold))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .lineLimit(1)
            if showsNumber, let value = metric.value, value.isFinite {
                Text(String(Int(min(max(value, 0), 100).rounded())))
                    .font(AppFont.micro(caps))
                    .foregroundStyle(Tokens.Colors.primary)
                    .lineLimit(1)
            }
        }
        .frame(width: 68)
        .position(x: point.x, y: point.y)
    }

    private var accessibilityValue: String {
        metrics.map { metric in
            guard let value = metric.value, value.isFinite else { return "\(metric.label) 暂无数据" }
            if caps.showsNumericScore {
                return "\(metric.label) \(Int(min(max(value, 0), 100).rounded()))"
            }
            return metric.label
        }
        .joined(separator: "，")
    }
}

/// 雷达图几何：角度从正上方开始顺时针均分。
private struct RadarLayout {
    static let ringRatios: [Double] = [0.25, 0.5, 0.75, 1.0]

    let center: CGPoint
    let radius: CGFloat
    let count: Int

    func point(index: Int, ratio: Double) -> CGPoint {
        let safeCount = max(count, 1)
        let angle = -Double.pi / 2 + Double(index) / Double(safeCount) * 2 * Double.pi
        let scaled = radius * CGFloat(ratio)
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * scaled,
            y: center.y + CGFloat(sin(angle)) * scaled
        )
    }
}

// MARK: - 柱状图

/// 通用柱状图（分项分数、音素掌握度、家长统计）。`value` 期望 0...100。
struct BarChartView: View {
    let items: [BarValue]
    var height: CGFloat = 160
    var tint: Color = Tokens.Colors.primary
    var showsValues: Bool = true

    @Environment(\.roleCapabilities) private var caps

    init(items: [BarValue], height: CGFloat = 160, tint: Color = Tokens.Colors.primary, showsValues: Bool = true) {
        self.items = items
        self.height = height
        self.tint = tint
        self.showsValues = showsValues
    }

    private var sampled: [BarValue] {
        ChartSampling.evenDownsample(items, limit: ChartSampling.maxBarItems)
    }

    private var showsNumber: Bool {
        showsValues && caps.showsNumericScore
    }

    var body: some View {
        if sampled.isEmpty {
            ChartPlaceholder(text: "暂无数据", height: height)
        } else {
            Chart(sampled) { item in
                BarMark(
                    x: .value("项目", item.label),
                    y: .value("数值", clamped(item.value))
                )
                .foregroundStyle(item.tint?.color ?? tint)
                .cornerRadius(Tokens.Radius.small / 2)
                .annotation(position: .top, alignment: .center) {
                    if showsNumber {
                        Text(String(Int(clamped(item.value).rounded())))
                            .font(AppFont.micro(caps))
                            .foregroundStyle(Tokens.Colors.textSecondary)
                    }
                }
            }
            .chartYScale(domain: 0.0...100.0)
            .chartYAxis(caps.showsNumericScore ? .automatic : .hidden)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(AppFont.micro(caps))
                }
            }
            .frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("柱状图"))
            .accessibilityValue(Text(accessibilityValue))
        }
    }

    private func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 100)
    }

    private var accessibilityValue: String {
        sampled.map { item in
            if showsNumber {
                return "\(item.label) \(Int(clamped(item.value).rounded()))"
            }
            return item.label
        }
        .joined(separator: "，")
    }
}

// MARK: - 文件内私有辅助

private struct ChartPlaceholder: View {
    let text: String
    var height: CGFloat = 140

    @Environment(\.roleCapabilities) private var caps

    var body: some View {
        VStack(spacing: Tokens.Spacing.s8) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Tokens.Colors.textTertiary)
                .accessibilityHidden(true)
            Text(text)
                .font(AppFont.footnote(caps))
                .foregroundStyle(Tokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .padding(Tokens.Spacing.s12)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous)
                .fill(Tokens.Colors.surfaceSunken)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
    }
}

private enum ChartSampling {
    static let maxIntonationPoints = 200
    static let maxBarItems = 20

    /// 均匀降采样（保留首尾），避免图表卡顿；不足上限时原样返回。
    static func evenDownsample<T>(_ items: [T], limit: Int) -> [T] {
        guard limit > 1, items.count > limit else { return items }
        let step = Double(items.count - 1) / Double(limit - 1)
        var result: [T] = []
        result.reserveCapacity(limit)
        for index in 0..<limit {
            let position = min(items.count - 1, Int((Double(index) * step).rounded()))
            result.append(items[position])
        }
        return result
    }
}
