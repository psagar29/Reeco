import SwiftUI

/// The floating bottom control strip: transcript ribbon, manual chips, and the
/// typed/voice command bar. This is the always-available driver for the demo,
/// independent of the camera.
struct ControlStripView: View {
    var body: some View {
        VStack(spacing: 10) {
            TranscriptRibbonView()
            ChipRowView()
            CommandBarView()
        }
        .padding(.top, 4)
    }
}
