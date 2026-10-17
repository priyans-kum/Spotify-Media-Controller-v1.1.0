import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager {

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()

            if SMAppService.mainApp.status == .requiresApproval {
                throw LoginItemError.approvalRequired
            }
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum LoginItemError: LocalizedError {
    case approvalRequired

    var errorDescription: String? {
        switch self {
        case .approvalRequired:
            return """
            macOS requires approval. Open System Settings,
            General, Login Items, and enable Spotify Media Controller.
            """
        }
    }
}
