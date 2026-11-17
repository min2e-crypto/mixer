import Testing
@testable import MixerCore

private let apps: [Int32: AppIdentity] = [
    100: AppIdentity(bundleID: "com.apple.Safari", name: "Safari"),
    200: AppIdentity(bundleID: "com.apple.Music", name: "Music"),
]
private let parents: [Int32: Int32] = [101: 100, 102: 101, 300: 1]

private func group(_ entries: [AudioProcessEntry], ownPID: Int32 = 999) -> [AppGroup] {
    AppGrouping.group(entries, ownPID: ownPID, app: { apps[$0] }, parent: { parents[$0] })
}

@Suite struct AppGroupingTests {
    @Test func 헬퍼_프로세스는_부모_체인으로_앱에_묶인다() {
        let result = group([
            AudioProcessEntry(objectID: 1, pid: 102, bundleID: "com.apple.WebKit.GPU", isPlaying: true),
            AudioProcessEntry(objectID: 2, pid: 100, bundleID: "com.apple.Safari", isPlaying: false),
        ])
        #expect(result == [AppGroup(identity: apps[100]!, pid: 100, processObjects: [1, 2], isPlaying: true, isApp: true)])
    }

    @Test func 앱마다_따로_묶는다() {
        let result = group([
            AudioProcessEntry(objectID: 1, pid: 100, bundleID: nil, isPlaying: false),
            AudioProcessEntry(objectID: 2, pid: 200, bundleID: nil, isPlaying: true),
        ])
        #expect(result.map(\.identity.bundleID) == ["com.apple.Safari", "com.apple.Music"])
        #expect(result.map(\.isPlaying) == [false, true])
    }

    @Test func 자기_자신은_제외한다() {
        let result = group([AudioProcessEntry(objectID: 1, pid: 100, bundleID: nil, isPlaying: true)], ownPID: 100)
        #expect(result.isEmpty)
    }

    @Test func 앱이_없으면_프로세스_번들_ID로_묶는다() {
        let result = group([AudioProcessEntry(objectID: 5, pid: 300, bundleID: "com.example.daemon", isPlaying: true)])
        #expect(result == [AppGroup(identity: AppIdentity(bundleID: "com.example.daemon", name: "com.example.daemon"), pid: 300, processObjects: [5], isPlaying: true, isApp: false)])
    }

    @Test func 앱도_번들_ID도_없으면_제외한다() {
        let result = group([AudioProcessEntry(objectID: 5, pid: 300, bundleID: nil, isPlaying: true)])
        #expect(result.isEmpty)
    }

    @Test func 부모_체인이_순환해도_끝난다() {
        let result = AppGrouping.group(
            [AudioProcessEntry(objectID: 1, pid: 10, bundleID: nil, isPlaying: true)],
            ownPID: 999, app: { _ in nil }, parent: { $0 == 10 ? 11 : 10 })
        #expect(result.isEmpty)
    }
}
