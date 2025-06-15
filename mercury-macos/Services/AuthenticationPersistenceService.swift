//
//  AuthenticationPersistenceService.swift
//  Mercury
//
//  Created by Claude on 2025-06-15.
//

import Foundation
import Combine
import SwiftUI

// MARK: - Authentication Status Persistence and Recovery Service

@MainActor
class AuthenticationPersistenceService: ObservableObject {
    static let shared = AuthenticationPersistenceService()
    
    @Published var lastKnownStatus: ConnectionStatus = .disconnected
    @Published var lastSuccessfulConnection: Date?
    @Published var connectionHistory: [ConnectionEvent] = []
    @Published var persistentUserInfo: PersistentUserInfo?
    @Published var recoveryAttempts: Int = 0
    @Published var isRecoveryInProgress: Bool = false
    
    private let maxConnectionHistory = 50
    private let maxRecoveryAttempts = 3
    private let recoveryBackoffIntervals: [TimeInterval] = [5.0, 15.0, 30.0, 60.0] // seconds
    
    // UserDefaults keys for persistence
    private let lastStatusKey = "mercury_last_connection_status"
    private let lastConnectionTimeKey = "mercury_last_connection_time"
    private let connectionHistoryKey = "mercury_connection_history"
    private let userInfoKey = "mercury_persistent_user_info"
    private let recoveryAttemptsKey = "mercury_recovery_attempts"
    private let lastRecoveryAttemptKey = "mercury_last_recovery_attempt"
    
    private var windowManager: WindowManager?
    private var authManager: AuthManager?
    private var cancellables = Set<AnyCancellable>()
    private var recoveryTimer: Timer?
    
    init() {
        loadPersistedData()
        setupPeriodicPersistence()
    }
    
    // MARK: - Setup and Configuration
    
    func configure(windowManager: WindowManager, authManager: AuthManager) {
        self.windowManager = windowManager
        self.authManager = authManager
        
        setupStatusObservation()
        setupAuthManagerObservation()
        
        // Attempt recovery on startup if needed
        Task {
            await attemptStartupRecovery()
        }
    }
    
    private func setupStatusObservation() {
        guard let windowManager = windowManager else { return }
        
        windowManager.$connectionStatus
            .removeDuplicates()
            .sink { [weak self] status in
                self?.handleConnectionStatusChange(status)
            }
            .store(in: &cancellables)
    }
    
