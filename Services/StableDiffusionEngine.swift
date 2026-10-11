import Foundation
import UIKit
import StableDiffusion
import CoreML
import CoreGraphics

@MainActor
final class StableDiffusionEngine: ObservableObject {
    @Published var isGenerating = false
    @Published var message = ""
    @Published var generatedImage: UIImage?
    @Published var progress: Double = 0
    @Published var currentStep = 0
    @Published var totalSteps = 20
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var remainingSeconds: TimeInterval?

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

    func generate(prompt: String, startingImage: CGImage? = nil, strength: Double = 0.45) async {
        guard !isGenerating else { return }
        if let error = validateResources() { message = error; return }
        if startingImage != nil && !FileManager.default.fileExists(atPath: resourceFolder().appendingPathComponent("VAEEncoder.mlmodelc").path) {
            message = "Image-to-image vereist VAEEncoder.mlmodelc in het model."
            return
        }
        isGenerating = true
        progress = 0
        currentStep = 0
        remainingSeconds = nil
        elapsedSeconds = 0
        let startTime = Date()
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
                if let startingImage {
                    let encoderURL = folder.appendingPathComponent("VAEEncoder.mlmodelc")
                    let encoderConfig = MLModelConfiguration()
                    encoderConfig.computeUnits = .cpuOnly
                    let vae = try MLModel(contentsOf: encoderURL, configuration: encoderConfig)
                    guard let input = vae.modelDescription.inputDescriptionsByName.values.first,
                          let shape = input.multiArrayConstraint?.shape.map({ $0.intValue }),
                          shape.count == 4, shape[1] == 3,
                          shape[2] > 0, shape[3] > 0 else {
                        throw NSError(domain: "ArtCraftOffline", code: 201,
                                      userInfo: [NSLocalizedDescriptionKey: "VAE-encoder heeft geen herkenbare invoerafmetingen."])
                    }
                    let width = shape[3], height = shape[2]
                    guard let ctx = CGContext(data: nil, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                        throw NSError(domain: "ArtCraftOffline", code: 202,
                                      userInfo: [NSLocalizedDescriptionKey: "Kon bronfoto niet voorbereiden."])
                    }
                    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                    let scale = min(CGFloat(width) / CGFloat(startingImage.width),
                                    CGFloat(height) / CGFloat(startingImage.height))
                    let targetW = CGFloat(startingImage.width) * scale
                    let targetH = CGFloat(startingImage.height) * scale
                    ctx.draw(startingImage, in: CGRect(x: (CGFloat(width) - targetW) / 2,
                                                       y: (CGFloat(height) - targetH) / 2,
                                                       width: targetW, height: targetH))
                    guard let resized = ctx.makeImage() else {
                        throw NSError(domain: "ArtCraftOffline", code: 203,
                                      userInfo: [NSLocalizedDescriptionKey: "Kon bronfoto niet schalen."])
                    }
                    configuration.startingImage = resized
                    configuration.strength = Float(max(0.1, min(0.9, strength)))
                }
                let images = try pipeline.generateImages(configuration: configuration) { progress in
                    let step = progress.step + 1
                    let count = max(configuration.stepCount, 1)
                    let seconds = Date().timeIntervalSince(startTime)
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.currentStep = min(step, count)
                        self.totalSteps = count
                        self.progress = min(1, Double(step) / Double(count))
                        self.elapsedSeconds = seconds
                        self.remainingSeconds = step > 0 ? seconds / Double(step) * Double(max(0, count - step)) : nil
                        self.message = "Genereren: stap \(min(step, count)) van \(count)"
                    }
                    return true
                }
                guard let cg = images.compactMap({ $0 }).first else {
                    throw NSError(domain: "ArtCraftOffline", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Geen afbeelding gegenereerd."])
                }
                return UIImage(cgImage: cg)
            }.value
            generatedImage = image
            message = startingImage == nil ? "Nieuwe afbeelding gegenereerd." : "Foto bewerkt. Voeg het resultaat toe als laag."
        } catch { message = "Core ML: \(error.localizedDescription)" }
        elapsedSeconds = Date().timeIntervalSince(startTime)
        isGenerating = false
    }
}
