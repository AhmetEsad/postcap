import SwiftUI

struct BinarySettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SectionView(title: "FFmpeg") {
            BinaryPathRow(
                title: "ffmpeg",
                path: model.pathsStore.ffmpegPath,
                isValid: FileManager.default.isExecutableFile(atPath: model.pathsStore.ffmpegPath),
                action: { model.chooseBinary(kind: .ffmpeg) }
            )

            BinaryPathRow(
                title: "ffprobe",
                path: model.pathsStore.ffprobePath,
                isValid: FileManager.default.isExecutableFile(atPath: model.pathsStore.ffprobePath),
                action: { model.chooseBinary(kind: .ffprobe) }
            )
        }
    }
}

private struct BinaryPathRow: View {
    var title: String
    var path: String
    var isValid: Bool
    var action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isValid ? .green : .orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(path.isEmpty ? "Not selected" : path)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button("Choose", action: action)
        }
    }
}
