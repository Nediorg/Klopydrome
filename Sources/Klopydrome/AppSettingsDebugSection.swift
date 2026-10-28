import SwiftUI

struct DebugSettingsSection: View {
    @AppStorage("debugShowPlayerState") private var debugShowPlayerState = false

    var body: some View {
        Section("Debug".localized) {
            Toggle("Developer Mode".localized, isOn: $debugShowPlayerState)
        }
    }
}