    private func setupAuthManagerObservation() {
        guard let authManager = authManager else { return }
        
        // Observe authentication state changes
        authManager.$isAuthenticated
            .removeDuplicates()
            .sink { [weak self] isAuthenticated in
                self?.handleAuthenticationStateChange(isAuthenticated)
            }
            .store(in: &cancellables)
        
        // Observe user info changes
        authManager.$currentUser
            .removeDuplicates { $0?.id == $1?.id }
            .sink { [weak self] user in
                self?.handleUserInfoChange(user)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Status Persistence
    
    private func handleConnectionStatusChange(_ status: ConnectionStatus) {
        lastKnownStatus = status
        
        // Record connection event
        let event = ConnectionEvent(
            status: status,
            timestamp: Date(),
            sessionId: getCurrentSessionId()
        )
        addConnectionEvent(event)
        
        // Update last successful connection time
        if status.isConnected {
            lastSuccessfulConnection = Date()
            recoveryAttempts = 0 // Reset recovery attempts on successful connection
        }
        
        // Persist immediately for important state changes
        if status.isConnected || status.isError {
            persistCurrentState()
        }
    }
    
    private func handleAuthenticationStateChange(_ isAuthenticated: Bool) {
        if isAuthenticated {
            // Authentication successful - update connection status
            windowManager?.connectionStatus = .connected
            recoveryAttempts = 0
        } else {
            // Authentication lost - update status and prepare for recovery
            if windowManager?.connectionStatus.isConnected == true {
                windowManager?.connectionStatus = .disconnected
                scheduleRecoveryAttempt()
            }
        }
        
        persistCurrentState()
    }
    
    private func handleUserInfoChange(_ user: AuthenticatedUser?) {
        if let user = user {
            persistentUserInfo = PersistentUserInfo(
                id: user.id,
                username: user.username,
                displayName: user.displayName,
                lastSeen: Date()
            )
        } else {
            persistentUserInfo = nil
        }
        
        persistCurrentState()
    }
    
    private func addConnectionEvent(_ event: ConnectionEvent) {
        connectionHistory.append(event)
        
        // Limit history size
        if connectionHistory.count > maxConnectionHistory {
            connectionHistory.removeFirst(connectionHistory.count - maxConnectionHistory)
        }
    }
    
    // MARK: - Recovery Logic
    
    private func attemptStartupRecovery() async {
        // Check if we should attempt recovery based on last known state
        guard shouldAttemptRecovery() else { return }
        
        isRecoveryInProgress = true
        
        do {
            let recoverySuccessful = await performRecoveryAttempt()
            
            if recoverySuccessful {
                resetRecoveryState()
            } else {
                handleRecoveryFailure()
            }
        } catch {
            handleRecoveryError(error)
        }
        
        isRecoveryInProgress = false
    }
    
    private func shouldAttemptRecovery() -> Bool {
        // Don't attempt recovery if too many recent attempts
        guard recoveryAttempts < maxRecoveryAttempts else { return false }
        
        // Don't attempt if last attempt was too recent
        if let lastAttempt = getLastRecoveryAttemptTime(),
           Date().timeIntervalSince(lastAttempt) < getRecoveryBackoffInterval() {
            return false
        }
        
        // Attempt recovery if we had a successful connection recently
        if let lastConnection = lastSuccessfulConnection,
           Date().timeIntervalSince(lastConnection) < 24 * 60 * 60 { // Within 24 hours
            return true
        }
        
        // Attempt recovery if we have persistent user info
        return persistentUserInfo != nil
    }
    
    private func performRecoveryAttempt() async -> Bool {
        guard let authManager = authManager else { return false }
        
        // Increment recovery attempts
        recoveryAttempts += 1
        setLastRecoveryAttemptTime(Date())
        
        // Update status to show recovery in progress
        windowManager?.connectionStatus = .connecting
        
        do {
            // Attempt to refresh authentication
            let success = await authManager.refreshAuthenticationIfNeeded()
            
            if success {
                // Verify connection is actually working
                return await verifyConnectionHealth()
            } else {
                return false
            }
        } catch {
            return false
        }
    }
    
    private func verifyConnectionHealth() async -> Bool {
        // This would perform a lightweight API call to verify the connection
        // For now, we'll simulate this check
        
        // Wait a moment for connection to stabilize
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Check if authentication is still valid
        return authManager?.isAuthenticated == true
    }
    
    private func scheduleRecoveryAttempt() {
        // Cancel any existing recovery timer
        recoveryTimer?.invalidate()
        
        guard shouldAttemptRecovery() else { return }
        
        let backoffInterval = getRecoveryBackoffInterval()
        
        recoveryTimer = Timer.scheduledTimer(withTimeInterval: backoffInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.attemptStartupRecovery()
            }
        }
    }
    
    private func getRecoveryBackoffInterval() -> TimeInterval {
        let index = min(recoveryAttempts, recoveryBackoffIntervals.count - 1)
        return recoveryBackoffIntervals[index]
    }
    
    private func resetRecoveryState() {
        recoveryAttempts = 0
        recoveryTimer?.invalidate()
        recoveryTimer = nil
        setLastRecoveryAttemptTime(nil)
    }
    
    private func handleRecoveryFailure() {
        if recoveryAttempts >= maxRecoveryAttempts {
            // Max attempts reached - stop trying for this session
            windowManager?.connectionStatus = .error
        } else {
            // Schedule next attempt with backoff
            windowManager?.connectionStatus = .disconnected
            scheduleRecoveryAttempt()
        }
    }
    
    private func handleRecoveryError(_ error: Error) {
        windowManager?.connectionStatus = .error
        
        // Log error for debugging
        addConnectionEvent(ConnectionEvent(
            status: .error,
            timestamp: Date(),
            sessionId: getCurrentSessionId(),
            error: error.localizedDescription
        ))
    }
    
    // MARK: - Data Persistence
    
    private func persistCurrentState() {
        UserDefaults.standard.set(lastKnownStatus.rawValue, forKey: lastStatusKey)
        
        if let lastConnection = lastSuccessfulConnection {
            UserDefaults.standard.set(lastConnection, forKey: lastConnectionTimeKey)
        }
        
        UserDefaults.standard.set(recoveryAttempts, forKey: recoveryAttemptsKey)
        
        // Persist connection history
        if let historyData = try? JSONEncoder().encode(connectionHistory) {
            UserDefaults.standard.set(historyData, forKey: connectionHistoryKey)
        }
        
        // Persist user info
        if let userInfo = persistentUserInfo,
           let userInfoData = try? JSONEncoder().encode(userInfo) {
            UserDefaults.standard.set(userInfoData, forKey: userInfoKey)
        }
    }
    
    private func loadPersistedData() {
        // Load last known status
        if let statusRawValue = UserDefaults.standard.object(forKey: lastStatusKey) as? String,
           let status = ConnectionStatus(rawValue: statusRawValue) {
            lastKnownStatus = status
        }
        
        // Load last connection time
        if let connectionTime = UserDefaults.standard.object(forKey: lastConnectionTimeKey) as? Date {
            lastSuccessfulConnection = connectionTime
        }
        
        // Load recovery attempts
        recoveryAttempts = UserDefaults.standard.integer(forKey: recoveryAttemptsKey)
        
        // Load connection history
        if let historyData = UserDefaults.standard.data(forKey: connectionHistoryKey),
           let history = try? JSONDecoder().decode([ConnectionEvent].self, from: historyData) {
            connectionHistory = history
        }
        
        // Load user info
        if let userInfoData = UserDefaults.standard.data(forKey: userInfoKey),
           let userInfo = try? JSONDecoder().decode(PersistentUserInfo.self, from: userInfoData) {
            persistentUserInfo = userInfo
        }
    }
    
    private func setupPeriodicPersistence() {
        // Persist state every 30 seconds to ensure we don't lose data
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.persistCurrentState()
        }
    }
    
