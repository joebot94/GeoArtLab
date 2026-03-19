import Foundation
import Metal

private struct MigrationParityKindSummary: Codable {
    var count: Int
    var meanXNorm: Double
    var meanYNorm: Double
    var meanSizeNorm: Double
    var meanAngleDeg: Double
    var fillRatio: Double

    enum CodingKeys: String, CodingKey {
        case count
        case meanXNorm = "mean_x_norm"
        case meanYNorm = "mean_y_norm"
        case meanSizeNorm = "mean_size_norm"
        case meanAngleDeg = "mean_angle_deg"
        case fillRatio = "fill_ratio"
    }
}

private struct MigrationParityOutput: Codable {
    var engine: String
    var seed: Int
    var width: Int
    var height: Int
    var sampleCount: Int
    var byKind: [String: MigrationParityKindSummary]

    enum CodingKeys: String, CodingKey {
        case engine
        case seed
        case width
        case height
        case sampleCount = "sample_count"
        case byKind = "by_kind"
    }
}

private struct PreviewBenchmarkEntry: Codable {
    var totalShapes: Int
    var averageMs: Double
    var p95Ms: Double
    var maxMs: Double

    enum CodingKeys: String, CodingKey {
        case totalShapes = "total_shapes"
        case averageMs = "average_ms"
        case p95Ms = "p95_ms"
        case maxMs = "max_ms"
    }
}

private struct PreviewBenchmarkOutput: Codable {
    var engine: String
    var metalAvailable: Bool
    var deviceName: String
    var width: Int
    var height: Int
    var iterations: Int
    var entries: [PreviewBenchmarkEntry]

    enum CodingKeys: String, CodingKey {
        case engine
        case metalAvailable = "metal_available"
        case deviceName = "device_name"
        case width
        case height
        case iterations
        case entries
    }
}

enum MigrationParityCLI {
    static func runIfRequested(arguments: [String]) -> Int? {
        if arguments.contains("--migration-preview-benchmark") {
            return runPreviewBenchmark(arguments: arguments)
        }

        guard arguments.contains("--migration-parity-sample") else {
            return nil
        }

        let seed = parseInt(arguments: arguments, flag: "--seed", defaultValue: 42)
        let width = min(max(parseInt(arguments: arguments, flag: "--width", defaultValue: 512), 64), 16384)
        let height = min(max(parseInt(arguments: arguments, flag: "--height", defaultValue: 512), 64), 16384)

        var params = RenderParameters()
        params.seed = seed
        params.shapeFamily = .mixed
        params.shapeCounts = ShapeCounts(circle: 20, triangle: 20, rectangle: 20, line: 20)
        params.symmetry = 1
        params.symmetryMode = .radial
        params.fillRatio = 0.65
        params.fillRatios.setAll(0.65)
        params.palette = .synthwave
        params.colorMode = .randomPerShape
        params.backgroundStyle = .paper

        var canvas = CanvasSettings()
        canvas.lockRatio = false
        canvas.manualWidth = width
        canvas.manualHeight = height

        let scene = SwiftRenderCore.sampleScene(params: params, canvas: canvas, seed: seed)
        let byKind = summarizeByKind(scene: scene)

        let payload = MigrationParityOutput(
            engine: "swift",
            seed: scene.seed,
            width: scene.width,
            height: scene.height,
            sampleCount: scene.samples.count,
            byKind: byKind
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            print("GEOARTLAB_PARITY_JSON_START")
            print(String(decoding: data, as: UTF8.self))
            return 0
        } catch {
            fputs("Failed to encode migration parity output: \(error)\n", stderr)
            return 2
        }
    }

    private static func parseInt(arguments: [String], flag: String, defaultValue: Int) -> Int {
        guard let idx = arguments.firstIndex(of: flag), idx + 1 < arguments.count else {
            return defaultValue
        }
        return Int(arguments[idx + 1]) ?? defaultValue
    }

    private static func parseIntList(arguments: [String], flag: String, defaultValue: [Int]) -> [Int] {
        guard let idx = arguments.firstIndex(of: flag), idx + 1 < arguments.count else {
            return defaultValue
        }
        let raw = arguments[idx + 1]
        let values = raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return values.isEmpty ? defaultValue : values
    }

