import Foundation

struct PairingInvitation {
    let name: String
    let secret: PairingSecret
    var url: URL {
        var components = URLComponents()
        components.scheme = "phonetouchpad"; components.host = "pair"
        components.queryItems = [URLQueryItem(name: "v", value: "1"), URLQueryItem(name: "name", value: name), URLQueryItem(name: "key", value: secret.text)]
        return components.url!
    }
    init(name: String, secret: PairingSecret) { self.name = name; self.secret = secret }
    init(text: String) throws {
        guard text.utf8.count < 2048, let components = URLComponents(string: text),
              components.scheme == "phonetouchpad", components.host == "pair",
              let items = components.queryItems, items.count == 3,
              items.first(where: { $0.name == "v" })?.value == "1",
              let name = items.first(where: { $0.name == "name" })?.value, !name.isEmpty, name.utf8.count <= 255,
              let key = items.first(where: { $0.name == "key" })?.value else { throw TransportError.invalidSecret }
        self.name = name; self.secret = try PairingSecret(text: key)
    }
}
