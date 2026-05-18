import SwiftUI

struct CardsScrollView: View {
    let clips: [Clip]
    @Binding var selectedID: Clip.ID?
    let onPaste: (Clip) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 24) {
                    ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                        ClipboardCardView(
                            clip: clip,
                            isSelected: clip.id == selectedID,
                            index: index
                        )
                        .id(clip.id)
                        // Single-click via simultaneousGesture to avoid the double-click delay
                        .onTapGesture(count: 2) {
                            selectedID = clip.id
                            onPaste(clip)
                        }
                        .simultaneousGesture(
                            TapGesture(count: 1).onEnded {
                                selectedID = clip.id
                            }
                        )
                    }
                }
                .padding(.horizontal, 23)
                .padding(.vertical, 15)
            }
            .onChange(of: selectedID) { _, newID in
                guard let id = newID else { return }
                withAnimation(.easeOut(duration: Theme.Duration.scrollSnap)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}
