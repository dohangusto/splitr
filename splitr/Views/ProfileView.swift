import SwiftUI

// MARK: - AvatarCatalog

/// All available avatar image assets.
enum AvatarCatalog {
    /// Number of "AvatarN" assets in Assets.xcassets.
    static let count = 12

    /// "Avatar1" ... "Avatar12"
    static let allNames: [String] = (1...count).map { "Avatar\($0)" }

    /// Fallback avatar when none is set.
    static let defaultName = "Avatar1"
}

// MARK: - UserProfile

struct UserProfile {
    var name: String

    /// Selected avatar's asset name (e.g. "Avatar3").
    var avatar: String

    private static let nameKey = "splitr.user_display_name"
    private static let avatarKey = "splitr.user_avatar_name"

    /// Old emoji storage key, kept only to clear it on save.
    private static let legacyEmojiKey = "splitr.user_avatar_emoji"

    static func load() -> UserProfile {
        let defaults = UserDefaults.standard
        let name = defaults.string(forKey: nameKey) ?? ""

        if let storedAvatar = defaults.string(forKey: avatarKey),
           AvatarCatalog.allNames.contains(storedAvatar) {
            return UserProfile(name: name, avatar: storedAvatar)
        }

        return UserProfile(name: name, avatar: AvatarCatalog.defaultName)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(name.trimmingCharacters(in: .whitespaces), forKey: Self.nameKey)
        defaults.set(avatar, forKey: Self.avatarKey)
        defaults.removeObject(forKey: Self.legacyEmojiKey)
    }
}

// MARK: - ProfileView

/// Standalone profile screen, pushed from Home. Edits stay local until the
/// confirm button saves them and pops back.
struct ProfileView: View {
    @Binding var profile: UserProfile

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var avatar = AvatarCatalog.defaultName

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    AvatarImage(name: avatar, size: 104)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            Section("Display name") {
                TextField("How friends see you", text: $name)
            }
            Section("Avatar") {
                AvatarPicker(selection: $avatar)
                    .listRowInsets(EdgeInsets())
            }
        }
        // Hide the default Form background so the asset color shows through.
        .scrollContentBackground(.hidden)
        .background(Color("PrimaryBackground"))
        .navigationTitle("Profile")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(role: .confirm) {
                    profile = UserProfile(name: trimmedName, avatar: avatar)
                    profile.save()
                    dismiss()
                }
                .disabled(trimmedName.isEmpty)
            }
        }
        .onAppear {
            name = profile.name
            avatar = profile.avatar
        }
    }
}

// MARK: - AvatarImage

/// Circular avatar image for a given asset name.
private struct AvatarImage: View {
    let name: String
    var size: CGFloat = 60

    var body: some View {
        Group {
            if let uiImage = UIImage(named: name) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                // Fallback if the asset name doesn't resolve.
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(size * 0.15)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - AvatarPicker

/// Grid of selectable avatars.
struct AvatarPicker: View {
    @Binding var selection: String
    var names: [String] = AvatarCatalog.allNames

    private let columns = [GridItem(.adaptive(minimum: 64, maximum: 72), spacing: 16)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(names, id: \.self) { name in
                avatarButton(for: name)
            }
        }
        .padding(.vertical, 12)
    }

    private func avatarButton(for name: String) -> some View {
        let isSelected = name == selection
        return Button {
            withAnimation(.snappy) {
                selection = name
            }
        } label: {
            AvatarImage(name: name, size: 60)
                .overlay(
                    // Ring indicates the currently selected avatar.
                    Circle()
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                )
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white, Color.accentColor)
                            .background(Circle().fill(.white).padding(2))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    @Previewable @State var profile = UserProfile(name: "Hano", avatar: "Avatar3")
    NavigationStack {
        ProfileView(profile: $profile)
    }
}
