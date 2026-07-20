//
//  PeopleListSheet.swift
//  splitr
//

import SwiftUI
import SplitBillCore

/// Roster of the room's members, plus the host's ways of adding people.
/// Wired to the store: the list is `room.members`, and "Add new" routes to
/// the existing add flows (nearby / invite link / manual) rather than
/// creating local-only people.
struct PeopleListSheet: View {

    let store: any RoomStoring
    let roomID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var showAddOptions = false
    @State private var showJoinMember = false
    @State private var showNearbyHost = false
    @State private var inviteURL: URL?

    private var room: Room? { store.room(withID: roomID) }
    /// New members can join only before settling starts.
    private var canAdd: Bool {
        room.map { $0.state == .open || $0.state == .claiming } ?? false
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: - Header
            ZStack {
                Text("List people")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.black)

                HStack {
                    // Close Button
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(.gray)
                            .frame(width: 56, height: 56)
                            .background(Color.gray.opacity(0.12))
                            .clipShape(Circle())
                    }

                    Spacer()

                    // Add New Button
                    if canAdd {
                        Button {
                            addNewTapped()
                        } label: {
                            Text("Add new")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.black.opacity(0.7))
                                .padding(.horizontal, 20)
                                .frame(height: 56)
                                .background(.white)
                                .clipShape(Capsule())
                                .shadow(
                                    color: .black.opacity(0.08),
                                    radius: 20,
                                    x: 0,
                                    y: 8
                                )
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            // MARK: - People List
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(room?.members ?? []) { member in
                        PersonRow(member: member)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
            }
        }
        .background(
            Color(
                red: 0.98,
                green: 0.98,
                blue: 0.98
            )
        )
        .confirmationDialog("Add people", isPresented: $showAddOptions) {
            Button("Add People Nearby") { showNearbyHost = true }
            Button("Invite via Link") { fetchInviteURL() }
            Button("Add Member Manually") { showJoinMember = true }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showJoinMember) {
            JoinMemberView(store: store, roomID: roomID)
        }
        .sheet(isPresented: $showNearbyHost) {
            if let cloudStore = AppComposition.cloudStore, let room {
                NearbyHostView(
                    store: cloudStore,
                    roomID: roomID,
                    roomName: room.name,
                    hostDisplayName: room.member(withID: room.hostMemberID)?.displayName ?? "Host",
                    onUseLink: { fetchInviteURL() }
                )
            }
        }
        .sheet(item: $inviteURL) { url in
            ShareLinkSheet(url: url, roomName: room?.name ?? "")
        }
    }

    /// With CloudKit, the host chooses how to add; without it (simulator),
    /// only manual add exists, so go straight there.
    private func addNewTapped() {
        if AppComposition.cloudStore != nil {
            showAddOptions = true
        } else {
            showJoinMember = true
        }
    }

    private func fetchInviteURL() {
        Task {
            inviteURL = await AppComposition.cloudStore?.inviteURL(roomID: roomID)
        }
    }
}


// MARK: - Person Row

struct PersonRow: View {

    let member: Member

    var body: some View {
        HStack(spacing: 16) {

            Text(member.avatarEmoji)
                .font(.system(size: 26))
                .frame(width: 48, height: 48)
                .background(Color(.systemGray6))
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(
                            Color.gray.opacity(0.15),
                            lineWidth: 1
                        )
                }

            Text(member.displayName)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.black)

            if member.isHost {
                Text("Host")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 80)
        .background(.white)
        .clipShape(
            RoundedRectangle(cornerRadius: 24)
        )
    }
}


// MARK: - Preview

#Preview {
    let store = MockRoomStore(rooms: MockData.rooms())
    PeopleListSheet(store: store, roomID: store.rooms[0].id)
}
