import SwiftUI

struct AudioTrackView: View {
    var track: AudioTrack
    @Binding var settings: AudioTrackSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle(isOn: $settings.isIncluded) {
                    Text("Track \(track.index + 1)")
                        .font(.headline)
                }

                Spacer()

                Button {
                    settings.volume = settings.volume == 0 ? 1 : 0
                    settings.isIncluded = true
                } label: {
                    Image(systemName: settings.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
                .help(settings.volume == 0 ? "Unmute track" : "Mute track")
            }

            HStack(spacing: 8) {
                Text(track.codec.uppercased())
                Text("\(track.channels) ch")
                Text(Formatters.sampleRate(track.sampleRate))
                if let language = track.language {
                    Text(language.uppercased())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Image(systemName: "speaker.wave.1")
                    .foregroundStyle(.secondary)
                Slider(value: $settings.volume, in: 0...2)
                    .disabled(!settings.isIncluded)
                Text("\(Int(settings.volume * 100))%")
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }
}
