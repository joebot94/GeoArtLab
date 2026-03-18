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

enum BackgroundStyle: String, CaseIterable, Identifiable {
    case paper
    case midnight
    case warm
    case flat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: return "Paper"
        case .midnight: return "Midnight"
        case .warm: return "Warm"
        case .flat: return "Flat"
        }
    }
}

enum ColorMode: String, CaseIterable, Identifiable {
    case randomPerShape = "random_per_shape"
    case paletteCycle = "palette_cycle"
    case quadrant = "quadrant"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .randomPerShape: return "Random Per Shape"
        case .paletteCycle: return "Palette Cycle"
        case .quadrant: return "Quadrant"
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
        }
    }

    var value: Double { width / height }
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
    var lockRatio: Bool = false
    var ratioPreset: AspectRatioPreset = .ratio1x1
    var longEdgePx: Int = 1024
    var manualWidth: Int = 1024
    var manualHeight: Int = 1024

    var clampedLongEdge: Int {
        min(max(longEdgePx, 512), 4096)
    }

    var resolvedWidth: Int {
        if lockRatio {
            let ratio = ratioPreset.value
            if ratio >= 1 {
                return clampDimension(clampedLongEdge)
            }
            return clampDimension(Int(round(Double(clampedLongEdge) * ratio)))
        }
        return clampDimension(manualWidth)
    }

    var resolvedHeight: Int {
        if lockRatio {
            let ratio = ratioPreset.value
            if ratio >= 1 {
                return clampDimension(Int(round(Double(clampedLongEdge) / ratio)))
            }
            return clampDimension(clampedLongEdge)
        }
        return clampDimension(manualHeight)
    }

    private func clampDimension(_ value: Int) -> Int {
        min(max(value, 64), 4096)
    }
}

struct RenderParameters: Equatable {
    var styleID: String = "clean_geometric"
    var shapeFamily: ShapeFamily = .mixed
    var shapeCounts = ShapeCounts()
    var angleRanges = ShapeAngleRanges()
    var placementRegions = ShapePlacementRegions()
    var symmetry: Int = 4
    var rotation: Double = 0
    var scaleRange: Double = 0.45
    var strokeWidth: Double = 2
    var fillRatio: Double = 0.65
    var palette: PalettePreset = .synthwave
    var customPaletteText: String = "#0B132B,#1C2541,#3A506B,#5BC0BE,#F3F9D2"
    var colorMode: ColorMode = .randomPerShape
    var backgroundStyle: BackgroundStyle = .paper
    var seed: Int = 42
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
