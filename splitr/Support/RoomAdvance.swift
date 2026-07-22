import SplitBillCore

/// Single source of truth for the host's advance-the-room semantics: button
/// label, confirmation question, and consequence copy per state. Relocated
/// from the retired RoomDetailView; consumed by DetailView (and anything
/// else that ever drives `store.advance`).
extension RoomState {
    var advanceLabel: String {
        switch self {
        case .open: return "Start Claiming"
        case .claiming: return "Close Claiming & Settle"
        case .settling: return "Close Room"
        case .closed: return ""
        }
    }

    var advanceQuestion: String {
        switch self {
        case .open: return "Start claiming?"
        case .claiming: return "Close claiming?"
        case .settling: return "Close this room?"
        case .closed: return ""
        }
    }

    var advanceDetail: String {
        switch self {
        case .open:
            return "Members will start claiming their items. You can still add bills and members while claiming."
        case .claiming:
            return "Tax and service will be split proportionally and everyone sees what they owe. You can reopen claiming later if something's wrong."
        case .settling:
            return "Closing is final. The room becomes read-only history."
        case .closed:
            return ""
        }
    }
}
