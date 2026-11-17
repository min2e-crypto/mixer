public enum EnginePolicy {
    /// DAW는 자체 출력 체인을 써서 탭하면 무음이 되고, 화상회의 앱은 화면 공유 자기음 제외·에코 처리가 깨진다.
    public static let excludedBundleIDs: Set<String> = [
        "com.apple.logic10",
        "com.apple.mainstage3",
        "com.apple.GarageBand10",
        "com.ableton.live",
        "com.avid.ProTools",
        "com.bitwig.BitwigStudio",
        "com.cockos.reaper",
        "com.image-line.flstudio",
        "com.presonus.studioone6",
        "us.zoom.xos",
        "com.hnc.Discord",
        "com.microsoft.teams",
        "com.microsoft.teams2",
    ]

    public static func isExcluded(_ bundleID: String) -> Bool {
        excludedBundleIDs.contains(bundleID)
    }

    public static func needsEngine(bundleID: String, state: AppVolumeState) -> Bool {
        !isExcluded(bundleID) && state != .default
    }
}
