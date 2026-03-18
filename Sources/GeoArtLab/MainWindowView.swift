import AppKit
import SwiftUI

struct MainWindowView: View {
    private enum RegionAxis {
        case xMin
        case xMax
        case yMin
        case yMax
    }

    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            controlsPanel
            Divider()
            previewPanel
            Divider()
            exportPanel
        }
        .onChange(of: appState.params) { _ in
            appState.schedulePreview()
        }
        .onChange(of: appState.canvas) { _ in
            appState.schedulePreview()
        }
    }

    private var controlsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Generator")

                Text("Total Shapes: \(appState.params.shapeCounts.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(ShapeKind.allCases) { kind in
                    GroupBox(kind.title) {
                        VStack(alignment: .leading, spacing: 8) {
                            Stepper("Count: \(appState.params.shapeCounts[kind])", value: shapeCountBinding(kind), in: 0...300)

                            labeledSlider(
                                title: "Angle Min",
                                value: angleBinding(kind, isMin: true),
                                range: 0...360,
                                step: 1,
                                format: "%.0f°"
                            )

                            labeledSlider(
                                title: "Angle Max",
                                value: angleBinding(kind, isMin: false),
                                range: 0...360,
                                step: 1,
                                format: "%.0f°"
                            )

                            labeledSlider(
                                title: "Region X Min",
                                value: regionBinding(kind, axis: .xMin),
                                range: 0...1,
                                step: 0.01,
                                format: "%.2f"
                            )

                            labeledSlider(
                                title: "Region X Max",
                                value: regionBinding(kind, axis: .xMax),
                                range: 0...1,
                                step: 0.01,
                                format: "%.2f"
                            )

                            labeledSlider(
                                title: "Region Y Min",
                                value: regionBinding(kind, axis: .yMin),
                                range: 0...1,
                                step: 0.01,
                                format: "%.2f"
                            )

                            labeledSlider(
                                title: "Region Y Max",
                                value: regionBinding(kind, axis: .yMax),
                                range: 0...1,
                                step: 0.01,
                                format: "%.2f"
                            )
                        }
                    }
                }

                Stepper("Symmetry: \(appState.params.symmetry)", value: $appState.params.symmetry, in: 1...12)

                labeledSlider(
                    title: "Rotation",
                    value: $appState.params.rotation,
                    range: 0...360,
                    step: 1,
                    format: "%.0f°"
                )

                labeledSlider(
                    title: "Scale Range",
                    value: $appState.params.scaleRange,
                    range: 0.1...1.0,
                    step: 0.01,
                    format: "%.2f"
                )

                labeledSlider(
                    title: "Stroke Width",
                    value: $appState.params.strokeWidth,
                    range: 0.5...18,
                    step: 0.5,
                    format: "%.1f"
                )

                labeledSlider(
                    title: "Fill Ratio",
                    value: $appState.params.fillRatio,
                    range: 0...1,
                    step: 0.01,
                    format: "%.2f"
                )

                Picker("Palette", selection: $appState.params.palette) {
                    ForEach(PalettePreset.allCases) { palette in
                        Text(palette.title).tag(palette)
                    }
                }

                Picker("Color Mode", selection: $appState.params.colorMode) {
                    ForEach(ColorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                if appState.params.palette == .custom {
                    TextField("Custom colors (#RRGGBB,#RRGGBB,...)", text: $appState.params.customPaletteText)
                        .textFieldStyle(.roundedBorder)
                }

                Picker("Background", selection: $appState.params.backgroundStyle) {
                    ForEach(BackgroundStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }

                Stepper("Seed: \(appState.params.seed)", value: $appState.params.seed, in: 0...1_000_000)

                Divider().padding(.vertical, 4)
                sectionTitle("Canvas")

                Toggle("Lock Aspect Ratio", isOn: $appState.canvas.lockRatio)

                if appState.canvas.lockRatio {
                    Picker("Ratio", selection: $appState.canvas.ratioPreset) {
                        ForEach(AspectRatioPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    Stepper("Long Edge: \(appState.canvas.clampedLongEdge)", value: $appState.canvas.longEdgePx, in: 512...4096)
                    Text("Computed: \(appState.canvas.resolvedWidth) × \(appState.canvas.resolvedHeight)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Stepper("Width: \(appState.canvas.manualWidth)", value: $appState.canvas.manualWidth, in: 64...4096)
                    Stepper("Height: \(appState.canvas.manualHeight)", value: $appState.canvas.manualHeight, in: 64...4096)
                }

                Divider().padding(.vertical, 4)
                sectionTitle("Batch")

                Stepper("Base Seed: \(appState.baseSeed)", value: $appState.baseSeed, in: 0...1_000_000)
                Stepper("Repeats: \(appState.repeats)", value: $appState.repeats, in: 1...512)

                Text("Output Root")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("~/JBT/geo_art_lab", text: $appState.outputRoot)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button("Render Now") {
                        appState.requestPreview()
                    }
                    Button("Ping Worker") {
                        appState.pingWorker()
                    }
                    Button("Export Batch") {
                        appState.exportBatch()
                    }
                    .keyboardShortcut("e", modifiers: [.command])
                    .disabled(appState.isExporting)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 360, idealWidth: 400, maxWidth: 420)
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Preview")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(appState.workerConnected ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(appState.workerConnected ? "Worker connected" : "Worker reconnecting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.9))

                if let image = appState.previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(10)
                } else {
                    Text("No preview yet")
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )

            Text(appState.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !appState.lastErrorText.isEmpty {
                Text(appState.lastErrorText)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var exportPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export")
                .font(.headline)

            ProgressView(value: appState.exportProgress)
                .progressViewStyle(.linear)

            Text(appState.exportStatusText.isEmpty ? "Idle" : appState.exportStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            List(appState.exportedFiles, id: \.self) { item in
                Text(item)
                    .font(.system(.caption, design: .monospaced))
            }
            .listStyle(.inset)

            Spacer()
        }
        .padding(16)
        .frame(minWidth: 290, idealWidth: 320, maxWidth: 360)
    }

    private func shapeCountBinding(_ kind: ShapeKind) -> Binding<Int> {
        Binding(
            get: { appState.params.shapeCounts[kind] },
            set: { newValue in
                appState.params.shapeCounts[kind] = newValue
            }
        )
    }

    private func angleBinding(_ kind: ShapeKind, isMin: Bool) -> Binding<Double> {
        Binding(
            get: {
                let range = appState.params.angleRanges[kind]
                return isMin ? range.minDeg : range.maxDeg
            },
            set: { newValue in
                var range = appState.params.angleRanges[kind]
                if isMin {
                    range.minDeg = newValue
                } else {
                    range.maxDeg = newValue
                }
                appState.params.angleRanges[kind] = range
            }
        )
    }

    private func regionBinding(_ kind: ShapeKind, axis: RegionAxis) -> Binding<Double> {
        Binding(
            get: {
                let region = appState.params.placementRegions[kind]
                switch axis {
                case .xMin: return region.xMin
                case .xMax: return region.xMax
                case .yMin: return region.yMin
                case .yMax: return region.yMax
                }
            },
            set: { newValue in
                var region = appState.params.placementRegions[kind]
                switch axis {
                case .xMin: region.xMin = newValue
                case .xMax: region.xMax = newValue
                case .yMin: region.yMin = newValue
                case .yMax: region.yMax = newValue
                }
                appState.params.placementRegions[kind] = region
            }
        )
    }

    @ViewBuilder
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    @ViewBuilder
    private func labeledSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title): \(String(format: format, value.wrappedValue))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: value, in: range, step: step)
        }
    }
}
