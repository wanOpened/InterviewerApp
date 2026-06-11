import AVFoundation
import UIKit

enum MicrophonePermissionStatus: Equatable {
    case allowed
    case denied
    case undetermined

    var isAllowed: Bool {
        self == .allowed
    }

    var actionLabel: String {
        isAllowed ? "已允许" : "去允许"
    }

    var settingsLabel: String {
        switch self {
        case .allowed:
            return "已允许"
        case .denied:
            return "未允许"
        case .undetermined:
            return "未询问"
        }
    }
}

protocol MicrophonePermissionProviding: AnyObject {
    var status: MicrophonePermissionStatus { get }
    func openSettings()
}

final class SystemMicrophonePermissionProvider: MicrophonePermissionProviding {
    var status: MicrophonePermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .allowed
        case .denied:
            return .denied
        case .undetermined:
            return .undetermined
        @unknown default:
            return .undetermined
        }
    }

    func openSettings() {
        Task { @MainActor in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        }
    }
}
