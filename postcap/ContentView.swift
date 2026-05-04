//
//  ContentView.swift
//  postcap
//
//  Created by ahmet on 03/05/2026.
//

import AVKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var selectedTab = InspectorTab.edit

    var body: some View {
        NavigationSplitView {
            EditorView(model: model, selectedTab: $selectedTab)
                .navigationSplitViewColumnWidth(min: 360, ideal: 430, max: 560)
                .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        } detail: {
            WorkspaceView(model: model)
        }
        .alert("Export Complete", isPresented: Binding(
            get: { model.exportCompletionMessage != nil },
            set: { if !$0 { model.exportCompletionMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.exportCompletionMessage ?? "")
        }
        .navigationTitle("Postcap")
        .frame(minWidth: 1120, minHeight: 760)
    }
}

private struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    @State private var isTargeted = false

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                ZStack {
                    if let player = model.player, let info = model.videoInfo {
                        PlayerSurfaceView(player: player)
                            .background(.black)
                            .overlay {
                                CropInteractiveOverlay(crop: $model.crop, videoSize: CGSize(width: info.width, height: info.height))
                                    .opacity(model.crop.enabled ? 1 : 0)
                            }
                            .overlay(alignment: .bottomLeading) {
                                Text("\(info.width)x\(info.height) • \(Formatters.duration(info.duration))")
                                    .font(.caption)
                                    .padding(8)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                                    .padding()
                            }
                    } else {
                        ContentUnavailableView(
                            "Drop Video",
                            systemImage: "film",
                            description: Text("Import a screen recording to trim, crop, clean up, and export.")
                        )
                    }

                    if isTargeted {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.tint, lineWidth: 3)
                            .padding(18)
                            .background(.tint.opacity(0.08))
                    }
                }
                .frame(minHeight: 220)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                PlaybackControlsView(model: model)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.bar)
            }
            .frame(minHeight: 260)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [UTType.fileURL.identifier, UTType.movie.identifier, UTType.video.identifier], isTargeted: $isTargeted) { providers in
                model.handleDroppedProviders(providers)
            }
            .overlay {
                FileDropView(isTargeted: $isTargeted) { url in
                    Task { await model.importVideo(url) }
                }
            }

            TimelineWaveformsView(model: model)
                .frame(minHeight: 120, idealHeight: model.videoInfo?.audioTracks.isEmpty == false ? 220 : 140, maxHeight: 360)
                .background(.regularMaterial)
        }
    }
}

private struct FileDropView: NSViewRepresentable {
    @Binding var isTargeted: Bool
    var onDrop: (URL) -> Void

    func makeNSView(context: Context) -> FileDropNSView {
        let view = FileDropNSView()
        view.onTargetChange = { targeted in
            DispatchQueue.main.async {
                isTargeted = targeted
            }
        }
        view.onDrop = onDrop
        return view
    }

    func updateNSView(_ nsView: FileDropNSView, context: Context) {
        nsView.onTargetChange = { targeted in
            DispatchQueue.main.async {
                isTargeted = targeted
            }
        }
        nsView.onDrop = onDrop
    }
}

private final class FileDropNSView: NSView {
    var onTargetChange: ((Bool) -> Void)?
    var onDrop: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL, .init(NSPasteboard.PasteboardType.string.rawValue)])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard firstVideoURL(from: sender.draggingPasteboard) != nil else {
            return []
        }
        onTargetChange?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        firstVideoURL(from: sender.draggingPasteboard) == nil ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetChange?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        firstVideoURL(from: sender.draggingPasteboard) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { onTargetChange?(false) }
        guard let url = firstVideoURL(from: sender.draggingPasteboard) else {
            return false
        }
        onDrop?(url)
        return true
    }

    private func firstVideoURL(from pasteboard: NSPasteboard) -> URL? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first(where: isSupportedVideoURL) {
            return url
        }

        if let path = pasteboard.string(forType: .fileURL),
           let url = URL(string: path),
           isSupportedVideoURL(url) {
            return url
        }

        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let paths = pasteboard.propertyList(forType: filenamesType) as? [String] {
            for path in paths {
                let url = URL(fileURLWithPath: path)
                if isSupportedVideoURL(url) {
                    return url
                }
            }
        }

        return nil
    }

    private func isSupportedVideoURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let supportedExtensions = ["mov", "mp4", "m4v", "mkv", "webm", "avi"]
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }
}

private struct PlayerSurfaceView: NSViewRepresentable {
    var player: AVPlayer

    func makeNSView(context: Context) -> PlayerSurfaceNSView {
        let view = PlayerSurfaceNSView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerSurfaceNSView, context: Context) {
        nsView.playerLayer.player = player
    }
}

private final class PlayerSurfaceNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

