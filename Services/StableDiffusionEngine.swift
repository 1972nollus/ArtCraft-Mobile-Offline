import Foundation
import UIKit
import StableDiffusion

@MainActor
final class StableDiffusionEngine: ObservableObject {
    @Published var isGenerating = false
    @Published var message = ""
    @Published var generatedImage: UIImage?

    func resourceFolder() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoreMLModels", isDirectory: true)
            .appendingPathComponent("Installed", isDirectory: true)
            .appendingPathComponent(UserDefaults.standard.string(forKey: "activeCoreMLModel") ?? "no-selection", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
    }

    func validateResources() -> String? {
        let folder = resourceFolder()
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else {
            return "Geen actief geïnstalleerd Core ML-model. Ga naar Instellingen → Modellen en selecteer een model."
        }
        for name in ["TextEncoder.mlmodelc", "VAEDecoder.mlmodelc", "vocab.json"] {
            if !fm.fileExists(atPath: folder.appendingPathComponent(name).path) { return "Ontbreekt: \(name)" }
        }
        let tokenizer = fm.fileExists(atPath: folder.appendingPathComponent("merges.txt").path)
            || fm.fileExists(atPath: folder.appendingPathComponent("merges.text").path)
        if !tokenizer { return "Ontbreekt: merges.txt" }
        let unet = fm.fileExists(atPath: folder.appendingPathComponent("Unet.mlmodelc").path)
        let chunks = fm.fileExists(atPath: folder.appendingPathComponent("UnetChunk1.mlmodelc").path)
            && fm.fileExists(atPath: folder.appendingPathComponent("UnetChunk2.mlmodelc").path)
        if !unet && !chunks { return "Ontbreekt: Unet of UnetChunk1 + UnetChunk2." }
        let report = CoreMLModelValidator.check(folder)
        return report.isComplete ? nil : report.details
    }

    func generate(prompt: String) async {
        guard !isGenerating else { return }
        if let error = validateResources() { message = error; return }
        isGenerating = true
        generatedImage = nil
        message = "Core ML-pipeline laden..."
        do {
            let folder = resourceFolder()
            let image = try await Task.detached(priority: .userInitiated) {
                let pipeline = try StableDiffusionPipeline(resourcesAt: folder, controlNet: [], reduceMemory: true)
                try pipeline.loadResources()
                defer { pipeline.unloadResources() }
                var configuration = StableDiffusionPipeline.Configuration(prompt: prompt)
                configuration.seed = UInt32.random(in: 0...UInt32.max)
                configuration.stepCount = 20
                let images = try pipeline.generateImages(configuration: configuration) { _ in true }
                guard let cg = images.compactMap({ $0 }).first else {
                    throw NSError(domain: "ArtCraftOffline", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Geen afbeelding gegenereerd."])
                }
                return UIImage(cgImage: cg)
            }.value
            generatedImage = image
            message = "Gegenereerd. Je kunt de afbeelding als laag toevoegen."
        } catch { message = "Core ML: \(error.localizedDescription)" }
        isGenerating = false
    }
}
