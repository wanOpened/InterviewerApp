import Foundation

enum Speaker: Equatable { case candidate, interviewer }

struct TranscriptTurn: Identifiable, Equatable {
    let id: String          // segmentId
    let speaker: Speaker
    var text: String
    var isFinal: Bool
}
