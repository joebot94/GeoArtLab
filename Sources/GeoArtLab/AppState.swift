import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var params = RenderParameters() {
        didSet {
            if !isApplyingTotalShapeRebalance {
                requestedTotalShapes = params.totalShapes
            }
        }
    }
    @Published var canvas = CanvasSettings()
    @Published var animation = AnimationSettings()

    @Published var baseSeed = 42
    @Published var repeats = 10
    @Published var outputRoot = "\(NSHomeDirectory())/JBT/geo_art_lab"

    @Published var requestedTotalShapes = 80

    @Published var previewImage: NSImage?
    @Published var animationPreviewImage: NSImage?

    @Published var statusText = "Waiting for worker..."
    @Published var workerConnected = false

    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var exportStatusText = ""
    @Published var exportedFiles: [String] = []

    @Published var isExportingAnimation = false
    @Published var animationExportProgress: Double = 0
    @Published var animationExportStatusText = ""
    @Published var animationExportedFiles: [String] = []

    @Published var lastErrorText = ""

    private let client: PythonWorkerClient
    private let nexusBridge: NexusBridgeProtocol
    private var previewDebounceTask: Task<Void, Never>?
    private var animationPreviewDebounceTask: Task<Void, Never>?
    private var hasStarted = false
    private var isApplyingTotalShapeRebalance = false
    private var previewRequestSerial = 0
    private var animationPreviewRequestSerial = 0

    var activeRenderEngine: RenderEngine {
        FeatureFlags.renderEngine
    }

    init(
        client: PythonWorkerClient = PythonWorkerClient(),
        nexusBridge: NexusBridgeProtocol = MockNexusBridge()
    ) {
        self.client = client
        self.nexusBridge = nexusBridge

        self.requestedTotalShapes = params.totalShapes
        self.animation.tracks = AnimationTrackFactory.makeDefaultTracks(from: params)
        self.animation.clamp()
        alignTrackEndpointsWithFrameCount()

        self.client.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleEvent(event)
            }
        }

        self.nexusBridge.onCommand = { [weak self] command in
            Task { @MainActor in
                self?.handleNexusCommand(command)
            }
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        statusText = "Launching worker... renderer=\(activeRenderEngine.rawValue)"
        client.startIfNeeded()
        sendHello()
        nexusBridge.start()

        canvas.applyResolutionPreset()
        canvas.applyRatioLock()
        alignTrackEndpointsWithFrameCount()

        schedulePreview()
        scheduleAnimationPreview()
    }

    func schedulePreview() {
        previewDebounceTask?.cancel()
        previewDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.requestPreview()
        }
    }

    func scheduleAnimationPreview() {
        animationPreviewDebounceTask?.cancel()
        animationPreviewDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.requestAnimationPreview(immediate: false)
        }
    }

    func requestPreview() {
        // Migration note: Swift renderer path scaffolding exists but preview currently
        // stays on Python worker until Metal preview path lands.
        if activeRenderEngine == .swiftCore {
            statusText = "Swift renderer enabled (preview fallback: python worker)"
        }
        previewRequestSerial += 1
        let requestSerial = previewRequestSerial
        let payload = previewPayload(seed: params.seed)
        statusText = "Rendering preview..."

        client.sendRequest(type: "render_preview", payload: payload) { [weak self] result in
            switch result {
            case .success(let response):
                let payload = response["payload"] as? [String: Any]
                let previewPath = payload?["preview_path"] as? String
                Task { @MainActor in
                    guard let self else { return }
                    guard requestSerial == self.previewRequestSerial else { return }
                    guard let previewPath else {
                        self.lastErrorText = "Preview response missing preview_path"
                        self.statusText = "Preview failed"
                        return
                    }

                    if let image = NSImage(contentsOf: URL(fileURLWithPath: previewPath)) {
                        self.previewImage = image
                        self.statusText = "Preview ready"
                    } else {
                        self.statusText = "Preview image unreadable"
                    }
                }
            case .failure(let error):
                Task { @MainActor in
                    guard let self else { return }
                    guard requestSerial == self.previewRequestSerial else { return }
                    self.lastErrorText = error.localizedDescription
                    self.statusText = "Preview failed"
                }
            }
        }
    }

    func requestAnimationPreview(immediate: Bool = true) {
        if immediate {
            animationPreviewDebounceTask?.cancel()
        }
        if activeRenderEngine == .swiftCore {
            statusText = "Swift renderer enabled (animation fallback: python worker)"
        }
        animationPreviewRequestSerial += 1
        let requestSerial = animationPreviewRequestSerial
        animation.clamp()
        let payload: [String: Any] = [
            "params": renderPayload(seed: params.seed),
            "canvas": [
                "width": canvas.resolvedWidthPreview,
                "height": canvas.resolvedHeightPreview,
            ],
            "timeline": animationTimelinePayload(),
            "frame": animation.scrubFrame,
            "output_root": outputRoot,
        ]

        client.sendRequest(type: "render_animation_preview", payload: payload) { [weak self] result in
            switch result {
            case .success(let response):
                let payload = response["payload"] as? [String: Any]
                let previewPath = payload?["preview_path"] as? String
                Task { @MainActor in
                    guard let self else { return }
                    guard requestSerial == self.animationPreviewRequestSerial else { return }
                    guard let previewPath else {
                        self.lastErrorText = "Animation preview missing preview_path"
                        return
                    }
                    if let image = NSImage(contentsOf: URL(fileURLWithPath: previewPath)) {
                        self.animationPreviewImage = image
                    }
                }
            case .failure(let error):
                Task { @MainActor in
                    guard let self else { return }
                    guard requestSerial == self.animationPreviewRequestSerial else { return }
                    self.lastErrorText = error.localizedDescription
                }
            }
        }
    }

    func exportBatch() {
        isExporting = true
        exportProgress = 0
        exportedFiles = []
        exportStatusText = "Exporting..."

        let payload: [String: Any] = [
            "base_seed": baseSeed,
            "repeats": max(repeats, 1),
            "output_root": outputRoot,
            "render": baseRenderPayload(),
            "canvas": [
                "width": canvas.resolvedWidthExport,
                "height": canvas.resolvedHeightExport,
            ],
        ]

        client.sendRequest(type: "export_batch", payload: payload) { [weak self] result in
            switch result {
            case .success(let response):
                let payload = response["payload"] as? [String: Any]
                let items = payload?["items"] as? [[String: Any]] ?? []
                let baseNames = items.compactMap { $0["base_name"] as? String }
                let itemCount = items.count
                let firstSeed = items.first?["seed"] as? Int

                Task { @MainActor in
                    guard let self else { return }
                    self.isExporting = false
                    self.exportedFiles = baseNames
                    self.exportProgress = 1
                    self.exportStatusText = "Export complete (\(itemCount) pieces)"
                    self.statusText = "Export complete"

                    if let firstSeed {
                        self.params.seed = firstSeed
                        self.schedulePreview()
                    }
                }
            case .failure(let error):
                Task { @MainActor in
                    guard let self else { return }
                    self.isExporting = false
                    self.lastErrorText = error.localizedDescription
                    self.exportStatusText = "Export failed"
                    self.statusText = "Export failed"
                }
            }
        }
    }

    func exportAnimation() {
        isExportingAnimation = true
        animationExportProgress = 0
        animationExportStatusText = "Exporting animation..."
        animationExportedFiles = []

        animation.clamp()
        let payload: [String: Any] = [
            "output_root": outputRoot,
            "canvas": [
                "width": canvas.resolvedWidthExport,
                "height": canvas.resolvedHeightExport,
            ],
            "render": renderPayload(seed: params.seed),
            "timeline": animationTimelinePayload(),
            "animation_name": animation.animationName,
        ]

        client.sendRequest(type: "export_animation", payload: payload) { [weak self] result in
            switch result {
            case .success(let response):
                let payload = response["payload"] as? [String: Any] ?? [:]
                let framesDir = payload["frames_dir"] as? String ?? ""
                let jbt = payload["animation_jbt_path"] as? String ?? ""
                Task { @MainActor in
                    guard let self else { return }
                    self.isExportingAnimation = false
                    self.animationExportProgress = 1
                    self.animationExportStatusText = "Animation export complete"
                    self.animationExportedFiles = [framesDir, jbt].filter { !$0.isEmpty }
                    self.statusText = "Animation export complete"
                }
            case .failure(let error):
                Task { @MainActor in
                    guard let self else { return }
                    self.isExportingAnimation = false
                    self.lastErrorText = error.localizedDescription
                    self.animationExportStatusText = "Animation export failed"
                }
            }
        }
    }

    func pingWorker() {
        client.sendRequest(type: "ping", payload: [:]) { [weak self] result in
            switch result {
            case .success:
                Task { @MainActor in
                    guard let self else { return }
                    self.workerConnected = true
                    self.statusText = "Worker reachable"
                }
            case .failure(let error):
                Task { @MainActor in
                    guard let self else { return }
                    self.workerConnected = false
                    self.lastErrorText = error.localizedDescription
                    self.statusText = "Worker ping failed"
                }
            }
        }
    }

    func applyGlobalFillRatioToAllShapes() {
        params.fillRatios.setAll(params.fillRatio)
    }

    func randomizeSeed() {
        params.seed = Int.random(in: 0...1_000_000)
    }

    func resetAll() {
        let existingOutputRoot = outputRoot
        params = RenderParameters()
        canvas = CanvasSettings()
        animation = AnimationSettings()
        animation.tracks = AnimationTrackFactory.makeDefaultTracks(from: params)
        requestedTotalShapes = params.totalShapes
        outputRoot = existingOutputRoot
        canvas.applyResolutionPreset()
        canvas.applyRatioLock()
        schedulePreview()
        scheduleAnimationPreview()
    }

    @discardableResult
    func savePreset() -> String? {
        let fm = FileManager.default
        let expandedRoot = NSString(string: outputRoot).expandingTildeInPath
        let presetsDir = URL(fileURLWithPath: expandedRoot).appendingPathComponent("presets", isDirectory: true)
        do {
            try fm.createDirectory(at: presetsDir, withIntermediateDirectories: true)
            let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let presetURL = presetsDir.appendingPathComponent("preset_\(ts).json")
            let payload: [String: Any] = [
                "created_at": ISO8601DateFormatter().string(from: Date()),
                "params": renderPayload(seed: params.seed),
                "canvas": [
                    "width": canvas.resolvedWidthExport,
                    "height": canvas.resolvedHeightExport,
                ],
                "animation": animationTimelinePayload(),
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: presetURL, options: .atomic)
            statusText = "Preset saved"
            return presetURL.path
        } catch {
            lastErrorText = "Preset save failed: \(error.localizedDescription)"
            return nil
        }
    }

    func rebalanceShapeCountsToRequestedTotal() {
        rebalanceShapeCounts(total: requestedTotalShapes)
    }

    func rebalanceShapeCounts(total: Int) {
        let clampedTotal = max(0, min(total, 1200))
        let current = [
            max(0, params.shapeCounts.circle),
            max(0, params.shapeCounts.triangle),
            max(0, params.shapeCounts.rectangle),
            max(0, params.shapeCounts.line),
        ]
        let currentTotal = current.reduce(0, +)

        var next = [Int](repeating: 0, count: 4)

        if clampedTotal == 0 {
            next = [0, 0, 0, 0]
        } else if currentTotal == 0 {
            let base = clampedTotal / 4
            var remainder = clampedTotal % 4
            for idx in 0..<4 {
                next[idx] = base
                if remainder > 0 {
                    next[idx] += 1
                    remainder -= 1
                }
            }
        } else {
            var distributed = 0
            for idx in 0..<4 {
                let scaled = Double(current[idx]) / Double(currentTotal) * Double(clampedTotal)
                next[idx] = Int(floor(scaled))
                distributed += next[idx]
            }
            var remainder = clampedTotal - distributed
            var idx = 0
            while remainder > 0 {
                next[idx % 4] += 1
                remainder -= 1
                idx += 1
            }
        }

        isApplyingTotalShapeRebalance = true
        params.shapeCounts.circle = next[0]
        params.shapeCounts.triangle = next[1]
        params.shapeCounts.rectangle = next[2]
        params.shapeCounts.line = next[3]
        requestedTotalShapes = params.totalShapes
        isApplyingTotalShapeRebalance = false
    }

    func applyResolutionPreset() {
        canvas.applyResolutionPreset()
    }

    func applyLongEdge() {
        canvas.applyLongEdge()
    }

    func applyRatioLock() {
        canvas.applyRatioLock()
    }

    func resetAnimationTracksFromCurrentParams() {
        animation.tracks = AnimationTrackFactory.makeDefaultTracks(from: params)
        alignTrackEndpointsWithFrameCount()
        animation.clamp()
    }

    func alignTrackEndpointsWithFrameCount() {
        let lastFrame = max(0, animation.frameCount - 1)
        for trackIndex in animation.tracks.indices {
            var keyframes = animation.tracks[trackIndex].keyframes
            if keyframes.isEmpty {
                keyframes = [TimelineKeyframe(frame: 0, value: trackDefaultValue(animation.tracks[trackIndex]), interpolation: .linear)]
            }
            for idx in keyframes.indices {
                keyframes[idx].frame = min(max(keyframes[idx].frame, 0), lastFrame)
                keyframes[idx].value = normalizedTrackValue(animation.tracks[trackIndex], keyframes[idx].value)
            }
            keyframes.sort { $0.frame < $1.frame }
            if keyframes.count == 1 {
                keyframes.append(TimelineKeyframe(frame: lastFrame, value: keyframes[0].value, interpolation: keyframes[0].interpolation))
            }
            animation.tracks[trackIndex].keyframes = keyframes
        }
        animation.scrubFrame = min(max(animation.scrubFrame, 0), lastFrame)
    }

    func addKeyframe(trackID: String, atFrame frame: Int) {
        guard let trackIndex = animation.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let track = animation.tracks[trackIndex]
        let lastFrame = max(0, animation.frameCount - 1)
        let clampedFrame = min(max(frame, 0), lastFrame)
        let value = valueForTrack(track, atFrame: clampedFrame)
        animation.tracks[trackIndex].keyframes.append(
            TimelineKeyframe(frame: clampedFrame, value: value, interpolation: .linear)
        )
        animation.tracks[trackIndex].keyframes.sort { $0.frame < $1.frame }
    }

    func deleteKeyframe(trackID: String, keyframeID: UUID) {
        guard let trackIndex = animation.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        animation.tracks[trackIndex].keyframes.removeAll { $0.id == keyframeID }
        if animation.tracks[trackIndex].keyframes.isEmpty {
            animation.tracks[trackIndex].keyframes = [TimelineKeyframe(frame: 0, value: trackDefaultValue(animation.tracks[trackIndex]), interpolation: .linear)]
        }
        alignTrackEndpointsWithFrameCount()
    }

    @discardableResult
    func duplicateKeyframe(trackID: String, keyframeID: UUID) -> UUID? {
        guard let trackIndex = animation.tracks.firstIndex(where: { $0.id == trackID }) else { return nil }
        guard let source = animation.tracks[trackIndex].keyframes.first(where: { $0.id == keyframeID }) else { return nil }
        let lastFrame = max(0, animation.frameCount - 1)
        let duplicated = TimelineKeyframe(
            frame: min(source.frame + 1, lastFrame),
            value: source.value,
            interpolation: source.interpolation
        )
        animation.tracks[trackIndex].keyframes.append(duplicated)
        animation.tracks[trackIndex].keyframes.sort { $0.frame < $1.frame }
        return duplicated.id
    }

    func updateKeyframe(trackID: String, keyframeID: UUID, frame: Int? = nil, value: Double? = nil, interpolation: TrackInterpolation? = nil) {
        guard let trackIndex = animation.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        guard let keyframeIndex = animation.tracks[trackIndex].keyframes.firstIndex(where: { $0.id == keyframeID }) else { return }

        if let frame {
            let lastFrame = max(0, animation.frameCount - 1)
            animation.tracks[trackIndex].keyframes[keyframeIndex].frame = min(max(frame, 0), lastFrame)
        }
        if let value {
            animation.tracks[trackIndex].keyframes[keyframeIndex].value = normalizedTrackValue(
                animation.tracks[trackIndex],
                value
            )
        }
        if let interpolation {
            animation.tracks[trackIndex].keyframes[keyframeIndex].interpolation = interpolation
        }
        animation.tracks[trackIndex].keyframes.sort { $0.frame < $1.frame }
    }

    private func sendHello() {
        client.sendRequest(type: "hello", payload: ["app": "GeoArtLab"]) { [weak self] result in
            switch result {
            case .success:
                Task { @MainActor in
                    guard let self else { return }
                    self.workerConnected = true
                    self.statusText = "Worker ready"
                }
            case .failure(let error):
                Task { @MainActor in
                    guard let self else { return }
                    self.workerConnected = false
                    self.lastErrorText = error.localizedDescription
                    self.statusText = "Worker failed to start"
                }
            }
        }
    }

    private func handleEvent(_ event: [String: Any]) {
        guard let type = event["type"] as? String else { return }

        if type == "export_progress",
           let payload = event["payload"] as? [String: Any],
           let completed = payload["completed"] as? Double,
           let total = payload["total"] as? Double {
            if total > 0 {
                exportProgress = completed / total
            }
            exportStatusText = "Exporting \(Int(completed))/\(Int(total))"
            return
        }

        if type == "animation_export_progress",
           let payload = event["payload"] as? [String: Any],
           let completed = payload["completed"] as? Double,
           let total = payload["total"] as? Double {
            if total > 0 {
                animationExportProgress = completed / total
            }
            animationExportStatusText = "Animation export \(Int(completed))/\(Int(total))"
            return
        }

        if type == "worker_started" {
            statusText = "Worker process started"
            return
        }

        if type == "worker_stopped" {
            workerConnected = false
            statusText = "Worker stopped, auto-restarting..."
            return
        }

        if type == "worker_stderr",
           let payload = event["payload"] as? [String: Any],
           let line = payload["line"] as? String {
            lastErrorText = line
            return
        }

        if type == "worker_error",
           let errorPayload = event["error"] as? [String: Any],
           let message = errorPayload["message"] as? String {
            lastErrorText = message
            statusText = "Worker error"
        }
    }

    private func previewPayload(seed: Int) -> [String: Any] {
        [
            "params": renderPayload(seed: seed),
            "canvas": [
                "width": canvas.resolvedWidthPreview,
                "height": canvas.resolvedHeightPreview,
            ],
            "output_root": outputRoot,
        ]
    }

    private func baseRenderPayload() -> [String: Any] {
        var payload = renderPayload(seed: params.seed)
        payload.removeValue(forKey: "seed")
        return payload
    }

    private func renderPayload(seed: Int) -> [String: Any] {
        [
            "style_id": params.styleID,
            "shape_family": params.shapeFamily.rawValue,
            "shape_count": max(1, min(params.totalShapes, 1200)),
            "total_shapes": max(1, min(params.totalShapes, 1200)),
            "symmetry": max(1, min(params.symmetry, 12)),
            "symmetry_mode": params.symmetryMode.rawValue,
            "rotation": params.rotation,
            "scale_range": params.scaleRange,
            "stroke_width": params.strokeWidth,
            "fill_ratio": params.fillRatio,
            "fill_ratios": [
                "circle": max(0, min(params.fillRatios.circle, 1)),
                "triangle": max(0, min(params.fillRatios.triangle, 1)),
                "rectangle": max(0, min(params.fillRatios.rectangle, 1)),
                "line": max(0, min(params.fillRatios.line, 1)),
            ],
            "palette_id": params.palette.rawValue,
            "palette_colors": PaletteLibrary.colors(for: params),
            "color_mode": params.colorMode.rawValue,
            "background_style": params.backgroundStyle.rawValue,
            "shape_counts": [
                "circle": max(0, min(params.shapeCounts.circle, 300)),
                "triangle": max(0, min(params.shapeCounts.triangle, 300)),
                "rectangle": max(0, min(params.shapeCounts.rectangle, 300)),
                "line": max(0, min(params.shapeCounts.line, 300)),
            ],
            "angle_ranges_deg": [
                "circle": ["min": params.angleRanges.circle.minDeg, "max": params.angleRanges.circle.maxDeg],
                "triangle": ["min": params.angleRanges.triangle.minDeg, "max": params.angleRanges.triangle.maxDeg],
                "rectangle": ["min": params.angleRanges.rectangle.minDeg, "max": params.angleRanges.rectangle.maxDeg],
                "line": ["min": params.angleRanges.line.minDeg, "max": params.angleRanges.line.maxDeg],
            ],
            "placement_regions": [
                "circle": [
                    "x_min": params.placementRegions.circle.xMin,
                    "x_max": params.placementRegions.circle.xMax,
                    "y_min": params.placementRegions.circle.yMin,
                    "y_max": params.placementRegions.circle.yMax,
                ],
                "triangle": [
                    "x_min": params.placementRegions.triangle.xMin,
                    "x_max": params.placementRegions.triangle.xMax,
                    "y_min": params.placementRegions.triangle.yMin,
                    "y_max": params.placementRegions.triangle.yMax,
                ],
                "rectangle": [
                    "x_min": params.placementRegions.rectangle.xMin,
                    "x_max": params.placementRegions.rectangle.xMax,
                    "y_min": params.placementRegions.rectangle.yMin,
                    "y_max": params.placementRegions.rectangle.yMax,
                ],
                "line": [
                    "x_min": params.placementRegions.line.xMin,
                    "x_max": params.placementRegions.line.xMax,
                    "y_min": params.placementRegions.line.yMin,
                    "y_max": params.placementRegions.line.yMax,
                ],
            ],
            "canvas_meta": [
                "lock_ratio": canvas.lockRatio,
                "ratio_preset": canvas.ratioPreset.rawValue,
                "long_edge_px": canvas.clampedLongEdge,
                "resolution_preset": canvas.resolutionPreset.rawValue,
                "preview_max_dim": canvas.clampedPreviewMaxDim,
                "export_max_dim": canvas.clampedExportMaxDim,
            ],
            "seed": seed,
            "tags": ["geo", "clean", "geometric"],
        ]
    }

    private func animationTimelinePayload() -> [String: Any] {
        let frameCount = max(1, min(animation.frameCount, 4096))
        let fps = max(1, min(animation.fps, 120))

        let tracks: [[String: Any]] = animation.tracks.compactMap { track in
            guard track.enabled else { return nil }
            let keyframes = normalizedKeyframes(for: track, frameCount: frameCount)
            return [
                "parameter_id": track.id,
                "keyframes": keyframes.map { key in
                    [
                        "frame": key.frame,
                        "value": key.value,
                        "interpolation": key.interpolation.rawValue,
                    ]
                },
            ]
        }

        return [
            "fps": fps,
            "frame_count": frameCount,
            "tracks": tracks,
        ]
    }

    private func normalizedTrackValue(_ track: AnimationTrack, _ value: Double) -> Double {
        let clamped = min(max(value, track.minValue), track.maxValue)
        if track.isInteger {
            return Double(Int(round(clamped)))
        }
        return clamped
    }

    private func normalizedKeyframes(for track: AnimationTrack, frameCount: Int) -> [TimelineKeyframe] {
        let lastFrame = max(0, frameCount - 1)
        var keyframes = track.keyframes
        if keyframes.isEmpty {
            let value = trackDefaultValue(track)
            return [
                TimelineKeyframe(frame: 0, value: value, interpolation: .linear),
                TimelineKeyframe(frame: lastFrame, value: value, interpolation: .linear),
            ]
        }
        for idx in keyframes.indices {
            keyframes[idx].frame = min(max(keyframes[idx].frame, 0), lastFrame)
            keyframes[idx].value = normalizedTrackValue(track, keyframes[idx].value)
        }
        keyframes.sort { $0.frame < $1.frame }
        if keyframes.count == 1 {
            keyframes.append(
                TimelineKeyframe(
                    frame: lastFrame,
                    value: keyframes[0].value,
                    interpolation: keyframes[0].interpolation
                )
            )
        }
        return keyframes
    }

    private func valueForTrack(_ track: AnimationTrack, atFrame frame: Int) -> Double {
        let keyframes = normalizedKeyframes(for: track, frameCount: animation.frameCount)
        guard let first = keyframes.first, let last = keyframes.last else {
            return trackDefaultValue(track)
        }
        if frame <= first.frame { return first.value }
        if frame >= last.frame { return last.value }

        for idx in 0..<(keyframes.count - 1) {
            let left = keyframes[idx]
            let right = keyframes[idx + 1]
            if frame < left.frame || frame > right.frame { continue }
            if frame == left.frame { return left.value }
            if frame == right.frame { return right.value }

            let span = max(1, right.frame - left.frame)
            var t = Double(frame - left.frame) / Double(span)
            switch left.interpolation {
            case .hold:
                t = 0
            case .linear:
                break
            case .easeIn:
                t = t * t
            case .easeOut:
                t = t * (2 - t)
            case .easeInOut:
                t = t < 0.5 ? (2 * t * t) : (-1 + (4 - 2 * t) * t)
            case .bounce:
                if t < 1 / 2.75 {
                    t = 7.5625 * t * t
                } else if t < 2 / 2.75 {
                    let n = t - (1.5 / 2.75)
                    t = (7.5625 * n * n) + 0.75
                } else if t < 2.5 / 2.75 {
                    let n = t - (2.25 / 2.75)
                    t = (7.5625 * n * n) + 0.9375
                } else {
                    let n = t - (2.625 / 2.75)
                    t = (7.5625 * n * n) + 0.984375
                }
            }
            return normalizedTrackValue(track, left.value + ((right.value - left.value) * t))
        }
        return trackDefaultValue(track)
    }

    private func trackDefaultValue(_ track: AnimationTrack) -> Double {
        switch track.id {
        case "rotation": return params.rotation
        case "stroke_width": return params.strokeWidth
        case "fill_ratio": return params.fillRatio
        case "symmetry": return Double(params.symmetry)
        case let id where id.hasPrefix("shape_counts."):
            let kind = id.replacingOccurrences(of: "shape_counts.", with: "")
            switch kind {
            case "circle": return Double(params.shapeCounts.circle)
            case "triangle": return Double(params.shapeCounts.triangle)
            case "rectangle": return Double(params.shapeCounts.rectangle)
            case "line": return Double(params.shapeCounts.line)
            default: return 0
            }
        case let id where id.hasPrefix("fill_ratios."):
            let kind = id.replacingOccurrences(of: "fill_ratios.", with: "")
            switch kind {
            case "circle": return params.fillRatios.circle
            case "triangle": return params.fillRatios.triangle
            case "rectangle": return params.fillRatios.rectangle
            case "line": return params.fillRatios.line
            default: return params.fillRatio
            }
        default:
            return 0
        }
    }

    private func handleNexusCommand(_ command: NexusCommand) {
        switch command.type {
        case .patchRenderParams:
            if let seed = command.int("seed") { params.seed = seed }
            if let symmetry = command.int("symmetry") { params.symmetry = min(max(symmetry, 1), 12) }
            if let symmetryModeRaw = command.payload["symmetry_mode"] as? String,
               let symmetryMode = SymmetryMode(rawValue: symmetryModeRaw) {
                params.symmetryMode = symmetryMode
            }
            if let rotation = command.double("rotation") { params.rotation = min(max(rotation, 0), 360) }
            if let stroke = command.double("stroke_width") { params.strokeWidth = min(max(stroke, 0.5), 18) }
            if let fill = command.double("fill_ratio") {
                params.fillRatio = min(max(fill, 0), 1)
            }
            schedulePreview()
        case .patchCanvas:
            if let width = command.int("width") { canvas.manualWidth = width }
            if let height = command.int("height") { canvas.manualHeight = height }
            if let lockRatio = command.payload["lock_ratio"] as? Bool { canvas.lockRatio = lockRatio }
            canvas.applyRatioLock()
            schedulePreview()
        case .requestPreview:
            requestPreview()
        case .requestAnimationPreview:
            requestAnimationPreview()
        case .exportBatch:
            exportBatch()
        case .exportAnimation:
            exportAnimation()
        }
    }
}
