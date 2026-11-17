import Combine
import Foundation
import MixerAudio
import MixerCore

setvbuf(stdout, nil, _IOLBF, 0)

let arguments = Array(CommandLine.arguments.dropFirst())
guard !arguments.isEmpty else {
    print("""
    사용법:
      tapspike list                         오디오 프로세스를 앱 단위로 보여 준다
      tapspike <번들ID>=<0~1> [...]          볼륨을 적용하고 Enter·SIGINT·SIGTERM에 100%로 되돌린 뒤 종료
    """)
    exit(2)
}

// 앱의 저장값을 건드리지 않도록 별도 도메인을 쓴다.
let suite = "local.mixer.tapspike.volumes"
UserDefaults.standard.removePersistentDomain(forName: suite)
let controller = MixerController(store: VolumeStore(defaults: UserDefaults(suiteName: suite)!))

func describe(_ apps: [MixerApp]) -> String {
    apps.map { app in
        "  \(app.identity.bundleID) pid=\(app.pid) \(app.isPlaying ? "재생중" : "대기") volume=\(app.state.volume) muted=\(app.state.muted)\(app.isExcluded ? " (제외)" : "")"
    }.joined(separator: "\n")
}

if arguments == ["list"] {
    controller.start()
    print(describe(controller.apps))
    exit(0)
}

let requests = arguments.compactMap { argument -> (String, Float)? in
    let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
    guard parts.count == 2, let volume = Float(parts[1]) else {
        print("무시: \(argument)")
        return nil
    }
    return (parts[0], volume)
}

let subscription = controller.$apps.sink { apps in print("앱 목록:\n\(describe(apps))") }
let permission = controller.$needsPermission.sink { if $0 { print("권한 필요 상태") } }
controller.start()
for (bundleID, volume) in requests {
    controller.setVolume(volume, for: bundleID)
    print("적용: \(bundleID) → \(volume)")
}

@MainActor func finish() -> Never {
    print("100%로 되돌림")
    for (bundleID, _) in requests { controller.setVolume(1, for: bundleID) }
    controller.stop()
    UserDefaults.standard.removePersistentDomain(forName: suite)
    // 백그라운드 해제가 끝나도록 잠깐 기다린다.
    Thread.sleep(forTimeInterval: 0.5)
    print("종료")
    exit(0)
}

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let signalSources = [SIGINT, SIGTERM].map { number in
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler { MainActor.assumeIsolated { finish() } }
    source.resume()
    return source
}
Thread.detachNewThread {
    // `open`으로 띄우면 stdin이 비어 있어 readLine이 바로 nil을 돌려주므로 그때는 신호만 기다린다.
    if readLine() != nil { DispatchQueue.main.async { MainActor.assumeIsolated { finish() } } }
}
RunLoop.main.run()
