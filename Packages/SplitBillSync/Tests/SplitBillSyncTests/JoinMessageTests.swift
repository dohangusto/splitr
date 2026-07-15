import Foundation
import Testing
@testable import SplitBillSync

@Suite("JoinMessage codec")
struct JoinMessageTests {

    @Test("Discovery token round trip")
    func tokenRoundTrip() throws {
        let token = Data([0x01, 0x02, 0xFF, 0x00, 0x7A])
        let decoded = try JoinMessage.decoded(from: try JoinMessage.discoveryToken(token).encoded())
        #expect(decoded == .discoveryToken(token))
    }

    @Test("Join request round trip preserves name and emoji")
    func joinRequestRoundTrip() throws {
        let request = JoinRequest(displayName: "Dita", avatarEmoji: "🐱")
        let decoded = try JoinMessage.decoded(from: try JoinMessage.joinRequest(request).encoded())
        #expect(decoded == .joinRequest(request))
    }

    @Test("Invitation round trip preserves URL and host-assigned member ID")
    func invitationRoundTrip() throws {
        let invitation = JoinInvitation(
            roomID: UUID(),
            roomName: "Makan Malam Tim",
            shareURL: URL(string: "https://www.icloud.com/share/abc#Makan_Malam")!,
            memberID: UUID()
        )
        let decoded = try JoinMessage.decoded(from: try JoinMessage.invitation(invitation).encoded())
        #expect(decoded == .invitation(invitation))
    }

    @Test("Garbage data throws instead of crashing")
    func garbageThrows() {
        #expect(throws: (any Error).self) {
            _ = try JoinMessage.decoded(from: Data("not json at all".utf8))
        }
        #expect(throws: (any Error).self) {
            _ = try JoinMessage.decoded(from: Data("{\"unknown\":{}}".utf8))
        }
    }
}
