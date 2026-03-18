import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var params = RenderParameters()
    @Published var canvas = CanvasSettings()
    @Published var baseSeed = 42
    @Published var repeats = 10
    @Published var outputRoot = "\(NSHomeDirectory())/JBT/geo_art_lab"

    @Published var previewImage: NSImage?
    @Published var statusText = "Waiting for worker..."
    @Published var workerConnected = false
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var exportStatusText = ""
    @Published var exportedFiles: [String] = []
    @Published var lastErrorText = ""

    private let client: PythonWorkerClient
    private var previewDebounceTask: Task<Void, Never>?
    private var hasStarted = false

    init(client: PythonWorkerClient = PythonWorkerClient()) {
        self.client = client
        self.client.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleEvent(event)
            }
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        statusText = "Launching Python worker..."
        client.startIfNeeded()
        sendHello()
        schedulePreview()
    }

    func schedulePreview() {
        previewDebounceTask?.cancel()
        previewDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.requestPreview()
        }
    }

    func requestPreview() {
        let payload = previewPayload(seed: params.seed)
        statusText = "Rendering preview..."

        client.sendRequest(type: "render_preview", payload: payload) { [weak self] result in
            switch result {
            case .success(let response):
                let payload = response["payload"] as? [String: Any]
                let previewPath = payload?["preview_path"] as? String
                Task { @MainActor in
                    guard let self else { return }
                    guard let previewPath else {
                        self.lastErrorText = "Preview response missing preview_path"
                        self.statusText = "Preview failed"
                        return
                    }

                    let previewURL = URL(fileURLWithPath: previewPath)
                    if let image = NSImage(contentsOf: previewURL) {
                        self.previewImage = image
                        self.statusText = "Preview ready"
                    } else {
                        self.statusText = "Preview image unreadable"
                    }
                }
            case .failure(let error):
                let errorMessage = error.localizedDescription
                Task { @MainActor in
                    guard let self else { return }
                    self.lastErrorText = errorMessage
                    self.statusText = "Preview failed"
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
                "width": canvas.resolvedWidth,
                "height": canvas.resolvedHeight
            ]
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
                let errorMessage = error.localizedDescription
                Task { @MainActor in
                    guard let self else { return }
                    self.isExporting = false
                    self.lastErrorText = errorMessage
                    self.exportStatusText = "Export failed"
                    self.statusText = "Export failed"
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
                let errorMessage = error.localizedDescription
                Task { @MainActor in
                    guard let self else { return }
                    self.workerConnected = false
                    self.lastErrorText = errorMessage
                    self.statusText = "Worker ping failed"
                }
            }
        }
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
                let errorMessage = error.localizedDescription
                Task { @MainActor in
                    guard let self else { return }
                    self.workerConnected = false
                    self.lastErrorText = errorMessage
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
            let seedText: String
            if let seed = payload["seed"] as? Int {
                seedText = " seed \(seed)"
            } else {
                seedText = ""
            }
            exportStatusText = "Exporting \(Int(completed))/\(Int(total))\(seedText)"
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
                "width": canvas.resolvedWidth,
                "height": canvas.resolvedHeight
            ]
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
            "shape_count": max(1, min(params.shapeCounts.total, 1200)),
            "symmetry": max(1, min(params.symmetry, 12)),
            "rotation": params.rotation,
            "scale_range": params.scaleRange,
            "stroke_width": params.strokeWidth,
            "fill_ratio": params.fillRatio,
            "palette_id": params.palette.rawValue,
            "palette_colors": PaletteLibrary.colors(for: params),
            "color_mode": params.colorMode.rawValue,
            "background_style": params.backgroundStyle.rawValue,
            "shape_counts": [
                "circle": max(0, min(params.shapeCounts.circle, 300)),
                "triangle": max(0, min(params.shapeCounts.triangle, 300)),
                "rectangle": max(0, min(params.shapeCounts.rectangle, 300)),
                "line": max(0, min(params.shapeCounts.line, 300))
            ],
            "angle_ranges_deg": [
                "circle": ["min": params.angleRanges.circle.minDeg, "max": params.angleRanges.circle.maxDeg],
                "triangle": ["min": params.angleRanges.triangle.minDeg, "max": params.angleRanges.triangle.maxDeg],
                "rectangle": ["min": params.angleRanges.rectangle.minDeg, "max": params.angleRanges.rectangle.maxDeg],
                "line": ["min": params.angleRanges.line.minDeg, "max": params.angleRanges.line.maxDeg]
            ],
            "placement_regions": [
                "circle": [
                    "x_min": params.placementRegions.circle.xMin,
                    "x_max": params.placementRegions.circle.xMax,
                    "y_min": params.placementRegions.circle.yMin,
                    "y_max": params.placementRegions.circle.yMax
                ],
                "triangle": [
                    "x_min": params.placementRegions.triangle.xMin,
                    "x_max": params.placementRegions.triangle.xMax,
                    "y_min": params.placementRegions.triangle.yMin,
                    "y_max": params.placementRegions.triangle.yMax
                ],
                "rectangle": [
                    "x_min": params.placementRegions.rectangle.xMin,
                    "x_max": params.placementRegions.rectangle.xMax,
                    "y_min": params.placementRegions.rectangle.yMin,
                    "y_max": params.placementRegions.rectangle.yMax
                ],
                "line": [
                    "x_min": params.placementRegions.line.xMin,
                    "x_max": params.placementRegions.line.xMax,
                    "y_min": params.placementRegions.line.yMin,
                    "y_max": params.placementRegions.line.yMax
                ]
            ],
            "canvas_meta": [
                "lock_ratio": canvas.lockRatio,
                "ratio_preset": canvas.ratioPreset.rawValue,
                "long_edge_px": canvas.clampedLongEdge
            ],
            "seed": seed,
            "tags": ["geo", "clean", "geometric"]
        ]
    }
}
