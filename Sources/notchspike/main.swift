import AppKit

// 3.5-a: 노치 영역 클릭이 패널 mouseDown으로 오는지, 전역 모니터로만 보이는지 높이별로 기록한다.
setvbuf(stdout, nil, _IOLBF, 0)

guard let screen = NSScreen.screens.first(where: { screen in
    let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    return screen.safeAreaInsets.top > 0 && CGDisplayIsBuiltin(id) != 0
}), let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
    print("노치 화면이 없습니다")
    exit(1)
}

let notch = NSRect(x: left.maxX, y: screen.frame.maxY - screen.safeAreaInsets.top, width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
print("화면 \(screen.frame) 노치 \(notch) 메뉴바 높이 \(menuBarHeight)")

let screenTop = screen.frame.maxY
let depth: @MainActor (NSPoint) -> String = { point in String(format: "위에서 %.1fpt", screenTop - point.y) }

final class ProbeView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        print("패널 mouseDown \(depth(NSEvent.mouseLocation))")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let panel = NSPanel(contentRect: notch, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
panel.backgroundColor = .black
panel.hasShadow = false
panel.contentView = ProbeView(frame: NSRect(origin: .zero, size: notch.size))
panel.orderFrontRegardless()

let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { event in
    let location = NSEvent.mouseLocation
    guard notch.insetBy(dx: -20, dy: 0).contains(location) || location.y >= notch.minY else { return }
    print("전역 \(event.type == .leftMouseDown ? "down" : "up") \(depth(location)) 노치 안=\(notch.contains(location))")
}
let seconds = Double(CommandLine.arguments.dropFirst().first ?? "") ?? 60
print("\(Int(seconds))초 동안 노치를 위에서부터 여러 높이로 클릭해 보세요")
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
app.run()
