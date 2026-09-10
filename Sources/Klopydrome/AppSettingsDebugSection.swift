import SwiftUI

struct DebugSettingsSection: View {
    @AppStorage("debugShowPlayerState") private var debugShowPlayerState = false

    var body: some View {
        Section("Отладка") {
            Toggle("Режим разработчика", isOn: $debugShowPlayerState)
        }
    }
}
