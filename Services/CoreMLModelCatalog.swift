import Foundation

struct ModelPreset: Identifiable {
    let id: String
    let title: String
    let url: String
    let note: String
    static let realisticVision = ModelPreset(
        id: "realisticvision-v20",
        title: "Realistic Vision v2.0 · split_einsum",
        url: "https://huggingface.co/coreml-community/coreml-realisticVision-v20/resolve/main/split_einsum/realisticVision-v20_split-einsum.zip",
        note: "1,98 GB · Core ML · geen chunked UNet. iPhone 14-compatibiliteit onzeker."
    )
    static let all: [ModelPreset] = [.realisticVision]
}

enum CoreMLModelValidator {
    struct Report {
        var isComplete: Bool
        var isRecommendedForIPhone: Bool
        var details: String
    }

    static func check(_ folder: URL) -> Report {
        let fm = FileManager.default
        let has: (String) -> Bool = { fm.fileExists(atPath: folder.appendingPathComponent($0).path) }
        let required = ["TextEncoder.mlmodelc", "VAEDecoder.mlmodelc", "vocab.json"]
        let missing = required.filter { !has($0) }
        let merges = has("merges.txt") || has("merges.text")
        let chunked = has("UnetChunk1.mlmodelc") && has("UnetChunk2.mlmodelc")
        let regular = has("Unet.mlmodelc")
        var issues = missing
        if !merges { issues.append("merges.txt") }
        if !chunked && !regular { issues.append("Unet.mlmodelc / UnetChunk1+2") }
        if !issues.isEmpty {
            return Report(isComplete: false, isRecommendedForIPhone: false,
                          details: "Ontbrekende onderdelen: " + issues.joined(separator: ", "))
        }
        if !chunked {
            return Report(isComplete: true, isRecommendedForIPhone: false,
                          details: "Compleet Core ML-model, maar zonder opgesplitste UNet. Gebruik op iPhone kan mislukken door RAM-limieten.")
        }
        return Report(isComplete: true, isRecommendedForIPhone: true,
                      details: "Core ML-bestanden aanwezig en UNet opgesplitst. Werkelijke werking blijft afhankelijk van iPhone-geheugen.")
    }

    static func findResources(in folder: URL, depth: Int = 0) -> URL? {
        if depth > 5 { return nil }
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.appendingPathComponent("TextEncoder.mlmodelc").path) { return folder }
        guard let children = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for child in children {
            if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
               let result = findResources(in: child, depth: depth + 1) { return result }
        }
        return nil
    }
}
