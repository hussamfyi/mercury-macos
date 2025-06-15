import Foundation
import Crypto

/// PKCE (Proof Key for Code Exchange) generator for OAuth 2.0 flow
/// Implements RFC 7636 specification for secure OAuth flow
public struct PKCEGenerator {
    
    /// Generate a cryptographically secure code verifier
    /// - Returns: URL-safe string between 43-128 characters
    public static func generateCodeVerifier() -> String {
        // Generate 32 random bytes (256 bits) for strong entropy
        let randomBytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let data = Data(randomBytes)
        
        // Base64 URL encode without padding
        return data.base64URLEncodedString()
    }
    
    /// Generate code challenge from code verifier using SHA256
    /// - Parameter codeVerifier: The code verifier string
    /// - Returns: Base64 URL encoded SHA256 hash of the code verifier
    public static func generateCodeChallenge(from codeVerifier: String) -> String {
        let data = Data(codeVerifier.utf8)
        let digest = SHA256.hash(data: data)
        return Data(digest).base64URLEncodedString()
    }
    
    /// Validate that a code verifier meets X API requirements
    /// - Parameter codeVerifier: The code verifier to validate
    /// - Returns: True if valid, false otherwise
    public static func isValidCodeVerifier(_ codeVerifier: String) -> Bool {
        // Must be between 43 and 128 characters
        guard codeVerifier.count >= 43 && codeVerifier.count <= 128 else {
            return false
        }
        
        // Must contain only URL-safe characters: [A-Z] [a-z] [0-9] - . _ ~
        let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return codeVerifier.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }
}

// MARK: - Data Extension for Base64 URL Encoding
extension Data {
    /// Base64 URL encode without padding as per RFC 4648 Section 5
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}