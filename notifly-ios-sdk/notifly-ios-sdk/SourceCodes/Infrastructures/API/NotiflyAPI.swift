import Foundation
import Combine

class NotiflyAPI {
    
    // MARK: Public Methods
    
    func authorizeSession(credentials: Auth.Credentials) -> AnyPublisher<String, Error> {
        if let authToken = Globals.authTokenInUserDefaults {
            return Just(authToken)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        } else {
            return 
            request(to: "https://api.notifly.tech/authorize", method: .POST, authTokenRequired: false)
                .map { $0.set(body: credentials) }
                .flatMap { (builder: RequestBuilder) -> AnyPublisher<String, Error> in builder.buildAndFire() }
                .handleEvents(receiveOutput: { authToken in
                    Globals.authTokenInUserDefaults = authToken
                    Notifly.main.auth.authorizationPub = Just(authToken)
                        .setFailureType(to: Error.self)
                        .eraseToAnyPublisher()
                })
                .eraseToAnyPublisher()
        }
    }
    
    func trackEvent(_ event: TrackingEventProtocol) -> AnyPublisher<String, Error> {
        request(to: "https://12lnng07q2.execute-api.ap-northeast-2.amazonaws.com/prod/records", method: .POST, authTokenRequired: true)
            .map { $0.set(body: event) }
            .flatMap{ $0.buildAndFireWithRawJSONResponseType() }
            .flatMap { 
                let data = $0.data(using: .utf8)!
                let json = try! JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
                if let response = json["message"],
                   response as! String == "The incoming token has expired" {
                    return self.authorizeSession(credentials: Notifly.main.auth.loginCred)
                        .flatMap { _ in self.trackEvent(event) }
                        .eraseToAnyPublisher() 
                }
                return Just($0)
                    .setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: Private Methods
    
    private func request(to uri: String,
                         method: RequestMethod,
                         authTokenRequired: Bool) -> AnyPublisher<RequestBuilder, Error> {
        let request = RequestBuilder()
                        .set(url: URL(string: uri))
                        .set(method: method)
        
        if authTokenRequired {
            return Notifly.main.auth.authorizationPub
                .map { request.set(authorizationToken: $0) }
                .eraseToAnyPublisher()
        } else {
            return Just(request)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
    }
}

