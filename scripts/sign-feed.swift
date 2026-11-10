#!/usr/bin/env swift
import CryptoKit
import Foundation

func readPrivateKeyHex() -> String? {
    // 1. Intentar desde Keychain: security find-generic-password -s findaro-update-signing -a release -w
    let pipe = Pipe()
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = ["find-generic-password", "-s", "findaro-update-signing", "-a", "release", "-w"]
    p.standardOutput = pipe
    p.standardError = Pipe()
    do {
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                return str
            }
        }
    } catch {}

    // 2. Intentar desde ~/.findaro/update_signing_key
    let home = FileManager.default.homeDirectoryForCurrentUser
    let keyFile = home.appendingPathComponent(".findaro/update_signing_key")
    if let str = try? String(contentsOf: keyFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
        return str
    }

    return nil
}

func dataFromHex(_ hex: String) -> Data? {
    let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.count % 2 == 0 else { return nil }
    var data = Data(capacity: clean.count / 2)
    var index = clean.startIndex
    while index < clean.endIndex {
        let nextIndex = clean.index(index, offsetBy: 2)
        guard let b = UInt8(clean[index..<nextIndex], radix: 16) else { return nil }
        data.append(b)
        index = nextIndex
    }
    return data
}

guard CommandLine.arguments.count >= 3 else {
    fputs("Uso: \(CommandLine.arguments[0]) <ruta/a/latest.json> <ruta/a/latest.json.sig>\n", stderr)
    exit(1)
}

let jsonPath = CommandLine.arguments[1]
let sigPath = CommandLine.arguments[2]

guard let privHex = readPrivateKeyHex() else {
    fputs("ERROR: No se encontró la clave privada de firma de actualizaciones.\n", stderr)
    fputs("Buscada en Keychain (servicio 'findaro-update-signing', cuenta 'release') y en ~/.findaro/update_signing_key\n", stderr)
    exit(1)
}

guard let privData = dataFromHex(privHex), privData.count == 32 else {
    fputs("ERROR: La clave privada encontrada tiene un formato inválido (debe ser 32 bytes hex).\n", stderr)
    exit(1)
}

let jsonURL = URL(fileURLWithPath: jsonPath)
guard let jsonData = try? Data(contentsOf: jsonURL) else {
    fputs("ERROR: No se pudo leer el archivo \(jsonPath)\n", stderr)
    exit(1)
}

do {
    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privData)
    let signature = try privateKey.signature(for: jsonData)

    // Auto-verificación antes de escribir
    guard privateKey.publicKey.isValidSignature(signature, for: jsonData) else {
        fputs("ERROR: Falló la auto-verificación de la firma generada.\n", stderr)
        exit(1)
    }

    let b64Sig = signature.base64EncodedString() + "\n"
    let sigURL = URL(fileURLWithPath: sigPath)
    try b64Sig.write(to: sigURL, atomically: true, encoding: .utf8)
    print("Firma Ed25519 generada con éxito en \(sigPath)")
} catch {
    fputs("ERROR al firmar: \(error.localizedDescription)\n", stderr)
    exit(1)
}
