import Foundation

enum NexusCommandType: String {
    case patchRenderParams = "patch_render_params"
    case patchCanvas = "patch_canvas"
    case requestPreview = "request_preview"
    case requestAnimationPreview = "request_animation_preview"
    case exportBatch = "export_batch"
    case exportAnimation = "export_animation"
}

struct NexusCommand {
    let type: NexusCommandType
    let payload: [String: Any]

    init(type: NexusCommandType, payload: [String: Any] = [:]) {
        self.type = type
        self.payload = payload
    }

    func int(_ key: String) -> Int? {
        if let value = payload[key] as? Int {
            return value
        }
        if let value = payload[key] as? Double {
            return Int(round(value))
        }
        if let value = payload[key] as? String {
            return Int(value)
        }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let value = payload[key] as? Double {
            return value
        }
        if let value = payload[key] as? Int {
            return Double(value)
        }
        if let value = payload[key] as? String {
            return Double(value)
        }
        return nil
    }
}

protocol NexusBridgeProtocol: AnyObject {
    var onCommand: ((NexusCommand) -> Void)? { get set }
    func start()
    func stop()
}

final class MockNexusBridge: NexusBridgeProtocol {
    var onCommand: ((NexusCommand) -> Void)?

    private(set) var isRunning = false

    func start() {
        isRunning = true
    }

    func stop() {
        isRunning = false
    }

    func ingest(_ command: NexusCommand) {
        guard isRunning else { return }
        onCommand?(command)
    }
}
