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

    static let backgroundID = "nl.artcraftmobile.offline.background-models"
    private var session: URLSession!
    private var proxy: BackgroundModelDownloadDelegate!
    private var currentTask: URLSessionDownloadTask?

    var modelDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoreMLModels", isDirectory: true)
    }

    init() {
        scan()
        let proxy = BackgroundModelDownloadDelegate()
        self.proxy = proxy
        proxy.backgroundEventsDone = {
            let completion = BackgroundSessionBridge.completionHandler
            BackgroundSessionBridge.completionHandler = nil
            completion?()
        }
        proxy.progressHandler = { [weak self] progress in
            Task { @MainActor in self?.progress = progress }
        }
        proxy.completedHandler = { [weak self] file, taskDescription, error in
            Task { @MainActor in
                await self?.completeDownload(file, taskDescription: taskDescription, error: error)
            }
        }
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundID)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.waitsForConnectivity = true
        session = URLSession(configuration: config, delegate: proxy, delegateQueue: nil)
        session.getAllTasks { [weak self] tasks in
            Task { @MainActor in
                guard let self else { return }
                self.currentTask = tasks.first as? URLSessionDownloadTask
                self.downloading = self.currentTask != nil
                if self.downloading { self.status = "Achtergronddownload wordt voortgezet…" }
            }
        }
    }

    func usePreset(_ preset: ModelPreset) { urlText = preset.url }

    func scan() {
        try? FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        let root = modelDirectory.appendingPathComponent("Installed", isDirectory: true)
        models = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { $0.lastPathComponent }.sorted()
        if !models.contains(selectedModel) {
            selectedModel = ""
            UserDefaults.standard.removeObject(forKey: "activeCoreMLModel")
        }
    }

    func activate(_ id: String) {
        let folder = modelDirectory.appendingPathComponent("Installed").appendingPathComponent(id).appendingPathComponent("Resources")
        let report = CoreMLModelValidator.check(folder)
        guard report.isComplete else { status = report.details; return }
        selectedModel = id
        UserDefaults.standard.set(id, forKey: "activeCoreMLModel")
        status = "Model actief: " + id + ". " + report.details
    }

    func validation(_ id: String) -> String {
        let folder = modelDirectory.appendingPathComponent("Installed").appendingPathComponent(id).appendingPathComponent("Resources")
        return CoreMLModelValidator.check(folder).details
    }

    func download() {
        guard !downloading else { return }
        guard let url = URL(string: urlText), url.scheme == "https",
              url.pathExtension.lowercased() == "zip" else {
            status = "Gebruik een directe HTTPS-link naar een Core ML ZIP-bestand."
            return
        }
        let id = ModelPreset.all.first(where: { $0.url == urlText })?.id ??
            url.deletingPathExtension().lastPathComponent
        guard !id.isEmpty else { status = "Ongeldige modelnaam."; return }
        if models.contains(id) {
            status = "Dit model is al geïnstalleerd. Kies 'Gebruik model' in de lijst."
            return
        }
        progress = 0
        status = "Achtergronddownload gestart. Je kunt de app verlaten."
        downloading = true
        let task = session.downloadTask(with: url)
        task.taskDescription = id
        currentTask = task
        task.resume()
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        downloading = false
        status = "Download geannuleerd."
    }

    func importLocal(from url: URL) {
        guard !downloading else { status = "Wacht op de lopende download."; return }
        let access = url.startAccessingSecurityScopedResource()
        let directory = modelDirectory
        let staging = directory.appendingPathComponent("Picked-" + UUID().uuidString, isDirectory: url.hasDirectoryPath)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if url.hasDirectoryPath {
                try FileManager.default.copyItem(at: url, to: staging)
            } else {
                try FileManager.default.copyItem(at: url, to: staging.appendingPathExtension(url.pathExtension))
            }
            if access { url.stopAccessingSecurityScopedResource() }
        } catch {
            if access { url.stopAccessingSecurityScopedResource() }
            status = "Importfout: " + error.localizedDescription
            return
        }
        let local = url.hasDirectoryPath ? staging : staging.appendingPathExtension(url.pathExtension)
        status = "Model wordt lokaal geïmporteerd…"
        Task {
            do {
                let result = try await Task.detached(priority: .utility) {
                    try CoreMLModelInstaller.install(from: local, modelsDirectory: directory)
                }.value
                try? FileManager.default.removeItem(at: local)
                scan()
                activate(result.id)
            } catch {
                try? FileManager.default.removeItem(at: local)
                status = "Import mislukt: " + error.localizedDescription
            }
        }
    }

    private func completeDownload(_ file: URL?, taskDescription: String?, error: Error?) async {
        downloading = false
        currentTask = nil
        guard let file else {
            status = "Download mislukt: " + (error?.localizedDescription ?? "bestand niet ontvangen")
            return
        }
        status = "Download afgerond. Core ML-bestanden controleren en uitpakken…"
        let directory = modelDirectory
        do {
            let result = try await Task.detached(priority: .utility) {
                try CoreMLModelInstaller.install(from: file, modelsDirectory: directory,
                                                  preferredID: taskDescription)
            }.value
            try? FileManager.default.removeItem(at: file)
            scan()
            activate(result.id)
        } catch {
            try? FileManager.default.removeItem(at: file)
            status = "Modelinstallatie mislukt: " + error.localizedDescription
        }
    }

    func delete(_ name: String) {
        guard models.contains(name) else { return }
        try? FileManager.default.removeItem(at: modelDirectory.appendingPathComponent("Installed").appendingPathComponent(name))
        scan()
    }
}

final class BackgroundModelDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var progressHandler: ((Double) -> Void)?
    var completedHandler: ((URL?, String?, Error?) -> Void)?
    var backgroundEventsDone: (() -> Void)?

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            progressHandler?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoreMLModels", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent("Received-" + UUID().uuidString + ".zip")
            try FileManager.default.moveItem(at: location, to: destination)
            completedHandler?(destination, downloadTask.taskDescription, nil)
        } catch {
            completedHandler?(nil, downloadTask.taskDescription, error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            completedHandler?(nil, task.taskDescription, error)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in self?.backgroundEventsDone?() }
    }
}
