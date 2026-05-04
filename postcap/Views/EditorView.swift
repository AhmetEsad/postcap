import SwiftUI

struct EditorView: View {
    @ObservedObject var model: AppModel
    @Binding var selectedTab: InspectorTab

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding<InspectorTab?>(
                get: { selectedTab },
                set: { if let tab = $0 { selectedTab = tab } }
            )) {
                ForEach(InspectorTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(Optional(tab))
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(height: 108)
            .padding(.top, 8)

            Divider()

            ScrollView {
                Group {
                    switch selectedTab {
                    case .edit:
                        EditInspectorContent(model: model)
                    case .settings:
                        WaveformSettingsSection(model: model)
                    case .ffmpeg:
                        VStack(alignment: .leading, spacing: 18) {
                            BinarySettingsView(model: model)
                            FfmpegLogSection(model: model)
                        }
                    }
                }
                .padding(18)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.refreshEncoders() }
    }
}

enum InspectorTab: CaseIterable, Identifiable {
    case edit
    case settings
    case ffmpeg

    var id: Self { self }

    var title: String {
        switch self {
        case .edit:
            "Edit"
        case .settings:
            "Settings"
        case .ffmpeg:
            "FFmpeg"
        }
    }

    var systemImage: String {
        switch self {
        case .edit:
            "slider.horizontal.3"
        case .settings:
            "gearshape"
        case .ffmpeg:
            "terminal"
        }
    }
}

private struct EditInspectorContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ImportSection(model: model)

            if let info = model.videoInfo {
                VideoSettingsSection(model: model, info: info)
                AudioSection(model: model, info: info)
                ExportSection(model: model)
            }

            if let error = model.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct ImportSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SectionView(title: "Source") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.inputURL?.lastPathComponent ?? "No video selected")
                        .font(.headline)
                        .lineLimit(1)
                    if let info = model.videoInfo {
                        Text("\(info.width)x\(info.height) • \(Formatters.duration(info.duration)) • \(info.videoCodec) • \(Formatters.bitrate(info.bitrate))")
                            .foregroundStyle(.secondary)
            } else {
                        Text("Import or drag a screen recording into the preview.")
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if model.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    model.chooseInput()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }
        }
    }
}

private struct VideoSettingsSection: View {
    @ObservedObject var model: AppModel
    var info: VideoInfo
    @State private var cropControlsExpanded = false

