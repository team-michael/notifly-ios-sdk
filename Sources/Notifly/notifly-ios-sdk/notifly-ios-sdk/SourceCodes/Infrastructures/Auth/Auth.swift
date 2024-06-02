import Combine
import Foundation

@available(iOSApplicationExtension, unavailable)
class Auth {
    // MARK: - Properties

    private let accessQueue = DispatchQueue(label: "com.notifly.tracking.access.queue")
    private var authorizationRequestCancellable = Set<AnyCancellable>()

    private var _authorizationPub: AnyPublisher<String, Error>?
    var authorizationPub: AnyPublisher<String, Error> {
        get {
            if let pub = _authorizationPub {
                return pub
                    .catch { _ -> AnyPublisher<String, Error> in
                        Logger.error("Failed to get authorization.")
                        return Fail(outputType: String.self, failure: NotiflyError.notAuthorized)
                            .eraseToAnyPublisher()
                    }
                    .eraseToAnyPublisher()
            } else {
                Logger.error("Failed to get authorization ")
                return Fail(outputType: String.self, failure: NotiflyError.notAuthorized)
                    .eraseToAnyPublisher()
            }
        }
        set {
            _authorizationPub = newValue
        }
    }

    var authorizationPromise: Future<String, Error>.Promise?

    private var authorizationPromiseTimeoutInterval: TimeInterval = 10.0
    let loginCred: Credentials

    // MARK: - Lifecycle

    init(username: String, password: String) {
        loginCred = Credentials(userName: username, password: password)
        authorizationPub = Future { [weak self] promise in
            self?.authorizationPromise = promise
            DispatchQueue.main.asyncAfter(deadline: .now() + (self?.authorizationPromiseTimeoutInterval ?? 0.0)) {
                if let promise = self?.authorizationPromise {
                    promise(.failure(NotiflyError.promiseTimeout))
                }
            }
        }
        .eraseToAnyPublisher()
        setup()
    }

    private func storeCancellable(cancellable: AnyCancellable) {
        accessQueue.async {
            cancellable.store(in: &self.authorizationRequestCancellable)
        }
    }

    private func setup() {
        let setupTask = NotiflyAPI().authorizeSession(credentials: loginCred)
            .tryMap {
                NotiflyCustomUserDefaults.authTokenInUserDefaults = $0
                return $0
            }
            .sink(receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    Logger.error("Authorization error: \(error)")
                }
            }, receiveValue: { [weak self] authToken in
                guard let self = self else { return }
                self.authorizationPromise?(.success(authToken))
                self.authorizationPub = Just(authToken)
                    .setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            })

        storeCancellable(cancellable: setupTask)
    }

    func refreshAuth() -> AnyPublisher<String, Error> {
        NotiflyCustomUserDefaults.authTokenInUserDefaults = nil
        return NotiflyAPI().authorizeSession(credentials: loginCred).handleEvents(receiveOutput: { [weak self] authToken in
            self?.authorizationPromise?(.success(authToken))
            self?.authorizationPub = Just(authToken)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
            NotiflyCustomUserDefaults.authTokenInUserDefaults = authToken
        })
        .eraseToAnyPublisher()
    }
}
