import Combine
import Foundation

class Auth {
    // MARK: - Properties

    var authorizationPub: AnyPublisher<String, Error>

    let loginCred: Credentials
    private var authorizationRequestCancellable: AnyCancellable?

    // MARK: - Lifecycle

    init(username: String, password: String) {
        loginCred = Credentials(userName: username, password: password)
        authorizationPub = NotiflyAPI().authorizeSession(credentials: loginCred)
        setup()
    }

    private func setup() {
        // Kick off the auth task and log the sucess state.
        authorizationRequestCancellable = authorizationPub.sink(
            receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    Logger.error("Authorization error: \(error)")
                }
            },
            receiveValue: { authToken in
                Logger.info("Successfully authorized with username and password")
            }
        )
    }
}
