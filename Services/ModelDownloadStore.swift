import Foundation
import Combine

@MainActor
final class ModelDownloadStore: ObservableObject {
    @Published var urlText = ""
    @Published var models: [String] = []
    @Published var progress: Double = 0
    @Published var downloading = false
    @Published var status = ""
    @Published var selectedModel: String = ""
    private var task: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?
    private var session: URLSession?
    private var delegate: DownloadDelegate?

    var modelDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoreMLModels", isDirectory: true)
    }

    init() { scan() }

    func scan() {
        try? FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        models = (try? FileManager.default.contentsOfDirectory(at: modelDirectory, includingPropertiesForKeys: nil))?
            .filter { ["mlpackage", "mlmodelc", "zip"].contains($0.pathExtension.lowercased()) }
            .map(\.lastPathComponent).sorted() ?? []
        if !models.contains(selectedModel) { selectedModel = models.first ?? "" }
    }

    func download() {
        guard !downloading else { return }
        guard let url = URL(string: urlText), url.scheme == "https" else {
            status = "Gebruik een geldige HTTPS-downloadlink."; return
        }
        let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
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
                    self.selectedModel = name
                    self.status = "Opgeslagen: \(name). Nog niet geactiveerd voor generatie."
                } catch { self.status = "Opslagfout: \(error.localizedDescription)" }
            }
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        self.session = session
        task = session.downloadTask(with: url)
        task?.resume()
    }

    func cancel() { task?.cancel() }

    func delete(_ name: String) {
        guard models.contains(name) else { return }
        try? FileManager.default.removeItem(at: modelDirectory.appendingPathComponent(name))
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
