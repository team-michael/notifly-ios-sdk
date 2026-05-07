//
//  SSEController.swift
//  notifly-ios-sdk
//

import Foundation

@available(iOSApplicationExtension, unavailable)
final class SSEController: @unchecked Sendable {

    enum Mode: Equatable {
        case sse
        case fallback
    }

    // MARK: - Configuration

    let sseClient: SSEClient
    private let onSyncRequested: (@escaping () -> Void) -> Void
    private let onServerEventTriggered: (_ name: String, _ eventParams: [String: Any]?) -> Void
    private let scheduler: (TimeInterval, @escaping () -> Void) -> Void
    private let syncDebounceInterval: TimeInterval

    // MARK: - State

    private let stateQueue = DispatchQueue(label: "com.notifly.sse.controllerStateQueue")
    private var _mode: Mode = .sse
    private var _hasReachedOpen: Bool = false
    private var _pendingSyncDispatch: Bool = false
    private var _syncInFlight: Bool = false
    private var _generation: Int = 0

    // MARK: - Init

    init(
        sseClient: SSEClient,
        onSyncRequested: @escaping (@escaping () -> Void) -> Void,
        onServerEventTriggered: @escaping (_ name: String, _ eventParams: [String: Any]?) -> Void,
        syncDebounceInterval: TimeInterval = 1.0,
        scheduler: @escaping (TimeInterval, @escaping () -> Void) -> Void = SSEController.defaultScheduler
    ) {
        self.sseClient = sseClient
        self.onSyncRequested = onSyncRequested
        self.onServerEventTriggered = onServerEventTriggered
        self.syncDebounceInterval = syncDebounceInterval
        self.scheduler = scheduler

        sseClient.onMessage = { [weak self] type, data in
            self?.handleMessage(type: type, data: data)
        }
        sseClient.onState = { [weak self] state in
            self?.handleStateChange(state)
        }
    }

    static let defaultScheduler: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Public API

    func start() {
        sseClient.connect()
    }

    func stop() {
        stateQueue.sync { _generation += 1 }
        sseClient.disconnect()
    }

    func reconnect(reason: String) {
        Logger.info("SSE reconnect requested: \(reason)")
        sseClient.disconnect()
        sseClient.connect()
    }

    var mode: Mode {
        stateQueue.sync { _mode }
    }

    // MARK: - Internal handlers

    func handleMessage(type: String, data: String) {
        let message = SSEMessage.decode(type: type, data: data)
        switch message {
        case .connected:
            stateQueue.sync {
                _hasReachedOpen = true
                _mode = .sse
            }
        case .sync:
            triggerSyncStateDebounced()
        case .event(let name, let params):
            onServerEventTriggered(name, params)
        case .shutdown(let ms):
            handleShutdown(reconnectInMs: ms)
        case .ttlExpired:
            reconnect(reason: "ttl-expired")
        case .unknown(let raw):
            Logger.info("SSE unknown message type: \(raw)")
        case .malformed(let raw):
            Logger.error("SSE malformed message: type=\(raw)")
        }
    }

    func handleStateChange(_ state: SSEClient.State) {
        switch state {
        case .open:
            stateQueue.sync {
                _hasReachedOpen = true
                _mode = .sse
            }
        case .reconnecting(let attempt):
            let shouldFallback: Bool = stateQueue.sync {
                guard !_hasReachedOpen, attempt >= 3, _mode != .fallback else { return false }
                _mode = .fallback
                return true
            }
            if shouldFallback {
                Logger.info("SSE entering fallback mode (attempt=\(attempt))")
                sseClient.disconnect()
            }
        default:
            break
        }
    }

    // MARK: - Private

    private func triggerSyncStateDebounced() {
        let shouldDispatchNow: Bool = stateQueue.sync {
            if _pendingSyncDispatch || _syncInFlight {
                return false
            }
            _pendingSyncDispatch = true
            _syncInFlight = true
            return true
        }
        guard shouldDispatchNow else { return }

        onSyncRequested { [weak self] in
            self?.stateQueue.sync { self?._syncInFlight = false }
        }
        scheduler(syncDebounceInterval) { [weak self] in
            self?.stateQueue.sync { self?._pendingSyncDispatch = false }
        }
    }

    private func handleShutdown(reconnectInMs: Int) {
        Logger.info("SSE shutdown received, reconnect in \(reconnectInMs)ms")
        sseClient.disconnect()
        let scheduledGen = stateQueue.sync { _generation }
        let delay = max(TimeInterval(reconnectInMs) / 1000.0, 0)
        scheduler(delay) { [weak self] in
            guard let self = self else { return }
            let currentGen = self.stateQueue.sync { self._generation }
            guard currentGen == scheduledGen else { return }
            self.sseClient.connect()
        }
    }
}
