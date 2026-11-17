import CoreAudio
import Foundation

public struct HALError: Error, CustomStringConvertible {
    public let step: String
    public let status: OSStatus

    public var description: String { "\(step) 실패 (OSStatus \(status))" }
}

func check(_ status: OSStatus, _ step: String) throws {
    if status != noErr { throw HALError(step: step, status: status) }
}

enum HAL {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    static func scalar<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as _: T.Type) -> T? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    static func defaultOutputDevice() -> AudioObjectID? {
        scalar(system, kAudioHardwarePropertyDefaultOutputDevice, as: AudioObjectID.self).flatMap { $0 == kAudioObjectUnknown ? nil : $0 }
    }
}

/// HAL 리스너 블록은 제거한 뒤에도 늦게 불릴 수 있어, 블록은 약한 참조만 잡고 해제는 이 토큰으로 한다.
final class HALListener {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock
    private var active = false

    init(object: AudioObjectID, selector: AudioObjectPropertySelector, handler: @escaping @MainActor () -> Void) {
        self.object = object
        self.address = HAL.address(selector)
        self.block = { _, _ in MainActor.assumeIsolated { handler() } }
        active = AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr
    }

    func remove() {
        guard active else { return }
        active = false
        AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
    }

    deinit { remove() }
}
