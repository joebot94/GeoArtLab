import Foundation

enum RenderEngine: String, Codable, CaseIterable {
    case swiftCore = "swift"
    case pythonLegacy = "python_legacy"

    var title: String {
        switch self {
        case .swiftCore:
            return "Swift"
        case .pythonLegacy:
            return "Python Legacy"
        }
    }
}

enum FeatureFlags {
    private static let forcePythonRendererKey = "geoartlab.internal.force_python_renderer"
    private static let enableSwiftRendererKey = "geoartlab.internal.enable_swift_renderer"
    private static let enableMetalPreviewKey = "geoartlab.internal.enable_metal_preview"
    private static let forcePythonEnv = "GEOARTLAB_FORCE_PYTHON_RENDERER"
    private static let enableSwiftEnv = "GEOARTLAB_ENABLE_SWIFT_RENDERER"
    private static let enableMetalPreviewEnv = "GEOARTLAB_ENABLE_METAL_PREVIEW"

    static var renderEngine: RenderEngine {
        let env = ProcessInfo.processInfo.environment
        if env[forcePythonEnv] == "1" {
            return .pythonLegacy
        }
        if env[enableSwiftEnv] == "1" {
            return .swiftCore
        }

        if UserDefaults.standard.bool(forKey: forcePythonRendererKey) {
            return .pythonLegacy
        }
        if UserDefaults.standard.bool(forKey: enableSwiftRendererKey) {
            return .swiftCore
        }

        return .pythonLegacy
    }

    static func enablePythonFallback() {
        UserDefaults.standard.set(true, forKey: forcePythonRendererKey)
        UserDefaults.standard.set(false, forKey: enableSwiftRendererKey)
    }

    static func enableSwiftRendererForInternalTesting() {
        UserDefaults.standard.set(false, forKey: forcePythonRendererKey)
        UserDefaults.standard.set(true, forKey: enableSwiftRendererKey)
    }

    static func clearInternalRendererOverrides() {
        UserDefaults.standard.removeObject(forKey: forcePythonRendererKey)
        UserDefaults.standard.removeObject(forKey: enableSwiftRendererKey)
        UserDefaults.standard.removeObject(forKey: enableMetalPreviewKey)
    }

    static var metalPreviewEnabled: Bool {
        let env = ProcessInfo.processInfo.environment
        if env[enableMetalPreviewEnv] == "1" {
            return true
        }
        return UserDefaults.standard.bool(forKey: enableMetalPreviewKey)
    }

    static func enableMetalPreviewForInternalTesting() {
        UserDefaults.standard.set(true, forKey: enableMetalPreviewKey)
    }

    static func disableMetalPreviewForInternalTesting() {
        UserDefaults.standard.set(false, forKey: enableMetalPreviewKey)
    }
}
