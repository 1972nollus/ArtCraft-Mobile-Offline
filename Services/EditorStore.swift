import SwiftUI
import UIKit
@MainActor final class EditorStore: ObservableObject {
    @Published var project = ArtProject()
    @Published var selectedLayerID: UUID?
    @Published var errorMessage: String?
    private var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ArtProjects", isDirectory: true)
    }
    init() { load() }
    func image(for layer: ArtLayer) -> UIImage? {
        UIImage(contentsOfFile: folder.appendingPathComponent(layer.fileName).path)
    }
    func addImage(_ data: Data) {
        guard let image = UIImage(data: data), let png = image.pngData() else {
            errorMessage = "Afbeelding kon niet worden gelezen."; return
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let filename = UUID().uuidString + ".png"
            try png.write(to: folder.appendingPathComponent(filename), options: .atomic)
            let layer = ArtLayer(name: "Laag \(project.layers.count + 1)", fileName: filename)
            project.layers.append(layer); selectedLayerID = layer.id; save()
        } catch { errorMessage = error.localizedDescription }
    }
    func addGeneratedImage(_ data: Data) {
        guard let image = UIImage(data: data), let png = image.pngData() else {
            errorMessage = "AI-afbeelding kon niet worden gelezen."; return
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let filename = UUID().uuidString + ".png"
            try png.write(to: folder.appendingPathComponent(filename), options: .atomic)
            var layer = ArtLayer(name: "AI resultaat \(project.layers.count + 1)", fileName: filename)
            layer.x = 0.5
            layer.y = 0.5
            layer.scale = 1.2
            layer.opacity = 1
            layer.rotation = 0
            project.layers.append(layer)
            selectedLayerID = layer.id
            save()
        } catch { errorMessage = error.localizedDescription }
    }
    func update(_ id: UUID, _ change: (inout ArtLayer) -> Void) {
        guard let index = project.layers.firstIndex(where: { $0.id == id }) else { return }
        change(&project.layers[index]); save()
    }
    func deleteSelected() {
        guard let id = selectedLayerID,
              let index = project.layers.firstIndex(where: { $0.id == id }) else { return }
        let layer = project.layers.remove(at: index)
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(layer.fileName))
        selectedLayerID = nil; save()
    }
    func moveSelected(_ direction: Int) {
        guard let id = selectedLayerID,
              let index = project.layers.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + direction
        guard project.layers.indices.contains(destination) else { return }
        project.layers.swapAt(index, destination); save()
    }
    func newProject() {
        project = ArtProject(); selectedLayerID = nil; save()
    }
    func save() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(project).write(to: folder.appendingPathComponent("project.json"), options: .atomic)
        } catch { errorMessage = error.localizedDescription }
    }
    func load() {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("project.json")),
              let saved = try? JSONDecoder().decode(ArtProject.self, from: data) else { return }
        project = saved
    }
    func renderedImage() -> UIImage {
        let size = CGSize(width: project.canvasWidth, height: project.canvasHeight)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            for layer in project.layers where layer.isVisible {
                guard let image = image(for: layer) else { continue }
                let side = min(size.width, size.height) * 0.75 * layer.scale
                let aspect = image.size.width / max(image.size.height, 1)
                let dimensions = aspect >= 1 ? CGSize(width: side, height: side / aspect) : CGSize(width: side * aspect, height: side)
                let cg = context.cgContext; cg.saveGState()
                cg.translateBy(x: size.width * layer.x, y: size.height * layer.y)
                cg.rotate(by: layer.rotation * .pi / 180); cg.setAlpha(layer.opacity)
                image.draw(in: CGRect(x: -dimensions.width / 2, y: -dimensions.height / 2, width: dimensions.width, height: dimensions.height))
                cg.restoreGState()
            }
        }
    }
}
