import Foundation

struct RenderCoreSample: Equatable {
    var kind: ShapeKind
    var x: Double
    var y: Double
    var size: Double
    var angleDeg: Double
    var filled: Bool
    var colorIndex: Int
}

struct RenderCoreScene: Equatable {
    var seed: Int
    var width: Int
    var height: Int
    var samples: [RenderCoreSample]
}

enum SwiftRenderCore {
    /// Deterministic sample scene generation scaffold for migration parity work.
    static func sampleScene(
        params: RenderParameters,
        canvas: CanvasSettings,
        seed overrideSeed: Int? = nil
    ) -> RenderCoreScene {
        let seed = overrideSeed ?? params.seed
        var rootRng = DeterministicRNG(seed: UInt64(bitPattern: Int64(seed)))
        let width = canvas.resolvedWidthPreview
        let height = canvas.resolvedHeightPreview
        let paletteCount = max(PaletteLibrary.colors(for: params).count, 1)

        var samples: [RenderCoreSample] = []
        for (idx, kind) in ShapeKind.allCases.enumerated() {
            let count = max(0, params.shapeCounts[kind])
            let region = params.placementRegions[kind]
            let angleRange = params.angleRanges[kind]
            let fillRatio = min(max(params.fillRatios[kind], 0), 1)

            var rng = rootRng.spawn(stream: UInt64(idx))
            let xRange = (region.xMin * Double(width))...(region.xMax * Double(width))
            let yRange = (region.yMin * Double(height))...(region.yMax * Double(height))
            let angleMin = min(angleRange.minDeg, angleRange.maxDeg)
            let angleMax = max(angleRange.minDeg, angleRange.maxDeg)

            for _ in 0..<count {
                let sample = RenderCoreSample(
                    kind: kind,
                    x: rng.nextDouble(in: xRange),
                    y: rng.nextDouble(in: yRange),
                    size: rng.nextDouble(in: 6...72),
                    angleDeg: rng.nextDouble(in: angleMin...angleMax),
                    filled: rng.nextUnitDouble() <= fillRatio,
                    colorIndex: rng.nextInt(in: 0...(paletteCount - 1))
                )
                samples.append(sample)
            }
            rootRng = rootRng.spawn(stream: UInt64(idx + 100))
        }

        return RenderCoreScene(
            seed: seed,
            width: width,
            height: height,
            samples: samples
        )
    }
}
