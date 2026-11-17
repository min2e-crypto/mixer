import MixerAudio
import SwiftUI

struct MixerNotchView: View {
    @ObservedObject var controller: MixerController
    let topInset: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                MixerListView(controller: controller)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.top, topInset + 6)
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}
