import Foundation

enum ShapeFamily: String, CaseIterable, Identifiable {
    case mixed
    case circles
    case triangles
    case rectangles
    case lines

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mixed: return "Mixed"
        case .circles: return "Circles"
        case .triangles: return "Triangles"
        case .rectangles: return "Rectangles"
        case .lines: return "Lines"
        }
    }
}

enum ShapeKind: String, CaseIterable, Identifiable {
    case circle
    case triangle
    case rectangle
    case line

    var id: String { rawValue }

    var title: String {
        switch self {
        case .circle: return "Circles"
        case .triangle: return "Triangles"
        case .rectangle: return "Rectangles"
        case .line: return "Lines"
        }
    }
}

enum SymmetryMode: String, CaseIterable, Identifiable {
    case radial
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .radial: return "Radial"
        case .none: return "None (Random Placement)"
        }
    }
}

enum BackgroundStyle: String, CaseIterable, Identifiable {
    case paper
    case midnight
    case warm
    case flat
    case pureBlack = "pure_black"
    case creme

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: return "Paper"
        case .midnight: return "Midnight"
        case .warm: return "Warm"
        case .flat: return "Flat"
        case .pureBlack: return "Pure Black"
        case .creme: return "Creme"
        }
    }
}

enum ColorMode: String, CaseIterable, Identifiable {
    case randomPerShape = "random_per_shape"
    case paletteCycle = "palette_cycle"
    case quadrant
    case paletteLock = "palette_lock"
    case paletteRotatePerRing = "palette_rotate_per_ring"
    case seedDerivedIndex = "seed_derived_index"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .randomPerShape: return "Random Per Shape"
        case .paletteCycle: return "Palette Cycle"
        case .quadrant: return "Quadrant"
        case .paletteLock: return "Palette Lock"
        case .paletteRotatePerRing: return "Palette Rotate Per Ring"
        case .seedDerivedIndex: return "Seed Derived Index"
        }
    }
}

enum PalettePreset: String, CaseIterable, Identifiable {
    case synthwave
    case oceanic
    case citrus
    case monoPop
    case sunset
    case forest
    case neonSign
    case clay
    case aurora
    case desertBloom
    case retroPrint
    case electricMint
    case duskDrive
    case candyStore
    case blueprint
    case emberSmoke
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .synthwave: return "Synthwave"
        case .oceanic: return "Oceanic"
        case .citrus: return "Citrus"
        case .monoPop: return "Mono Pop"
        case .sunset: return "Sunset"
        case .forest: return "Forest"
        case .neonSign: return "Neon Sign"
        case .clay: return "Clay"
        case .aurora: return "Aurora"
        case .desertBloom: return "Desert Bloom"
        case .retroPrint: return "Retro Print"
        case .electricMint: return "Electric Mint"
        case .duskDrive: return "Dusk Drive"
        case .candyStore: return "Candy Store"
        case .blueprint: return "Blueprint"
        case .emberSmoke: return "Ember Smoke"
        case .custom: return "Custom"
        }
    }
}

enum AspectRatioPreset: String, CaseIterable, Identifiable {
    case ratio1x1 = "1:1"
    case ratio4x5 = "4:5"
    case ratio3x4 = "3:4"
    case ratio2x3 = "2:3"
    case ratio16x9 = "16:9"
    case ratio3x2 = "3:2"
    case ratio9x16 = "9:16"
    case ratio21x9 = "21:9"
    case ratio4x3 = "4:3"
    case ratio31x9 = "31:9"
    case ratio9x31 = "9:31"

    var id: String { rawValue }

    var title: String { rawValue }

    var width: Double {
        switch self {
        case .ratio1x1: return 1
        case .ratio4x5: return 4
        case .ratio3x4: return 3
        case .ratio2x3: return 2
        case .ratio16x9: return 16
        case .ratio3x2: return 3
        case .ratio9x16: return 9
        case .ratio21x9: return 21
        case .ratio4x3: return 4
        case .ratio31x9: return 31
        case .ratio9x31: return 9
        }
    }

    var height: Double {
        switch self {
        case .ratio1x1: return 1
        case .ratio4x5: return 5
        case .ratio3x4: return 4
        case .ratio2x3: return 3
        case .ratio16x9: return 9
        case .ratio3x2: return 2
        case .ratio9x16: return 16
        case .ratio21x9: return 9
        case .ratio4x3: return 3
        case .ratio31x9: return 9
        case .ratio9x31: return 31
        }
    }

    var value: Double { width / height }
}

enum ResolutionPreset: String, CaseIterable, Identifiable {
    case custom
    case p720 = "720p"
    case p1080 = "1080p"
    case p1440 = "1440p"
    case k4 = "4K"
    case k8 = "8K"
    case k16 = "16K"

    var id: String { rawValue }

    var title: String { rawValue.uppercased() }

