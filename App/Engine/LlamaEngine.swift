import Foundation
import llama

/// One message handed to the model, already stripped of UI-only data.
struct ChatTurn: Equatable, Sendable {
    enum Role: String, Sendable { case system, user, assistant }
    var role: Role
    var content: String
}

struct GenerationOptions: Sendable, Equatable {
    var temperature: Float = 0.7
    var topP: Float = 0.8
    var topK: Int32 = 20
    var minP: Float = 0.0
    var repeatPenalty: Float = 1.05
    var maxNewTokens: Int = 2048
    /// When false, an empty reasoning block is pre-filled so Qwen-style models answer directly.
    var thinking: Bool = false
}

struct GenerationStats: Sendable, Equatable {
    var promptTokens: Int
    var reusedTokens: Int
    var generatedTokens: Int
    var promptSeconds: Double
    var generationSeconds: Double
    var droppedTurns: Int
    /// The assistant turn exactly as the model saw it (any pre-filled block plus its output).
    /// Feeding this back verbatim next turn lets the engine reuse its memory instead of re-reading the chat.
    var transcript: String

    var tokensPerSecond: Double {
        generationSeconds > 0 ? Double(generatedTokens) / generationSeconds : 0
    }
}

enum GenerationEvent: Sendable {
    case text(String)
    case finished(GenerationStats)
}

enum LlamaEngineError: LocalizedError {
    case modelLoadFailed(String)
    case contextInitFailed
    case noModelLoaded
    case promptTooLong
    case decodeFailed(Int32)
    case templateFailed

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let name): return "Couldn't load \(name). The file may be damaged or too large for this iPhone."
        case .contextInitFailed: return "Couldn't prepare the model's memory. Try a smaller context length in Settings."
        case .noModelLoaded: return "No model is loaded."
        case .promptTooLong: return "This message is too long for the model's context. Try a shorter message or a longer context in Settings."
        case .decodeFailed(let code): return "The model stopped unexpectedly (code \(code))."
        case .templateFailed: return "Couldn't format the conversation for this model."
        }
    }
}

