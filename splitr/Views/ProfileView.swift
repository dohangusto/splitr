import SwiftUI

/// The user's default identity (display name + emoji), the prefill for every
/// join and create. Deliberately not an account: each room still keeps its
/// own per-room identity with a host-assigned ID.
struct UserProfile {
    var name: String
    var emoji: String

    static func load() -> UserProfile {
        UserProfile(
            name: UserDefaults.standard.string(forKey: "splitr.user_display_name") ?? "",
            emoji: UserDefaults.standard.string(forKey: "splitr.user_avatar_emoji") ?? "🙂"
        )
    }

    func save() {
        UserDefaults.standard.set(
            name.trimmingCharacters(in: .whitespaces),
            forKey: "splitr.user_display_name"
        )
        UserDefaults.standard.set(emoji, forKey: "splitr.user_avatar_emoji")
    }
}

/// Standalone profile screen, pushed from Home. Edits stay local until the
/// confirm button saves them and pops back.
struct ProfileView: View {
    @Binding var profile: UserProfile

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "🙂"

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    Text(emoji)
                        .font(.system(size: 64))
                        .padding(20)
                        .background(.tint.opacity(0.12), in: .circle)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            Section("Display name") {
                TextField("How friends see you", text: $name)
            }
            Section("Avatar") {
                EmojiPicker(selection: $emoji)
            }
            Section {
            } footer: {
                Text("This is how you appear when you join or create a room. You can still change it per room.")
            }
        }
        .navigationTitle("Profile")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .confirm) {
                    profile = UserProfile(name: trimmedName, emoji: emoji)
                    profile.save()
                    dismiss()
                }
                .disabled(trimmedName.isEmpty)
            }
        }
        .onAppear {
            name = profile.name
            emoji = profile.emoji
        }
    }
}

#Preview {
    @Previewable @State var profile = UserProfile(name: "Hano", emoji: "🧑‍🍳")
    NavigationStack {
        ProfileView(profile: $profile)
    }
}
