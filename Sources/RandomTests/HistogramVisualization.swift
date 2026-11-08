/// Utilities for visualizing distribution histograms in terminal output.
struct HistogramVisualization<Value> where Value: HistogramValue {
    /// Unicode block characters used for high-precision bar charts.
    private static var blocks: [Unicode.Scalar] { ["▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"] }

    /// Standard column widths for consistent table output.
    struct ColumnWidths {
        let value: Int
        let count: Int
        let percent: Int
        let bar: Int

        static var standard: Self { .init(value: 9, count: 11, percent: 12, bar: 20) }
        static var compact: Self { .init(value: 3, count: 11, percent: 12, bar: 20) }
    }

    // MARK: - Instance Properties

    private let columnWidths: ColumnWidths
    private let valueLabel: String
    private let maxFrequency: Double
    private let maxExpected: Double

    // MARK: - Private Initializer

    private init(
        valueLabel: String,
        columnWidths: ColumnWidths,
        maxFrequency: Double,
        maxExpected: Double
    ) {
        self.valueLabel = valueLabel
        self.columnWidths = columnWidths
        self.maxFrequency = maxFrequency
        self.maxExpected = maxExpected
    }
}
extension HistogramVisualization<Double> {
    /// Visualizes a continuous distribution histogram with accurate expected probabilities.
    /// - Parameters:
    ///   - histogram: Array of (midpoint, count) pairs for each bin
    ///   - sampleCount: Total number of samples
    ///   - expectedProbabilities: Pre-calculated exact probabilities for each bin (using CDF differences)
    ///   - columnWidths: Column width configuration for display
    static func visualizeContinuousHistogram(
        histogram: [(Double, Int)],
        sampleCount: Int,
        expectedProbabilities: [Double],
        columnWidths: ColumnWidths = .standard
    ) {
        let data: [(value: Double, count: Int)] = histogram
        let maxCount: Int = data.reduce(1) { max($0, $1.count) }

        let visualizer: Self = .init(
            valueLabel: "    x     ",
            columnWidths: columnWidths,
            maxFrequency: Double.init(maxCount) / Double.init(sampleCount),
            maxExpected: expectedProbabilities.max() ?? 0.01
        )

        // Draw with index-based probability lookup
        visualizer.drawWithIndexedProbabilities(
            data: data,
            sampleCount: sampleCount,
            expectedProbabilities: expectedProbabilities.enumerated().reduce(into: [:]) {
                $0[$1.offset] = $1.element
            }
        )
    }
}
extension HistogramVisualization<Int64> {
    static func visualizeDiscreteHistogram(
        histogram: [Int64: Int],
        sampleCount: Int,
        expectedProbability: (Int64) -> Double,
        range: ClosedRange<Int64>,
        columnWidths: ColumnWidths = .compact
    ) {
        let data: [(value: Int64, count: Int)] = range.map { ($0, histogram[$0, default: 0]) }
        let maxCount: Int = data.reduce(1) { max($0, $1.count) }
        let visualizer: Self = .init(
            valueLabel: " k  ",
            columnWidths: columnWidths,
            maxFrequency: .init(maxCount) / .init(sampleCount),
            maxExpected: data.map { expectedProbability($0.value) }.max() ?? 0.01
        )
        visualizer.draw(
            data: data,
            sampleCount: sampleCount,
            expectedProbability: expectedProbability
        )
    }
}
extension HistogramVisualization {
    private func draw(
        data: [(value: Value, count: Int)],
        sampleCount: Int,
        expectedProbability: (Value) -> Double
    ) {
        self.printTableHeader()
        for (value, count): (Value, Int) in data.sorted(by: { $0.value < $1.value }) {
            let expected: Double = expectedProbability(value)
            if !expected.isFinite {
                fatalError("invalid expected probability ([\(value)] = \(expected))")
            }
            self.printTableRow(
                value: value,
                count: count,
                sampleCount: sampleCount,
                expectedPercent: expected
            )
        }
    }

    private func drawWithIndexedProbabilities(
        data: [(value: Value, count: Int)],
        sampleCount: Int,
        expectedProbabilities: [Int: Double]
    ) {
        self.printTableHeader()
        let sorted = data.sorted(by: { $0.value < $1.value })
        for (index, (value, count)) in sorted.enumerated() {
            self.printTableRow(
                value: value,
                count: count,
                sampleCount: sampleCount,
                expectedPercent: expectedProbabilities[index] ?? 0.0
            )
        }
    }

    private func printTableHeader() {
        let header: String = """
        \(self.valueLabel.padding(left: self.columnWidths.value)) \
        |    Count    \
        |   Actual %   \
        |  Expected %  \
        | Actual \("".padding(right: self.columnWidths.bar - 7)) \
        | Expected
        """
        let separator: String = """
        \(String.init(repeating: "-", count: self.columnWidths.value))--\
        +-------------\
        +--------------\
        +--------------\
        +----------------------\
        +----------------------
        """
        print(header)
        print(separator)
    }

    private func printTableRow(
        value: Value,
        count: Int,
        sampleCount: Int,
        expectedPercent: Double
    ) {
        let actualPercent: Double = .init(count) / .init(sampleCount)
        let actualBar: String = self.bar(value: actualPercent, maxValue: self.maxFrequency)
        let expectedBar: String = self.bar(value: expectedPercent, maxValue: self.maxExpected)

        let formatted: (
            value: String,
            count: String,
            actualPercent: String,
            expectedPercent: String
        ) = (
            value: value.formattedString(width: self.columnWidths.value),
            count: "\(count)".padding(left: self.columnWidths.count),
            actualPercent: actualPercent.percent().padding(left: self.columnWidths.percent),
            expectedPercent: expectedPercent.percent().padding(left: self.columnWidths.percent)
        )

        print(
            """
             \(formatted.value) \
            | \(formatted.count) \
            | \(formatted.actualPercent) \
            | \(formatted.expectedPercent) \
            | \(actualBar.padding(left: self.columnWidths.bar)) \
            | \(expectedBar)
            """
        )
    }

    private func bar(value: Double, maxValue: Double) -> String {
        guard maxValue > 0, value > 0 else {
            return ""
        }
        guard
        let quantized: Int = .init(
            exactly: ((value / maxValue) * Double.init(self.columnWidths.bar * 8)).rounded()
        ) else {
            fatalError(
                "Bar length calculation overflowed for value: \(value), maxValue: \(maxValue)"
            )
        }
        let pixels: Int = quantized > 0 ? max(1, quantized) : 0
        let (blocks, remainder): (Int, remainder: Int) = pixels.quotientAndRemainder(
            dividingBy: 8
        )
        var bar: String = .init(repeating: "█", count: blocks)
        if  remainder > 0 {
            bar.append(Character.init(Self.blocks[remainder - 1]))
        }
        return bar
    }
}
