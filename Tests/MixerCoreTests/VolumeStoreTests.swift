import Foundation
import Testing
@testable import MixerCore

private func makeDefaults() -> UserDefaults {
    let name = "mixer-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Suite struct VolumeStoreTests {
    @Test func 저장한_값을_복원한다() {
        let defaults = makeDefaults()
        VolumeStore(defaults: defaults).set(AppVolumeState(volume: 0.4, muted: true), for: "com.apple.Music")
        #expect(VolumeStore(defaults: defaults).state(for: "com.apple.Music") == AppVolumeState(volume: 0.4, muted: true))
    }

    @Test func 없는_앱은_nil이다() {
        #expect(VolumeStore(defaults: makeDefaults()).state(for: "com.apple.Music") == nil)
    }

    @Test func 기본_상태로_되돌리면_기록을_지운다() {
        let defaults = makeDefaults()
        let store = VolumeStore(defaults: defaults)
        store.set(AppVolumeState(volume: 0.4, muted: false), for: "com.apple.Music")
        store.set(.default, for: "com.apple.Music")
        #expect(store.state(for: "com.apple.Music") == nil)
        #expect((defaults.dictionary(forKey: VolumeStore.key) ?? [:]).isEmpty)
    }

    @Test func 손상된_값은_무시한다() {
        let defaults = makeDefaults()
        defaults.set([
            "a": "문자열",
            "b": ["volume": "0.5", "muted": false],
            "c": ["volume": Double.nan, "muted": false],
            "d": ["volume": 5.0, "muted": false],
            "e": ["volume": 0.3],
            "ok": ["volume": 0.3, "muted": false],
        ], forKey: VolumeStore.key)
        let store = VolumeStore(defaults: defaults)
        for id in ["a", "b", "c", "d", "e"] { #expect(store.state(for: id) == nil) }
        #expect(store.state(for: "ok") == AppVolumeState(volume: 0.3, muted: false))
    }

    @Test func 저장소_자체가_손상돼도_새로_쓸_수_있다() {
        let defaults = makeDefaults()
        defaults.set("깨짐", forKey: VolumeStore.key)
        let store = VolumeStore(defaults: defaults)
        #expect(store.state(for: "x") == nil)
        store.set(AppVolumeState(volume: 0.5, muted: false), for: "x")
        #expect(store.state(for: "x") == AppVolumeState(volume: 0.5, muted: false))
    }
}
