import XCTest
@testable import TerminalThingy

final class CryptoServiceTests: XCTestCase {

    func testDeriveKeyProducesSameResultForSameInputs() {
        let key1 = CryptoService.deriveKey(code: "123456", saltHex: "abababababababababababababababab")
        let key2 = CryptoService.deriveKey(code: "123456", saltHex: "abababababababababababababababab")
        XCTAssertEqual(key1, key2)
    }

    func testDeriveKeyProducesDifferentResultForDifferentCodes() {
        let salt = "abababababababababababababababab"
        let key1 = CryptoService.deriveKey(code: "123456", saltHex: salt)
        let key2 = CryptoService.deriveKey(code: "654321", saltHex: salt)
        XCTAssertNotEqual(key1, key2)
    }

    func testEncryptDecryptRoundTrip() throws {
        let key = CryptoService.deriveKey(code: "123456", saltHex: "abababababababababababababababab")
        let plaintext = #"{"type":"state","cols":80,"rows":24}"#
        let encrypted = try CryptoService.encrypt(plaintext.data(using: .utf8)!, key: key)
        let decrypted = try CryptoService.decrypt(base64Payload: encrypted, key: key)
        let decryptedString = String(data: decrypted, encoding: .utf8)!
        XCTAssertEqual(decryptedString, plaintext)
    }

    func testDecryptWithWrongKeyThrows() {
        let key1 = CryptoService.deriveKey(code: "123456", saltHex: "abababababababababababababababab")
        let key2 = CryptoService.deriveKey(code: "654321", saltHex: "abababababababababababababababab")
        let plaintext = "hello".data(using: .utf8)!
        let encrypted = try! CryptoService.encrypt(plaintext, key: key1)
        XCTAssertThrowsError(try CryptoService.decrypt(base64Payload: encrypted, key: key2))
    }

    func testEncryptProducesDifferentOutputEachTime() {
        let key = CryptoService.deriveKey(code: "123456", saltHex: "abababababababababababababababab")
        let plaintext = "hello".data(using: .utf8)!
        let c1 = try! CryptoService.encrypt(plaintext, key: key)
        let c2 = try! CryptoService.encrypt(plaintext, key: key)
        XCTAssertNotEqual(c1, c2)
    }
}
