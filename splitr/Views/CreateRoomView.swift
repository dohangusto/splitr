import SwiftUI
import SplitBillCore

/// "Create Room" sheet: room name + host identity (display name + emoji avatar).
struct CreateRoomView: View {
    let store: any RoomStoring

    @Environment(\.dismiss) private var dismiss
    @State private var roomName = ""
    @State private var hostName = ""
    @State private var emoji = "🧑‍🍳"

    var body: some View {
        NavigationStack {
            Form {
                Section("Room") {
                    TextField("Room name (e.g. Makan Malam Tim)", text: $roomName)
                }
                Section("You (the host — you pay first, friends pay you back)") {
                    TextField("Your display name", text: $hostName)
                    EmojiPicker(selection: $emoji)
                }
            }
            .navigationTitle("Create Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        store.createRoom(
                            named: roomName.trimmingCharacters(in: .whitespaces),
                            hostName: hostName.trimmingCharacters(in: .whitespaces),
                            hostEmoji: emoji
                        )
                        dismiss()
                    }
                    .disabled(roomName.trimmingCharacters(in: .whitespaces).isEmpty
                        || hostName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Sheet for adding a member locally (stand-in for the Milestone 5 proximity join).
struct JoinMemberView: View {
    let store: any RoomStoring
    let roomID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "🙂"

    var body: some View {
        NavigationStack {
            Form {
                Section("New member") {
                    TextField("Display name", text: $name)
                    EmojiPicker(selection: $emoji)
                }
            }
            .navigationTitle("Add Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.joinMember(
                            named: name.trimmingCharacters(in: .whitespaces),
                            emoji: emoji,
                            roomID: roomID
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct EmojiPicker: View {
    @Binding var selection: String

    private static let options = [
        "🧑‍🍳", "🐱", "🦖", "🌺", "🐨", "🦊", "🐼", "🐸",
        "🦁", "🐰", "🐧", "🦉", "🍜", "🍣", "🍕", "🧋",
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
            ForEach(Self.options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(option)
                        .font(.title2)
                        .padding(6)
                        .background(
                            selection == option ? Color.accentColor.opacity(0.2) : .clear,
                            in: .circle
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
