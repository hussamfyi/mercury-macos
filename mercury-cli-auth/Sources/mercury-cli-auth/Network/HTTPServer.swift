import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix

/// Lightweight HTTP server for OAuth callback handling
/// Uses SwiftNIO for efficient async HTTP operations
public class HTTPServer {
    
    // MARK: - Properties
    
    private let group: MultiThreadedEventLoopGroup
    private var bootstrap: ServerBootstrap?
    private var channel: Channel?
    private var isRunning = false
    
    /// Callback handler for authorization response
    public var authorizationCallback: ((String?, String?, Error?) -> Void)?
    
    /// Timeout callback handler for when authorization flow times out
    public var timeoutCallback: (() -> Void)?
    
    /// Timeout task for authorization flow
    private var timeoutTask: Scheduled<Void>?
    
    // MARK: - Initialization
    
    public init() {
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        setupBootstrap()
    }
    
    deinit {
        try? shutdown()
    }
    
    // MARK: - Server Management
    
    /// Start the HTTP server on specified port
    /// - Parameter port: Port number to bind to
    /// - Returns: The actual port the server is listening on
    /// - Throws: HTTPServerError if startup fails
    public func start(on port: Int) async throws -> Int {
        guard !isRunning else {
            throw HTTPServerError.serverAlreadyRunning
        }
        
        guard let bootstrap = self.bootstrap else {
            throw HTTPServerError.serverNotConfigured
        }
        
        do {
            // Bind to the specified port
            self.channel = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
            self.isRunning = true
            
            guard let localAddress = channel?.localAddress,
                  let actualPort = localAddress.port else {
                throw HTTPServerError.failedToGetPort
            }
            
            print("HTTP server listening on port \(actualPort)")
            return actualPort
            
        } catch {
            throw HTTPServerError.bindFailed(port: port, underlying: error)
        }
    }
    
    /// Start the HTTP server with automatic port selection
    /// Tries ports in preferred range (8080-8090) then fallback options
    /// - Returns: The actual port the server is listening on
    /// - Throws: HTTPServerError if all port attempts fail
    public func startWithPortSelection() async throws -> Int {
        guard !isRunning else {
            throw HTTPServerError.serverAlreadyRunning
        }
        
        // Define port ranges to try
        let preferredPorts = Array(8080...8090)
        let fallbackPorts = [3000, 4000, 5000, 8000, 9000, 8888, 7777]
        let randomPorts = generateRandomPorts(count: 5, excluding: preferredPorts + fallbackPorts)
        
        let allPortsToTry = preferredPorts + fallbackPorts + randomPorts
        var lastError: Error?
        
        print("Attempting to start HTTP server on available port...")
        
        for port in allPortsToTry {
            do {
                let actualPort = try await start(on: port)
                print("✅ Successfully bound to port \(actualPort)")
                return actualPort
            } catch {
                lastError = error
                // Continue to next port
                print("Port \(port) unavailable, trying next...")
                
                // Reset server state for next attempt
                self.isRunning = false
                if let channel = self.channel {
                    try? channel.close().wait()
                    self.channel = nil
                }
            }
        }
        
        // If we get here, all ports failed
        throw HTTPServerError.allPortsUnavailable(lastError: lastError)
    }
    
    /// Start the HTTP server with automatic port selection and timeout
    /// - Parameter timeoutSeconds: Timeout in seconds (default: 30)
    /// - Returns: The actual port the server is listening on
    /// - Throws: HTTPServerError if startup fails or times out
    public func startWithPortSelectionAndTimeout(timeoutSeconds: TimeInterval = 30.0) async throws -> Int {
        // Start the server with port selection
        let port = try await startWithPortSelection()
        
        // Schedule timeout task
        guard let channel = self.channel else {
            throw HTTPServerError.serverNotConfigured
        }
        
        print("⏱️  Starting \(Int(timeoutSeconds))-second timeout for OAuth authorization...")
        
        self.timeoutTask = channel.eventLoop.scheduleTask(in: .seconds(Int64(timeoutSeconds))) {
            print("⏰ Authorization flow timed out after \(Int(timeoutSeconds)) seconds")
            
            // Notify timeout callback if set
            self.timeoutCallback?()
            
            // Invoke authorization callback with timeout error
            self.authorizationCallback?(nil, nil, HTTPServerError.authorizationTimeout)
            
            // Shutdown the server
            try? self.shutdown()
        }
        
        return port
    }
    
