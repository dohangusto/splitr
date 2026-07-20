import SwiftUI
import SplitBillCore

/// The one place role routing happens: the host (penalang) gets the full
/// DetailView surface; everyone else gets MemberClaim. A covered member can
/// never reach the host surface — the branch re-evaluates on every store
/// change, so a kicked/renamed acting member falls out naturally.
///
/// Also the room-level surface for `store.alert` (claim races, host-only
/// rule violations), so both role views inherit it without duplicating the
/// modifier.
struct RoomRootView: View {
    let store: any RoomStoring
    let roomID: UUID

    private var room: Room? { store.room(withID: roomID) }

    var body: some View {
        Group {
            if let room {
                if store.actingMemberID(in: roomID) == room.hostMemberID {
                    DetailView(store: store, roomID: roomID)
                } else {
                    MemberClaim(store: store, roomID: roomID)
                }
            } else {
                ContentUnavailableView("Room not found", systemImage: "questionmark.circle")
            }
        }
        .alert(
            "Heads up",
            isPresented: Binding(
                get: { store.alert != nil },
                set: { if !$0 { store.alert = nil } }
            ),
            presenting: store.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }
}
