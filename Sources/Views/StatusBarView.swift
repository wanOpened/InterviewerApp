import SwiftUI

struct StatusBarView: View {
    let phaseText: String
    let connected: Bool
    let liveStartedAt: Date?     // nil until live; drives the elapsed timer
    var body: some View {
        HStack {
            Circle().fill(connected ? .green : .orange).frame(width: 10, height: 10)
            Text(phaseText).font(.footnote).foregroundStyle(.secondary)
            Spacer()
            if let start = liveStartedAt {
                TimelineView(.periodic(from: start, by: 1)) { ctx in
                    let secs = Int(ctx.date.timeIntervalSince(start))
                    Text(String(format: "%02d:%02d", secs / 60, secs % 60))
                        .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }.padding(.horizontal)
    }
}
