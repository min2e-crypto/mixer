import Foundation

public struct AppVolumeState: Equatable, Sendable {
    public var volume: Float
    public var muted: Bool

    public static let `default` = AppVolumeState(volume: 1, muted: false)

    public init(volume: Float, muted: Bool) {
        self.volume = volume
        self.muted = muted
    }

    public var gain: Float { muted ? 0 : GainCurve.gain(forVolume: volume) }
}

/// 번들 ID → 볼륨 상태를 UserDefaults에 저장한다. 기본 상태는 저장하지 않는다.
public final class VolumeStore {
    public static let key = "appVolumes"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func state(for bundleID: String) -> AppVolumeState? {
        guard let entry = all()[bundleID] as? [String: Any],
              let volume = entry["volume"] as? Double,
              let muted = entry["muted"] as? Bool,
              volume.isFinite, (0...Double(GainCurve.maxVolume)).contains(volume)
        else { return nil }
        return AppVolumeState(volume: Float(volume), muted: muted)
    }

    public func set(_ state: AppVolumeState, for bundleID: String) {
        var entries = all()
        if state == .default {
            entries.removeValue(forKey: bundleID)
        } else {
            entries[bundleID] = ["volume": Double(state.volume), "muted": state.muted]
        }
        defaults.set(entries, forKey: Self.key)
    }

    private func all() -> [String: Any] {
        defaults.dictionary(forKey: Self.key) ?? [:]
    }
}
