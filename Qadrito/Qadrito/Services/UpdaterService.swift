import Foundation
import Sparkle

@MainActor
final class UpdaterService: NSObject, ObservableObject {
    static let shared = UpdaterService()
    
    private let updaterController: SPUStandardUpdaterController
    
    @Published private(set) var canCheckForUpdates = false
    
    private override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
        
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
    
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