    var longEdge: Int? {
        switch self {
        case .custom: return nil
        case .p720: return 720
        case .p1080: return 1080
        case .p1440: return 1440
        case .k4: return 2160
        case .k8: return 4320
        case .k16: return 8640
        }
    }
}

enum RatioDrivingDimension: String, CaseIterable, Identifiable {
    case width
    case height

    var id: String { rawValue }

    var title: String {
        switch self {
        case .width: return "Width Drives"
        case .height: return "Height Drives"
        }
    }
}

struct ShapeCounts: Equatable {
    var circle: Int = 20
    var triangle: Int = 20
    var rectangle: Int = 20
    var line: Int = 20

    var total: Int {
        circle + triangle + rectangle + line
    }

    subscript(_ kind: ShapeKind) -> Int {
        get {
            switch kind {
            case .circle: return circle
            case .triangle: return triangle
            case .rectangle: return rectangle
            case .line: return line
            }
        }
        set {
            switch kind {
            case .circle: circle = newValue
            case .triangle: triangle = newValue
            case .rectangle: rectangle = newValue
            case .line: line = newValue
            }
        }
    }
}

struct ShapeFillRatios: Equatable {
    var circle: Double = 0.65
    var triangle: Double = 0.65
    var rectangle: Double = 0.65
    var line: Double = 0.65

    subscript(_ kind: ShapeKind) -> Double {
        get {
            switch kind {
            case .circle: return circle
            case .triangle: return triangle
            case .rectangle: return rectangle
            case .line: return line
            }
        }
        set {
            switch kind {
            case .circle: circle = newValue
            case .triangle: triangle = newValue
            case .rectangle: rectangle = newValue
            case .line: line = newValue
            }
        }
    }

    mutating func setAll(_ value: Double) {
        circle = value
        triangle = value
        rectangle = value
        line = value
    }
}

struct AngleRangeSettings: Equatable {
    var minDeg: Double = 0
    var maxDeg: Double = 360
}

struct ShapeAngleRanges: Equatable {
    var circle = AngleRangeSettings()
    var triangle = AngleRangeSettings()
    var rectangle = AngleRangeSettings()
    var line = AngleRangeSettings()

    subscript(_ kind: ShapeKind) -> AngleRangeSettings {
        get {
            switch kind {
            case .circle: return circle
            case .triangle: return triangle
            case .rectangle: return rectangle
            case .line: return line
            }
        }
        set {
            switch kind {
            case .circle: circle = newValue
            case .triangle: triangle = newValue
            case .rectangle: rectangle = newValue
            case .line: line = newValue
            }
        }
    }
}

struct PlacementRegionSettings: Equatable {
    var xMin: Double = 0
    var xMax: Double = 1
    var yMin: Double = 0
    var yMax: Double = 1
}

struct ShapePlacementRegions: Equatable {
    var circle = PlacementRegionSettings()
    var triangle = PlacementRegionSettings()
    var rectangle = PlacementRegionSettings()
    var line = PlacementRegionSettings()

    subscript(_ kind: ShapeKind) -> PlacementRegionSettings {
        get {
            switch kind {
            case .circle: return circle
            case .triangle: return triangle
            case .rectangle: return rectangle
            case .line: return line
            }
        }
        set {
            switch kind {
            case .circle: circle = newValue
            case .triangle: triangle = newValue
            case .rectangle: rectangle = newValue
            case .line: line = newValue
            }
        }
    }
}

struct CanvasSettings: Equatable {
    var lockRatio: Bool = true
    var ratioPreset: AspectRatioPreset = .ratio1x1
    var ratioDrivingDimension: RatioDrivingDimension = .width
    var resolutionPreset: ResolutionPreset = .p1080
    var longEdgePx: Int = 1080
    var manualWidth: Int = 1080
    var manualHeight: Int = 1080

    var previewMaxDim: Int = 4096
    var exportMaxDim: Int = 16384

    var clampedPreviewMaxDim: Int {
        clampDimension(previewMaxDim, minimum: 512, maximum: 4096)
    }

    var clampedExportMaxDim: Int {
        clampDimension(exportMaxDim, minimum: 1024, maximum: 16384)
    }

    var clampedLongEdge: Int {
        clampDimension(longEdgePx, minimum: 512, maximum: clampedExportMaxDim)
    }

    var clampedManualWidth: Int {
        clampDimension(manualWidth, minimum: 64, maximum: clampedExportMaxDim)
    }

    var clampedManualHeight: Int {
        clampDimension(manualHeight, minimum: 64, maximum: clampedExportMaxDim)
    }

    var resolvedWidthExport: Int {
        resolvedExportDimensions.width
    }

    var resolvedHeightExport: Int {
        resolvedExportDimensions.height
    }

    var resolvedWidthPreview: Int {
        min(resolvedExportDimensions.width, clampedPreviewMaxDim)
    }

