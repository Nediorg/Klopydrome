import Foundation
import NavidromeClient

extension AppState {
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
