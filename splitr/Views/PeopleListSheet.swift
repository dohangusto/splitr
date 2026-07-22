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
    @State private var memberToRemove: Member?

    private var room: Room? { store.room(withID: roomID) }
    /// New members can join only before settling starts.
    private var canAdd: Bool {
        room.map { $0.state == .open || $0.state == .claiming } ?? false
    }
    /// Only the host removes people, and only while the room is still live.
    private var canManageMembers: Bool {
        guard let room else { return false }
        return store.actingMemberID(in: roomID) == room.hostMemberID && room.state != .closed
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: - Header
            ZStack {
                Text("List people")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack {
                    // Close Button
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(.title2, weight: .regular))
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
                                .font(.system(.headline, weight: .medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 20)
                                .frame(minHeight: 56)
                                .background(Color(.secondarySystemGroupedBackground))
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
                        PersonRow(
                            member: member,
                            // Host can remove any non-host member; never itself.
                            onRemove: (canManageMembers && !member.isHost)
                                ? { memberToRemove = member }
                                : nil
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
            }
        }
        .background(Color(.systemGroupedBackground))
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
            if let room {
                NearbyHostView(
                    store: store,
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
        .alert(item: $memberToRemove) { member in
            Alert(
                title: Text("Remove \(member.displayName)?"),
                message: Text("All items they claimed — including their share of split items — will return to unclaimed."),
                primaryButton: .destructive(Text("Remove")) {
                    store.kick(memberID: member.id, roomID: roomID)
                },
                secondaryButton: .cancel()
            )
        }
    }

    /// Allows the host to choose between Nearby Interaction, invite link, or manual entry.
    private func addNewTapped() {
        showAddOptions = true
    }

    private func fetchInviteURL() {
        Task {
            inviteURL = await store.inviteURL(roomID: roomID)
        }
    }
}


// MARK: - Person Row

struct PersonRow: View {

    let member: Member
    /// Non-nil only when the acting host may remove this person. When set, a
    /// trailing remove control appears; the confirmation lives in the sheet.
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 16) {

            Group {
                if let uiImage = UIImage(named: member.avatarEmoji) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(member.avatarEmoji)
                        .font(.system(.title2))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemGray6))
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(
                        Color.gray.opacity(0.15),
                        lineWidth: 1
                    )
            }

            Text(member.displayName)
                .font(.system(.headline, weight: .medium))
                .foregroundStyle(.primary)

            if member.isHost {
                Text("Host")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let onRemove {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(.title2))
                        .foregroundStyle(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(member.displayName)")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 80)
        .background(Color(.secondarySystemGroupedBackground))
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
