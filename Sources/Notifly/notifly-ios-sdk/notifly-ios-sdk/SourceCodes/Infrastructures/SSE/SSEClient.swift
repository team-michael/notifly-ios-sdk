//
//  SSEClient.swift
//  notifly-ios-sdk
//
//  서버→SDK 실시간 채널의 트랜스포트 계층.
//  URLSession.bytes(for:) + AsyncSequence 기반으로 SSE 스트림을 수신하고
//  지수 백오프 재연결 / heartbeat 타임아웃 / Last-Event-ID 관리를 수행한다.
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

    /// HTTP 응답 헤더 + line 시퀀스를 반환. 테스트는 결정적 라인 입력을 주입할 수 있다.
    typealias StreamLineProvider = (URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>)

    // MARK: - Static defaults

    static let defaultBackoffSchedule: [TimeInterval] = [10]
    static let defaultHeartbeatTimeout: TimeInterval = 60
    /// .open 이 이 시간 이상 유지된 뒤 끊기면 정상 운영 상태로 간주, 백오프 attempt 카운터를 리셋한다.
    static let openStableThreshold: TimeInterval = 30

    static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = defaultHeartbeatTimeout
        config.timeoutIntervalForResource = 35 * 60
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 1
        config.httpShouldUsePipelining = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }

    // MARK: - Configuration (immutable)

    private let projectId: String
    private let notiflyUserId: String
    private let deviceId: String?
    private let tokenProvider: () async throws -> String
    /// nil 이면 connect 시 makeRequest 가 invalidURL throw 하여 백오프 진입.
    /// SDK 는 host app 을 죽이지 않으므로 init 자체는 항상 성공시킨다.
    private let baseURL: URL?
    private let backoffSchedule: [TimeInterval]
    private let heartbeatTimeout: TimeInterval
    private let streamLineProvider: StreamLineProvider
    private let jitterProvider: () -> Double
    private let nowProvider: () -> Date

    // MARK: - Mutable state (stateAccessQueue 로 보호)

    private let stateAccessQueue = DispatchQueue(label: "com.notifly.sse.stateAccessQueue")
    private var _state: State = .idle
    private var _lastEventId: String?
    private var _connectionTask: Task<Void, Never>?
    private var _lastDataAt: Date
    private var _lastOpenAt: Date?

    // MARK: - Callbacks
    //
    // 콜백 호출은 main queue 로 dispatch 된다. 콜백 클로저 내부에서 동일 SSEClient 의
    // setter 를 호출하면 stateAccessQueue self-recursive sync 로 deadlock 가능하니 호출자가 회피.

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
        // 잘못된 baseURLString → 컴파일타임 상수 fallback. 모두 실패해도 init 은 성공시키고
        // connect 시점에 invalidURL throw 하도록 nil 로 둔다 (host app crash 방지).
        let resolvedBaseURL = URL(string: baseURLString) ?? URL(string: NotiflyConstant.EndPoint.streamEndPoint)
        if resolvedBaseURL == nil {
            Logger.error("SSEClient: failed to resolve baseURL — connect will fail with invalidURL")
        }
        self.baseURL = resolvedBaseURL
        self.backoffSchedule = backoffSchedule.isEmpty ? SSEClient.defaultBackoffSchedule : backoffSchedule
        self.heartbeatTimeout = heartbeatTimeout
        self.streamLineProvider = streamLineProvider ?? SSEClient.makeURLSessionStreamProvider(session: session)
        self.jitterProvider = jitterProvider
        self.nowProvider = nowProvider
        self._lastDataAt = nowProvider()
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

    internal static func splitSSELines<S: AsyncSequence>(_ bytes: S) -> AsyncThrowingStream<String, Error>
    where S.Element == UInt8 {
        AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    var buffer: [UInt8] = []
                    var prevWasCR = false
                    for try await byte in bytes {
                        if byte == 0x0A {
                            if prevWasCR {
                                prevWasCR = false
                                continue
                            }
                            continuation.yield(String(decoding: buffer, as: UTF8.self))
                            buffer.removeAll(keepingCapacity: true)
                        } else if byte == 0x0D {
                            continuation.yield(String(decoding: buffer, as: UTF8.self))
                            buffer.removeAll(keepingCapacity: true)
                            prevWasCR = true
                        } else {
                            prevWasCR = false
                            buffer.append(byte)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    deinit {
        // Task.cancel() 은 thread-safe 라 stateAccessQueue 동기화 없이 호출.
        // (deinit 안에서 자기 큐로 sync 들어가면 deadlock 가능.)
        _connectionTask?.cancel()
    }

    // MARK: - Public API

    /// 멱등. 이미 .connecting / .open / .reconnecting 이면 무시한다.
    /// 강제 reconnect 는 disconnect() + connect() 조합으로 가능.
    func connect() {
        // Task 생성과 _connectionTask 할당이 한 sync 블록에 묶여야
        // disconnect() 와 race 시 새 task 가 누락되지 않는다.
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
                await self.runConnectionLoop()
            }
            _connectionTask = task
            didStart = true
        }
        if didStart {
            Logger.info("SSE connect requested: projectId=\(projectId) userId=\(notiflyUserId) deviceId=\(deviceId ?? "-")")
            emitState(.connecting)
        }
    }

    /// .stopped 로 전이하고 진행 중인 연결을 취소. 이후 connect() 로 재시작 가능.
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
            Logger.info("SSE disconnect requested: projectId=\(projectId) userId=\(notiflyUserId)")
            emitState(.stopped)
        }
    }

    var state: State {
        stateAccessQueue.sync { _state }
    }

    var lastEventId: String? {
        stateAccessQueue.sync { _lastEventId }
    }

    // MARK: - 연결 루프

    private func runConnectionLoop() async {
        var attempt = 0

        while !Task.isCancelled, !isStopped() {
            do {
                try await runOneConnection(attempt: attempt)
            } catch is CancellationError {
                break
            } catch {
                Logger.info("SSE connection error: \(error)")
            }

            if isStopped() || Task.isCancelled { break }

            // .open 으로 충분히 오래 유지된 뒤 끊긴 경우만 정상 운영으로 간주, attempt 리셋.
            // connecting 단계만 길어진 케이스는 백오프 누적 유지.
            let openedAt: Date? = stateAccessQueue.sync { _lastOpenAt }
            if let openedAt = openedAt,
               nowProvider().timeIntervalSince(openedAt) >= SSEClient.openStableThreshold {
                attempt = 0
            }

            attempt += 1
            transition(to: .reconnecting(attempt: attempt))
            let delay = backoffDelay(attempt: attempt)
            do {
                try await Task.sleep(nanoseconds: nanoseconds(from: delay))
            } catch {
                break
            }
        }
    }

    private func runOneConnection(attempt: Int) async throws {
        if attempt > 0 {
            transition(to: .connecting)
        }

        // long-idle 후 connect() 호출 시 watchdog 가 첫 라인 받기 전에 잘못 timeout 판정하지 않도록
        // tokenProvider 직전에 lastDataAt 을 다시 찍는다.
        setLastDataAt(nowProvider())

        let token = try await tokenProvider()
        let request = try makeRequest(token: token)

        let (http, lines) = try await streamLineProvider(request)
        // 200 외 status (204, 304 등) 는 빈 body 로 즉시 종료 → 재연결 thrashing 유발하므로 reject.
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
        Logger.info("SSE connected: projectId=\(projectId) userId=\(notiflyUserId) deviceId=\(deviceId ?? "-")")
        setLastDataAt(nowProvider())

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                guard let self = self else { return }
                try await self.consumeStream(lines: lines)
            }
            group.addTask { [weak self] in
                guard let self = self else { return }
                try await self.runHeartbeatWatchdog()
            }
            // 첫 child 완료(정상 종료 또는 throw)까지 대기 → 나머지 취소.
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
        // timeout 의 1/4 분해능, 상한 5s — 60s timeout 이라도 worst-case 65s 안에 reconnect.
        let checkInterval = max(min(heartbeatTimeout / 4, 5), 0.05)
        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: nanoseconds(from: checkInterval))
            let elapsed = nowProvider().timeIntervalSince(getLastDataAt())
            if elapsed > heartbeatTimeout {
                Logger.info("SSE heartbeat timeout: \(Int(elapsed))s")
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
            // .stopped 는 흡수 상태.
            if _state == .stopped {
                return false
            }
            let did = _state != new
            _state = new
            // .open 진입 시점만 기록. 그 외 상태에서는 stale 판정 방지를 위해 nil.
            if case .open = new {
                _lastOpenAt = nowProvider()
            } else {
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
        let delay = max(0.1, base * jitterProvider())
        Logger.info("SSE backoff attempt=\(attempt) delay=\(Int(delay * 1000))ms")
        return delay
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
            Logger.info("SSE sending Last-Event-ID: \(last)")
        } else {
            Logger.info("SSE sending Last-Event-ID: (none)")
        }
        return request
    }
}
