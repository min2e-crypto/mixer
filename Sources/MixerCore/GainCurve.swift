public enum GainCurve {
    public static let maxVolume: Float = 2

    /// 0~1은 v²(50% ≈ -12dB)로 귀에 고르게 들리게 하고, 1~2 부스트 구간은 선형으로 올린다.
    public static func gain(forVolume volume: Float) -> Float {
        guard volume > 0 else { return 0 }
        let v = min(volume, maxVolume)
        return v <= 1 ? v * v : v
    }
}
