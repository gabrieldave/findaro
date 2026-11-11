import Foundation
import OrdenCore
import Security
import Darwin

#if !DEBUG
/// Blindaje Release: anti-attach + comprobación ligera de bundle/firma Developer ID.
enum ReleaseIntegrity {
    static func hardenAtLaunch() {
        denyDebuggerAttach()
        verifyBundleIntegrity()
    }

    private static func denyDebuggerAttach() {
        typealias PtraceFn = @convention(c) (Int32, pid_t, UnsafeMutableRawPointer?, Int) -> Int32
        let PT_DENY_ATTACH: Int32 = 31
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "ptrace") else { return } // RTLD_DEFAULT
        let ptrace = unsafeBitCast(sym, to: PtraceFn.self)
        _ = ptrace(PT_DENY_ATTACH, 0, nil, 0)
    }

    private static func verifyBundleIntegrity() {
        guard Bundle.main.bundleIdentifier == "app.findaro.files" else {
            LicenseGate.setWriteAllowed(false)
            return
        }

        guard let url = Bundle.main.bundleURL as CFURL? else { return }
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url, [], &staticCode)
        guard createStatus == errSecSuccess, let code = staticCode else { return }

        // Solo aplica el requisito de Team ID si el binario ya está firmado con Developer ID.
        // Builds locales ad-hoc no deben quedar en solo-lectura por este check.
        var signingInfo: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfo)
        guard infoStatus == errSecSuccess,
              let info = signingInfo as? [String: Any],
              let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
              !certs.isEmpty
        else {
            return
        }

        var requirement: SecRequirement?
        let reqStatus = SecRequirementCreateWithString(
            "anchor apple generic and certificate leaf[subject.OU] = \"YH6W55MP95\"" as CFString,
            [],
            &requirement
        )
        guard reqStatus == errSecSuccess, let requirement else { return }

        let check = SecStaticCodeCheckValidity(code, [], requirement)
        if check != errSecSuccess {
            LicenseGate.setWriteAllowed(false)
        }
    }
}
#endif
