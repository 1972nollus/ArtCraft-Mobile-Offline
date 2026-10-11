import ZIPFoundation
import Foundation
import Combine

@MainActor
final class ModelDownloadStore: ObservableObject {
    @Published var urlText = ""
    @Published var models: [String] = []
    @Published var progress: Double = 0
    @Published var downloading = false
    @Published var status = ""
    @Published var selectedModel: String = UserDefaults.standard.string(forKey: "activeCoreMLModel") ?? ""
    private var task: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?
    private var session: URLSession?
    private var delegate: DownloadDelegate?

    var modelDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoreMLModels", isDirectory: true)
    }

    init() { scan() }

    func activate(_ id: String) {
        let folder = modelDirectory.appendingPathComponent("Installed").appendingPathComponent(id).appendingPathComponent("Resources")
        let report = CoreMLModelValidator.check(folder)
        guard report.isComplete else { status = report.details; return }
        selectedModel = id
        UserDefaults.standard.set(id, forKey: "activeCoreMLModel")
        status = report.details
    }

    func validation(_ id: String) -> String {
        let folder = modelDirectory.appendingPathComponent("Installed").appendingPathComponent(id).appendingPathComponent("Resources")
        return CoreMLModelValidator.check(folder).details
    }

    func usePreset(_ preset: ModelPreset) {
        urlText = preset.url
    }

    func scan() {
        try? FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        let root = modelDirectory.appendingPathComponent("Installed", isDirectory: true)
        models = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.map { $0.lastPathComponent }.sorted()
        if !models.contains(selectedModel) { selectedModel = ""; UserDefaults.standard.removeObject(forKey: "activeCoreMLModel") }
    }

    func download() {
        guard !downloading else { return }
        guard let url = URL(string: urlText), url.scheme == "https" else {
            status = "Gebruik een geldige HTTPS-downloadlink."; return
        }
        let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        let modelID = ModelPreset.all.first(where: { $0.url == urlText })?.id ?? URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\"),
              ["zip", "mlpackage", "mlmodelc"].contains(URL(fileURLWithPath: name).pathExtension.lowercased()) else {
            status = "Alleen Core ML modelarchieven (.zip), .mlpackage of .mlmodelc."; return
        }
        downloading = true; progress = 0; status = "Downloaden..."
        let delegate = DownloadDelegate()
        self.delegate = delegate
        delegate.onProgress = { [weak self] value in
            Task { @MainActor in self?.progress = value }
        }
        delegate.onComplete = { [weak self] temporary, error in
            Task { @MainActor in
                guard let self else { return }
                self.downloading = false
                defer { self.scan(); self.task = nil; self.session = nil; self.delegate = nil }
                if let error { self.status = "Download mislukt: \(error.localizedDescription)"; return }
                guard let temporary else { self.status = "Geen downloadbestand ontvangen."; return }
                do {
                    try FileManager.default.createDirectory(at: self.modelDirectory, withIntermediateDirectories: true)
                    let target = self.modelDirectory.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                    try FileManager.default.moveItem(at: temporary, to: target)
                    if target.pathExtension.lowercased() == "zip" {
                        let unpack = self.modelDirectory.appendingPathComponent("Unpacked", isDirectory: true)
                        if FileManager.default.fileExists(atPath: unpack.path) {
                            try FileManager.default.removeItem(at: unpack)
                        }
                        try FileManager.default.createDirectory(at: unpack, withIntermediateDirectories: true)
                        try FileManager.default.unzipItem(at: target, to: unpack)
                        let resources = CoreMLModelValidator.findResources(in: unpack)
                        if let resources {
                            let parent = self.modelDirectory.appendingPathComponent("Installed").appendingPathComponent(modelID)
                            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                            let destination = parent.appendingPathComponent("Resources", isDirectory: true)
                            if FileManager.default.fileExists(atPath: destination.path) {
                                try FileManager.default.removeItem(at: destination)
                            }
                            try FileManager.default.copyItem(at: resources, to: destination)
                            self.status = CoreMLModelValidator.check(destination).details
                        } else {
                            self.status = "ZIP uitgepakt, maar geen volledige gecompileerde Core ML Resources-map gevonden."
                        }
                        try FileManager.default.removeItem(at: unpack)
                    }
                    self.selectedModel = name
                    if target.pathExtension.lowercased() != "zip" { self.status = "Bestand opgeslagen, nog niet geïnstalleerd." }
                } catch { self.status = "Opslagfout: \(error.localizedDescription)" }
            }
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        self.session = session
        task = session.downloadTask(with: url)
        task?.resume()
    }

    private func findResources(in folder: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.appendingPathComponent("TextEncoder.mlmodelc").path) {
            return folder
        }
        guard let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for entry in entries {
            if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
               let found = findResources(in: entry) { return found }
        }
        return nil
    }

    func cancel() { task?.cancel() }

    func delete(_ name: String) {
        guard models.contains(name) else { return }
        try? FileManager.default.removeItem(at: modelDirectory.appendingPathComponent("Installed").appendingPathComponent(name))
        scan()
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var onProgress: ((Double) -> Void)?
    var onComplete: ((URL?, Error?) -> Void)?
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            onProgress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temporary URL is only valid during this callback: copy before returning.
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.copyItem(at: location, to: temp)
            onComplete?(temp, nil)
        } catch { onComplete?(nil, error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { onComplete?(nil, error) }
    }
}
