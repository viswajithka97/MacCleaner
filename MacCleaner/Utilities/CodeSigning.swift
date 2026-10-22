import Foundation
import Security

struct CodeSignInfo: Hashable {
    var signed: Bool
    var valid: Bool
    var teamIdentifier: String?
    var signingAuthority: String?
    var isApple: Bool
}

enum CodeSigning {
    static func inspect(path: String) -> CodeSignInfo {
        let url = URL(fileURLWithPath: path)
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return CodeSignInfo(signed: false, valid: false, teamIdentifier: nil, signingAuthority: nil, isApple: false)
        }

        let valid = SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess

        var info: CFDictionary?
        SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        let dict = info as? [String: Any] ?? [:]
        let ident = dict[kSecCodeInfoTeamIdentifier as String] as? String
        let authorities = dict[kSecCodeInfoCertificates as String] as? [SecCertificate]
        var authorityName: String?
        if let cert = authorities?.first {
            var name: CFString?
            SecCertificateCopyCommonName(cert, &name)
            authorityName = name as String?
        }

        let apple = (ident == "Apple") || (authorityName?.contains("Apple") == true) ||
            (dict[kSecCodeInfoIdentifier as String] as? String)?.hasPrefix("com.apple.") == true

        let signed = dict[kSecCodeInfoIdentifier as String] != nil || ident != nil || authorityName != nil
        return CodeSignInfo(signed: signed, valid: valid, teamIdentifier: ident, signingAuthority: authorityName, isApple: apple)
    }

    static func verifyWithCodesign(_ path: String) -> Bool {
        guard let result = try? ProcessRunner.run("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", path]) else {
            return false
        }
        return result.exitCode == 0
    }
}
