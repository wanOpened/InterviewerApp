import SwiftUI

struct MessageBoxView: View {
    let turns: [TranscriptTurn]
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(turns) { turn in
                        HStack {
                            if turn.speaker == .candidate { Spacer(minLength: 40) }
                            VStack(alignment: turn.speaker == .candidate ? .trailing : .leading) {
                                Text(turn.speaker == .candidate ? "我" : "面试官")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(turn.text)
                                    .padding(10)
                                    .background(turn.speaker == .candidate ? Color.blue.opacity(0.15)
                                                                           : Color.gray.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .opacity(turn.isFinal ? 1 : 0.6)
                            }
                            if turn.speaker == .interviewer { Spacer(minLength: 40) }
                        }.id(turn.id)
                    }
                }.padding()
            }
            .onChange(of: turns.count) { _, _ in
                if let last = turns.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }
}
