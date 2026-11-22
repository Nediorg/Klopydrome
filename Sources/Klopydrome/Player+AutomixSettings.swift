import Foundation

extension Player {
    func configureReplayGain(mode: ReplayGainMode, preampDB: Float) {
        let safePreamp = AutomixLoudness.clampPreamp(preampDB)
        replayGainMode = mode
        replayGainPreampDB = safePreamp
        mpvEngine.replayGainMode = mode
        mpvEngine.replayGainPreampDB = safePreamp
        crossfadeEngine?.replayGainMode = mode
        crossfadeEngine?.replayGainPreampDB = safePreamp
    }

    func configureSilenceTrim(mode: SilenceTrimMode) {
        silenceTrimMode = mode
        mpvEngine.silenceTrimMode = mode
        crossfadeEngine?.silenceTrimMode = mode
    }

    #if DEBUG
    func setEngineKindForTesting(_ kind: EngineKind) {
        engineKind = kind
    }
    #endif
}
