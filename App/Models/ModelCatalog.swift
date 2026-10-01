import Foundation

struct ModelInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let tagline: String
    let fileName: String
    let url: URL
    let bytes: Int64
    let sha256: String
    let license: String
    /// Rough working memory needed on top of the file (KV cache, Metal buffers), in bytes.
    let overheadBytes: Int64
    let recommendedContext: Int

    var sizeLabel: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

enum ModelCatalog {
    static let defaultModelID = "qwen3.5-2b"

    /// Every URL is pinned to an exact Hugging Face revision, so the SHA-256 below can never drift.
    static let all: [ModelInfo] = [
        ModelInfo(
            id: "qwen3.5-0.8b",
            name: "Qwen3.5 0.8B",
            tagline: "Fastest. Good for quick questions and short replies.",
            fileName: "Qwen_Qwen3.5-0.8B-Q8_0.gguf",
            url: URL(string: "https://huggingface.co/bartowski/Qwen_Qwen3.5-0.8B-GGUF/resolve/f36b1ea49a332ede8fe5f389bbf5b3575ef71f48/Qwen_Qwen3.5-0.8B-Q8_0.gguf")!,
            bytes: 835_325_024,
            sha256: "7182e2362766bb9569209bbc24cf1a4cdfbb8ab161babdb2080c84fa62c08c2f",
            license: "Apache-2.0",
            overheadBytes: 400_000_000,
            recommendedContext: 8192
        ),
        ModelInfo(
            id: "qwen3.5-2b",
            name: "Qwen3.5 2B",
            tagline: "Balanced. The recommended everyday model.",
            fileName: "Qwen_Qwen3.5-2B-Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/bartowski/Qwen_Qwen3.5-2B-GGUF/resolve/7d26695454df6de5fbcce2e58681e62dae06ce43/Qwen_Qwen3.5-2B-Q4_K_M.gguf")!,
            bytes: 1_396_198_496,
            sha256: "57a1085840f497d764a7fc5d346922dbde961efb54cc792ea81d694fd846a1d8",
            license: "Apache-2.0",
            overheadBytes: 600_000_000,
            recommendedContext: 8192
        ),
        ModelInfo(
            id: "qwen3.5-4b",
            name: "Qwen3.5 4B",
            tagline: "Smartest. Slower, and needs an iPhone with 8 GB of memory.",
            fileName: "Qwen_Qwen3.5-4B-Q4_K_M.gguf",
            url: URL(string: "https://huggingface.co/bartowski/Qwen_Qwen3.5-4B-GGUF/resolve/4168f45a16a1290d65a4ec0fa312ae917a4c15d6/Qwen_Qwen3.5-4B-Q4_K_M.gguf")!,
            bytes: 3_013_027_808,
            sha256: "13c16f426047e2de38cd075bdade4a7bcbc8c774384876f677740cda65f8a983",
            license: "Apache-2.0",
            overheadBytes: 900_000_000,
            recommendedContext: 4096
        ),
    ]

    static func model(id: String) -> ModelInfo? { all.first { $0.id == id } }
}
