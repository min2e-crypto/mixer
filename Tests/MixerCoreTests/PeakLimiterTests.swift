import Foundation
import Testing
@testable import MixerCore

private func process(_ limiter: PeakLimiter, _ input: [Float], channels: Int, blockFrames: [Int]? = nil) -> [Float] {
    var buffer = input
    let totalFrames = input.count / channels
    let blocks = blockFrames ?? [totalFrames]
    buffer.withUnsafeMutableBufferPointer { pointer in
        var frame = 0
        var index = 0
        while frame < totalFrames {
            let frames = min(blocks[index % blocks.count], totalFrames - frame)
            limiter.process(pointer.baseAddress! + frame * channels, frames: frames, channels: channels)
            frame += frames
            index += 1
        }
    }
    return buffer
}

private func sine(frames: Int, channels: Int, amplitude: Float, period: Float = 37) -> [Float] {
    (0..<frames).flatMap { frame in
        (0..<channels).map { channel in amplitude * sin(2 * .pi * Float(frame) / period + Float(channel)) }
    }
}

@Suite struct PeakLimiterTests {
    @Test func 천장을_넘는_입력은_천장_아래로_줄인다() {
        let limiter = PeakLimiter(channels: 2, lookaheadFrames: 32, releaseFrames: 400)
        var input = sine(frames: 4000, channels: 2, amplitude: 1.8)
        input[2001 * 2] = 4
        let output = process(limiter, input, channels: 2)
        #expect(output.allSatisfy { abs($0) <= 1 })
        #expect(output.contains { abs($0) > 0.9 })
    }

    @Test func 천장_이하_입력은_지연만_된다() {
        let limiter = PeakLimiter(channels: 2, lookaheadFrames: 32, releaseFrames: 400)
        let input = sine(frames: 2000, channels: 2, amplitude: 1)
        let output = process(limiter, input, channels: 2)
        let latency = limiter.latencyFrames
        #expect(latency == 31)
        #expect(output.prefix(latency * 2).allSatisfy { $0 == 0 })
        #expect(Array(output.dropFirst(latency * 2)) == Array(input.prefix(input.count - latency * 2)))
    }

    @Test func 블록을_나눠도_결과가_같다() {
        let input = sine(frames: 3000, channels: 2, amplitude: 2.5, period: 53)
        let whole = process(PeakLimiter(channels: 2, lookaheadFrames: 32, releaseFrames: 400), input, channels: 2)
        let split = process(PeakLimiter(channels: 2, lookaheadFrames: 32, releaseFrames: 400), input, channels: 2, blockFrames: [1, 7, 31, 32, 33, 100, 512])
        #expect(whole == split)
    }

    @Test func 피크가_지나면_게인이_서서히_돌아온다() {
        let limiter = PeakLimiter(channels: 1, lookaheadFrames: 8, releaseFrames: 100)
        var input = [Float](repeating: 0.5, count: 2000)
        input[100] = 2
        let output = process(limiter, input, channels: 1)
        let peakOut = 100 + limiter.latencyFrames
        #expect(abs(output[peakOut]) <= 1)
        #expect(output[peakOut + 20] < 0.5)
        #expect(output[1999] > 0.499)
    }

    @Test func 채널_수가_다르면_건드리지_않는다() {
        let limiter = PeakLimiter(channels: 2, lookaheadFrames: 8, releaseFrames: 100)
        let input: [Float] = [3, 3, 3, 3, 3, 3]
        #expect(process(limiter, input, channels: 3) == input)
    }
}
