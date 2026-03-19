import AppKit
import SwiftUI

struct TimelineEditorView: View {
    @ObservedObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var selectedTrackID: String?
    @State private var selectedKeyframeID: UUID?
    @State private var isPlaying = false
    @State private var playTask: Task<Void, Never>?
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            scrubber
            Divider()
            content
        }
        .frame(minWidth: 1100, minHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.alignTrackEndpointsWithFrameCount()
            if selectedTrackID == nil {
                selectedTrackID = appState.animation.tracks.first?.id
            }
            if selectedKeyframeID == nil,
               let selectedTrackID,
               let track = appState.animation.tracks.first(where: { $0.id == selectedTrackID }) {
                selectedKeyframeID = track.keyframes.first?.id
            }
            appState.requestAnimationPreview(immediate: true)
            registerKeyboardShortcuts()
        }
        .onDisappear {
            stopPlayback()
            unregisterKeyboardShortcuts()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(isPlaying ? "Pause" : "Play") {
                togglePlayback()
            }
            .buttonStyle(.borderedProminent)

            Button("Stop") {
                stopPlayback(resetFrame: true)
            }
            .buttonStyle(.bordered)

            Divider().frame(height: 18)

            LabeledContent("FPS") {
                TextField("", value: $appState.animation.fps, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .onSubmit {
                        appState.animation.clamp()
                    }
            }
            .font(.caption)

            LabeledContent("Frames") {
                TextField("", value: $appState.animation.frameCount, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onSubmit {
                        appState.animation.clamp()
                        appState.alignTrackEndpointsWithFrameCount()
                    }
            }
            .font(.caption)

            TextField("Animation Name", text: $appState.animation.animationName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)

            Spacer()

            Button("Export Animation") {
                appState.exportAnimation()
            }
            .buttonStyle(.borderedProminent)

            Button("Close") {
                isPresented = false
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    private var scrubber: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Frame \(appState.animation.scrubFrame + 1) / \(max(1, appState.animation.frameCount))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timecodeForCurrentFrame())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { Double(appState.animation.scrubFrame) },
                    set: { appState.animation.scrubFrame = Int($0.rounded()) }
                ),
                in: 0...Double(max(0, appState.animation.frameCount - 1)),
                step: 1
            )
            .onChange(of: appState.animation.scrubFrame) { _ in
                appState.requestAnimationPreview(immediate: true)
            }

            HStack(spacing: 0) {
                let seconds = max(1, Int(ceil(Double(max(1, appState.animation.frameCount)) / Double(max(1, appState.animation.fps)))))
                ForEach(0...seconds, id: \.self) { second in
                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.45))
                            .frame(width: 1, height: 6)
                        Text("\(second)s")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
    }

    private var content: some View {
        HStack(spacing: 0) {
            tracksList
            Divider()
            selectedProperties
        }
    }

    private var tracksList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(appState.animation.tracks.indices, id: \.self) { index in
                    trackRow(index: index)
                }
            }
            .padding(12)
        }
    }

    private func trackRow(index: Int) -> some View {
        let track = appState.animation.tracks[index]
        let selected = selectedTrackID == track.id

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(colorFromHex(track.colorHex))
                    .frame(width: 10, height: 10)
                Toggle(track.title, isOn: trackEnabledBinding(index))
                Spacer()
                Button("Add Key") {
                    selectedTrackID = track.id
                    appState.addKeyframe(trackID: track.id, atFrame: appState.animation.scrubFrame)
                    selectedKeyframeID = appState.animation.tracks[index].keyframes.last?.id
                }
                .buttonStyle(.bordered)
            }

            TimelineTrackBar(
                track: track,
                frameCount: max(1, appState.animation.frameCount),
                selectedKeyframeID: selectedKeyframeID,
                onSelect: { keyframeID in
                    selectedTrackID = track.id
                    selectedKeyframeID = keyframeID
                },
                onMove: { keyframeID, newFrame in
                    appState.updateKeyframe(trackID: track.id, keyframeID: keyframeID, frame: newFrame)
                }
            )
            .frame(height: 34)
        }
        .padding(10)
        .background(selected ? Color.orange.opacity(0.14) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            selectedTrackID = track.id
        }
    }

    private var selectedProperties: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keyframe Properties")
                .font(.headline)

            if let selectedTrack, let selectedKeyframe {
                Text(selectedTrack.title)
                    .font(.subheadline.weight(.semibold))

                LabeledContent("Frame") {
                    TextField(
                        "",
                        value: Binding(
                            get: { selectedKeyframe.frame },
                            set: { appState.updateKeyframe(trackID: selectedTrack.id, keyframeID: selectedKeyframe.id, frame: $0) }
                        ),
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                }
                .font(.caption)

                LabeledContent("Value") {
                    TextField(
                        "",
                        value: Binding(
                            get: { selectedKeyframe.value },
                            set: { appState.updateKeyframe(trackID: selectedTrack.id, keyframeID: selectedKeyframe.id, value: $0) }
                        ),
                        format: .number.precision(.fractionLength(selectedTrack.isInteger ? 0 : 2))
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                }
                .font(.caption)

                LabeledContent("Easing") {
                    Picker("", selection: Binding(
                        get: { selectedKeyframe.interpolation },
                        set: { appState.updateKeyframe(trackID: selectedTrack.id, keyframeID: selectedKeyframe.id, interpolation: $0) }
                    )) {
                        ForEach(TrackInterpolation.allCases) { interpolation in
                            Text(interpolation.title).tag(interpolation)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }
                .font(.caption)

                HStack(spacing: 8) {
                    Button("Duplicate") {
                        selectedKeyframeID = appState.duplicateKeyframe(trackID: selectedTrack.id, keyframeID: selectedKeyframe.id)
                    }
                    .buttonStyle(.bordered)

                    Button("Delete") {
                        appState.deleteKeyframe(trackID: selectedTrack.id, keyframeID: selectedKeyframe.id)
                        selectedKeyframeID = appState.animation.tracks.first(where: { $0.id == selectedTrack.id })?.keyframes.first?.id
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("Select a track and keyframe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Live Preview")
                .font(.subheadline.weight(.semibold))

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)

                if let image = appState.animationPreviewImage ?? appState.previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(8)
                } else {
                    Text("No animation preview")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 260)

            Spacer()
        }
        .padding(12)
        .frame(width: 340)
    }

    private var selectedTrack: AnimationTrack? {
        guard let selectedTrackID else { return nil }
        return appState.animation.tracks.first(where: { $0.id == selectedTrackID })
    }

    private var selectedKeyframe: TimelineKeyframe? {
        guard let selectedTrack else { return nil }
        guard let selectedKeyframeID else { return nil }
        return selectedTrack.keyframes.first(where: { $0.id == selectedKeyframeID })
    }

    private func trackEnabledBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { appState.animation.tracks[index].enabled },
            set: { appState.animation.tracks[index].enabled = $0 }
        )
    }

    private func timecodeForCurrentFrame() -> String {
        let fps = max(1, appState.animation.fps)
        let seconds = Double(appState.animation.scrubFrame) / Double(fps)
        return String(format: "%.2fs", seconds)
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback(resetFrame: false)
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        stopPlayback(resetFrame: false)
        isPlaying = true
        let fps = max(1, appState.animation.fps)
        let sleepNanos = UInt64(1_000_000_000 / fps)
        playTask = Task {
            while Task.isCancelled == false {
                await MainActor.run {
                    let lastFrame = max(0, appState.animation.frameCount - 1)
                    if appState.animation.scrubFrame >= lastFrame {
                        appState.animation.scrubFrame = 0
                    } else {
                        appState.animation.scrubFrame += 1
                    }
                    appState.requestAnimationPreview(immediate: true)
                }
                try? await Task.sleep(nanoseconds: sleepNanos)
            }
        }
    }

    private func stopPlayback(resetFrame: Bool = false) {
        isPlaying = false
        playTask?.cancel()
        playTask = nil
        if resetFrame {
            appState.animation.scrubFrame = 0
            appState.requestAnimationPreview(immediate: true)
        }
    }

    private func colorFromHex(_ hex: String) -> Color {
        let raw = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard raw.count == 6, let value = Int(raw, radix: 16) else { return .orange }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    private func registerKeyboardShortcuts() {
        unregisterKeyboardShortcuts()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            return handleKeyDown(event)
        }
    }

    private func unregisterKeyboardShortcuts() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if NSApp.keyWindow?.firstResponder is NSTextView {
            return event
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

        if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "d" {
            duplicateSelectedKeyframe()
            return nil
        }

        switch event.keyCode {
        case 49: // space
            togglePlayback()
            return nil
        case 123: // left
            stepFrame(-1)
            return nil
        case 124: // right
            stepFrame(1)
            return nil
        case 115: // home
            appState.animation.scrubFrame = 0
            appState.requestAnimationPreview(immediate: true)
            return nil
        case 119: // end
            appState.animation.scrubFrame = max(0, appState.animation.frameCount - 1)
            appState.requestAnimationPreview(immediate: true)
            return nil
        case 51, 117: // delete / forward delete
            deleteSelectedKeyframe()
            return nil
        case 53: // escape
            isPresented = false
            return nil
        default:
            return event
        }
    }

    private func stepFrame(_ delta: Int) {
        let last = max(0, appState.animation.frameCount - 1)
        appState.animation.scrubFrame = min(max(appState.animation.scrubFrame + delta, 0), last)
        appState.requestAnimationPreview(immediate: true)
    }

    private func deleteSelectedKeyframe() {
        guard let selectedTrack else { return }
        guard let selectedKeyframe else { return }
        appState.deleteKeyframe(trackID: selectedTrack.id, keyframeID: selectedKeyframe.id)
        selectedKeyframeID = appState.animation.tracks.first(where: { $0.id == selectedTrack.id })?.keyframes.first?.id
    }

    private func duplicateSelectedKeyframe() {
        guard let selectedTrack else { return }
        guard let selectedKeyframe else { return }
        selectedKeyframeID = appState.duplicateKeyframe(trackID: selectedTrack.id, keyframeID: selectedKeyframe.id)
    }
}