/// Owns the llama.cpp model and context. All C calls happen on this actor.
actor LlamaEngine {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var chatTemplate: String?
    private(set) var loadedPath: String?
    private(set) var contextLength: Int = 0

    /// Tokens currently held in the KV cache, so the next turn can reuse the shared prefix.
    private var cachedTokens: [llama_token] = []

    private static let backendInit: Void = { llama_backend_init() }()

    init() { _ = LlamaEngine.backendInit }

    deinit {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }

    var isLoaded: Bool { context != nil }

    func load(path: String, contextLength: Int) throws {
        if loadedPath == path, self.contextLength == contextLength, context != nil { return }
        unload()

        var modelParams = llama_model_default_params()
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
        #else
        modelParams.n_gpu_layers = 999
        #endif
        // Default load mode (AUTO) memory-maps the file, so the weights don't count twice against RAM.

        guard let model = llama_model_load_from_file(path, modelParams) else {
            throw LlamaEngineError.modelLoadFailed(URL(fileURLWithPath: path).lastPathComponent)
        }

        let threads = Int32(max(1, min(6, ProcessInfo.processInfo.activeProcessorCount - 2)))
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = UInt32(contextLength)
        ctxParams.n_batch = 512
        ctxParams.n_ubatch = 512
        ctxParams.n_threads = threads
        ctxParams.n_threads_batch = threads

        guard let context = llama_init_from_model(model, ctxParams) else {
            llama_model_free(model)
            throw LlamaEngineError.contextInitFailed
        }

        self.model = model
        self.context = context
        self.vocab = llama_model_get_vocab(model)
        if let tmpl = llama_model_chat_template(model, nil) {
            self.chatTemplate = String(cString: tmpl)
        } else {
            self.chatTemplate = nil
        }
        self.loadedPath = path
        self.contextLength = Int(llama_n_ctx(context))
        self.cachedTokens = []
    }

    func unload() {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil
        model = nil
        vocab = nil
        chatTemplate = nil
        loadedPath = nil
        contextLength = 0
        cachedTokens = []
    }

    /// Streams the assistant's reply. Cancel the consuming task to stop generation.
    nonisolated func generate(turns: [ChatTurn], options: GenerationOptions) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(turns: turns, options: options) { event in
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Generation

    private func run(turns: [ChatTurn], options: GenerationOptions, emit: (GenerationEvent) -> Void) throws {
        guard let context, let vocab else { throw LlamaEngineError.noModelLoaded }

        // Leave room for the answer; drop the oldest exchanges until the prompt fits.
        let reserve = min(options.maxNewTokens, contextLength / 2)
        let budget = contextLength - reserve
        var working = turns
        var dropped = 0
        var promptTokens = try tokenize(prompt(for: working, thinking: options.thinking))
        while promptTokens.count > budget {
            guard let index = PromptTrimmer.indexToDrop(in: working) else { throw LlamaEngineError.promptTooLong }
            working.remove(at: index)
            dropped += 1
            promptTokens = try tokenize(prompt(for: working, thinking: options.thinking))
        }

        // Reuse the KV cache for the prefix shared with the previous turn.
        let memory = llama_get_memory(context)
        var reuse = PromptTrimmer.commonPrefixLength(cachedTokens, promptTokens)
        if reuse == promptTokens.count { reuse -= 1 } // must decode at least one token to get logits
        if reuse < 0 { reuse = 0 }
        if reuse == 0 {
            llama_memory_clear(memory, true)
        } else if !llama_memory_seq_rm(memory, 0, llama_pos(reuse), -1) {
            llama_memory_clear(memory, true)
            reuse = 0
        }
        cachedTokens = Array(promptTokens[..<reuse])

        let promptStart = Date()
        var index = reuse
        while index < promptTokens.count {
            try Task.checkCancellation()
            let end = min(index + 512, promptTokens.count)
            var chunk = Array(promptTokens[index..<end])
            let result = chunk.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress, Int32(buffer.count)))
            }
            if result != 0 {
                cachedTokens = []
                llama_memory_clear(memory, true)
                throw LlamaEngineError.decodeFailed(result)
            }
            cachedTokens.append(contentsOf: chunk)
            index = end
        }
        let promptSeconds = Date().timeIntervalSince(promptStart)

        let sampler = makeSampler(options: options, vocab: vocab)
        defer { llama_sampler_free(sampler) }

        var utf8 = UTF8Accumulator()
        var output = prefill(thinking: options.thinking)
        var generated = 0
        let genStart = Date()
        let maxTokens = min(options.maxNewTokens, contextLength - cachedTokens.count - 1)

        while generated < maxTokens {
            if Task.isCancelled { break }
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }

            let text = utf8.append(piece(for: token))
            if !text.isEmpty {
                output += text
                emit(.text(text))
            }
            generated += 1

            let result = withUnsafeMutablePointer(to: &token) { pointer in
                llama_decode(context, llama_batch_get_one(pointer, 1))
            }
            if result != 0 { throw LlamaEngineError.decodeFailed(result) }
            cachedTokens.append(token)
        }
        let tail = utf8.flush()
        if !tail.isEmpty {
            output += tail
            emit(.text(tail))
        }

        emit(.finished(GenerationStats(
            promptTokens: promptTokens.count,
            reusedTokens: reuse,
            generatedTokens: generated,
            promptSeconds: promptSeconds,
            generationSeconds: Date().timeIntervalSince(genStart),
            droppedTurns: dropped,
            transcript: output
        )))
    }

    private func makeSampler(options: GenerationOptions, vocab: OpaquePointer) -> UnsafeMutablePointer<llama_sampler> {
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        if options.repeatPenalty > 1.0 {
            llama_sampler_chain_add(chain, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 128, options.repeatPenalty, 0, 0))
        }
        if options.temperature <= 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
            return chain
        }
        if options.topK > 0 { llama_sampler_chain_add(chain, llama_sampler_init_top_k(options.topK)) }
        if options.topP < 1 { llama_sampler_chain_add(chain, llama_sampler_init_top_p(options.topP, 1)) }
        if options.minP > 0 { llama_sampler_chain_add(chain, llama_sampler_init_min_p(options.minP, 1)) }
        llama_sampler_chain_add(chain, llama_sampler_init_temp(options.temperature))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max - 1)))
        return chain
    }

    // MARK: - Prompt formatting

    private func prompt(for turns: [ChatTurn], thinking: Bool) throws -> String {
        var text: String
        if let chatTemplate {
            text = try apply(template: chatTemplate, turns: turns)
        } else {
            text = ChatML.render(turns)
        }
        return text + prefill(thinking: thinking)
    }

    private func prefill(thinking: Bool) -> String {
        !thinking && ChatML.supportsThinkPrefill(template: chatTemplate) ? ChatML.noThinkPrefill : ""
    }

    private func apply(template: String, turns: [ChatTurn]) throws -> String {
        let roles = turns.map { strdup($0.role.rawValue)! }
        let contents = turns.map { strdup($0.content)! }
        defer {
            roles.forEach { free($0) }
            contents.forEach { free($0) }
        }
        var messages = zip(roles, contents).map { llama_chat_message(role: $0, content: $1) }
        let estimate = turns.reduce(256) { $0 + $1.content.utf8.count * 2 + 64 }
        var buffer = [CChar](repeating: 0, count: estimate)
        var length = llama_chat_apply_template(template, &messages, messages.count, true, &buffer, Int32(buffer.count))
        if length < 0 {
            // Unknown template: fall back to ChatML, which Qwen-family models use.
            return ChatML.render(turns)
        }
        if Int(length) > buffer.count {
            buffer = [CChar](repeating: 0, count: Int(length) + 1)
            length = llama_chat_apply_template(template, &messages, messages.count, true, &buffer, Int32(buffer.count))
            guard length >= 0 else { throw LlamaEngineError.templateFailed }
        }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Tokens

    private func tokenize(_ text: String) throws -> [llama_token] {
        guard let vocab else { throw LlamaEngineError.noModelLoaded }
        let utf8Count = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(utf8Count) + 16)
        // Templates already contain the special tokens, so don't add BOS twice and do parse specials.
        var count = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), false, true)
        if count < 0, count != Int32.min {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), false, true)
        }
        guard count >= 0 else { throw LlamaEngineError.templateFailed }
        return Array(tokens.prefix(Int(count)))
    }

    private func piece(for token: llama_token) -> [UInt8] {
        guard let vocab else { return [] }
        // special = true so reasoning markers like <think> come through; end-of-turn tokens stop the loop before this.
        var buffer = [CChar](repeating: 0, count: 64)
        var count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)
        if count < 0 {
            buffer = [CChar](repeating: 0, count: Int(-count))
            count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)
        }
        guard count > 0 else { return [] }
        return buffer.prefix(Int(count)).map { UInt8(bitPattern: $0) }
    }
}
