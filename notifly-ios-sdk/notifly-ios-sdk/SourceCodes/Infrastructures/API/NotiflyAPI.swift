import Foundation
import Combine

class NotiflyAPI {
    
    // MARK: Public Methods
    
    func authorizeSession(credentials: Auth.Credentials) -> AnyPublisher<String, Error> {
        return request(to: "https://api.notifly.tech/authorize", method: .POST, authTokenRequired: false)
            .map { $0.set(body: credentials) }
            .flatMap { (builder: RequestBuilder) -> AnyPublisher<String, Error> in builder.buildAndFire() }
            .eraseToAnyPublisher()
    }
    
    func trackEvent(_ event: TrackingEvent) -> AnyPublisher<String, Error> {
        request(to: "https://api.notifly.tech/track-event", method: .POST, authTokenRequired: true)
            .map { $0.set(body: event) }
            .flatMap{ $0.buildAndFireWithRawJSONResponseType() }
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

