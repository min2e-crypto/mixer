import MixerAudio
import SwiftUI

struct MenuPanelView: View {
    @ObservedObject var controller: MixerController
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mixer").font(.headline)
            MixerListView(controller: controller)
            Divider()
            HStack {
                Toggle("로그인 시 실행", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: launchAtLogin) { _, enabled in LoginItem.set(enabled) }
                Spacer()
                Button("종료") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }
}
