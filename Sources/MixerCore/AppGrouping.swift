public struct AppIdentity: Equatable, Hashable, Sendable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

public struct AudioProcessEntry: Equatable, Sendable {
    public let objectID: UInt32
    public let pid: Int32
    public let bundleID: String?
    public let isPlaying: Bool

    public init(objectID: UInt32, pid: Int32, bundleID: String?, isPlaying: Bool) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.isPlaying = isPlaying
    }
}

public struct AppGroup: Equatable, Sendable {
    public let identity: AppIdentity
    public let pid: Int32
    public var processObjects: [UInt32]
    public var isPlaying: Bool
    /// 일반 앱에 묶였는지. false면 앱 없이 프로세스 번들 ID로만 묶인 시스템 프로세스다.
    public let isApp: Bool

    public init(identity: AppIdentity, pid: Int32, processObjects: [UInt32], isPlaying: Bool, isApp: Bool) {
        self.identity = identity
        self.pid = pid
        self.processObjects = processObjects
        self.isPlaying = isPlaying
        self.isApp = isApp
    }
}

public enum AppGrouping {
    /// 브라우저 helper는 앱 → helper → 하위 helper처럼 몇 단계 아래에 있다.
    static let maxParentDepth = 6

    /// - Parameters:
    ///   - app: pid가 일반 앱이면 그 정체. 아니면 nil.
    ///   - parent: pid를 소유한 상위 pid(책임 프로세스 또는 부모).
    public static func group(
        _ entries: [AudioProcessEntry],
        ownPID: Int32,
        app: (Int32) -> AppIdentity?,
        parent: (Int32) -> Int32?
    ) -> [AppGroup] {
        var groups: [AppGroup] = []
        for entry in entries where entry.pid != ownPID {
            guard let (identity, pid, isApp) = owner(of: entry, app: app, parent: parent), pid != ownPID else { continue }
            if let index = groups.firstIndex(where: { $0.identity.bundleID == identity.bundleID }) {
                groups[index].processObjects.append(entry.objectID)
                groups[index].isPlaying = groups[index].isPlaying || entry.isPlaying
            } else {
                groups.append(AppGroup(identity: identity, pid: pid, processObjects: [entry.objectID], isPlaying: entry.isPlaying, isApp: isApp))
            }
        }
        return groups
    }

    private static func owner(
        of entry: AudioProcessEntry,
        app: (Int32) -> AppIdentity?,
        parent: (Int32) -> Int32?
    ) -> (AppIdentity, Int32, Bool)? {
        var pid = entry.pid
        for _ in 0...maxParentDepth {
            if let identity = app(pid) { return (identity, pid, true) }
            guard let next = parent(pid), next > 1, next != pid else { break }
            pid = next
        }
        guard let bundleID = entry.bundleID, !bundleID.isEmpty else { return nil }
        return (AppIdentity(bundleID: bundleID, name: bundleID), entry.pid, false)
    }
}
