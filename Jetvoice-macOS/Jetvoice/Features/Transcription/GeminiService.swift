//
//  GeminiService.swift
//  Jetvoice
//
//  Gemini API client for audio transcription
//

import Foundation

actor GeminiService {
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"
    private let uploadURL = "https://generativelanguage.googleapis.com/upload/v1beta/files"
    private let defaultModel = "gemini-2.5-flash"

    // Audio at or above this size is uploaded via the Files API instead of being
    // inlined as base64 (which inflates ~33% and risks the ~20MB request cap).
    private static let inlineSizeLimit = 8 * 1024 * 1024  // 8MB (~4 min @ 16kHz mono)

    private let session: URLSession

    // Timeout configuration for long recordings
    // At 16kHz mono, a 20-minute recording is ~38MB and may take time to upload and process
    private static let requestTimeout: TimeInterval = 120  // 2 minutes per request
    private static let resourceTimeout: TimeInterval = 300  // 5 minutes total (upload + processing)

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Self.requestTimeout
        config.timeoutIntervalForResource = Self.resourceTimeout
        self.session = URLSession(configuration: config)
    }

    // Get selected model from UserDefaults
    private func getSelectedModel() -> String {
        UserDefaults.standard.string(forKey: "selectedGeminiModel") ?? defaultModel
    }

    // MARK: - API Models

    struct TranscriptionRequest: Codable {
        let contents: [Content]
        let generationConfig: GenerationConfig?

        struct Content: Codable {
            let parts: [Part]
        }

        struct Part: Codable {
            let text: String?
            let inlineData: InlineData?
            let fileData: FileData?

            struct InlineData: Codable {
                let mimeType: String
                let data: String  // Base64 encoded
            }

            // Reference to an audio file already uploaded via the Files API.
            struct FileData: Codable {
                let mimeType: String
                let fileUri: String
            }

            init(text: String) {
                self.text = text
                self.inlineData = nil
                self.fileData = nil
            }

            init(audioData: Data, mimeType: String) {
                self.text = nil
                self.inlineData = InlineData(
                    mimeType: mimeType,
                    data: audioData.base64EncodedString()
                )
                self.fileData = nil
            }

            init(fileURI: String, mimeType: String) {
                self.text = nil
                self.inlineData = nil
                self.fileData = FileData(mimeType: mimeType, fileUri: fileURI)
            }
        }

        struct GenerationConfig: Codable {
            let temperature: Double?
            let maxOutputTokens: Int?
            let thinkingConfig: ThinkingConfig?

            // Gemini 3 models "think" by default, which adds latency and can
            // consume the entire output-token budget before any transcription
            // is emitted (looks like an infinite hang). Transcription needs no
            // reasoning, so we disable thinking. Harmless on 2.5 Flash too.
            struct ThinkingConfig: Codable {
                let thinkingBudget: Int
            }
        }
    }

    struct TranscriptionResponse: Codable {
        let candidates: [Candidate]?
        let error: APIError?

        struct Candidate: Codable {
            let content: Content?

            struct Content: Codable {
                let parts: [Part]?

                struct Part: Codable {
                    let text: String?
                }
            }
        }

        struct APIError: Codable {
            let code: Int
            let message: String
            let status: String?
        }
    }

    // MARK: - Transcription

    // Maximum audio size for inline data (Gemini's limit is around 20MB for inline base64)
    // At 16kHz mono 16-bit, 20 minutes = ~38MB raw, but we should warn before hitting limits
    private static let maxAudioSize = 25 * 1024 * 1024  // 25MB (conservative limit)

    func transcribe(audioData: Data) async throws -> String {
        print("[Jetvoice] GeminiService.transcribe called with \(audioData.count) bytes")

        // Check for overly large audio files
        if audioData.count > Self.maxAudioSize {
            let sizeMB = Double(audioData.count) / (1024 * 1024)
            print("[Jetvoice] ERROR: Audio file too large (\(String(format: "%.1f", sizeMB)) MB)")
            throw GeminiError.audioTooLarge(sizeMB: sizeMB)
        }

        guard let apiKey = KeychainHelper.getAPIKey(), !apiKey.isEmpty else {
            print("[Jetvoice] ERROR: API key not configured")
            throw GeminiError.apiKeyNotConfigured
        }

        // Small clips go inline (lowest latency); larger ones use the Files API
        // to avoid base64 bloat and the inline request-size cap.
        let audioPart: TranscriptionRequest.Part
        if audioData.count >= Self.inlineSizeLimit {
            print("[Jetvoice] Audio \(audioData.count) bytes ≥ inline limit, using Files API")
            let fileURI = try await uploadAudio(audioData, mimeType: "audio/wav", apiKey: apiKey)
            audioPart = TranscriptionRequest.Part(fileURI: fileURI, mimeType: "audio/wav")
        } else {
            audioPart = TranscriptionRequest.Part(audioData: audioData, mimeType: "audio/wav")
        }

        let request = TranscriptionRequest(
            contents: [
                TranscriptionRequest.Content(parts: [
                    TranscriptionRequest.Part(text: """
                        Transcribe this audio exactly as spoken. \
                        Output only the verbatim transcription text — no language labels, \
                        no commentary, no formatting, no prefixes, no metadata.
                        """),
                    audioPart
                ])
            ],
            generationConfig: TranscriptionRequest.GenerationConfig(
                temperature: 0.1,  // Low temperature for accuracy
                maxOutputTokens: 65536,  // ~50,000 words, enough for 10+ minutes of speech
                thinkingConfig: .init(thinkingBudget: 0)  // disable thinking — fixes Gemini 3 hang
            )
        )

        let model = getSelectedModel()
        print("[Jetvoice] Using model: \(model)")

        guard let url = URL(string: "\(baseURL)/models/\(model):generateContent") else {
            throw GeminiError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        // The Gemini API intermittently returns transient empty-body 404/5xx
        // (and 429) responses under load. Retry a few times with backoff before
        // surfacing an error so a flaky response doesn't fail a transcription.
        let maxAttempts = 3
        var data = Data()
        var httpResponse: HTTPURLResponse!
        for attempt in 1...maxAttempts {
            try Task.checkCancellation()
            print("[Jetvoice] Sending request to Gemini API (attempt \(attempt)/\(maxAttempts))...")
            let (respData, response) = try await session.data(for: urlRequest)

            guard let http = response as? HTTPURLResponse else {
                throw GeminiError.invalidResponse
            }
            data = respData
            httpResponse = http
            print("[Jetvoice] Response received: HTTP \(http.statusCode), \(respData.count) bytes")

            let isTransient = http.statusCode == 404
                || http.statusCode == 429
                || http.statusCode >= 500
                || respData.isEmpty
            if isTransient && attempt < maxAttempts {
                let delayNs = UInt64(attempt) * 500_000_000  // 0.5s, then 1.0s
                print("[Jetvoice] Transient response, retrying in \(Double(delayNs) / 1e9)s...")
                try await Task.sleep(nanoseconds: delayNs)
                continue
            }
            break
        }

        // Decode response
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(TranscriptionResponse.self, from: data)

        // Check for API error
        if let apiError = apiResponse.error {
            print("[Jetvoice] API Error: \(apiError.code) - \(apiError.message)")
            throw GeminiError.apiError(code: apiError.code, message: apiError.message)
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[Jetvoice] HTTP Error \(httpResponse.statusCode): \(errorBody)")
            throw GeminiError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Extract transcription text
        guard let text = apiResponse.candidates?.first?.content?.parts?.first?.text else {
            print("[Jetvoice] No transcription in response. Raw response: \(String(data: data, encoding: .utf8) ?? "nil")")
            throw GeminiError.noTranscriptionReturned
        }

        print("[Jetvoice] Transcription extracted: '\(text.prefix(100))...'")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Files API

    private struct FileResource: Codable {
        let uri: String?
        let name: String?
        let state: String?
    }
    private struct FileEnvelope: Codable {
        let file: FileResource?
    }

    /// Upload audio via the Gemini resumable Files API and return its file URI,
    /// waiting until the file is ACTIVE (ready to be referenced in a prompt).
    private func uploadAudio(_ audioData: Data, mimeType: String, apiKey: String) async throws -> String {
        guard let startURL = URL(string: uploadURL) else { throw GeminiError.invalidURL }

        // 1. Start a resumable upload session.
        var start = URLRequest(url: startURL)
        start.httpMethod = "POST"
        start.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        start.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        start.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        start.setValue("\(audioData.count)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        start.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        start.setValue("application/json", forHTTPHeaderField: "Content-Type")
        start.httpBody = try JSONEncoder().encode(["file": ["display_name": "jetvoice_audio"]])

        let (_, startResponse) = try await session.data(for: start)
        guard let startHTTP = startResponse as? HTTPURLResponse,
              startHTTP.statusCode == 200,
              let sessionURLString = startHTTP.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let sessionURL = URL(string: sessionURLString) else {
            throw GeminiError.fileUploadFailed("Could not start upload session")
        }

        // 2. Upload the bytes and finalize in one request.
        var upload = URLRequest(url: sessionURL)
        upload.httpMethod = "POST"
        upload.setValue("\(audioData.count)", forHTTPHeaderField: "Content-Length")
        upload.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        upload.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        upload.httpBody = audioData

        let (uploadData, uploadResponse) = try await session.data(for: upload)
        guard let uploadHTTP = uploadResponse as? HTTPURLResponse, uploadHTTP.statusCode == 200 else {
            throw GeminiError.fileUploadFailed("Upload failed")
        }

        var file = try JSONDecoder().decode(FileEnvelope.self, from: uploadData).file
        guard let name = file?.name, let initialURI = file?.uri else {
            throw GeminiError.fileUploadFailed("No file URI returned")
        }

        // 3. Poll until the file leaves PROCESSING (audio usually clears quickly).
        var attempts = 0
        while (file?.state ?? "ACTIVE") == "PROCESSING" && attempts < 15 {
            try await Task.sleep(nanoseconds: 500_000_000)  // 0.5s
            attempts += 1
            guard let statusURL = URL(string: "\(baseURL)/\(name)") else { break }
            var statusReq = URLRequest(url: statusURL)
            statusReq.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            let (statusData, _) = try await session.data(for: statusReq)
            file = try? JSONDecoder().decode(FileResource.self, from: statusData)
        }

        if let state = file?.state, state != "ACTIVE" {
            throw GeminiError.fileUploadFailed("File not ready (state: \(state))")
        }

        return file?.uri ?? initialURI
    }
}

// MARK: - Errors

enum GeminiError: LocalizedError {
    case apiKeyNotConfigured
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case apiError(code: Int, message: String)
    case noTranscriptionReturned
    case audioTooLarge(sizeMB: Double)
    case fileUploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileUploadFailed(let message):
            return "Audio upload failed: \(message)"
        case .apiKeyNotConfigured:
            return "Gemini API key is not configured"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .httpError(let code, let message):
            return "HTTP error \(code): \(message)"
        case .apiError(let code, let message):
            return "API error \(code): \(message)"
        case .noTranscriptionReturned:
            return "No transcription was returned. The recording may be too long or contain unclear audio."
        case .audioTooLarge(let sizeMB):
            return "Recording too large (\(String(format: "%.1f", sizeMB)) MB). Try a shorter recording."
        }
    }
}
