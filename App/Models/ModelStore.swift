import CryptoKit
import Foundation
import Observation

enum ModelInstallState: Equatable {
    case notDownloaded
    case downloading(progress: Double, bytesWritten: Int64)
    case verifying
    case installed
    case failed(String)
}

/// Downloads, verifies and stores model files. Downloads continue while the app is in the background.
@MainActor
@Observable
final class ModelStore: NSObject {
    static let backgroundSessionID = "app.offgrid.model-downloads"

    private(set) var states: [String: ModelInstallState] = [:]
    var backgroundCompletionHandler: (() -> Void)?

    @ObservationIgnored private var session: URLSession!
    @ObservationIgnored private var resumeData: [String: Data] = [:]

    let modelsDirectory: URL

    override init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        modelsDirectory = support.appendingPathComponent("Models", isDirectory: true)
        super.init()
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        var directory = modelsDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)

        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionID)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        for model in ModelCatalog.all {
            states[model.id] = FileManager.default.fileExists(atPath: fileURL(for: model).path) ? .installed : .notDownloaded
        }
        restoreRunningDownloads()
    }

    func fileURL(for model: ModelInfo) -> URL {
        modelsDirectory.appendingPathComponent(model.fileName)
    }

    func state(for model: ModelInfo) -> ModelInstallState {
        states[model.id] ?? .notDownloaded
    }

    var installedModels: [ModelInfo] {
        ModelCatalog.all.filter { state(for: $0) == .installed }
    }

    var freeDiskBytes: Int64 {
        let values = try? modelsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// Whether this iPhone has enough memory to run the model comfortably.
    func deviceCanRun(_ model: ModelInfo) -> Bool {
        let physical = Int64(ProcessInfo.processInfo.physicalMemory)
        // iOS lets one app use roughly 60% of RAM with the increased-memory entitlement.
        return Double(model.bytes + model.overheadBytes) < Double(physical) * 0.6
    }

    // MARK: - Actions

    func download(_ model: ModelInfo) {
        switch state(for: model) {
        case .downloading, .verifying, .installed: return
        default: break
        }
        let needed = model.bytes + 200_000_000
        if freeDiskBytes > 0, freeDiskBytes < needed {
            let needLabel = ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)
            states[model.id] = .failed("Not enough free space. \(needLabel) is needed.")
            return
        }
        let task: URLSessionDownloadTask
        if let data = resumeData.removeValue(forKey: model.id) {
            task = session.downloadTask(withResumeData: data)
        } else {
            task = session.downloadTask(with: model.url)
        }
        task.taskDescription = model.id
        task.countOfBytesClientExpectsToReceive = model.bytes
        states[model.id] = .downloading(progress: 0, bytesWritten: 0)
        task.resume()
    }

    func cancelDownload(_ model: ModelInfo) {
        session.getAllTasks { tasks in
            for task in tasks where task.taskDescription == model.id {
                task.cancel()
            }
        }
        resumeData[model.id] = nil
        states[model.id] = .notDownloaded
    }

    func delete(_ model: ModelInfo) {
        try? FileManager.default.removeItem(at: fileURL(for: model))
        states[model.id] = .notDownloaded
    }

    private func restoreRunningDownloads() {
        session.getAllTasks { tasks in
            let running = tasks.compactMap { task -> (String, Double)? in
                guard let id = task.taskDescription, task.state == .running || task.state == .suspended else { return nil }
                let expected = max(task.countOfBytesExpectedToReceive, 1)
                return (id, Double(task.countOfBytesReceived) / Double(expected))
            }
            Task { @MainActor in
                for (id, progress) in running {
                    self.states[id] = .downloading(progress: progress, bytesWritten: 0)
                }
            }
        }
    }

    // MARK: - Verification

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try autoreleasepool { try handle.read(upToCount: 8 * 1024 * 1024) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func finishDownload(modelID: String, stagedFile: URL) {
        guard let model = ModelCatalog.model(id: modelID) else {
            try? FileManager.default.removeItem(at: stagedFile)
            return
        }
        states[model.id] = .verifying
        let destination = fileURL(for: model)
        Task.detached(priority: .userInitiated) {
            let result: Result<Void, Error> = Result {
                let digest = try ModelStore.sha256(of: stagedFile)
                guard digest == model.sha256 else { throw DownloadError.checksumMismatch }
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: stagedFile, to: destination)
            }
            try? FileManager.default.removeItem(at: stagedFile)
            await MainActor.run {
                switch result {
                case .success: self.states[model.id] = .installed
                case .failure(let error): self.states[model.id] = .failed(error.localizedDescription)
                }
            }
        }
    }

    enum DownloadError: LocalizedError {
        case checksumMismatch
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .checksumMismatch: return "The download was damaged (checksum mismatch). Please try again."
            case .http(let code): return "The server refused the download (HTTP \(code))."
            }
        }
    }
}

extension ModelStore: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription, let model = ModelCatalog.model(id: id) else { return }
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : model.bytes
        let progress = min(1, Double(totalBytesWritten) / Double(expected))
        Task { @MainActor in
            if case .downloading(let old, _) = self.states[id], progress - old < 0.002, progress < 1 { return }
            self.states[id] = .downloading(progress: progress, bytesWritten: totalBytesWritten)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        if let response = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            let code = response.statusCode
            Task { @MainActor in self.states[id] = .failed(DownloadError.http(code).localizedDescription) }
            return
        }
        // The temporary file disappears when this method returns, so move it synchronously.
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent("\(id)-\(UUID().uuidString).part")
        do {
            try FileManager.default.moveItem(at: location, to: staged)
        } catch {
            Task { @MainActor in self.states[id] = .failed(error.localizedDescription) }
            return
        }
        Task { @MainActor in self.finishDownload(modelID: id, stagedFile: staged) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription, let error else { return }
        let nsError = error as NSError
        let data = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        let cancelled = nsError.code == NSURLErrorCancelled && data == nil
        Task { @MainActor in
            if let data { self.resumeData[id] = data }
            if cancelled {
                if case .downloading = self.states[id] { self.states[id] = .notDownloaded }
            } else {
                self.states[id] = .failed("Download interrupted. Tap to resume. (\(error.localizedDescription))")
            }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