    // MARK: - Recovery Attempt Tracking
    
    private func setLastRecoveryAttemptTime(_ time: Date?) {
        if let time = time {
            UserDefaults.standard.set(time, forKey: lastRecoveryAttemptKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastRecoveryAttemptKey)
        }
    }
    
    private func getLastRecoveryAttemptTime() -> Date? {
        return UserDefaults.standard.object(forKey: lastRecoveryAttemptKey) as? Date
    }
    
    // MARK: - Session Management
    
    private func getCurrentSessionId() -> String {
        // Generate or retrieve session ID for this app launch
        let sessionKey = "mercury_current_session_id"
        
        if let existingSession = UserDefaults.standard.string(forKey: sessionKey) {
            return existingSession
        } else {
            let newSession = UUID().uuidString
            UserDefaults.standard.set(newSession, forKey: sessionKey)
            return newSession
        }
    }
    
    // MARK: - Public Interface
    
    func getConnectionHealthScore() -> Double {
        guard !connectionHistory.isEmpty else { return 0.5 }
        
        // Calculate health score based on recent connection history
        let recentEvents = connectionHistory.suffix(10)
        let connectedEvents = recentEvents.filter { $0.status.isConnected }
        
        return Double(connectedEvents.count) / Double(recentEvents.count)
    }
    
    func getLastConnectionDuration() -> TimeInterval? {
        // Find the most recent connected period
        let reversedHistory = connectionHistory.reversed()
        
        var lastDisconnect: Date?
        var lastConnect: Date?
        
        for event in reversedHistory {
            if event.status.isConnected && lastConnect == nil {
                lastConnect = event.timestamp
            } else if !event.status.isConnected && lastConnect != nil && lastDisconnect == nil {
                lastDisconnect = event.timestamp
                break
            }
        }
        
        if let connect = lastConnect, let disconnect = lastDisconnect {
            return connect.timeIntervalSince(disconnect)
        }
        
        return nil
    }
    
    func clearPersistedData() {
        UserDefaults.standard.removeObject(forKey: lastStatusKey)
        UserDefaults.standard.removeObject(forKey: lastConnectionTimeKey)
        UserDefaults.standard.removeObject(forKey: connectionHistoryKey)
        UserDefaults.standard.removeObject(forKey: userInfoKey)
        UserDefaults.standard.removeObject(forKey: recoveryAttemptsKey)
        UserDefaults.standard.removeObject(forKey: lastRecoveryAttemptKey)
        
        // Reset state
        lastKnownStatus = .disconnected
        lastSuccessfulConnection = nil
        connectionHistory = []
        persistentUserInfo = nil
        recoveryAttempts = 0
        resetRecoveryState()
    }
    
    func forceRecoveryAttempt() {
        guard !isRecoveryInProgress else { return }
        
        recoveryAttempts = 0 // Reset to allow immediate attempt
        
        Task {
            await attemptStartupRecovery()
        }
    }
}

// MARK: - Supporting Data Types

struct ConnectionEvent: Codable {
    let id: UUID
    let status: ConnectionStatus
    let timestamp: Date
    let sessionId: String
    let error: String?
    
    init(status: ConnectionStatus, timestamp: Date, sessionId: String, error: String? = nil) {
        self.id = UUID()
        self.status = status
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.error = error
    }
}

struct PersistentUserInfo: Codable, Equatable {
    let id: String
    let username: String
    let displayName: String?
    let lastSeen: Date
    
    static func == (lhs: PersistentUserInfo, rhs: PersistentUserInfo) -> Bool {
        return lhs.id == rhs.id && lhs.username == rhs.username
    }
}

// MARK: - ConnectionStatus Extensions

