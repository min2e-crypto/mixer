import AppKit
import MixerAudio
import ServiceManagement
import SwiftUI

@main
struct MixerMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Mixer", systemImage: "slider.horizontal.3") {
            MenuPanelView(controller: delegate.controller)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = MixerController()
    private lazy var notch = NotchController(controller: controller)

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.registerOnFirstLaunch()
        controller.start()
        notch.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}

@MainActor
enum LoginItem {
    private static let setupKey = "loginItemConfigured"

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("로그인 항목 변경 실패: \(error)")
        }
    }

    /// 처음 한 번만 켜고, 이후 마스터가 끈 설정은 존중한다.
    static func registerOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: setupKey) else { return }
        UserDefaults.standard.set(true, forKey: setupKey)
        set(true)
    }
}
