import CoreAudio
import Foundation
import MixerAtomics
import MixerCore
import os

let log = Logger(subsystem: "local.mixer", category: "audio")

/// 앱 하나의 소리를 가로채 게인을 적용해 다시 출력한다: process tap → private aggregate → IO proc.
public final class TapEngine {
    public let processObjects: [AudioObjectID]
    public let outputDeviceUID: String

    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private let state: IOState
    private var stopped = false

    /// HAL이 destroy 호출에서 멈추는 경우가 있어 메인 스레드 밖에서, 하나가 멈춰도 나머지가 진행되도록 병렬로 처리한다.
    private static let teardownQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "local.mixer.teardown"
        queue.maxConcurrentOperationCount = 4
        return queue
    }()

    public init(processObjects: [AudioObjectID], outputDeviceUID: String, gain: Float) throws {
        self.processObjects = processObjects
        self.outputDeviceUID = outputDeviceUID
        state = IOState(gain: gain)
        do {
            try build()
        } catch {
            stop()
            throw error
        }
    }

    deinit { stop() }

    public func setGain(_ gain: Float) {
        mixer_atomic_float_store(state.targetGain, gain)
    }

    /// 원래 소리가 바로 돌아오도록 `AudioDeviceStop`만 동기로 부르고, 나머지 해제는 백그라운드에서 한다.
    public func stop() {
        guard !stopped else { return }
        stopped = true
        if aggregate != kAudioObjectUnknown, let ioProc {
            AudioDeviceStop(aggregate, ioProc)
            log.info("AudioDeviceStop aggregate=\(self.aggregate, privacy: .public)")
        }
        let (tap, aggregate, ioProc) = (tap, aggregate, ioProc)
        Self.teardownQueue.addOperation {
            if aggregate != kAudioObjectUnknown {
                if let ioProc { AudioDeviceDestroyIOProcID(aggregate, ioProc) }
                AudioHardwareDestroyAggregateDevice(aggregate)
            }
            if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        }
    }

    private func build() throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjects)
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        description.name = "mixer"
        try check(AudioHardwareCreateProcessTap(description, &tap), "AudioHardwareCreateProcessTap")

        if let format = HAL.scalar(tap, kAudioTapPropertyFormat, as: AudioStreamBasicDescription.self) {
            state.tapChannels = Int(format.mChannelsPerFrame)
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "mixer",
            kAudioAggregateDeviceUIDKey: "local.mixer.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate), "AudioHardwareCreateAggregateDevice")
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, nil, state.makeBlock()), "AudioDeviceCreateIOProcIDWithBlock")
        try check(AudioDeviceStart(aggregate, ioProc), "AudioDeviceStart")
        log.info("엔진 시작 aggregate=\(self.aggregate, privacy: .public) objects=\(self.processObjects, privacy: .public) output=\(self.outputDeviceUID, privacy: .public)")
    }
}

/// IO 스레드가 쓰는 상태. IO 블록 안에서는 락·할당·컬렉션 생성 없이 이 값들만 읽고 쓴다.
private final class IOState {
    let targetGain: OpaquePointer
    var currentGain: Float
    var tapChannels = 2

    init(gain: Float) {
        targetGain = mixer_atomic_float_create(gain)
        currentGain = gain
    }

    deinit { mixer_atomic_float_destroy(targetGain) }

    func makeBlock() -> AudioDeviceIOBlock {
        { [self] _, input, _, output, _ in
            let target = mixer_atomic_float_load(targetGain)
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let outputs = UnsafeMutableAudioBufferListPointer(output)
            let tapIndex = Render.tapBufferIndex(channelCounts: inputs.lazy.map { Int($0.mNumberChannels) }, tapChannels: tapChannels)
            var source: UnsafePointer<Float>?
            var sourceChannels = 0
            var sourceFrames = 0
            if let tapIndex, let data = inputs[tapIndex].mData {
                source = UnsafePointer(data.assumingMemoryBound(to: Float.self))
                sourceChannels = Int(inputs[tapIndex].mNumberChannels)
                sourceFrames = Int(inputs[tapIndex].mDataByteSize) / (MemoryLayout<Float>.size * sourceChannels)
            }
            for buffer in outputs {
                guard let data = buffer.mData, buffer.mNumberChannels > 0 else { continue }
                let channels = Int(buffer.mNumberChannels)
                Render.render(
                    input: source, inputFrames: sourceFrames, inputChannels: sourceChannels,
                    output: data.assumingMemoryBound(to: Float.self),
                    outputFrames: Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels),
                    outputChannels: channels,
                    fromGain: currentGain, toGain: target)
            }
            currentGain = target
        }
    }
}