private struct PlaybackControlsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            Button {
                model.skipPlayback(by: -10)
            } label: {
                Image(systemName: "gobackward.10")
            }
            .help("Back 10 seconds")
            .disabled(model.player == nil)

            Button {
                model.togglePlayback()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 16)
            }
            .keyboardShortcut(.space, modifiers: [])
            .help(model.isPlaying ? "Pause" : "Play")
            .disabled(model.player == nil)

            Button {
                model.skipPlayback(by: 10)
            } label: {
                Image(systemName: "goforward.10")
            }
            .help("Forward 10 seconds")
            .disabled(model.player == nil)

            Text(Formatters.duration(model.playbackSeconds))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { model.playbackSeconds },
                    set: { model.seek(to: $0) }
                ),
                in: 0...max(model.videoInfo?.duration ?? 0, 0.01)
            )
            .disabled(model.player == nil)

            Text(Formatters.duration(model.videoInfo?.duration ?? 0))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
        }
        .buttonStyle(.borderless)
        .controlSize(.large)
    }
}

private struct CropInteractiveOverlay: View {
    @Binding var crop: CropSettings
    var videoSize: CGSize
    @State private var startingCrop: CropSettings?
    @State private var activeInteraction: CropInteraction?

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / videoSize.width, proxy.size.height / videoSize.height)
            let renderedSize = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
            let origin = CGPoint(x: (proxy.size.width - renderedSize.width) / 2, y: (proxy.size.height - renderedSize.height) / 2)
            let rect = CGRect(
                x: origin.x + CGFloat(crop.x) * scale,
                y: origin.y + CGFloat(crop.y) * scale,
                width: CGFloat(crop.width) * scale,
                height: CGFloat(crop.height) * scale
            )

            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.35))
                    .mask {
                        Rectangle()
                            .overlay(alignment: .topLeading) {
                                Rectangle()
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                                    .blendMode(.destinationOut)
                            }
                    }
                    .allowsHitTesting(false)

                Rectangle()
                    .stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)

                ForEach(CropResizeHandle.allCases) { handle in
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .shadow(radius: 2)
                        .position(handle.point(in: rect))
                        .help(handle.help)
                        .allowsHitTesting(false)
                }

                Rectangle()
                    .fill(.clear)
                    .frame(width: renderedSize.width, height: renderedSize.height)
                    .position(x: origin.x + renderedSize.width / 2, y: origin.y + renderedSize.height / 2)
                    .contentShape(Rectangle())
                    .gesture(cropGesture(rect: rect, scale: scale))
            }
        }
    }

    private func cropGesture(rect: CGRect, scale: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = startingCrop ?? crop
                startingCrop = start
                let interaction = activeInteraction ?? interaction(at: value.startLocation, in: rect)
                activeInteraction = interaction

                let dx = Int((value.translation.width / scale).rounded())
                let dy = Int((value.translation.height / scale).rounded())

                switch interaction {
                case .move:
                    moveCrop(from: start, dx: dx, dy: dy)
                case .resize(let handle):
                    resizeCrop(from: start, handle: handle, dx: dx, dy: dy)
                case .none:
                    break
                }
            }
            .onEnded { _ in
                startingCrop = nil
                activeInteraction = nil
            }
    }

    private func interaction(at point: CGPoint, in rect: CGRect) -> CropInteraction? {
        let handleHitRadius = 24.0

        for handle in CropResizeHandle.allCases {
            let handlePoint = handle.point(in: rect)
            if hypot(point.x - handlePoint.x, point.y - handlePoint.y) <= handleHitRadius {
                return .resize(handle)
            }
        }

        return rect.contains(point) ? .move : nil
    }

    private func moveCrop(from start: CropSettings, dx: Int, dy: Int) {
        crop.x = clamped(start.x + dx, min: 0, max: Int(videoSize.width) - start.width)
        crop.y = clamped(start.y + dy, min: 0, max: Int(videoSize.height) - start.height)
    }

    private func resizeCrop(from start: CropSettings, handle: CropResizeHandle, dx: Int, dy: Int) {
        let minSize = 32
        let maxVideoWidth = Int(videoSize.width)
        let maxVideoHeight = Int(videoSize.height)

        switch handle {
        case .topLeft:
            let newX = clamped(start.x + dx, min: 0, max: start.x + start.width - minSize)
            let newY = clamped(start.y + dy, min: 0, max: start.y + start.height - minSize)
            crop.x = newX
            crop.y = newY
            crop.width = start.width + (start.x - newX)
            crop.height = start.height + (start.y - newY)
        case .topRight:
            let newY = clamped(start.y + dy, min: 0, max: start.y + start.height - minSize)
            crop.y = newY
            crop.width = clamped(start.width + dx, min: minSize, max: maxVideoWidth - start.x)
            crop.height = start.height + (start.y - newY)
        case .bottomLeft:
            let newX = clamped(start.x + dx, min: 0, max: start.x + start.width - minSize)
            crop.x = newX
            crop.width = start.width + (start.x - newX)
            crop.height = clamped(start.height + dy, min: minSize, max: maxVideoHeight - start.y)
        case .bottomRight:
            crop.width = clamped(start.width + dx, min: minSize, max: maxVideoWidth - start.x)
            crop.height = clamped(start.height + dy, min: minSize, max: maxVideoHeight - start.y)
        }
    }

    private func clamped(_ value: Int, min lower: Int, max upper: Int) -> Int {
        Swift.min(Swift.max(value, lower), Swift.max(lower, upper))
    }
}

