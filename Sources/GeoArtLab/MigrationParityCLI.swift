import Foundation

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

enum MigrationParityCLI {
    static func runIfRequested(arguments: [String]) -> Int? {
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