    /// Start the HTTP server with simplified interface
    /// - Returns: The actual port the server is listening on
    /// - Throws: HTTPServerError if startup fails
    public func start() async throws -> Int {
        return try await startWithPortSelection()
    }
    
    /// Wait for OAuth callback response
    /// - Returns: OAuth callback response with authorization code and state
    /// - Throws: HTTPServerError if callback fails or times out
    public func waitForCallback() async throws -> OAuthCallbackResponse {
        return try await withCheckedThrowingContinuation { continuation in
            self.authorizationCallback = { authCode, state, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    let response = OAuthCallbackResponse(
                        authorizationCode: authCode,
                        state: state,
                        error: nil,
                        errorDescription: nil
                    )
                    continuation.resume(returning: response)
                }
            }
        }
    }
    
    /// Stop the HTTP server
    public func stop() async throws {
        try shutdown()
    }
    
    /// Cancel any active timeout
    internal func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }
    
    /// Shutdown the HTTP server
    public func shutdown() throws {
        guard isRunning else { return }
        
        isRunning = false
        
        // Cancel any active timeout
        cancelTimeout()
        
        // Close the server channel
        if let channel = self.channel {
            try channel.close().wait()
            self.channel = nil
        }
        
        // Shutdown the event loop group
        try group.syncShutdownGracefully()
    }
    
    // MARK: - Private Methods
    
    /// Generate random ports for fallback attempts
    /// - Parameters:
    ///   - count: Number of random ports to generate
    ///   - excluding: Ports to exclude from generation
    /// - Returns: Array of random port numbers
    private func generateRandomPorts(count: Int, excluding: [Int]) -> [Int] {
        let excludedSet = Set(excluding)
        var randomPorts: [Int] = []
        
        while randomPorts.count < count {
            let randomPort = Int.random(in: 1024...65535) // User ports range
            if !excludedSet.contains(randomPort) && !randomPorts.contains(randomPort) {
                randomPorts.append(randomPort)
            }
        }
        
        return randomPorts
    }
    
    // MARK: - Private Setup
    
    private func setupBootstrap() {
        self.bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                return channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPCallbackHandler(server: self))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
    }
}

// MARK: - HTTP Handler