    var resolvedHeightPreview: Int {
        min(resolvedExportDimensions.height, clampedPreviewMaxDim)
    }

    var resolvedExportDimensions: (width: Int, height: Int) {
        if !lockRatio {
            return (clampedManualWidth, clampedManualHeight)
        }

        let ratio = ratioPreset.value
        switch ratioDrivingDimension {
        case .width:
            let width = clampedManualWidth
            let height = clampDimension(Int(round(Double(width) / ratio)), minimum: 64, maximum: clampedExportMaxDim)
            return (width, height)
        case .height:
            let height = clampedManualHeight
            let width = clampDimension(Int(round(Double(height) * ratio)), minimum: 64, maximum: clampedExportMaxDim)
            return (width, height)
        }
    }

    mutating func applyResolutionPreset() {
        guard let edge = resolutionPreset.longEdge else { return }
        longEdgePx = edge
        applyLongEdge()
    }

    mutating func applyLongEdge() {
        let edge = clampedLongEdge
        let ratio = ratioPreset.value
        if ratio >= 1 {
            manualWidth = edge
            manualHeight = clampDimension(Int(round(Double(edge) / ratio)), minimum: 64, maximum: clampedExportMaxDim)
        } else {
            manualHeight = edge
            manualWidth = clampDimension(Int(round(Double(edge) * ratio)), minimum: 64, maximum: clampedExportMaxDim)
        }
    }

    mutating func applyRatioLock() {
        guard lockRatio else { return }
        switch ratioDrivingDimension {
        case .width:
            manualWidth = clampedManualWidth
            manualHeight = clampDimension(Int(round(Double(manualWidth) / ratioPreset.value)), minimum: 64, maximum: clampedExportMaxDim)
        case .height:
            manualHeight = clampedManualHeight
            manualWidth = clampDimension(Int(round(Double(manualHeight) * ratioPreset.value)), minimum: 64, maximum: clampedExportMaxDim)
        }
        longEdgePx = max(manualWidth, manualHeight)
    }

    private func clampDimension(_ value: Int, minimum: Int, maximum: Int) -> Int {
        min(max(value, minimum), maximum)
    }
}

struct RenderParameters: Equatable {
    var styleID: String = "clean_geometric"
    var shapeFamily: ShapeFamily = .mixed
    var shapeCounts = ShapeCounts()
    var angleRanges = ShapeAngleRanges()
    var placementRegions = ShapePlacementRegions()
    var symmetry: Int = 4
    var symmetryMode: SymmetryMode = .radial
    var rotation: Double = 0
    var scaleRange: Double = 0.45
    var strokeWidth: Double = 2
    var fillRatio: Double = 0.65
    var fillRatios = ShapeFillRatios()
    var palette: PalettePreset = .synthwave
    var customPaletteText: String = "#0B132B,#1C2541,#3A506B,#5BC0BE,#F3F9D2"
    var colorMode: ColorMode = .randomPerShape
    var backgroundStyle: BackgroundStyle = .paper
    var seed: Int = 42

    var totalShapes: Int {
        shapeCounts.total
    }
}

enum TrackInterpolation: String, CaseIterable, Identifiable {
    case hold
    case linear
    case easeInOut = "ease_in_out"
    case easeIn = "ease_in"
    case easeOut = "ease_out"
    case bounce

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hold: return "Hold"
        case .linear: return "Linear"
        case .easeInOut: return "Ease In Out"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .bounce: return "Bounce"
        }
    }
}

struct TimelineKeyframe: Identifiable, Equatable {
    var id = UUID()
    var frame: Int
    var value: Double
    var interpolation: TrackInterpolation
}

struct AnimationTrack: Identifiable, Equatable {
    let id: String
    var title: String
    var enabled: Bool
    var minValue: Double
    var maxValue: Double
    var step: Double
    var isInteger: Bool
    var colorHex: String
    var keyframes: [TimelineKeyframe]
}

struct AnimationSettings: Equatable {
    var fps: Int = 24
    var frameCount: Int = 96
    var scrubFrame: Int = 0
    var animationName: String = "geo-art-animation"
    var tracks: [AnimationTrack] = []

    mutating func clamp() {
        fps = min(max(fps, 1), 120)
        frameCount = min(max(frameCount, 1), 4096)
        scrubFrame = min(max(scrubFrame, 0), frameCount - 1)
    }
}

