import Foundation
import CryptoKit

enum CryptoService {

    /// Derive a 32-byte AES-256 key from a code and hex-encoded salt using HKDF-SHA256.
    /// Must produce identical output to the Node.js CLI's `deriveKey(code, salt)`.
    static func deriveKey(code: String, saltHex: String) -> SymmetricKey {
        let ikm = SymmetricKey(data: code.data(using: .utf8)!)
        let salt = Data(hexString: saltHex)!
        let info = "terminal-thingy".data(using: .utf8)!
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: salt,
            info: info,
            outputByteCount: 32
        )
    }

    /// Encrypt data using AES-256-GCM. Returns base64(nonce[12] + tag[16] + ciphertext).
    /// Wire format matches the Node.js CLI's `encrypt()`.
    static func encrypt(_ plaintext: Data, key: SymmetricKey) throws -> String {
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        // sealedBox.combined = nonce(12) + ciphertext + tag(16)
        // Node.js format = nonce(12) + tag(16) + ciphertext
        // We need to reorder.
        let nonce = sealedBox.nonce
        let ciphertext = sealedBox.ciphertext
        let tag = sealedBox.tag

        var data = Data()
        data.append(contentsOf: nonce)      // 12 bytes
        data.append(tag)                     // 16 bytes
        data.append(ciphertext)              // variable
        return data.base64EncodedString()
    }

    /// Decrypt a base64-encoded payload from the Node.js CLI.
    /// Wire format: base64(nonce[12] + tag[16] + ciphertext).
    static func decrypt(base64Payload: String, key: SymmetricKey) throws -> Data {
        guard let data = Data(base64Encoded: base64Payload) else {
            throw CryptoError.invalidBase64
        }
        guard data.count >= 28 else { // 12 nonce + 16 tag minimum
            throw CryptoError.payloadTooShort
        }

        let nonce = try AES.GCM.Nonce(data: data[0..<12])
        let tag = data[12..<28]
        let ciphertext = data[28...]

        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealedBox, using: key)
    }

    enum CryptoError: Error {
        case invalidBase64
        case payloadTooShort
    }
}

extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
