import XCTest
@testable import mercury_cli_auth

final class PKCEGeneratorTests: XCTestCase {
    
    func testCodeVerifierGeneration() throws {
        let codeVerifier = PKCEGenerator.generateCodeVerifier()
        
        // Test length is within valid range (43-128 characters)
        XCTAssertGreaterThanOrEqual(codeVerifier.count, 43, "Code verifier should be at least 43 characters")
        XCTAssertLessThanOrEqual(codeVerifier.count, 128, "Code verifier should be at most 128 characters")
        
        // Test that generated verifier is valid
        XCTAssertTrue(PKCEGenerator.isValidCodeVerifier(codeVerifier), "Generated code verifier should be valid")
    }
    
    func testCodeVerifierUniqueness() throws {
        // Generate multiple code verifiers and ensure they're unique
        let verifiers = (0..<10).map { _ in PKCEGenerator.generateCodeVerifier() }
        let uniqueVerifiers = Set(verifiers)
        
        XCTAssertEqual(verifiers.count, uniqueVerifiers.count, "Generated code verifiers should be unique")
    }
    
    func testCodeChallengeGeneration() throws {
        let codeVerifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let codeChallenge = PKCEGenerator.generateCodeChallenge(from: codeVerifier)
        
        // Test that code challenge is generated and not empty
        XCTAssertFalse(codeChallenge.isEmpty, "Code challenge should not be empty")
        
        // Test that same verifier produces same challenge (deterministic)
        let codeChallenge2 = PKCEGenerator.generateCodeChallenge(from: codeVerifier)
        XCTAssertEqual(codeChallenge, codeChallenge2, "Same code verifier should produce same code challenge")
        
        // Test that code challenge is URL-safe (no +, /, or = characters)
        XCTAssertFalse(codeChallenge.contains("+"), "Code challenge should not contain '+'")
        XCTAssertFalse(codeChallenge.contains("/"), "Code challenge should not contain '/'")
        XCTAssertFalse(codeChallenge.contains("="), "Code challenge should not contain '='")
    }
    
    func testCodeVerifierValidation() throws {
        // Test valid code verifiers
        XCTAssertTrue(PKCEGenerator.isValidCodeVerifier("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "Valid 43-char verifier should pass")
        XCTAssertTrue(PKCEGenerator.isValidCodeVerifier(String(repeating: "a", count: 43)), "Minimum length verifier should pass")
        XCTAssertTrue(PKCEGenerator.isValidCodeVerifier(String(repeating: "a", count: 128)), "Maximum length verifier should pass")
        XCTAssertTrue(PKCEGenerator.isValidCodeVerifier("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn-._~123"), "All allowed characters should pass")
        
        // Test invalid code verifiers - too short
        XCTAssertFalse(PKCEGenerator.isValidCodeVerifier(String(repeating: "a", count: 42)), "Too short verifier should fail")
        XCTAssertFalse(PKCEGenerator.isValidCodeVerifier(""), "Empty verifier should fail")
        
        // Test invalid code verifiers - too long
        XCTAssertFalse(PKCEGenerator.isValidCodeVerifier(String(repeating: "a", count: 129)), "Too long verifier should fail")
        
        // Test invalid characters
        XCTAssertFalse(PKCEGenerator.isValidCodeVerifier("invalid+char" + String(repeating: "a", count: 31)), "Verifier with '+' should fail")
        XCTAssertFalse(PKCEGenerator.isValidCodeVerifier("invalid/char" + String(repeating: "a", count: 31)), "Verifier with '/' should fail")
        XCTAssertFalse(PKCEGenerator.isValidCodeVerifier("invalid=char" + String(repeating: "a", count: 31)), "Verifier with '=' should fail")
        XCTAssertFalse(PKCEGenerator.isValidCodeVerifier("invalid@char" + String(repeating: "a", count: 31)), "Verifier with '@' should fail")
        XCTAssertFalse(PKCEGenerator.isValidCodeVerifier("invalid#char" + String(repeating: "a", count: 31)), "Verifier with '#' should fail")
        XCTAssertFalse(PKCEGenerator.isValidCodeVerifier("invalid space" + String(repeating: "a", count: 30)), "Verifier with space should fail")
    }
    
    func testBase64URLEncoding() throws {
        // Test the Data extension for Base64 URL encoding
        let testData = "Hello World!".data(using: .utf8)!
        let base64URL = testData.base64URLEncodedString()
        
        // Standard Base64 would be: SGVsbG8gV29ybGQh
        // Base64 URL should be the same in this case (no +, /, or = in this example)
        XCTAssertEqual(base64URL, "SGVsbG8gV29ybGQh", "Base64 URL encoding should work correctly")
        
        // Test with data that would normally have padding
        let testDataWithPadding = "Hello".data(using: .utf8)!
        let base64URLWithPadding = testDataWithPadding.base64URLEncodedString()
        
        // Standard Base64 would be: SGVsbG8=
        // Base64 URL should remove the padding
        XCTAssertEqual(base64URLWithPadding, "SGVsbG8", "Base64 URL encoding should remove padding")
        XCTAssertFalse(base64URLWithPadding.contains("="), "Base64 URL should not contain padding")
    }
    
    func testPKCEFlowIntegration() throws {
        // Test complete PKCE flow
        let codeVerifier = PKCEGenerator.generateCodeVerifier()
        let codeChallenge = PKCEGenerator.generateCodeChallenge(from: codeVerifier)
        
        // Verify the complete flow works
        XCTAssertTrue(PKCEGenerator.isValidCodeVerifier(codeVerifier), "Generated verifier should be valid")
        XCTAssertFalse(codeChallenge.isEmpty, "Generated challenge should not be empty")
        XCTAssertNotEqual(codeVerifier, codeChallenge, "Verifier and challenge should be different")
        
        // Verify challenge length is reasonable (Base64 encoded SHA256 is typically 43 chars without padding)
        XCTAssertEqual(codeChallenge.count, 43, "SHA256 Base64 URL encoded should be 43 characters")
    }
}