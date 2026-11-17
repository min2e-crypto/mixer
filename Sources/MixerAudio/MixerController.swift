import Combine
import CoreAudio
import Foundation
import MixerCore

public struct MixerApp: Identifiable, Equatable, Sendable {
    public var id: String { identity.bundleID }
    public let identity: AppIdentity
    public let pid: Int32
    public let isPlaying: Bool
    public let state: AppVolumeState
    public let isExcluded: Bool
    public let isApp: Bool
}

/// 앱별 볼륨 상태와 엔진을 맞춘다. 메뉴바 패널과 노치 패널이 함께 관찰한다.
@MainActor
public final class MixerController: ObservableObject {
    @Published public private(set) var apps: [MixerApp] = []
    @Published public private(set) var needsPermission = false

    private let monitor = ProcessMonitor()
    private let store: VolumeStore
    private var engines: [String: TapEngine] = [:]
    private var failures: [String: Int] = [:]
    private var outputListener: HALListener?
    private var started = false

    public init(store: VolumeStore = VolumeStore()) {
        self.store = store
    }

    public func start() {
        guard !started else { return }
        started = true
        monitor.onChange = { [weak self] _ in self?.reconcile() }
        outputListener = HALListener(object: HAL.system, selector: kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            log.info("기본 출력 장치 변경 → 엔진 재생성")
            self?.reconcile()
        }
        monitor.start()
        reconcile()
    }

    public func stop() {
        outputListener?.remove()
        outputListener = nil
        engines.values.forEach { $0.stop() }
        engines.removeAll()
    }

    public func setVolume(_ volume: Float, for bundleID: String) {
        var state = store.state(for: bundleID) ?? .default
        state.volume = GainCurve.volume(fromSlider: volume)
        update(state, for: bundleID)
    }

    public func toggleMute(_ bundleID: String) {
        var state = store.state(for: bundleID) ?? .default
        state.muted.toggle()
        update(state, for: bundleID)
    }

    private func update(_ state: AppVolumeState, for bundleID: String) {
        store.set(state, for: bundleID)
        reconcile()
    }

    private func reconcile() {
        let groups = monitor.groups
        let outputUID = HAL.defaultOutputDevice().flatMap { HAL.string($0, kAudioDevicePropertyDeviceUID) }

        for (bundleID, engine) in engines where !groups.contains(where: { $0.identity.bundleID == bundleID }) {
            engine.stop()
            engines[bundleID] = nil
        }

        for group in groups {
            let bundleID = group.identity.bundleID
            let state = store.state(for: bundleID) ?? .default
            guard EnginePolicy.needsEngine(bundleID: bundleID, state: state), let outputUID else {
                if let engine = engines.removeValue(forKey: bundleID) {
                    engine.stop()
                    log.info("엔진 해제 \(bundleID, privacy: .public)")
                }
                continue
            }
            if let engine = engines[bundleID], engine.processObjects == group.processObjects, engine.outputDeviceUID == outputUID {
                engine.setGain(state.gain)
                continue
            }
            engines.removeValue(forKey: bundleID)?.stop()
            do {
                engines[bundleID] = try TapEngine(processObjects: group.processObjects, outputDeviceUID: outputUID, gain: state.gain)
                failures[bundleID] = nil
            } catch {
                let count = (failures[bundleID] ?? 0) + 1
                failures[bundleID] = count
                log.error("엔진 생성 실패 \(bundleID, privacy: .public) \(count)회: \(String(describing: error), privacy: .public)")
                // 실패 원인이 권한인지 일시적인 포맷 변경인지 구분할 수 없어 한 번만 다시 시도한다.
                if count == 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        MainActor.assumeIsolated { self?.reconcile() }
                    }
                }
            }
        }

        let failedBundleIDs = Set(failures.filter { $0.value >= 2 }.keys)
        needsPermission = !failedBundleIDs.isEmpty && engines.isEmpty
        apps = groups
            .filter { $0.isApp || $0.isPlaying }
            .map { group in
                let bundleID = group.identity.bundleID
                return MixerApp(
                    identity: group.identity,
                    pid: group.pid,
                    isPlaying: group.isPlaying,
                    state: store.state(for: bundleID) ?? .default,
                    isExcluded: EnginePolicy.isExcluded(bundleID),
                    isApp: group.isApp)
            }
            .sorted { $0.identity.name.localizedCaseInsensitiveCompare($1.identity.name) == .orderedAscending }
    }
}
