import Foundation
import Security

/// What we learned about a program's code signature.
struct SignatureInfo {
    enum Status: Equatable {
        case valid
        case unsigned
        case invalid(String)
        case missing          // the file does not exist
    }

    var status: Status
    var signer: String?       // e.g. "Developer ID Application: Google LLC (EQHXZ8M8AV)"
    var teamID: String?
    var isApple: Bool

    /// Short text for the UI.
    var summary: String {
        switch status {
        case .valid: return isApple ? "Apple" : (signer ?? teamID ?? "Signed")
        case .unsigned: return "Unsigned"
        case .invalid(let why): return "Invalid signature (\(why))"
        case .missing: return "Missing"
        }
    }
}

/// Checks code signatures with the Security framework (the same engine `codesign --verify` uses).
enum CodeSign {

    // Raw flag values from <Security/CSCommon.h>.
    private static let checkAllArchitectures = SecCSFlags(rawValue: 1 << 0)
    private static let doNotValidateResources = SecCSFlags(rawValue: 1 << 2)
    private static let signingInformation = SecCSFlags(rawValue: 1 << 1)

    /// Requirement that only matches code signed by Apple itself.
    private static let appleRequirement: SecRequirement? = {
        var requirement: SecRequirement?
        SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement)
        return requirement
    }()

    /// - Parameter fast: skip hashing every resource file (much faster for big apps like Xcode;
    ///   the executable and the signature itself are still verified).
    static func check(path: String, fast: Bool = false) -> SignatureInfo {
        guard FileManager.default.fileExists(atPath: path) else {
            return SignatureInfo(status: .missing, signer: nil, teamID: nil, isApple: false)
        }
        var staticCode: SecStaticCode?
        let url = URL(fileURLWithPath: path) as CFURL
        guard SecStaticCodeCreateWithPath(url, [], &staticCode) == errSecSuccess, let code = staticCode else {
            return SignatureInfo(status: .unsigned, signer: nil, teamID: nil, isApple: false)
        }

        let flags = fast ? checkAllArchitectures.union(doNotValidateResources) : checkAllArchitectures
        let validity = SecStaticCodeCheckValidity(code, flags, nil)
        let status: SignatureInfo.Status
        switch validity {
        case errSecSuccess: status = .valid
        case errSecCSUnsigned: status = .unsigned
        default:
            let message = SecCopyErrorMessageString(validity, nil) as String? ?? "error \(validity)"
            status = .invalid(message)
        }

        var signer: String?
        var teamID: String?
        var info: CFDictionary?
        if status != .unsigned,
           SecCodeCopySigningInformation(code, signingInformation, &info) == errSecSuccess,
           let dict = info as? [String: Any] {
            teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String
            if let certs = dict[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certs.first {
                signer = SecCertificateCopySubjectSummary(leaf) as String?
            }
        }

        var isApple = false
        if status == .valid, let req = appleRequirement {
            isApple = SecStaticCodeCheckValidity(code, doNotValidateResources, req) == errSecSuccess
        }
        return SignatureInfo(status: status, signer: signer, teamID: teamID, isApple: isApple)
    }
}
