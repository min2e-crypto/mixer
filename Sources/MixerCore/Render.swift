/// IO 스레드에서 불리므로 할당·락 없이 포인터만 다룬다. 버퍼는 Float32 interleaved로 가정한다.
public enum Render {
    /// aggregate 입력에는 출력 장치 자체의 입력 스트림이 탭보다 앞에 올 수 있어, 채널 수가 맞는 마지막 버퍼를 탭으로 본다.
    public static func tapBufferIndex(channelCounts: [Int], tapChannels: Int) -> Int? {
        channelCounts.lastIndex(of: tapChannels)
    }

    public static func render(
        input: UnsafePointer<Float>?,
        inputFrames: Int,
        inputChannels: Int,
        output: UnsafeMutablePointer<Float>,
        outputFrames: Int,
        outputChannels: Int,
        fromGain: Float,
        toGain: Float
    ) {
        let frames = input == nil || inputChannels <= 0 ? 0 : min(inputFrames, outputFrames)
        if let input, frames > 0 {
            let step = (toGain - fromGain) / Float(frames)
            for frame in 0..<frames {
                let gain = frame == frames - 1 ? toGain : fromGain + step * Float(frame + 1)
                let inBase = frame * inputChannels
                let outBase = frame * outputChannels
                for channel in 0..<outputChannels {
                    let source: Float
                    if inputChannels == 1 {
                        source = input[inBase]
                    } else if channel < inputChannels {
                        source = input[inBase + channel]
                    } else {
                        source = 0
                    }
                    output[outBase + channel] = source * gain
                }
            }
        }
        // 출력 버퍼에는 이전 주기의 데이터가 남아 있어 못 채운 프레임을 0으로 지우지 않으면 잔음이 재생된다.
        let remaining = (outputFrames - frames) * outputChannels
        if remaining > 0 {
            (output + frames * outputChannels).initialize(repeating: 0, count: remaining)
        }
    }
}
