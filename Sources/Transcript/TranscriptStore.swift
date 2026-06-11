import Foundation

/// Merges LiveKit transcription segments into ordered conversation turns.
/// Not thread-safe by itself; the owner marshals calls onto the main actor.
final class TranscriptStore {
    private(set) var turns: [TranscriptTurn] = []
    private var indexBySegment: [String: Int] = [:]
    private let localIdentity: String

    init(localIdentity: String) { self.localIdentity = localIdentity }

    func ingest(segmentId: String, senderIdentity: String, text: String, isFinal: Bool) {
        let speaker: Speaker = (senderIdentity == localIdentity) ? .candidate : .interviewer
        if let idx = indexBySegment[segmentId] {
            turns[idx].text = text
            turns[idx].isFinal = isFinal
        } else {
            indexBySegment[segmentId] = turns.count
            turns.append(TranscriptTurn(id: segmentId, speaker: speaker, text: text, isFinal: isFinal))
        }
    }

    func reset() { turns.removeAll(); indexBySegment.removeAll() }
}
