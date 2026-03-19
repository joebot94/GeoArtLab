import AppKit
import SwiftUI

struct MainWindowView: View {
    private enum PreviewMode: String, CaseIterable, Identifiable {
        case staticImage = "Static"
        case animation = "Animation"

        var id: String { rawValue }
    }

    private enum RegionAxis {
        case xMin
        case xMax
        case yMin
        case yMax
    }

    @ObservedObject var appState: AppState

    @AppStorage("geoartlab.section.generator.open") private var generatorOpen = true
    @AppStorage("geoartlab.section.shapes.open") private var shapesOpen = true
    @AppStorage("geoartlab.section.color.open") private var colorOpen = false
    @AppStorage("geoartlab.section.canvas.open") private var canvasOpen = false
    @AppStorage("geoartlab.section.animation.open") private var animationOpen = false

    @State private var selectedShapeKind: ShapeKind = .circle
    @State private var previewMode: PreviewMode = .staticImage
    @State private var showTimeline = false
    @State private var showExportSheet = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)

            Divider()

            previewPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            outputPane
                .frame(width: 280)
        }
        .onChange(of: appState.params) { _ in
            appState.schedulePreview()
        }
        .onChange(of: appState.canvas) { _ in
            appState.schedulePreview()
        }
        .onChange(of: appState.animation) { _ in
            appState.scheduleAnimationPreview()
        }
        .sheet(isPresented: $showTimeline) {
            TimelineEditorView(appState: appState, isPresented: $showTimeline)
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheetView(appState: appState, isPresented: $showExportSheet)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    DisclosureGroup(isExpanded: $generatorOpen) {
                        generatorSection
                            .padding(.top, 6)
                    } label: {
                        sectionLabel("Generator")
                    }

                    DisclosureGroup(isExpanded: $shapesOpen) {
                        shapesSection
                            .padding(.top, 6)
                    } label: {
                        sectionLabel("Shapes")
                    }

                    DisclosureGroup(isExpanded: $colorOpen) {
                        colorSection
                            .padding(.top, 6)
                    } label: {
                        sectionLabel("Color")
                    }

                    DisclosureGroup(isExpanded: $canvasOpen) {
                        canvasSection
                            .padding(.top, 6)
                    } label: {
                        sectionLabel("Canvas")
                    }

                    DisclosureGroup(isExpanded: $animationOpen) {
                        animationSection
                            .padding(.top, 6)
                    } label: {
                        sectionLabel("Animation")
                    }
                }
                .padding(10)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Button("Reset All") {
                    appState.resetAll()
                }
                .buttonStyle(.bordered)

                Button("Save Preset") {
                    _ = appState.savePreset()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("s", modifiers: [.command])

                Button("Open Timeline") {
                    showTimeline = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("t", modifiers: [.command])

                Button("Export...") {
                    showExportSheet = true
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("e", modifiers: [.command])
            }
            .padding(10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var generatorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            compactIntField(title: "Total Shapes", value: $appState.requestedTotalShapes, range: 0...1200)
            compactIntField(title: "Seed", value: $appState.params.seed, range: 0...1_000_000)
            compactIntSlider(title: "Symmetry Count", value: $appState.params.symmetry, range: 1...12)
                .disabled(appState.params.symmetryMode == .none)
            compactPicker("Symmetry Mode", selection: $appState.params.symmetryMode) {
                ForEach(SymmetryMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            HStack(spacing: 6) {
                Button("Random") {
                    appState.randomizeSeed()
                }
                .buttonStyle(.bordered)

                Button("Rebalance") {
                    appState.rebalanceShapeCountsToRequestedTotal()
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Circles: \(appState.params.shapeCounts.circle)")
                Text("Triangles: \(appState.params.shapeCounts.triangle)")
                Text("Rectangles: \(appState.params.shapeCounts.rectangle)")
                Text("Lines: \(appState.params.shapeCounts.line)")
                if appState.params.symmetryMode == .none {
                    Text("Symmetry Off: random placement")
                } else {
                    Text("Instances x\(appState.params.symmetry)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var shapesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(ShapeKind.allCases) { kind in
                    Button {
                        selectedShapeKind = kind
                    } label: {
                        Text(kind.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                selectedShapeKind == kind ?
                                    Color.orange.opacity(0.2) :
                                    Color.secondary.opacity(0.08)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }

            compactIntField(title: "Count", value: shapeCountBinding(selectedShapeKind), range: 0...300)
            compactDoubleSlider(title: "Fill Ratio", value: shapeFillRatioBinding(selectedShapeKind), range: 0...1, step: 0.01, precision: 2)
            compactDoubleSlider(title: "Angle Min", value: angleBinding(selectedShapeKind, isMin: true), range: 0...360, step: 1, precision: 0)
            compactDoubleSlider(title: "Angle Max", value: angleBinding(selectedShapeKind, isMin: false), range: 0...360, step: 1, precision: 0)
            compactDoubleSlider(title: "Region X Min", value: regionBinding(selectedShapeKind, axis: .xMin), range: 0...1, step: 0.01, precision: 2)
            compactDoubleSlider(title: "Region X Max", value: regionBinding(selectedShapeKind, axis: .xMax), range: 0...1, step: 0.01, precision: 2)
            compactDoubleSlider(title: "Region Y Min", value: regionBinding(selectedShapeKind, axis: .yMin), range: 0...1, step: 0.01, precision: 2)
            compactDoubleSlider(title: "Region Y Max", value: regionBinding(selectedShapeKind, axis: .yMax), range: 0...1, step: 0.01, precision: 2)
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            compactPicker("Palette", selection: $appState.params.palette) {
                ForEach(PalettePreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }

            compactPicker("Color Mode", selection: $appState.params.colorMode) {
                ForEach(ColorMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            compactPicker("Background", selection: $appState.params.backgroundStyle) {
                ForEach(BackgroundStyle.allCases) { background in
                    Text(background.title).tag(background)
                }
            }

            compactDoubleSlider(title: "Global Fill", value: $appState.params.fillRatio, range: 0...1, step: 0.01, precision: 2)

            Button("Apply Global Fill To Shapes") {
                appState.applyGlobalFillRatioToAllShapes()
            }
            .buttonStyle(.bordered)

            if appState.params.palette == .custom {
                TextField("#RRGGBB,#RRGGBB,#RRGGBB", text: $appState.params.customPaletteText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }
        }
    }

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            compactPicker("Ratio", selection: $appState.canvas.ratioPreset) {
                ForEach(AspectRatioPreset.allCases) { ratio in
                    Text(ratio.title).tag(ratio)
                }
            }
            .onChange(of: appState.canvas.ratioPreset) { _ in
                appState.applyRatioLock()
            }

            compactPicker("Resolution", selection: $appState.canvas.resolutionPreset) {
                ForEach(ResolutionPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .onChange(of: appState.canvas.resolutionPreset) { _ in
                appState.applyResolutionPreset()
            }

            Toggle("Lock Ratio", isOn: $appState.canvas.lockRatio)
                .font(.caption)
                .onChange(of: appState.canvas.lockRatio) { _ in
                    appState.applyRatioLock()
                }

            compactPicker("Drive", selection: $appState.canvas.ratioDrivingDimension) {
                ForEach(RatioDrivingDimension.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .onChange(of: appState.canvas.ratioDrivingDimension) { _ in
                appState.applyRatioLock()
            }

            compactIntField(title: "Width", value: $appState.canvas.manualWidth, range: 64...16384)
            compactIntField(title: "Height", value: $appState.canvas.manualHeight, range: 64...16384)

            Text("Preview \(appState.canvas.resolvedWidthPreview)x\(appState.canvas.resolvedHeightPreview)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Export \(appState.canvas.resolvedWidthExport)x\(appState.canvas.resolvedHeightExport)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var animationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            compactIntField(title: "FPS", value: $appState.animation.fps, range: 1...120)
                .onChange(of: appState.animation.fps) { _ in
                    appState.animation.clamp()
                }

            compactIntField(title: "Frames", value: $appState.animation.frameCount, range: 1...4096)
                .onChange(of: appState.animation.frameCount) { _ in
                    appState.animation.clamp()
                    appState.alignTrackEndpointsWithFrameCount()
                }

            compactIntSlider(title: "Scrub Frame", value: $appState.animation.scrubFrame, range: 0...max(0, appState.animation.frameCount - 1))
                .onChange(of: appState.animation.scrubFrame) { _ in
                    appState.requestAnimationPreview()
                }

            Button("Open Timeline Editor") {
                showTimeline = true
            }
            .buttonStyle(.borderedProminent)

            Button("Preview Current Frame") {
                appState.requestAnimationPreview()
            }
            .buttonStyle(.bordered)
        }
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Preview")
                    .font(.headline)

                Spacer()

                Picker("Preview", selection: $previewMode) {
                    ForEach(PreviewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Circle()
                    .fill(appState.workerConnected ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)

                if let image = currentPreviewImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(8)
                } else {
                    Text("No preview")
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

            if appState.lastErrorText.isEmpty == false {
                Text(appState.lastErrorText)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                Button("Render") {
                    appState.requestPreview()
                }
                .buttonStyle(.bordered)

                Button("Animation Frame") {
                    appState.requestAnimationPreview()
                }
                .buttonStyle(.bordered)

                Button("Timeline") {
                    showTimeline = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
    }

    private var outputPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export")
                .font(.headline)

            GroupBox("Image") {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: appState.exportProgress)
                    Text(appState.exportStatusText.isEmpty ? "Idle" : appState.exportStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    List(appState.exportedFiles, id: \.self) { item in
                        Text(item)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .frame(minHeight: 120)
                }
            }

            GroupBox("Animation") {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: appState.animationExportProgress)
                    Text(appState.animationExportStatusText.isEmpty ? "Idle" : appState.animationExportStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    List(appState.animationExportedFiles, id: \.self) { item in
                        Text(item)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .frame(minHeight: 100)
                }
            }

            Spacer()
        }
        .padding(12)
    }

    private var currentPreviewImage: NSImage? {
        switch previewMode {
        case .staticImage:
            return appState.previewImage
        case .animation:
            return appState.animationPreviewImage ?? appState.previewImage
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }

    private func compactPicker<T: Hashable, Content: View>(
        _ title: String,
        selection: Binding<T>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Picker(title, selection: selection, content: content)
                .pickerStyle(.menu)
                .labelsHidden()
        }
    }

    private func compactIntField(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField("", value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit {
                        value.wrappedValue = min(max(value.wrappedValue, range.lowerBound), range.upperBound)
                    }

                Stepper("", value: value, in: range)
                    .labelsHidden()
                    .controlSize(.small)
            }
        }
    }

    private func compactIntSlider(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            compactIntField(title: title, value: value, range: range)
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
        }
    }

    private func compactDoubleSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        precision: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField("", value: value, format: .number.precision(.fractionLength(precision)))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(width: 84)
                    .onSubmit {
                        value.wrappedValue = min(max(value.wrappedValue, range.lowerBound), range.upperBound)
                    }
                Slider(value: value, in: range, step: step)
            }
        }
    }

    private func shapeCountBinding(_ kind: ShapeKind) -> Binding<Int> {
        Binding(
            get: { appState.params.shapeCounts[kind] },
            set: { newValue in
                appState.params.shapeCounts[kind] = min(max(newValue, 0), 300)
            }
        )
    }

    private func shapeFillRatioBinding(_ kind: ShapeKind) -> Binding<Double> {
        Binding(
            get: { appState.params.fillRatios[kind] },
            set: { newValue in
                appState.params.fillRatios[kind] = min(max(newValue, 0), 1)
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
}

private struct ExportSheetView: View {
    private enum ExportType: String, CaseIterable, Identifiable {
        case staticBatch = "Static Batch"
        case animation = "Animation"

        var id: String { rawValue }
    }

    @ObservedObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var exportType: ExportType = .staticBatch

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export")
                .font(.headline)

            Picker("Type", selection: $exportType) {
                ForEach(ExportType.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if exportType == .staticBatch {
                Text("Exports PNG + SVG + JBT for the configured repeats.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Exports PNG frames + animation.jbt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                Button("Export") {
                    if exportType == .staticBatch {
                        appState.exportBatch()
                    } else {
                        appState.exportAnimation()
                    }
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}
