public enum GainCurve {
    public static let maxVolume: Float = 2
    public static let sliderRange: ClosedRange<Float> = 0...maxVolume
    /// 연속 슬라이더로는 정확히 1에 놓기 어려워, 가까우면 1로 붙여야 탭하지 않는 상태(ADR 002)로 돌아갈 수 있다.
    static let snapTolerance: Float = 0.025

    /// 0~1은 v²(50% ≈ -12dB)로 귀에 고르게 들리게 하고, 1~2 부스트 구간은 선형으로 올린다.
    public static func gain(forVolume volume: Float) -> Float {
        guard volume > 0 else { return 0 }
        let v = min(volume, maxVolume)
        return v <= 1 ? v * v : v
    }

    public static func volume(fromSlider value: Float) -> Float {
        guard !value.isNaN else { return 1 }
        if abs(value - 1) <= snapTolerance { return 1 }
        return min(max(value, sliderRange.lowerBound), sliderRange.upperBound)
    }
}
