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

    @Test func 슬라이더_가운데는_원래_소리다() {
        #expect(GainCurve.sliderRange == 0...2)
        #expect(GainCurve.volume(fromSlider: 1) == 1)
        #expect(GainCurve.gain(forVolume: GainCurve.volume(fromSlider: 1)) == 1)
    }

    @Test(arguments: [Float(0.98), 1.02, 0.975, 1.025])
    func 가운데_근처는_100퍼센트로_붙인다(slider: Float) {
        #expect(GainCurve.volume(fromSlider: slider) == 1)
    }

    @Test(arguments: [(Float(0), Float(0)), (0.5, 0.5), (0.96, 0.96), (1.04, 1.04), (2, 2), (-1, 0), (3, 2), (.nan, 1)])
    func 슬라이더_값을_볼륨으로_바꾼다(slider: Float, volume: Float) {
        #expect(GainCurve.volume(fromSlider: slider) == volume)
    }
}
