import SwiftUI

// NOTE (deferred polish): a fine-grained agent "listening / speaking / thinking"
// indicator is NOT in v1 — it needs LiveKit audio-activity wiring. The phase
// text + the live caption updates already signal who's talking. Add it in a
// later pass if dogfooding shows it's needed.

struct MicIndicatorView: View {
    let active: Bool
    var body: some View {
        Label(active ? "麦克风开启" : "麦克风关闭",
              systemImage: active ? "mic.fill" : "mic.slash")
            .font(.footnote).foregroundStyle(active ? .green : .secondary)
    }
}