extension ConnectionStatus: Codable {
    enum CodingKeys: String, CodingKey {
        case connected, connecting, disconnected, error, refreshing
    }
    
    var rawValue: String {
        switch self {
        case .connected: return "connected"
        case .connecting: return "connecting"
        case .disconnected: return "disconnected"
        case .error: return "error"
        case .refreshing: return "refreshing"
        }
    }
    
    init?(rawValue: String) {
        switch rawValue {
        case "connected": self = .connected
        case "connecting": self = .connecting
        case "disconnected": self = .disconnected
        case "error": self = .error
        case "refreshing": self = .refreshing
        default: return nil
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        
        guard let status = ConnectionStatus(rawValue: rawValue) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid status: \(rawValue)")
            )
        }
        
        self = status
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Recovery Status View

struct RecoveryStatusView: View {
    @ObservedObject var persistenceService: AuthenticationPersistenceService
    @State private var showingDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Recovery status header
            HStack {
                if persistenceService.isRecoveryInProgress {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Recovering connection...")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else if persistenceService.recoveryAttempts > 0 {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.orange)
                    Text("Recovery attempted (\(persistenceService.recoveryAttempts)/3)")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.green)
                    Text("Ready")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                Button("Details") {
                    showingDetails = true
                }
                .font(.caption)
            }
            
            // Last connection info
            if let lastConnection = persistenceService.lastSuccessfulConnection {
                Text("Last connected: \(lastConnection, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Connection health score
            let healthScore = persistenceService.getConnectionHealthScore()
            HStack {
                Text("Health:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                ProgressView(value: healthScore, total: 1.0)
                    .frame(width: 60)
                
                Text("\(Int(healthScore * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
        .sheet(isPresented: $showingDetails) {
            RecoveryDetailsView(persistenceService: persistenceService)
        }
    }
}

// MARK: - Recovery Details View

struct RecoveryDetailsView: View {
    @ObservedObject var persistenceService: AuthenticationPersistenceService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                // Current status
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Status")
                        .font(.headline)
                    
                    HStack {
                        statusIcon
                        Text(statusText)
                            .font(.body)
                    }
                }
                
                Divider()
                
                // Recovery attempts
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recovery Information")
                        .font(.headline)
                    
                    Text("Attempts: \(persistenceService.recoveryAttempts) / 3")
                    
                    if persistenceService.isRecoveryInProgress {
                        Text("Status: In progress...")
                            .foregroundColor(.blue)
                    } else if persistenceService.recoveryAttempts >= 3 {
                        Text("Status: Max attempts reached")
                            .foregroundColor(.red)
                    } else {
                        Text("Status: Ready for recovery")
                            .foregroundColor(.green)
                    }
                }
                
                Divider()
                
                // Connection history
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Connection Events")
                        .font(.headline)
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(persistenceService.connectionHistory.suffix(10).reversed(), id: \.id) { event in
                                HStack {
                                    connectionEventIcon(for: event.status)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.status.displayName)
                                            .font(.caption)
                                        Text(event.timestamp, style: .time)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        
                                        if let error = event.error {
                                            Text(error)
                                                .font(.caption2)
                                                .foregroundColor(.red)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                
                Spacer()
                
                // Actions
                HStack {
                    Button("Force Recovery") {
                        persistenceService.forceRecoveryAttempt()
                    }
                    .disabled(persistenceService.isRecoveryInProgress)
                    
                    Spacer()
                    
                    Button("Clear Data") {
                        persistenceService.clearPersistedData()
                    }
                    .foregroundColor(.red)
                }
            }
            .padding()
            .navigationTitle("Authentication Recovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch persistenceService.lastKnownStatus {
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .connecting:
            Image(systemName: "arrow.clockwise")
                .foregroundColor(.blue)
        case .refreshing:
            Image(systemName: "arrow.clockwise")
                .foregroundColor(.orange)
        case .disconnected:
            Image(systemName: "wifi.slash")
                .foregroundColor(.gray)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
        }
    }
    
    private var statusText: String {
        persistenceService.lastKnownStatus.displayName
    }
    
    @ViewBuilder
    private func connectionEventIcon(for status: ConnectionStatus) -> some View {
        switch status {
        case .connected:
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
        case .connecting:
            Circle()
                .fill(.blue)
                .frame(width: 8, height: 8)
        case .refreshing:
            Circle()
                .fill(.orange)
                .frame(width: 8, height: 8)
        case .disconnected:
            Circle()
                .fill(.gray)
                .frame(width: 8, height: 8)
        case .error:
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
        }
    }
}

extension ConnectionStatus {
    var displayName: String {
        switch self {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .refreshing: return "Refreshing"
        case .disconnected: return "Disconnected"
        case .error: return "Error"
        }
    }
}