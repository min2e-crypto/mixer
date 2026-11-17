import AppKit
import MixerAudio
import MixerCore
import SwiftUI

/// 메뉴바 패널과 노치 패널이 함께 쓰는 앱 목록.
struct MixerListView: View {
    @ObservedObject var controller: MixerController

    var body: some View {
        if controller.needsPermission {
            PermissionRow()
        } else if controller.apps.isEmpty {
            Text("소리를 내는 앱이 없습니다")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else {
            VStack(spacing: 6) {
                ForEach(controller.apps) { app in
                    AppRow(app: app, controller: controller)
                }
            }
        }
    }
}

struct PermissionRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("시스템 오디오 녹음 권한이 필요합니다", systemImage: "exclamationmark.triangle")
            Button("설정 열기") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppRow: View {
    let app: MixerApp
    @ObservedObject var controller: MixerController

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(app.identity.name).lineLimit(1)
                    if app.isPlaying {
                        Image(systemName: "waveform").font(.caption2).foregroundStyle(.green)
                    }
                    if app.isExcluded {
                        Text("제외").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Slider(
                    value: Binding(
                        get: { Double(app.state.volume) },
                        set: { controller.setVolume(Float($0), for: app.id) }),
                    in: Double(GainCurve.sliderRange.lowerBound)...Double(GainCurve.sliderRange.upperBound))
                    .controlSize(.small)
                    .disabled(app.isExcluded)
            }
            Text("\(Int((app.state.volume * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
            Button {
                controller.toggleMute(app.id)
            } label: {
                Image(systemName: app.state.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)
            .disabled(app.isExcluded)
        }
    }

    private var icon: NSImage {
        NSRunningApplication(processIdentifier: app.pid)?.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
    }
}