private struct TimelineTrackBar: View {
    let track: AnimationTrack
    let frameCount: Int
    let selectedKeyframeID: UUID?
    let onSelect: (UUID) -> Void
    let onMove: (UUID, Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(1.0, proxy.size.width)
            let safeFrames = max(1, frameCount)
            let lastFrame = max(0, safeFrames - 1)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.14))

                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(height: 1)
                    .padding(.horizontal, 8)

                ForEach(track.keyframes) { keyframe in
                    let x = (Double(min(max(keyframe.frame, 0), lastFrame)) / Double(max(1, lastFrame))) * (width - 16) + 8
                    Circle()
                        .fill(selectedKeyframeID == keyframe.id ? Color.white : Color.orange)
                        .overlay(Circle().stroke(Color.orange, lineWidth: selectedKeyframeID == keyframe.id ? 2 : 1))
                        .frame(width: selectedKeyframeID == keyframe.id ? 12 : 10, height: selectedKeyframeID == keyframe.id ? 12 : 10)
                        .position(x: x, y: proxy.size.height / 2)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let normalized = min(max(value.location.x / width, 0), 1)
                                    let frame = Int(round(normalized * Double(lastFrame)))
                                    onMove(keyframe.id, frame)
                                }
                                .onEnded { _ in
                                    onSelect(keyframe.id)
                                }
                        )
                        .onTapGesture {
                            onSelect(keyframe.id)
                        }
                }
            }
        }
    }
}
