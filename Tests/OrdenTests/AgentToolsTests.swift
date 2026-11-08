import XCTest
@testable import OrdenCore

final class AgentToolsTests: XCTestCase {
    func testInferArchivosHoy() {
        let s = AgentIntentParser.inferShortcut(from: "archivos de hoy")
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.categories, [])
        XCTAssertEqual(s?.dateWindow, .today)
        XCTAssertEqual(s?.title, "Archivos hoy")
    }

    func testPlanCreateFolder() {
        let plan = AgentIntentParser.plan(from: "crea carpeta Facturas", currentPath: "/tmp/demo")
        XCTAssertTrue(plan.needsApproval)
        XCTAssertEqual(plan.steps.first?.name, .createDirectory)
        XCTAssertEqual(plan.steps.first?.arguments["name"], "Facturas")
        XCTAssertEqual(plan.steps.first?.arguments["parent"], "/tmp/demo")
    }

    func testPlanMoveToRelative() {
        let plan = AgentIntentParser.plan(from: "mueve a Fotos", currentPath: "/Users/me/Downloads")
        XCTAssertEqual(plan.steps.first?.name, .moveFiles)
        XCTAssertEqual(plan.steps.first?.arguments["destination"], "/Users/me/Downloads/Fotos")
    }

    func testPlanOrganize() {
        let plan = AgentIntentParser.plan(from: "organiza por tipo", currentPath: "/tmp")
        XCTAssertEqual(plan.steps.first?.name, .organizeFiles)
        XCTAssertTrue(plan.needsApproval)
    }

    func testLabelSpanishCreate() {
        let step = AgentToolCall(
            name: .createDirectory,
            arguments: ["name": "PDFs"],
            risk: .write
        )
        XCTAssertEqual(step.labelSpanish, "Crear carpeta «PDFs»")
    }

    func testPlanRenamePreservesExtension() {
        let plan = AgentIntentParser.plan(from: "renombrar a QA-renombrado.txt", currentPath: "/tmp")
        XCTAssertEqual(plan.steps.first?.name, .renameFiles)
        XCTAssertEqual(plan.steps.first?.arguments["newName"], "QA-renombrado.txt")
        XCTAssertTrue(plan.needsApproval)
    }

    func testPlanRenamePreservesCompoundExtension() {
        let plan = AgentIntentParser.plan(from: "renombra a archivo.tar.gz", currentPath: "/tmp")
        XCTAssertEqual(plan.steps.first?.name, .renameFiles)
        XCTAssertEqual(plan.steps.first?.arguments["newName"], "archivo.tar.gz")
    }

    func testPlanRenameTrimsTrailingPunctuation() {
        let plan = AgentIntentParser.plan(from: "renombrar a QA-renombrado.txt.", currentPath: "/tmp")
        XCTAssertEqual(plan.steps.first?.arguments["newName"], "QA-renombrado.txt")
    }

    func testPlanRenameWithoutExtension() {
        let plan = AgentIntentParser.plan(from: "cambiar nombre a reporte sin extension", currentPath: "/tmp")
        XCTAssertEqual(plan.steps.first?.arguments["newName"], "reporte sin extension")
    }

    func testPlanRenameWithQuotedNames() {
        let plan1 = AgentIntentParser.plan(from: "renombrar a \"Mi Documento 2026.pdf\"", currentPath: "/tmp")
        XCTAssertEqual(plan1.steps.first?.arguments["newName"], "Mi Documento 2026.pdf")

        let plan2 = AgentIntentParser.plan(from: "renombrar a ‘Otro Archivo.docx’", currentPath: "/tmp")
        XCTAssertEqual(plan2.steps.first?.arguments["newName"], "Otro Archivo.docx")
    }
}

final class RecursiveContentSearchTests: XCTestCase {
    func testContentSearchFindsNeedleInsideTxt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ordena-content-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("nota.txt")
        try "Hola IBAN secreto 123".write(to: file, atomically: true, encoding: .utf8)
        let decoy = root.appendingPathComponent("otro.txt")
        try "nada relevante".write(to: decoy, atomically: true, encoding: .utf8)

        var hits: [SearchHit] = []
        RecursiveSearch.run(
            query: .init(text: "IBAN", root: root.path, searchContent: true),
            isCancelled: { false },
            onProgress: { _ in },
            onHit: { hits.append($0) }
        )
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.name, "nota.txt")
    }
}
