import AppKit
import Foundation
import NavidromeClient

extension AppState {
    /// Confirms before initiating a media library scan on the server.
    @MainActor
    func confirmServerScan() -> Bool {
        if serverConfig.effectiveSuppressServerScanWarning {
            return true
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Обновить медиатеку?".localized
        // swiftlint:disable:next line_length
        alert.informativeText = "Этот процесс займёт некоторое время и обновит контент на сервере. Продолжить?".localized
        alert.addButton(withTitle: "Обновить".localized)
        let cancel = alert.addButton(withTitle: "Отмена".localized)
        cancel.keyEquivalent = "\u{1b}"

        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Больше не спрашивать".localized

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            serverConfig.suppressServerScanWarning = true
            saveSettings()
        }
        return response == .alertFirstButtonReturn
    }

    /// Polls or checks whether the Navidrome server is currently scanning its media folders.
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
            // Server may not support getScanStatus or is temporarily unreachable
        }
    }

    /// Triggers a media library scan on the Navidrome server (File > Scan Library).
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
