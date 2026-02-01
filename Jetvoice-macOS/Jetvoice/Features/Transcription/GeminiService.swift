//
//  GeminiService.swift
//  Jetvoice
//
//  Gemini API client for audio transcription
//

import Foundation
import Security

actor GeminiService {
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"
    private let defaultModel = "gemini-2.5-flash"

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

    // Fetch API key from Keychain
    private func getAPIKey() -> String? {
        let service = "ai.jetvoice.api"
        let account = "gemini-api-key"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }

        return key
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

            struct InlineData: Codable {
                let mimeType: String
                let data: String  // Base64 encoded
            }

            init(text: String) {
                self.text = text
                self.inlineData = nil
            }

            init(audioData: Data, mimeType: String) {
                self.text = nil
                self.inlineData = InlineData(
                    mimeType: mimeType,
                    data: audioData.base64EncodedString()
                )
            }
        }

        struct GenerationConfig: Codable {
            let temperature: Double?
            let maxOutputTokens: Int?
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

        guard let apiKey = getAPIKey() else {
            print("[Jetvoice] ERROR: API key not configured")
            throw GeminiError.apiKeyNotConfigured
        }

        let request = TranscriptionRequest(
            contents: [
                TranscriptionRequest.Content(parts: [
                    TranscriptionRequest.Part(text: """
                        Transcribe this audio accurately.
                        Detect the language automatically.
                        Return only the transcription text, no additional commentary or formatting.
                        If multiple languages are spoken, transcribe each in its original language.
                        """),
                    TranscriptionRequest.Part(audioData: audioData, mimeType: "audio/wav")
                ])
            ],
            generationConfig: TranscriptionRequest.GenerationConfig(
                temperature: 0.1,  // Low temperature for accuracy
                maxOutputTokens: 65536  // ~50,000 words, enough for 10+ minutes of speech
            )
        )

        let model = getSelectedModel()
        print("[Jetvoice] Using model: \(model)")

        guard let url = URL(string: "\(baseURL)/models/\(model):generateContent?key=\(apiKey)") else {
            throw GeminiError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        print("[Jetvoice] Sending request to Gemini API...")
        let (data, response) = try await session.data(for: urlRequest)
        print("[Jetvoice] Response received, size: \(data.count) bytes")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
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

    var errorDescription: String? {
        switch self {
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
