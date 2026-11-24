//
//  SSEClient.swift
//  notifly-ios-sdk
//
// Transport layer for the real-time server-to-SDK channel.
// Receives SSE streams through URLSession.bytes(for:) and AsyncSequence,
// with exponential reconnect backoff, heartbeat timeouts, and Last-Event-ID tracking.
//

import Foundation

@available(iOSApplicationExtension, unavailable)
final class SSEClient: @unchecked Sendable {

    // MARK: - Public types

    enum State: Equatable {

        case idle
        case connecting
        case open
        case reconnecting(attempt: Int)
        case stopped
    }

    enum ConnectionError: Error, Equatable {

        case invalidURL
        case invalidResponse
        case httpStatus(Int)
        case heartbeatTimeout
    }

    /// Returns the HTTP response and line sequence so tests can inject deterministic input.
    typealias StreamLineProvider = (URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>)

    // MARK: - Static defaults

    static let defaultBackoffSchedule: [TimeInterval] = [10]
    static let defaultHeartbeatTimeout: TimeInterval = 60
    /// Resets backoff attempts after an open connection lasts at least this interval.
    static let openStableThreshold: TimeInterval = 30

    // MARK: - Configuration (immutable)

    private let projectId: String
    private let notiflyUserId: String
    private let deviceId: String?
    private let tokenProvider: () async throws -> String
    /// If nil, makeRequest throws invalidURL during connection and enters backoff.
    /// Initialization itself succeeds to avoid terminating the host application.
    private let baseURL: URL?
    private let backoffSchedule: [TimeInterval]
    private let heartbeatTimeout: TimeInterval
    private let streamLineProvider: StreamLineProvider
    private let jitterProvider: () -> Double
    private let nowProvider: () -> Date

    // MARK: - Mutable state protected by stateAccessQueue

    private let stateAccessQueue = DispatchQueue(label: "com.notifly.sse.stateAccessQueue")
    private var _state: State = .idle
    private var _lastEventId: String?
    private var _connectionTask: Task<Void, Never>?
    private var _lastDataAt: Date
    private var _lastOpenAt: Date?

    // MARK: - Callbacks
    //
    // Callbacks are dispatched to the main queue. Avoid reentrant synchronous access
    // to stateAccessQueue, which can deadlock if a setter is called from that queue.

    var onMessage: ((_ type: String, _ data: String) -> Void)? {
        get { stateAccessQueue.sync { _onMessage } }
        set { stateAccessQueue.sync { _onMessage = newValue } }
    }
    var onState: ((State) -> Void)? {
        get { stateAccessQueue.sync { _onState } }
        set { stateAccessQueue.sync { _onState = newValue } }
    }
    private var _onMessage: ((_ type: String, _ data: String) -> Void)?
    private var _onState: ((State) -> Void)?

    // MARK: - Init

    init(
        projectId: String,
        notiflyUserId: String,
        deviceId: String?,
        tokenProvider: @escaping () async throws -> String,
        session: URLSession = SSEClient.makeDefaultSession(),
        baseURLString: String = NotiflyConstant.EndPoint.streamEndPoint,
        backoffSchedule: [TimeInterval] = SSEClient.defaultBackoffSchedule,
        heartbeatTimeout: TimeInterval = SSEClient.defaultHeartbeatTimeout,
        streamLineProvider: StreamLineProvider? = nil,
        jitterProvider: @escaping () -> Double = { Double.random(in: 0..<1) },
        nowProvider: @escaping () -> Date = { Date() }
    ) {
        self.projectId = projectId
        self.notiflyUserId = notiflyUserId
        self.deviceId = deviceId
        self.tokenProvider = tokenProvider
        // Fall back to the built-in base URL if the supplied value is invalid. If both fail,
        // retain nil and report invalidURL when connecting instead of crashing the host app.
        let resolvedBaseURL = URL(string: baseURLString) ?? URL(string: NotiflyConstant.EndPoint.streamEndPoint)
        if resolvedBaseURL == nil {
            Logger.error("SSEClient: failed to resolve baseURL — connect will fail with invalidURL")
        }
        baseURL = resolvedBaseURL
        self.backoffSchedule = backoffSchedule.isEmpty ? SSEClient.defaultBackoffSchedule : backoffSchedule
        self.heartbeatTimeout = heartbeatTimeout
        self.streamLineProvider = streamLineProvider ?? SSEClient.makeURLSessionStreamProvider(session: session)
        self.jitterProvider = jitterProvider
        self.nowProvider = nowProvider
        _lastDataAt = nowProvider()
    }

