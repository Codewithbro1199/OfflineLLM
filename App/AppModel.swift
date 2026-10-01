import Foundation
import Observation

struct AppSettings: Codable, Equatable {
    var temperature: Double = 0.7
    var contextLength: Int = 4096
    var thinking: Bool = false
    var maxNewTokens: Int = 1536
    var systemPrompt: String = AppSettings.defaultSystemPrompt

    static let defaultSystemPrompt = """
    You are Offgrid, a helpful assistant running entirely on the user's iPhone. \
    You have no internet access and cannot look anything up, so answer from what you know. \
    Be clear and concise, use Markdown when it helps, and say so when you are unsure.
    """

    static let contextOptions = [2048, 4096, 8192]
}

enum EngineState: Equatable {
    case noModel
    case idle
    case loading(String)
    case ready(String)
    case failed(String)
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let engine = LlamaEngine()
    let store = ModelStore()
    private(set) var engineState: EngineState = .noModel

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            save(settings)
            if settings.contextLength != oldValue.contextLength { invalidateEngine() }
        }
    }

    var selectedModelID: String? {
        didSet {
            UserDefaults.standard.set(selectedModelID, forKey: Keys.selectedModel)
            if selectedModelID != oldValue { invalidateEngine() }
        }
    }

    private enum Keys {
        static let settings = "settings.v1"
        static let selectedModel = "selectedModel.v1"
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Keys.settings),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
        selectedModelID = UserDefaults.standard.string(forKey: Keys.selectedModel)
        refreshSelection()
    }

    var selectedModel: ModelInfo? {
        selectedModelID.flatMap(ModelCatalog.model(id:))
    }

    var hasUsableModel: Bool {
        guard let model = selectedModel else { return false }
        return store.state(for: model) == .installed
    }

    /// Picks an installed model if the current selection isn't usable.
    func refreshSelection() {
        if let model = selectedModel, store.state(for: model) == .installed {
            if engineState == .noModel { engineState = .idle }
            return
        }
        let installed = store.installedModels
        let preferred = installed.first { $0.id == ModelCatalog.defaultModelID } ?? installed.first
        selectedModelID = preferred?.id
        engineState = preferred == nil ? .noModel : .idle
    }

    func select(_ model: ModelInfo) {
        selectedModelID = model.id
        refreshSelection()
    }

    func delete(_ model: ModelInfo) async {
        if selectedModelID == model.id {
            await engine.unload()
            engineState = .idle
        }
        store.delete(model)
        refreshSelection()
    }

    /// Loads the selected model if needed. Safe to call before every message.
    func prepareEngine() async throws {
        guard let model = selectedModel, store.state(for: model) == .installed else {
            engineState = .noModel
            throw LlamaEngineError.noModelLoaded
        }
        let path = store.fileURL(for: model).path
        if await engine.isLoaded, await engine.loadedPath == path, await engine.contextLength == settings.contextLength {
            engineState = .ready(model.name)
            return
        }
        engineState = .loading(model.name)
        do {
            try await engine.load(path: path, contextLength: settings.contextLength)
            engineState = .ready(model.name)
        } catch {
            engineState = .failed(error.localizedDescription)
            throw error
        }
    }

    func releaseMemory() async {
        await engine.unload()
        if case .ready = engineState { engineState = .idle }
    }

    var generationOptions: GenerationOptions {
        var options = GenerationOptions()
        options.temperature = Float(settings.temperature)
        options.thinking = settings.thinking
        options.maxNewTokens = settings.maxNewTokens
        // Qwen's recommended sampling differs between reasoning and direct answers.
        options.topP = settings.thinking ? 0.95 : 0.8
        options.topK = 20
        return options
    }

    private func invalidateEngine() {
        Task { await engine.unload() }
        if case .ready = engineState { engineState = .idle }
    }

    private func save(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Keys.settings)
        }
    }
}