    var body: some View {
        SectionView(title: "Picture") {
            Toggle("Trim", isOn: $model.trim.enabled)

            if model.trim.enabled {
                HStack {
                    NumberField(title: "Start", value: $model.trim.start, range: 0...info.duration)
                        .onChange(of: model.trim.start) { _, newValue in
                            model.seek(to: newValue)
                        }
                    NumberField(title: "End", value: $model.trim.end, range: 0...info.duration)
                        .onChange(of: model.trim.end) { _, newValue in
                            model.seek(to: newValue)
                        }
                    Text(Formatters.duration(max(model.trim.end - model.trim.start, 0)))
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .trailing)
                }
            }

            Divider()

            Toggle("Crop", isOn: $model.crop.enabled)

            if model.crop.enabled {
                HStack {
                    ForEach(CropPreset.allCases) { preset in
                        Button(preset.rawValue) {
                            model.applyCropPreset(preset)
                        }
                    }
                }
                .buttonStyle(.bordered)

                DisclosureGroup("Coordinates", isExpanded: $cropControlsExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        CropControlRow(title: "X1", value: x1Binding, range: 0...max(x2 - 32, 0))
                        CropControlRow(title: "Y1", value: y1Binding, range: 0...max(y2 - 32, 0))
                        CropControlRow(title: "X2", value: x2Binding, range: min(info.width, model.crop.x + 32)...info.width)
                        CropControlRow(title: "Y2", value: y2Binding, range: min(info.height, model.crop.y + 32)...info.height)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private var x2: Int {
        model.crop.x + model.crop.width
    }

    private var y2: Int {
        model.crop.y + model.crop.height
    }

    private var x1Binding: Binding<Int> {
        Binding(
            get: { model.crop.x },
            set: { newValue in
                let newX = clamped(newValue, min: 0, max: max(x2 - 32, 0))
                model.crop.width = x2 - newX
                model.crop.x = newX
            }
        )
    }

    private var y1Binding: Binding<Int> {
        Binding(
            get: { model.crop.y },
            set: { newValue in
                let newY = clamped(newValue, min: 0, max: max(y2 - 32, 0))
                model.crop.height = y2 - newY
                model.crop.y = newY
            }
        )
    }

    private var x2Binding: Binding<Int> {
        Binding(
            get: { x2 },
            set: { newValue in
                let newX2 = clamped(newValue, min: min(info.width, model.crop.x + 32), max: info.width)
                model.crop.width = newX2 - model.crop.x
            }
        )
    }

    private var y2Binding: Binding<Int> {
        Binding(
            get: { y2 },
            set: { newValue in
                let newY2 = clamped(newValue, min: min(info.height, model.crop.y + 32), max: info.height)
                model.crop.height = newY2 - model.crop.y
            }
        )
    }

    private func clamped(_ value: Int, min lower: Int, max upper: Int) -> Int {
        Swift.min(Swift.max(value, lower), Swift.max(lower, upper))
    }
}

private struct AudioSection: View {
    @ObservedObject var model: AppModel
    var info: VideoInfo

    var body: some View {
        SectionView(title: "Audio") {
            if info.audioTracks.isEmpty {
                Text("No audio tracks found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(info.audioTracks) { track in
                    AudioTrackView(
                        track: track,
                        settings: Binding(
                            get: { model.audioSettings[track.index, default: AudioTrackSettings()] },
                            set: { model.audioSettings[track.index] = $0 }
                        )
                    )
                }
            }
        }
    }
}

private struct ExportSection: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var exporter: FFmpegExporter

    init(model: AppModel) {
        self.model = model
        self.exporter = model.exporter
    }

    var body: some View {
        SectionView(title: "Export") {
            Picker("Encoder", selection: $model.encoder) {
                ForEach(VideoEncoder.allCases) { encoder in
                    HStack {
                        Text(encoder.title)
                        if encoder.isHardwareAccelerated {
                            Text("Hardware")
                        }
                        if !model.availableEncoders.isEmpty, !model.availableEncoders.contains(encoder) {
                            Text("Unavailable")
                        }
                    }
                    .tag(encoder)
                }
            }

            TextField("Video bitrate (optional, e.g. 8M)", text: $model.bitrate)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text(model.outputURL?.path ?? "No output selected")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Choose Output") {
                    model.chooseOutput()
                }
            }

            ProgressView(value: exporter.progress.fraction)

            HStack {
                Text(exporter.progress.status)
                Spacer()
                Text(Formatters.duration(exporter.progress.currentSeconds))
                if !exporter.progress.speed.isEmpty {
                    Text(exporter.progress.speed)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button {
                    model.export()
                } label: {
                    Label("Export", systemImage: "play.fill")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canExport)

                if exporter.isExporting {
                    Button(role: .destructive) {
                        exporter.cancel()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                }
            }
        }
    }
}

private struct FfmpegLogSection: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var exporter: FFmpegExporter

    init(model: AppModel) {
        self.model = model
        self.exporter = model.exporter
    }

    var body: some View {
        SectionView(title: "Log") {
            ScrollView {
                Text(exporter.progress.logLines.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 260)
        }
    }
}

private struct WaveformSettingsSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionView(title: "Waveforms") {
                Toggle("Auto-generate waveforms", isOn: $model.autoGenerateWaveforms)

                Stepper(value: $model.autoGenerateWaveformsUnderMinutes, in: 1...60) {
                    HStack {
                        Text("Auto-generate for videos under")
                        Spacer()
                        Text("\(model.autoGenerateWaveformsUnderMinutes) min")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("Color")
                    TextField("FFFFFF", text: $model.waveformColorHex)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 90)
                }

                Button {
                    model.generateWaveforms(width: model.waveformRenderWidth)
                } label: {
                    Label("Generate Now", systemImage: "waveform")
                }
                .disabled(model.videoInfo?.audioTracks.isEmpty ?? true || model.isGeneratingWaveforms)
            }

            SectionView(title: "Export") {
                Toggle("Open destination folder after export", isOn: $model.openDestinationFolderAfterExport)
            }
        }
    }
}

private struct NumberField: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            TextField(title, value: $value, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .onChange(of: value) { _, newValue in
                    value = min(max(newValue, range.lowerBound), range.upperBound)
                }
        }
    }
}

private struct CropControlRow: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .leading)
                TextField(title, value: numericBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .frame(width: 96)
            }

            Slider(value: sliderBinding, in: Double(range.lowerBound)...Double(range.upperBound))
        }
    }

    private var numericBinding: Binding<Int> {
        Binding(
            get: { value },
            set: { value = clamped($0) }
        )
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { Double(value) },
            set: { value = clamped(Int($0.rounded())) }
        )
    }

    private func clamped(_ newValue: Int) -> Int {
        min(max(newValue, range.lowerBound), range.upperBound)
    }
}
