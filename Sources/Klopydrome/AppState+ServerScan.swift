import AppKit
import Foundation
import NavidromeClient

extension AppState {
    @MainActor
    func confirmServerScan() -> Bool {
        if serverConfig.effectiveSuppressServerScanWarning {
            return true
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Scan Library?".localized
        alert.informativeText =
            "This process may take some time and will update content on the server. Continue?".localized
        alert.addButton(withTitle: "Refresh".localized)
        let cancel = alert.addButton(withTitle: "Cancel".localized)
        cancel.keyEquivalent = "\u{1b}"

        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Do not ask again".localized

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            serverConfig.suppressServerScanWarning = true
            saveSettings()
        }
        return response == .alertFirstButtonReturn
    }

    func checkServerScanStatus() async {
        guard let client, !isOfflineSession else { return }
        do {
            let status = try await client.getScanStatus()
            let wasScanning = isServerScanning
            isServerScanning = status.scanning
            if status.scanning {
                startScanStatusPolling()
            } else if wasScanning {
                handleScanCompleted()
            }
        } catch {
        }
    }

    func triggerServerScan() async {
        guard let client, !isOfflineSession else { return }
        guard confirmServerScan() else { return }
        do {
            let status = try await client.startScan()
            isServerScanning = status.scanning
            startScanStatusPolling()
        } catch {
            connectionError = error.localizedDescription
        }
    }

    private func handleScanCompleted() {
        library.invalidateForScan()
        Task {
            await refreshPlaylists()
        }
    }

    func startScanStatusPolling() {
        guard scanStatusPollingTask == nil else { return }
        scanStatusPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, !Task.isCancelled else { break }
                guard let client = self.client, !self.isOfflineSession else { break }
                do {
                    let status = try await client.getScanStatus()
                    self.isServerScanning = status.scanning
                    if !status.scanning {
                        self.scanStatusPollingTask = nil
                        self.handleScanCompleted()
                        break
                    }
                } catch {
                    self.scanStatusPollingTask = nil
                    break
                }
            }
        }
    }

    func stopScanStatusPolling() {
        scanStatusPollingTask?.cancel()
        scanStatusPollingTask = nil
        isServerScanning = false
    }
}
