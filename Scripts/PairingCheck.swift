import Foundation

@main struct PairingCheck {
    static func main() throws {
        let secret = PairingSecret.generate()
        precondition(secret.text.count == 64 && secret.bytes.count == 32)
        let upper = try PairingSecret(text: secret.text.uppercased())
        precondition(upper == secret)
        precondition(PairingSecret.generate() != secret)
        for invalid in ["123456", String(repeating: "g", count: 64), String(repeating: "é", count: 64), secret.text + "00"] {
            do { _ = try PairingSecret(text: invalid); fatalError("Invalid key accepted") } catch {}
        }
        let invitation = PairingInvitation(name: "我的 Mac & Work + 1", secret: secret)
        let decoded = try PairingInvitation(text: invitation.url.absoluteString)
        precondition(decoded.name == invitation.name && decoded.secret == secret)
        for invalid in ["https://example.com", invitation.url.absoluteString.replacingOccurrences(of: "v=1", with: "v=2"), invitation.url.absoluteString + "&key=" + secret.text] {
            do { _ = try PairingInvitation(text: invalid); fatalError("Invalid invitation accepted") } catch {}
        }
        print("Pairing key and invitation checks passed")
    }
}
