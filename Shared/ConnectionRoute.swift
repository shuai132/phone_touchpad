import Foundation
import Network

/// Connection establishment is independent of input messages and their encoding.
enum ConnectionRoute {
    case localNetwork(host: String, port: UInt16 = 49271)
    // A separately established forwarder supplies this endpoint. USB forwarding
    // and device discovery are not implemented by this route. TLS remains enabled.
    case forwardedTCP(host: String, port: UInt16)

    func endpoint() throws -> NWEndpoint {
        let host: String
        let port: UInt16
        switch self {
        case let .localNetwork(value, valuePort):
            host = value.trimmingCharacters(in: .whitespacesAndNewlines); port = valuePort
        case let .forwardedTCP(value, valuePort):
            host = value.trimmingCharacters(in: .whitespacesAndNewlines); port = valuePort
        }
        guard !host.isEmpty, port > 0, let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw URLError(.badURL)
        }
        return .hostPort(host: NWEndpoint.Host(host), port: endpointPort)
    }
}