/// HTTP request handler for OAuth callback
private class HTTPCallbackHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    
    private weak var server: HTTPServer?
    private var requestHead: HTTPRequestHead?
    private var requestComplete = false
    
    init(server: HTTPServer) {
        self.server = server
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)
        
        switch reqPart {
        case .head(let head):
            self.requestHead = head
            
        case .body:
            // We don't need to handle body for OAuth callback
            break
            
        case .end:
            self.requestComplete = true
            self.handleRequest(context: context)
        }
    }
    
    private func handleRequest(context: ChannelHandlerContext) {
        guard let head = requestHead else {
            sendErrorResponse(context: context, message: "Invalid request")
            return
        }
        
        // Parse callback URL for OAuth parameters
        if head.uri.hasPrefix("/callback") {
            handleOAuthCallback(context: context, uri: head.uri)
        } else {
            send404Response(context: context)
        }
    }
    
    private func handleOAuthCallback(context: ChannelHandlerContext, uri: String) {
        // Parse query parameters from callback URL
        guard let url = URL(string: "http://localhost\(uri)"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            sendErrorResponse(context: context, message: "Invalid callback URL")
            return
        }
        
        var authCode: String?
        var state: String?
        var error: String?
        
        for item in queryItems {
            switch item.name {
            case "code":
                authCode = item.value
            case "state":
                state = item.value
            case "error":
                error = item.value
            default:
                break
            }
        }
        
        // Cancel timeout since we received a callback
        server?.cancelTimeout()
        
        if let error = error {
            // OAuth error from authorization server
            let oauthError = HTTPServerError.oauthError(error)
            sendErrorResponse(context: context, message: "Authorization failed: \(error)")
            server?.authorizationCallback?(nil, nil, oauthError)
        } else if let authCode = authCode {
            // Successful authorization
            sendSuccessResponse(context: context)
            server?.authorizationCallback?(authCode, state, nil)
        } else {
            // Missing required parameters
            sendErrorResponse(context: context, message: "Missing authorization code")
            server?.authorizationCallback?(nil, nil, HTTPServerError.missingAuthorizationCode)
        }
        
        // Schedule server shutdown after response
        context.eventLoop.scheduleTask(in: .milliseconds(100)) {
            try? self.server?.shutdown()
        }
    }
    
    private func sendSuccessResponse(context: ChannelHandlerContext) {
        let responseBody = """
        <html>
        <head><title>Authorization Successful</title></head>
        <body>
            <h1>✅ Authorization Successful!</h1>
            <p>You can now close this window and return to the Mercury CLI.</p>
            <script>setTimeout(() => window.close(), 2000);</script>
        </body>
        </html>
        """
        
        sendHTMLResponse(context: context, statusCode: .ok, body: responseBody)
    }
    
    private func sendErrorResponse(context: ChannelHandlerContext, message: String) {
        let responseBody = """
        <html>
        <head><title>Authorization Error</title></head>
        <body>
            <h1>❌ Authorization Error</h1>
            <p>\(message)</p>
            <p>Please try again or contact support.</p>
            <script>setTimeout(() => window.close(), 3000);</script>
        </body>
        </html>
        """
        
        sendHTMLResponse(context: context, statusCode: .badRequest, body: responseBody)
    }
    
    private func send404Response(context: ChannelHandlerContext) {
        let responseBody = """
        <html>
        <head><title>Not Found</title></head>
        <body>
            <h1>404 - Not Found</h1>
            <p>The requested path was not found.</p>
        </body>
        </html>
        """
        
        sendHTMLResponse(context: context, statusCode: .notFound, body: responseBody)
    }
    
    private func sendHTMLResponse(context: ChannelHandlerContext, statusCode: HTTPResponseStatus, body: String) {
        let responseHead = HTTPResponseHead(
            version: .http1_1,
            status: statusCode,
            headers: HTTPHeaders([
                ("Content-Type", "text/html; charset=utf-8"),
                ("Content-Length", String(body.utf8.count)),
                ("Connection", "close")
            ])
        )
        
        context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
        
        let bodyData = ByteBuffer(string: body)
        context.write(self.wrapOutboundOut(.body(.byteBuffer(bodyData))), promise: nil)
        
        context.writeAndFlush(self.wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }
}

// MARK: - Error Types

/// HTTP server specific errors
public enum HTTPServerError: Error, LocalizedError {
    case serverAlreadyRunning
    case serverNotConfigured
    case bindFailed(port: Int, underlying: Error)
    case failedToGetPort
    case oauthError(String)
    case missingAuthorizationCode
    case serverStartupTimeout
    case allPortsUnavailable(lastError: Error?)
    case authorizationTimeout
    
    public var errorDescription: String? {
        switch self {
        case .serverAlreadyRunning:
            return "HTTP server is already running"
        case .serverNotConfigured:
            return "HTTP server is not properly configured"
        case .bindFailed(let port, let underlying):
            return "Failed to bind to port \(port): \(underlying.localizedDescription)"
        case .failedToGetPort:
            return "Failed to determine server port"
        case .oauthError(let error):
            return "OAuth authorization error: \(error)"
        case .missingAuthorizationCode:
            return "Authorization code not received in callback"
        case .serverStartupTimeout:
            return "Server startup timed out"
        case .allPortsUnavailable(let lastError):
            let underlying = lastError?.localizedDescription ?? "Unknown error"
            return "All attempted ports are unavailable. Last error: \(underlying)"
        case .authorizationTimeout:
            return "OAuth authorization flow timed out - user did not complete authorization within the specified time limit"
        }
    }
}