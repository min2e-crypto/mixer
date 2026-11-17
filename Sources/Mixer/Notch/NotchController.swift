import AppKit
import MixerAudio
import MixerCore

/// 노치 화면을 찾아 패널을 띄우고 클릭·바깥 클릭·Esc로 펼치고 접는다. 노치 화면이 없으면 아무것도 띄우지 않는다.
@MainActor
final class NotchController {
    private let controller: MixerController
    private var panel: NotchPanel?
    private var container: NotchContainerView?
    private var geometry: NotchGeometry?
    private var displayID: CGDirectDisplayID?
    private var isExpanded = false

    private var topRowMonitor: Any?
    private var pressStartedInNotch = false
    private var openMonitors: [Any] = []
    private var screenObserver: NSObjectProtocol?

    init(controller: MixerController) {
        self.controller = controller
    }

    func start() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateScreen() }
        }
        // 화면 맨 윗줄 클릭은 창 레벨과 관계없이 메뉴바가 가져가므로 전역 모니터로 본다. 마우스 관찰에는 권한이 필요 없다.
        topRowMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleTopRow(event) }
        }
        updateScreen()
    }

    private func updateScreen() {
        if isExpanded { close(animated: false) }
        guard let (screen, id) = Self.notchScreen(),
              let newGeometry = NotchGeometry(screen: Self.describe(screen))
        else {
            panel?.orderOut(nil)
            geometry = nil
            displayID = nil
            return
        }
        let panel = panel ?? makePanel(geometry: newGeometry)
        if newGeometry != geometry || id != displayID {
            // 보이는 채로 다른 화면에 setFrame하면 창 서버가 늘어나는 애니메이션을 그린다.
            panel.orderOut(nil)
            geometry = newGeometry
            displayID = id
            panel.setFrame(newGeometry.collapsed, display: false)
            container?.setShape(CGRect(origin: .zero, size: newGeometry.collapsed.size))
        }
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
    }

    private func makePanel(geometry: NotchGeometry) -> NotchPanel {
        let panel = NotchPanel(frame: geometry.collapsed)
        let container = NotchContainerView(content: MixerNotchView(controller: controller, topInset: geometry.camera.height))
        container.onCollapsedClick = { [weak self] in self?.toggle() }
        panel.contentView = container
        self.panel = panel
        self.container = container
        return panel
    }

    private func toggle() {
        if isExpanded { close(animated: true) } else { open() }
    }

    private func open() {
        guard let panel, let container, let geometry, !isExpanded else { return }
        isExpanded = true
        // 프레임을 펼친 크기로 한 번만 바꾸고 이후에는 마스크만 움직인다. 프레임마다 창 크기를 바꾸면 깜빡인다.
        panel.setFrame(geometry.expanded, display: true)
        container.layoutSubtreeIfNeeded()
        container.animateShape(from: geometry.collapsedInExpanded, to: CGRect(origin: .zero, size: geometry.expanded.size), expanding: true) {}
        panel.ignoresMouseEvents = false
        panel.acceptsKey = true
        panel.makeKey()
        installOpenMonitors()
    }

    private func close(animated: Bool) {
        guard let panel, let container, let geometry, isExpanded else { return }
        isExpanded = false
        // 접히는 동안에도 아래 메뉴바 클릭이 바로 통하도록 먼저 클릭을 끈다.
        panel.ignoresMouseEvents = true
        panel.acceptsKey = false
        panel.resignKey()
        removeOpenMonitors()

        let finish = { [weak self] in
            guard let self, !self.isExpanded, let panel = self.panel else { return }
            panel.setFrame(geometry.collapsed, display: true)
            self.container?.setShape(CGRect(origin: .zero, size: geometry.collapsed.size))
            panel.ignoresMouseEvents = false
        }
        guard animated else {
            container.collapseImmediately()
            finish()
            return
        }
        container.animateShape(from: CGRect(origin: .zero, size: geometry.expanded.size), to: geometry.collapsedInExpanded, expanding: false) {
            MainActor.assumeIsolated { finish() }
        }
    }

    private func handleTopRow(_ event: NSEvent) {
        guard let geometry else { return }
        let inNotch = geometry.collapsed.contains(NSEvent.mouseLocation)
        switch event.type {
        case .leftMouseDown:
            pressStartedInNotch = inNotch
        case .leftMouseUp:
            if pressStartedInNotch && inNotch { toggle() }
            pressStartedInNotch = false
        default:
            break
        }
    }

    private func installOpenMonitors() {
        let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let geometry = self.geometry else { return }
                // 노치 안 클릭은 토글 모니터가 처리한다. 여기서도 닫으면 닫혔다가 바로 다시 열린다.
                if !geometry.collapsed.contains(NSEvent.mouseLocation) { self.close(animated: true) }
            }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            let isEscape = event.type == .keyDown && event.keyCode == 53
            let isKey = event.type == .keyDown
            let window = event.window
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                if isEscape {
                    self.close(animated: true)
                    return true
                }
                if !isKey && window !== self.panel { self.close(animated: true) }
                return false
            }
            return consumed ? nil : event
        }
        openMonitors = [outside, local].compactMap { $0 }
    }

    private func removeOpenMonitors() {
        openMonitors.forEach(NSEvent.removeMonitor)
        openMonitors.removeAll()
    }

    private static func notchScreen() -> (NSScreen, CGDirectDisplayID)? {
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            if screen.safeAreaInsets.top > 0 && CGDisplayIsBuiltin(id) != 0 { return (screen, id) }
        }
        return nil
    }

    private static func describe(_ screen: NSScreen) -> NotchScreen {
        NotchScreen(
            frame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea,
            scale: screen.backingScaleFactor)
    }
}