private enum CropInteraction: Equatable {
    case move
    case resize(CropResizeHandle)
}

private enum CropResizeHandle: CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: Self { self }

    var help: String {
        switch self {
        case .topLeft: "Resize from top left"
        case .topRight: "Resize from top right"
        case .bottomLeft: "Resize from bottom left"
        case .bottomRight: "Resize from bottom right"
        }
    }

    func point(in rect: CGRect, inset: CGFloat = 0) -> CGPoint {
        switch self {
        case .topLeft:
            CGPoint(x: rect.minX + inset, y: rect.minY + inset)
        case .topRight:
            CGPoint(x: rect.maxX - inset, y: rect.minY + inset)
        case .bottomLeft:
            CGPoint(x: rect.minX + inset, y: rect.maxY - inset)
        case .bottomRight:
            CGPoint(x: rect.maxX - inset, y: rect.maxY - inset)
        }
    }
}

private struct TimelineWaveformsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Timeline")
                    .font(.headline)
                Spacer()
                if model.isGeneratingWaveforms {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let info = model.videoInfo, !info.audioTracks.isEmpty {
                GeometryReader { proxy in
                    let labelWidth = 34.0
                    let rowSpacing = 10.0
                    let waveformWidth = max(proxy.size.width - labelWidth - rowSpacing, 320)

                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 8) {
                            TimelineTrimRuler(model: model, duration: info.duration)
                                .padding(.leading, labelWidth + rowSpacing)

                            ForEach(info.audioTracks) { track in
                                HStack(spacing: rowSpacing) {
                                    Text("A\(track.index + 1)")
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .frame(width: labelWidth, alignment: .trailing)

                                    if let waveform = model.waveforms[track.index] {
                                        AsyncImage(url: waveform.imageURL) { image in
                                            image
                                                .resizable(resizingMode: .stretch)
                                                .interpolation(.medium)
                                        } placeholder: {
                                            Rectangle().fill(.quaternary)
                                        }
                                        .frame(width: waveformWidth, height: 34)
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                    } else {
                                        Rectangle()
                                            .fill(.quaternary)
                                            .frame(width: waveformWidth, height: 34)
                                            .clipShape(RoundedRectangle(cornerRadius: 5))
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onAppear {
                        model.updateTimelineWaveformWidth(waveformWidth)
                        model.generateWaveformsIfNeeded()
                    }
                    .onChange(of: waveformWidth) { _, newWidth in
                        model.updateTimelineWaveformWidth(newWidth)
                        model.generateWaveformsIfNeeded()
                    }
                }
            } else {
                Text("Import a video to see audio waveforms.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TimelineTrimRuler: View {
    @ObservedObject var model: AppModel
    var duration: Double

    var body: some View {
        GeometryReader { proxy in
            let startX = xPosition(for: model.trim.start, width: proxy.size.width)
            let endX = xPosition(for: model.trim.end > 0 ? model.trim.end : duration, width: proxy.size.width)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.secondary.opacity(0.16))
                    .frame(height: 18)

                if model.trim.enabled {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.tint.opacity(0.25))
                        .frame(width: max(endX - startX, 2), height: 18)
                        .offset(x: startX)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.seek(to: model.trim.start)
                        }

                    TrimHandle(label: "Start")
                        .position(x: startX, y: 9)
                        .onTapGesture {
                            model.seek(to: model.trim.start)
                        }
                        .gesture(DragGesture().onChanged { value in
                            model.trim.start = clampedSeconds(value.location.x / proxy.size.width * duration, max: max(model.trim.end - 0.1, 0))
                            model.seek(to: model.trim.start)
                        })

                    TrimHandle(label: "End")
                        .position(x: endX, y: 9)
                        .onTapGesture {
                            model.seek(to: model.trim.end)
                        }
                        .gesture(DragGesture().onChanged { value in
                            model.trim.end = clampedSeconds(value.location.x / proxy.size.width * duration, min: min(model.trim.start + 0.1, duration), max: duration)
                            model.seek(to: model.trim.end)
                        })
                }
            }
        }
        .frame(height: 24)
    }

    private func xPosition(for seconds: Double, width: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(seconds / duration, 0), 1) * width
    }

    private func clampedSeconds(_ seconds: Double, min lower: Double = 0, max upper: Double) -> Double {
        min(max(seconds, lower), upper)
    }
}

private struct TrimHandle: View {
    var label: String

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.tint)
                .frame(width: 3, height: 18)
            Text(label.prefix(1))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 24, height: 32)
        .contentShape(Rectangle())
        .help(label)
    }
}
