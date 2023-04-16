import Foundation
import Combine

class Auth {
    
    // MARK: - Properties
    
    var authorizationPub: AnyPublisher<String, Error>
    
    private let loginCred: Credentials
    
    // MARK: - Lifecycle
    
    init(username: String, password: String) {
        loginCred = Credentials(userName: username, password: password)
        authorizationPub = NotiflyAPI().authorizeSession(credentials: loginCred)
    }
}
