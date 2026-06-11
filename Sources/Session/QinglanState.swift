import Foundation

enum QinglanState: Equatable {
    case idle
    case connecting
    case attention
    case success
    case listening
    case thinking
    case speaking
    case waiting
    case error
}
