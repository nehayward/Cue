//
//  ThirdPartyMediaServerDecrypter.swift
//  Listener
//
//  Created by Nick Hayward on 6/13/25.
//


import Foundation
import CommonCrypto

final class ThirdPartyMediaServerDecrypter {
    static let ids: Data = Data([
        26, 1, 167, 49, 201, 110, 158, 189,
        232, 71, 81, 130, 178, 116, 183, 14
    ])
    
    // MARK: - MD5 Hash
    @available(iOS, introduced: 2.0, deprecated: 13.0, message: "MD5 is deprecated, but used here for compatibility.")
    private func md5(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_MD5($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
    
    // MARK: - AES CBC Decrypt
    private func aesCBCDecrypt(data: Data, key: Data, iv: Data) throws -> Data {
        var outLength = Int(0)
        var outBytes = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128)
        var keyBytes = [UInt8](key)
        var ivBytes = [UInt8](iv)
        let status = data.withUnsafeBytes { dataBytes in
            CCCrypt(
                CCOperation(kCCDecrypt),
                CCAlgorithm(kCCAlgorithmAES),
                CCOptions(kCCOptionPKCS7Padding),
                &keyBytes, key.count,
                &ivBytes,
                dataBytes.baseAddress, data.count,
                &outBytes, outBytes.count,
                &outLength
            )
        }
        guard status == kCCSuccess else {
            throw NSError(domain: "AES", code: Int(status), userInfo: nil)
        }
        return Data(bytes: outBytes, count: outLength)
    }
    
    // MARK: - Item Handler
//    ThirdPartyMediaServerDecrypter().handleItem(sender: Data("Sonos_GBw44sBd7swQ55xlbUSTzNmTlp".utf8), input: input)

    func handleItem(householdID: Data, encodedInput: String) -> String? {
        guard encodedInput.hasPrefix("2:") else { return nil }
        // Combine sender and ids
        var span1 = Data()
        span1.append(householdID)
        span1.append(ThirdPartyMediaServerDecrypter.ids)
        // MD5 hash of span1
        let array2 = md5(span1)
        // Decode base64 from input (after "2:")
        let base64String = String(encodedInput.dropFirst(2))
        guard let numArray1 = Data(base64Encoded: base64String) else { return nil }
        guard numArray1.count >= 16 else { return nil }
        // span3 = first 16 bytes of numArray1 + array2
        var span3 = Data()
        span3.append(numArray1.prefix(16))
        span3.append(array2)
        // MD5 hash of span3
        let numArray2 = md5(span3)
        // array4 = first 16 bytes of numArray1 (IV)
        let array4 = numArray1.prefix(16)
        // array3 = bytes after first 16 (ciphertext)
        let array3 = numArray1.dropFirst(16)
        do {
            let decrypted = try aesCBCDecrypt(data: array3, key: numArray2, iv: array4)
            // Remove last 4 bytes (as in original)
            let resultData = decrypted.dropLast(4)
            let output = String(decoding: resultData, as: UTF8.self)
            return output
        } catch {
            return nil
        }
    }
}
