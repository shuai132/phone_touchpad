import Foundation
import Network
import Security
import CryptoKit

struct PairingSecret: Equatable {
    let bytes: Data
    var text: String { bytes.map { String(format: "%02x", $0) }.joined() }
    static func generate() -> PairingSecret {
        let key = SymmetricKey(size: .bits256)
        return PairingSecret(bytes: key.withUnsafeBytes { Data($0) })
    }
    init(text: String) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count == 64, text.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            throw TransportError.invalidSecret
        }
        var bytes = Data()
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let value = UInt8(text[index..<next], radix: 16) else { throw TransportError.invalidSecret }
            bytes.append(value); index = next
        }
        self.bytes = bytes
    }
    private init(bytes: Data) { self.bytes = bytes }
}

enum TransportError: Error { case invalidSecret }

enum SecureTransport {
    static func isAuthenticatedPSK(_ connection: NWConnection) -> Bool {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else { return false }
        return sec_protocol_metadata_get_negotiated_tls_protocol_version(metadata.securityProtocolMetadata) == .TLSv12 && sec_protocol_metadata_get_negotiated_tls_ciphersuite(metadata.securityProtocolMetadata).rawValue == 0x00A8
    }
    static func parameters(secret: PairingSecret) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        // RFC 5487 TLS_PSK_WITH_AES_128_GCM_SHA256; absent from Swift's named enum cases.
        // Network.framework's legacy PSK path uses TLS 1.2. Never accept another negotiated suite.
        sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: 0x00A8)!)
        let key = secret.bytes.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data("phone-touchpad-v1".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(options, key as __DispatchData, identity as __DispatchData)
        sec_protocol_options_set_tls_pre_shared_key_identity_hint(options, identity as __DispatchData)
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.allowLocalEndpointReuse = true
        return parameters
    }
}
