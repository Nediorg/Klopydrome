import SwiftUI

struct DebugSettingsSection: View {
    @AppStorage("debugShowPlayerState") private var debugShowPlayerState = false

    var body: some View {
        Section("Отладка".localized) {
            Toggle("Режим разработчика".localized, isOn: $debugShowPlayerState)
        }
    }
}
