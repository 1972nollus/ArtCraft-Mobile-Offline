import Foundation
import ZIPFoundation

enum CoreMLModelInstaller {
    struct Result {
        let id: String
        let report: CoreMLModelValidator.Report
    }

    static func install(from source: URL, modelsDirectory: URL, preferredID: String? = nil) throws -> Result {
        let fm = FileManager.default
        let baseName = preferredID ?? source.deletingPathExtension().lastPathComponent
        let sanitized = String(baseName.map { c in
            c.isASCII && (c.isLetter || c.isNumber || c == "-" || c == "_") ? c : "-"
        }.prefix(72))
        guard !sanitized.isEmpty else {
            throw NSError(domain: "ModelInstaller", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Ongeldige modelnaam"])
        }
        let stage = modelsDirectory.appendingPathComponent("Staging-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }

        let sourceFolder: URL
        if source.pathExtension.lowercased() == "zip" {
            let unpack = stage.appendingPathComponent("Unpacked", isDirectory: true)
            try fm.createDirectory(at: unpack, withIntermediateDirectories: true)
            try fm.unzipItem(at: source, to: unpack)
            sourceFolder = unpack
        } else if source.hasDirectoryPath {
            sourceFolder = source
        } else {
            throw NSError(domain: "ModelInstaller", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Selecteer een ZIP of Resources-map"])
        }

        guard let resources = CoreMLModelValidator.findResources(in: sourceFolder) else {
            throw NSError(domain: "ModelInstaller", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Geen gecompileerde Core ML Resources gevonden"])
        }
        let report = CoreMLModelValidator.check(resources)
        guard report.isComplete else {
            throw NSError(domain: "ModelInstaller", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: report.details])
        }

        let root = modelsDirectory.appendingPathComponent("Installed", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var candidate = sanitized
        var count = 2
        while fm.fileExists(atPath: root.appendingPathComponent(candidate).path) {
            candidate = sanitized + "-" + String(count)
            count += 1
        }

        let incoming = stage.appendingPathComponent("Ready", isDirectory: true)
        try fm.createDirectory(at: incoming, withIntermediateDirectories: true)
        try fm.copyItem(at: resources, to: incoming.appendingPathComponent("Resources", isDirectory: true))
        try fm.moveItem(at: incoming, to: root.appendingPathComponent(candidate, isDirectory: true))
        return Result(id: candidate, report: report)
    }
}
