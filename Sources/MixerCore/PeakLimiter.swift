import Foundation

/// lookahead 피크 리미터. 피크가 천장을 넘을 때만 게인을 줄이고, 넘지 않으면 지연 외에는 소리를 바꾸지 않는다.
/// IO 스레드에서 쓰므로 버퍼는 init에서만 할당하고 `process`는 할당·락이 없다. 버퍼는 Float32 interleaved로 가정한다.
///
/// 게인 = (lookahead 창의 필요 게인 최솟값 → 내려갈 땐 즉시·올라갈 땐 release로 천천히) 의 lookahead 길이 이동 평균.
/// 평균 창 안의 값이 모두 출력될 샘플의 필요 게인 이하라서, 출력은 천장을 넘지 않으면서 게인 변화는 램프가 된다.
public final class PeakLimiter {
    public let channels: Int
    public let ceiling: Float = 1
    public var latencyFrames: Int { lookahead - 1 }

    private let lookahead: Int
    private let releaseCoefficient: Float

    private let delay: UnsafeMutablePointer<Float>
    private let delayCapacity: Int
    private var delayIndex = 0

    private let minValues: UnsafeMutablePointer<Float>
    private let minFrames: UnsafeMutablePointer<Int>
    private var minHead = 0
    private var minCount = 0
    private var frameCounter = 0

    private var releasedGain: Float = 1
    private let averageRing: UnsafeMutablePointer<Float>
    private var averageIndex = 0
    private var averageSum: Double

    public init(channels: Int, lookaheadFrames: Int, releaseFrames: Int) {
        precondition(channels > 0 && lookaheadFrames > 0 && releaseFrames > 0)
        self.channels = channels
        lookahead = lookaheadFrames
        releaseCoefficient = Float(1 - exp(-1 / Double(releaseFrames)))
        delayCapacity = max(lookaheadFrames - 1, 1) * channels
        delay = .allocate(capacity: delayCapacity)
        delay.initialize(repeating: 0, count: delayCapacity)
        minValues = .allocate(capacity: lookaheadFrames)
        minValues.initialize(repeating: 1, count: lookaheadFrames)
        minFrames = .allocate(capacity: lookaheadFrames)
        minFrames.initialize(repeating: 0, count: lookaheadFrames)
        averageRing = .allocate(capacity: lookaheadFrames)
        averageRing.initialize(repeating: 1, count: lookaheadFrames)
        averageSum = Double(lookaheadFrames)
    }

    public convenience init(channels: Int, sampleRate: Double, lookaheadSeconds: Double = 0.005, releaseSeconds: Double = 0.1) {
        self.init(
            channels: channels,
            lookaheadFrames: max(Int(sampleRate * lookaheadSeconds), 1),
            releaseFrames: max(Int(sampleRate * releaseSeconds), 1))
    }

    deinit {
        delay.deallocate()
        minValues.deallocate()
        minFrames.deallocate()
        averageRing.deallocate()
    }

    /// 지연 줄이 채널 수에 맞춰 잡혀 있어, 채널 수가 다른 버퍼는 건드리지 않는다.
    public func process(_ buffer: UnsafeMutablePointer<Float>, frames: Int, channels: Int) {
        guard channels == self.channels, frames > 0 else { return }
        let latency = latencyFrames
        for frame in 0..<frames {
            let base = frame * channels
            var peak: Float = 0
            for channel in 0..<channels {
                peak = max(peak, abs(buffer[base + channel]))
            }
            let gain = nextGain(required: peak > ceiling ? ceiling / peak : 1)
            for channel in 0..<channels {
                let sample: Float
                if latency > 0 {
                    let slot = delayIndex * channels + channel
                    sample = delay[slot]
                    delay[slot] = buffer[base + channel]
                } else {
                    sample = buffer[base + channel]
                }
                // 이동 평균의 부동소수 반올림으로 천장을 아주 조금 넘을 수 있어 마지막에 자른다.
                buffer[base + channel] = min(max(sample * gain, -ceiling), ceiling)
            }
            if latency > 0 { delayIndex = (delayIndex + 1) % latency }
        }
    }

    private func nextGain(required: Float) -> Float {
        if minCount > 0, minFrames[minHead] <= frameCounter - lookahead {
            minHead = (minHead + 1) % lookahead
            minCount -= 1
        }
        while minCount > 0, minValues[(minHead + minCount - 1) % lookahead] >= required {
            minCount -= 1
        }
        let tail = (minHead + minCount) % lookahead
        minValues[tail] = required
        minFrames[tail] = frameCounter
        minCount += 1
        frameCounter += 1
        let windowMin = minValues[minHead]

        if windowMin < releasedGain {
            releasedGain = windowMin
        } else {
            releasedGain = min(releasedGain + (windowMin - releasedGain) * releaseCoefficient, windowMin)
        }

        averageSum += Double(releasedGain) - Double(averageRing[averageIndex])
        averageRing[averageIndex] = releasedGain
        averageIndex = (averageIndex + 1) % lookahead
        return Float(averageSum / Double(lookahead))
    }
}
