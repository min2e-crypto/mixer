import Testing
@testable import MixerCore

@Suite struct EnginePolicyTests {
    @Test func 볼륨_100퍼센트면_엔진이_없다() {
        #expect(!EnginePolicy.needsEngine(bundleID: "com.apple.Music", state: AppVolumeState(volume: 1, muted: false)))
    }

    @Test func 볼륨을_줄이거나_음소거하면_엔진이_필요하다() {
        #expect(EnginePolicy.needsEngine(bundleID: "com.apple.Music", state: AppVolumeState(volume: 0.5, muted: false)))
        #expect(EnginePolicy.needsEngine(bundleID: "com.apple.Music", state: AppVolumeState(volume: 1, muted: true)))
    }

    @Test(arguments: ["com.apple.logic10", "com.ableton.live", "us.zoom.xos", "com.hnc.Discord", "com.microsoft.teams2"])
    func 제외_목록_앱은_엔진이_없다(bundleID: String) {
        #expect(EnginePolicy.isExcluded(bundleID))
        #expect(!EnginePolicy.needsEngine(bundleID: bundleID, state: AppVolumeState(volume: 0.2, muted: false)))
    }
}
