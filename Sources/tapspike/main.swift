import CoreAudio
import Foundation

func fail(_ message: String, _ status: OSStatus = noErr) -> Never {
    print("오류: \(message)\(status == noErr ? "" : " (OSStatus \(status))")")
    exit(1)
}

func readProperty<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
    if status != noErr { fail("속성 \(selector) 읽기 실패", status) }
    return value
}

func processObject(for pid: pid_t) -> AudioObjectID {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var input = pid
    var object = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &input, &size, &object)
    if status != noErr || object == kAudioObjectUnknown { fail("PID \(pid)의 오디오 프로세스 객체가 없습니다. 소리를 내는 중인지 확인하세요", status) }
    return object
}

setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments
guard args.count >= 3, let pid = pid_t(args[1]), let gain = Float(args[2]) else {
    print("사용법: tapspike <pid> <gain>")
    exit(2)
}

let process = processObject(for: pid)
let outputDevice = readProperty(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, AudioObjectID(kAudioObjectUnknown))
let outputUID = readProperty(outputDevice, kAudioDevicePropertyDeviceUID, "" as CFString) as String
print("프로세스 객체 \(process), 기본 출력 \(outputDevice) (\(outputUID))")

let description = CATapDescription(stereoMixdownOfProcesses: [process])
description.isPrivate = true
description.muteBehavior = .mutedWhenTapped
description.name = "tapspike"

var tap = AudioObjectID(kAudioObjectUnknown)
var status = AudioHardwareCreateProcessTap(description, &tap)
if status != noErr { fail("AudioHardwareCreateProcessTap", status) }
print("탭 생성: \(tap) uuid=\(description.uuid.uuidString)")

let tapFormat = readProperty(tap, kAudioTapPropertyFormat, AudioStreamBasicDescription())
print("탭 포맷: \(tapFormat.mSampleRate)Hz ch=\(tapFormat.mChannelsPerFrame) flags=\(tapFormat.mFormatFlags) bits=\(tapFormat.mBitsPerChannel)")

let aggregateDescription: [String: Any] = [
    kAudioAggregateDeviceNameKey: "tapspike",
    kAudioAggregateDeviceUIDKey: "local.mixer.tapspike.\(UUID().uuidString)",
    kAudioAggregateDeviceIsPrivateKey: true,
    kAudioAggregateDeviceMainSubDeviceKey: outputUID,
    kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
    kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
    kAudioAggregateDeviceTapAutoStartKey: true,
]
var aggregate = AudioObjectID(kAudioObjectUnknown)
status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate)
if status != noErr { fail("AudioHardwareCreateAggregateDevice", status) }
print("aggregate 생성: \(aggregate)")

nonisolated(unsafe) var renderCycles = 0
// 권한이 없으면 탭 입력이 0으로만 와서, 입력 피크로 권한 상태를 짐작한다.
nonisolated(unsafe) var inputPeak: Float = 0

// top-level 클로저는 MainActor로 추론되어 IO 스레드에서 격리 위반이 나므로 전역 함수에서 블록을 만든다.
func makeRenderBlock(gain: Float) -> AudioDeviceIOBlock {
    return { _, input, _, output, _ in
        renderCycles &+= 1
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        // 탭 스트림은 장치 자체 입력 스트림 뒤에 붙으므로 마지막 입력 버퍼를 쓴다(스파이크 한정 단순화).
        guard let source = inputs.last, let sourceData = source.mData?.assumingMemoryBound(to: Float.self), source.mNumberChannels > 0 else {
            for buffer in outputs { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
            return
        }
        let inChannels = Int(source.mNumberChannels)
        let inFrames = Int(source.mDataByteSize) / (4 * inChannels)
        for index in 0..<(inFrames * inChannels) { inputPeak = max(inputPeak, abs(sourceData[index])) }
        for buffer in outputs {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self), buffer.mNumberChannels > 0 else { continue }
            let outChannels = Int(buffer.mNumberChannels)
            let outFrames = Int(buffer.mDataByteSize) / (4 * outChannels)
            let frames = min(inFrames, outFrames)
            for frame in 0..<frames {
                for channel in 0..<outChannels {
                    data[frame * outChannels + channel] = sourceData[frame * inChannels + min(channel, inChannels - 1)] * gain
                }
            }
            if frames < outFrames {
                memset(data + frames * outChannels, 0, (outFrames - frames) * outChannels * 4)
            }
        }
    }
}

var ioProc: AudioDeviceIOProcID?
status = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, nil, makeRenderBlock(gain: gain))
if status != noErr { fail("AudioDeviceCreateIOProcIDWithBlock", status) }
status = AudioDeviceStart(aggregate, ioProc)
if status != noErr { fail("AudioDeviceStart", status) }
print("시작: gain=\(gain). Enter 또는 SIGINT/SIGTERM으로 종료")

@MainActor func teardown() -> Never {
    print("정리: render cycles=\(renderCycles) input peak=\(inputPeak)")
    AudioDeviceStop(aggregate, ioProc)
    print("AudioDeviceStop 완료")
    AudioDeviceDestroyIOProcID(aggregate, ioProc!)
    AudioHardwareDestroyAggregateDevice(aggregate)
    AudioHardwareDestroyProcessTap(tap)
    print("정리 완료")
    exit(0)
}

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let signalSources = [SIGINT, SIGTERM].map { number in
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler { MainActor.assumeIsolated { teardown() } }
    source.resume()
    return source
}
Thread.detachNewThread {
    // `open`으로 띄우면 stdin이 비어 있어 readLine이 바로 nil을 돌려주므로 그때는 신호만 기다린다.
    if readLine() != nil { DispatchQueue.main.async { MainActor.assumeIsolated { teardown() } } }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 2) { print("2초 경과 render cycles=\(renderCycles) input peak=\(inputPeak)") }
RunLoop.main.run()