    private static func runPreviewBenchmark(arguments: [String]) -> Int {
        let width = min(max(parseInt(arguments: arguments, flag: "--width", defaultValue: 1024), 64), 4096)
        let height = min(max(parseInt(arguments: arguments, flag: "--height", defaultValue: 1024), 64), 4096)
        let iterations = min(max(parseInt(arguments: arguments, flag: "--iterations", defaultValue: 5), 1), 50)
        let shapeTotals = parseIntList(arguments: arguments, flag: "--shape-counts", defaultValue: [200, 500, 1000])
        let seed = parseInt(arguments: arguments, flag: "--seed", defaultValue: 42)
        let backend = MetalPreviewBackend()

        guard backend.isAvailable else {
            fputs("Metal preview backend unavailable on this machine\n", stderr)
            return 3
        }

        var canvas = CanvasSettings()
        canvas.lockRatio = false
        canvas.manualWidth = width
        canvas.manualHeight = height
        canvas.previewMaxDim = 4096

        var params = RenderParameters()
        params.symmetry = 1
        params.symmetryMode = .none

        var entries: [PreviewBenchmarkEntry] = []
        for total in shapeTotals {
            params.shapeCounts = distributedShapeCounts(total: max(0, total))
            var timings: [Double] = []
            for offset in 0..<iterations {
                params.seed = seed + offset
                guard let frame = backend.renderPreview(params: params, canvas: canvas, seed: params.seed) else {
                    continue
                }
                timings.append(frame.renderMillis)
            }

            guard !timings.isEmpty else { continue }
            let sorted = timings.sorted()
            let p95Index = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))
            let average = sorted.reduce(0, +) / Double(sorted.count)
            entries.append(
                PreviewBenchmarkEntry(
                    totalShapes: total,
                    averageMs: average,
                    p95Ms: sorted[p95Index],
                    maxMs: sorted.last ?? average
                )
            )
        }

        let payload = PreviewBenchmarkOutput(
            engine: "swift_metal_preview_scaffold",
            metalAvailable: backend.isAvailable,
            deviceName: MTLCreateSystemDefaultDevice()?.name ?? "unknown",
            width: width,
            height: height,
            iterations: iterations,
            entries: entries
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            print("GEOARTLAB_PREVIEW_BENCH_JSON_START")
            print(String(decoding: data, as: UTF8.self))
            return 0
        } catch {
            fputs("Failed to encode preview benchmark output: \(error)\n", stderr)
            return 2
        }
    }

    private static func distributedShapeCounts(total: Int) -> ShapeCounts {
        let clamped = max(0, min(total, 1200))
        let base = clamped / 4
        var remainder = clamped % 4
        var counts = ShapeCounts(circle: base, triangle: base, rectangle: base, line: base)
        if remainder > 0 {
            counts.circle += 1
            remainder -= 1
        }
        if remainder > 0 {
            counts.triangle += 1
            remainder -= 1
        }
        if remainder > 0 {
            counts.rectangle += 1
        }
        return counts
    }

    private static func summarizeByKind(scene: RenderCoreScene) -> [String: MigrationParityKindSummary] {
        let minDimension = max(1.0, Double(min(scene.width, scene.height)))
        var result: [String: MigrationParityKindSummary] = [:]

        for kind in ShapeKind.allCases {
            let samples = scene.samples.filter { $0.kind == kind }
            let count = samples.count
            guard count > 0 else {
                result[kind.rawValue] = MigrationParityKindSummary(
                    count: 0,
                    meanXNorm: 0,
                    meanYNorm: 0,
                    meanSizeNorm: 0,
                    meanAngleDeg: 0,
                    fillRatio: 0
                )
                continue
            }

            let xMean = samples.map(\.x).reduce(0, +) / Double(count)
            let yMean = samples.map(\.y).reduce(0, +) / Double(count)
            let sizeMean = samples.map(\.size).reduce(0, +) / Double(count)
            let angleMean = samples.map(\.angleDeg).reduce(0, +) / Double(count)
            let fillRatio = Double(samples.filter(\.filled).count) / Double(count)

            result[kind.rawValue] = MigrationParityKindSummary(
                count: count,
                meanXNorm: xMean / Double(max(scene.width, 1)),
                meanYNorm: yMean / Double(max(scene.height, 1)),
                meanSizeNorm: sizeMean / minDimension,
                meanAngleDeg: angleMean,
                fillRatio: fillRatio
            )
        }

        return result
    }
}
