import AppKit
import CoreAudio
import Darwin
import MixerCore

/// HAL 오디오 프로세스 목록과 재생 상태를 감시해 앱 단위 묶음으로 알린다.
@MainActor
public final class ProcessMonitor {
    public var onChange: (([AppGroup]) -> Void)?
    public private(set) var groups: [AppGroup] = []

    private var listListener: HALListener?
    private var runningListeners: [AudioObjectID: HALListener] = [:]

    public init() {}

    public func start() {
        listListener = HALListener(object: HAL.system, selector: kAudioHardwarePropertyProcessObjectList) { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    public func refresh() {
        let objects = HAL.objects(HAL.system, kAudioHardwarePropertyProcessObjectList)
        updateRunningListeners(objects)
        let entries = objects.compactMap { object -> AudioProcessEntry? in
            guard let pid = HAL.scalar(object, kAudioProcessPropertyPID, as: pid_t.self) else { return nil }
            return AudioProcessEntry(
                objectID: object,
                pid: pid,
                bundleID: HAL.string(object, kAudioProcessPropertyBundleID),
                isPlaying: (HAL.scalar(object, kAudioProcessPropertyIsRunningOutput, as: UInt32.self) ?? 0) != 0)
        }
        let newGroups = AppGrouping.group(entries, ownPID: getpid(), app: Self.regularApp, parent: Self.parentPID)
        guard newGroups != groups else { return }
        groups = newGroups
        onChange?(newGroups)
    }

    private func updateRunningListeners(_ objects: [AudioObjectID]) {
        let current = Set(objects)
        for (object, listener) in runningListeners where !current.contains(object) {
            listener.remove()
            runningListeners[object] = nil
        }
        for object in current where runningListeners[object] == nil {
            runningListeners[object] = HALListener(object: object, selector: kAudioProcessPropertyIsRunningOutput) { [weak self] in
                self?.refresh()
            }
        }
    }

    private static func regularApp(_ pid: Int32) -> AppIdentity? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular,
              let bundleID = app.bundleIdentifier
        else { return nil }
        return AppIdentity(bundleID: bundleID, name: app.localizedName ?? bundleID)
    }

    /// XPC helper(WebKit.GPU 등)는 부모가 launchd라서 부모 체인으로는 앱에 닿지 않는다.
    /// 공개 API가 없어 비공개 libsystem 심볼을 쓰고, 없으면 부모 pid로 대신한다.
    private static let responsiblePID: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    private static func parentPID(_ pid: Int32) -> Int32? {
        if let responsible = responsiblePID?(pid), responsible > 1, responsible != pid {
            return responsible
        }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Int32(info.pbi_ppid)
    }
}