enum AnimationTrackFactory {
    static func makeDefaultTracks(from params: RenderParameters) -> [AnimationTrack] {
        var tracks: [AnimationTrack] = [
            AnimationTrack(
                id: "rotation",
                title: "Rotation",
                enabled: false,
                minValue: 0,
                maxValue: 360,
                step: 1,
                isInteger: false,
                colorHex: "#FF5555",
                keyframes: defaultKeyframes(value: params.rotation)
            ),
            AnimationTrack(
                id: "stroke_width",
                title: "Stroke Width",
                enabled: false,
                minValue: 0.5,
                maxValue: 18,
                step: 0.1,
                isInteger: false,
                colorHex: "#FFAA44",
                keyframes: defaultKeyframes(value: params.strokeWidth)
            ),
            AnimationTrack(
                id: "fill_ratio",
                title: "Global Fill Ratio",
                enabled: false,
                minValue: 0,
                maxValue: 1,
                step: 0.01,
                isInteger: false,
                colorHex: "#55CC66",
                keyframes: defaultKeyframes(value: params.fillRatio)
            ),
            AnimationTrack(
                id: "symmetry",
                title: "Symmetry",
                enabled: false,
                minValue: 1,
                maxValue: 12,
                step: 1,
                isInteger: true,
                colorHex: "#6688FF",
                keyframes: defaultKeyframes(value: Double(params.symmetry))
            ),
        ]

        for kind in ShapeKind.allCases {
            let count = Double(params.shapeCounts[kind])
            tracks.append(
                AnimationTrack(
                    id: "shape_counts.\(kind.rawValue)",
                    title: "\(kind.title) Count",
                    enabled: false,
                    minValue: 0,
                    maxValue: 300,
                    step: 1,
                    isInteger: true,
                    colorHex: "#AA66FF",
                    keyframes: defaultKeyframes(value: count)
                )
            )
        }

        for kind in ShapeKind.allCases {
            let fillRatio = params.fillRatios[kind]
            tracks.append(
                AnimationTrack(
                    id: "fill_ratios.\(kind.rawValue)",
                    title: "\(kind.title) Fill Ratio",
                    enabled: false,
                    minValue: 0,
                    maxValue: 1,
                    step: 0.01,
                    isInteger: false,
                    colorHex: "#44CCAA",
                    keyframes: defaultKeyframes(value: fillRatio)
                )
            )
        }

        return tracks
    }

    private static func defaultKeyframes(value: Double) -> [TimelineKeyframe] {
        [
            TimelineKeyframe(frame: 0, value: value, interpolation: .linear),
            TimelineKeyframe(frame: 95, value: value, interpolation: .linear),
        ]
    }
}

enum PaletteLibrary {
    static let curated: [PalettePreset: [String]] = [
        .synthwave: ["#2D1E2F", "#D7263D", "#F46036", "#2E294E", "#1B998B"],
        .oceanic: ["#011627", "#2EC4B6", "#4DA8DA", "#F6F7EB", "#E71D36"],
        .citrus: ["#1B4332", "#95D5B2", "#F9C74F", "#F8961E", "#F3722C"],
        .monoPop: ["#111111", "#2A2A2A", "#666666", "#EAEAEA", "#FF4D6D"],
        .sunset: ["#003049", "#D62828", "#F77F00", "#FCBF49", "#EAE2B7"],
        .forest: ["#14342B", "#2D6A4F", "#40916C", "#95D5B2", "#D8F3DC"],
        .neonSign: ["#141414", "#00F5D4", "#F15BB5", "#9B5DE5", "#FEE440"],
        .clay: ["#2B2D42", "#8D99AE", "#EDF2F4", "#EF233C", "#D90429"],
        .aurora: ["#151E3F", "#00A8E8", "#00D9C0", "#F4D35E", "#EE964B"],
        .desertBloom: ["#3D2C2E", "#B06C49", "#E28F83", "#F2CC8F", "#3A7D44"],
        .retroPrint: ["#1F271B", "#19647E", "#28AFB0", "#F4D35E", "#EE964B"],
        .electricMint: ["#05204A", "#0A2463", "#1E96FC", "#D7FFAB", "#7AE582"],
        .duskDrive: ["#1B1B3A", "#693668", "#A74482", "#F84AA7", "#FF3562"],
        .candyStore: ["#3A0CA3", "#7209B7", "#F72585", "#4CC9F0", "#BDE0FE"],
        .blueprint: ["#0B1D51", "#1E3A8A", "#2563EB", "#93C5FD", "#E2E8F0"],
        .emberSmoke: ["#161A1D", "#660708", "#A4161A", "#E5383B", "#F4A261"]
    ]

    static func colors(for params: RenderParameters) -> [String] {
        if params.palette == .custom {
            let custom = parseCustomPalette(params.customPaletteText)
            if custom.count >= 3 {
                return custom
            }
            return curated[.synthwave] ?? ["#2D1E2F", "#D7263D", "#F46036"]
        }
        return curated[params.palette] ?? curated[.synthwave]!
    }

    static func parseCustomPalette(_ text: String) -> [String] {
        text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { value in
                let upper = value.uppercased()
                return upper.hasPrefix("#") ? upper : "#\(upper)"
            }
    }
}
