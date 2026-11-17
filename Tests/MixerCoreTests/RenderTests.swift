import Testing
@testable import MixerCore

private func render(_ input: [Float], inChannels: Int, outFrames: Int, outChannels: Int, from: Float, to: Float, prefill: Float = 9) -> [Float] {
    var output = [Float](repeating: prefill, count: outFrames * outChannels)
    input.withUnsafeBufferPointer { inPtr in
        output.withUnsafeMutableBufferPointer { outPtr in
            Render.render(input: inPtr.baseAddress, inputFrames: input.count / inChannels, inputChannels: inChannels,
                          output: outPtr.baseAddress!, outputFrames: outFrames, outputChannels: outChannels,
                          fromGain: from, toGain: to)
        }
    }
    return output
}

@Suite struct RenderTests {
    @Test func 게인을_곱한다() {
        #expect(render([1, -1, 0.5, 0.5], inChannels: 2, outFrames: 2, outChannels: 2, from: 0.5, to: 0.5) == [0.5, -0.5, 0.25, 0.25])
    }

    @Test func 입력보다_많은_출력_프레임은_0으로_채운다() {
        #expect(render([1, 1], inChannels: 2, outFrames: 3, outChannels: 2, from: 1, to: 1) == [1, 1, 0, 0, 0, 0])
    }

    @Test func 입력이_없으면_전부_0이다() {
        var output: [Float] = [9, 9, 9, 9]
        output.withUnsafeMutableBufferPointer {
            Render.render(input: nil, inputFrames: 0, inputChannels: 2, output: $0.baseAddress!, outputFrames: 2, outputChannels: 2, fromGain: 1, toGain: 1)
        }
        #expect(output == [0, 0, 0, 0])
    }

    @Test func 블록_안에서_게인을_선형으로_바꾼다() {
        #expect(render([1, 1, 1, 1], inChannels: 1, outFrames: 4, outChannels: 1, from: 0, to: 1) == [0.25, 0.5, 0.75, 1])
    }

    @Test func 모노_입력은_모든_출력_채널에_복사한다() {
        #expect(render([0.5], inChannels: 1, outFrames: 1, outChannels: 2, from: 1, to: 1) == [0.5, 0.5])
    }

    @Test func 입력에_없는_출력_채널은_0이다() {
        #expect(render([1, 1], inChannels: 2, outFrames: 1, outChannels: 4, from: 1, to: 1) == [1, 1, 0, 0])
    }

    @Test func 탭_버퍼는_채널_수가_맞는_마지막_버퍼다() {
        #expect(Render.tapBufferIndex(channelCounts: [1, 2], tapChannels: 2) == 1)
        #expect(Render.tapBufferIndex(channelCounts: [2], tapChannels: 2) == 0)
        #expect(Render.tapBufferIndex(channelCounts: [1], tapChannels: 2) == nil)
        #expect(Render.tapBufferIndex(channelCounts: [], tapChannels: 2) == nil)
    }
}