    private static func makeURLSessionStreamProvider(session: URLSession) -> StreamLineProvider {
        return { request in
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ConnectionError.invalidResponse
            }
            return (http, splitSSELines(bytes))
        }
    }

    deinit {
        // Task.cancel() is thread-safe and does not require stateAccessQueue synchronization.
        // Synchronously entering the same queue during deinitialization could deadlock.
        _connectionTask?.cancel()
    }

    // MARK: - Public API

    /// Does nothing when already connecting, open, or reconnecting.
    /// Call disconnect() followed by connect() to force a new connection.
    func connect() {
        // Create the task and assign _connectionTask in the same synchronized block
        // so a concurrent disconnect cannot miss the newly created task.
        var didStart = false
        stateAccessQueue.sync {
            switch _state {
            case .connecting, .open, .reconnecting:
                return
            default:
                break
            }
            _connectionTask?.cancel()
            _state = .connecting
            let task = Task { [weak self] in
                guard let self = self else { return }
                await runConnectionLoop()
            }
            _connectionTask = task
            didStart = true
        }
        if didStart {
            emitState(.connecting)
        }
    }

    /// Transitions to stopped and cancels the connection. Call connect() to restart.
    func disconnect() {
        var alreadyStopped = false
        var connTask: Task<Void, Never>?
        stateAccessQueue.sync {
            alreadyStopped = (_state == .stopped)
            connTask = _connectionTask
            _connectionTask = nil
            _state = .stopped
        }

        connTask?.cancel()
        if !alreadyStopped {
            Logger.info("SSE disconnected")
            emitState(.stopped)
        }
    }

    var state: State {
        stateAccessQueue.sync { _state }
    }

    var lastEventId: String? {
        stateAccessQueue.sync { _lastEventId }
    }

    // MARK: - Connection loop

    private func runConnectionLoop() async {
        var attempt = 0

        while !Task.isCancelled, !isStopped() {
            do {
                try await runOneConnection(attempt: attempt)
            }
            catch is CancellationError {
                break
            }
            catch {
                Logger.info("SSE connection error: \(error)")
            }

            if isStopped() || Task.isCancelled { break }

            // Reset attempts only after the connection remained open long enough to be healthy.
            // Time spent connecting alone does not reset the accumulated backoff.
            let openedAt: Date? = stateAccessQueue.sync { _lastOpenAt }
            if let openedAt = openedAt,
                nowProvider().timeIntervalSince(openedAt) >= SSEClient.openStableThreshold
            {
                attempt = 0
            }

            attempt += 1
            transition(to: .reconnecting(attempt: attempt))
            let delay = backoffDelay(attempt: attempt)
            do {
                try await Task.sleep(nanoseconds: nanoseconds(from: delay))
            }
            catch {
                break
            }
        }
    }

    private func runOneConnection(attempt: Int) async throws {
        if attempt > 0 {
            transition(to: .connecting)
        }

        // Refresh lastDataAt before requesting a token so a connection started after a long
        // idle period does not time out before receiving its first line.
        setLastDataAt(nowProvider())

        let token = try await tokenProvider()
        let request = try makeRequest(token: token)

        let (http, lines) = try await streamLineProvider(request)
        // Reject non-200 statuses, including 204 and 304, to avoid reconnect loops on empty bodies.
        guard http.statusCode == 200 else {
            Logger.error("SSE handshake failed: status=\(http.statusCode) projectId=\(projectId)")
            throw ConnectionError.httpStatus(http.statusCode)
        }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        guard contentType.hasPrefix("text/event-stream") else {
            Logger.error("SSE invalid content-type: \(contentType) projectId=\(projectId)")
            throw ConnectionError.invalidResponse
        }

        transition(to: .open)
        Logger.info("SSE connected")
        setLastDataAt(nowProvider())

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                guard let self = self else { return }
                try await consumeStream(lines: lines)
            }
            group.addTask { [weak self] in
                guard let self = self else { return }
                try await runHeartbeatWatchdog()
            }
            // Wait for the first child to finish or throw, then cancel the remaining children.
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func consumeStream(lines: AsyncThrowingStream<String, Error>) async throws {
        let parser = SSELineParser()
        for try await line in lines {
            try Task.checkCancellation()
            setLastDataAt(nowProvider())
            if let event = parser.feed(line) {
                if let id = event.id {
                    setLastEventId(id)
                }
                emitMessage(type: event.type, data: event.data)
            }
        }
    }

    private func runHeartbeatWatchdog() async throws {
        // Check every quarter-timeout, capped at five seconds, to limit timeout detection delay.
        let checkInterval = max(min(heartbeatTimeout / 4, 5), 0.05)
        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: nanoseconds(from: checkInterval))
            let elapsed = nowProvider().timeIntervalSince(getLastDataAt())
            if elapsed > heartbeatTimeout {
                throw ConnectionError.heartbeatTimeout
            }
        }
    }

    // MARK: - Helpers

    private func isStopped() -> Bool {
        stateAccessQueue.sync { _state == .stopped }
    }

    private func transition(to new: State) {
        let changed: Bool = stateAccessQueue.sync {
            // Do not transition away from stopped through an in-flight connection callback.
            if _state == .stopped {
                return false
            }
            let did = _state != new
            _state = new
            // Record only entry into open; clear other states to avoid stale health checks.
            if case .open = new {
                _lastOpenAt = nowProvider()
            }
            else {
                _lastOpenAt = nil
            }
            return did
        }
        if changed {
            emitState(new)
        }
    }

    private func emitState(_ s: State) {
        let cb: ((State) -> Void)? = stateAccessQueue.sync { _onState }
        DispatchQueue.main.async { cb?(s) }
    }

    private func emitMessage(type: String, data: String) {
        let cb: ((String, String) -> Void)? = stateAccessQueue.sync { _onMessage }
        DispatchQueue.main.async { cb?(type, data) }
    }

    private func setLastDataAt(_ d: Date) {
        stateAccessQueue.sync { _lastDataAt = d }
    }

    private func getLastDataAt() -> Date {
        stateAccessQueue.sync { _lastDataAt }
    }

    private func setLastEventId(_ id: String) {
        stateAccessQueue.sync { _lastEventId = id }
    }

    private func backoffDelay(attempt: Int) -> TimeInterval {
        let idx = min(max(attempt - 1, 0), backoffSchedule.count - 1)
        let base = backoffSchedule[idx]
        return max(0.1, base * jitterProvider())
    }

    private func nanoseconds(from seconds: TimeInterval) -> UInt64 {
        return UInt64(max(seconds, 0) * 1_000_000_000)
    }

    private func makeRequest(token: String) throws -> URLRequest {
        guard let baseURL = baseURL else {
            throw ConnectionError.invalidURL
        }
        var components = URLComponents()
        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.port = baseURL.port
        var pathSegmentAllowed = CharacterSet.urlPathAllowed
        pathSegmentAllowed.remove(charactersIn: "/")
        let encodedProjectId = projectId.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) ?? projectId
        let encodedUserId = notiflyUserId.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) ?? notiflyUserId
        let normalizedBasePath = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = normalizedBasePath.isEmpty ? "" : "/\(normalizedBasePath)"
        components.path = "\(prefix)/projects/\(encodedProjectId)/users/\(encodedUserId)/streams"
        if let device = deviceId, !device.isEmpty {
            components.queryItems = [URLQueryItem(name: "deviceId", value: device)]
        }
        guard let url = components.url else {
            throw ConnectionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.networkServiceType = .responsiveData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(NotiflySdkConfig.sdkVersion, forHTTPHeaderField: "x-notifly-sdk-version")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let last: String? = stateAccessQueue.sync { _lastEventId }
        if let last = last, !last.isEmpty {
            request.setValue(last, forHTTPHeaderField: "Last-Event-ID")
        }
        return request
    }
}
