import Testing
@testable import MixerCore

@Suite struct GainCurveTests {
    @Test(arguments: [(Float(0), Float(0)), (0.5, 0.25), (1, 1), (1.5, 1.5), (2, 2)])
    func 볼륨을_게인으로_바꾼다(volume: Float, gain: Float) {
        #expect(GainCurve.gain(forVolume: volume) == gain)
    }

    @Test func 범위_밖_값은_클램프한다() {
        #expect(GainCurve.gain(forVolume: -0.5) == 0)
        #expect(GainCurve.gain(forVolume: 3) == 2)
        #expect(GainCurve.gain(forVolume: .nan) == 0)
    }
}
