import SwiftUI
import SplitBillCore

/// "Create Room" sheet: room name + host identity (display name + emoji avatar).
struct CreateRoomView: View {
    let store: any RoomStoring

    @Environment(\.dismiss) private var dismiss
    @State private var roomName = ""
    @State private var profile = UserProfile.load()

    var body: some View {
        NavigationStack {
            Form {
                Section("Room") {
                    TextField("Room name (e.g. Makan Malam Tim)", text: $roomName)
                }
                Section("You") {
                    HStack(spacing: 16) {
                        Image(profile.avatar)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color(.systemGray5), lineWidth: 1))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Your display name", text: $profile.name)
                                .font(.headline)
                            Text("Profile Photo")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
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
                        profile.save()
                        store.createRoom(
                            named: roomName.trimmingCharacters(in: .whitespaces),
                            hostName: profile.name,
                            hostEmoji: profile.avatar
                        )
                        dismiss()
                    }
                    .disabled(roomName.trimmingCharacters(in: .whitespaces).isEmpty
                        || profile.name.trimmingCharacters(in: .whitespaces).isEmpty)
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
    @State private var avatar = AvatarCatalog.defaultName

    var body: some View {
        NavigationStack {
            Form {
                Section("New member") {
                    TextField("Display name", text: $name)
                    AvatarPicker(selection: $avatar)
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
                            emoji: avatar,
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
