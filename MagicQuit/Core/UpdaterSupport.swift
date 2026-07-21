import Foundation
import Sparkle

/// Silent background updates via Sparkle. Inactive until SUPublicEDKey holds a
/// real key (see RELEASING.md), so development builds never phone home.
enum UpdaterSupport {
    static let controller: SPUStandardUpdaterController? = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty else {
            return nil
        }
        return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }()
}
