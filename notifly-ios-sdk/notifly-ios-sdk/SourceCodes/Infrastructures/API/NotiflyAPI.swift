import Combine
import Foundation

class NotiflyAPI {
    // MARK: Public Methods

    func authorizeSession(credentials: Auth.Credentials) -> AnyPublisher<String, Error> {
        return request(to: "https://api.notifly.tech/authorize", method: .POST, authTokenRequired: false)
            .map { $0.set(body: ApiRequestBody(payload: .AuthCredentials(credentials))) }
            .flatMap { (builder: RequestBuilder) -> AnyPublisher<String, Error> in builder.buildAndFire() }
            .eraseToAnyPublisher()
    }

    func trackEvent(_ event: TrackingEvent) -> AnyPublisher<String, Error> {
        request(to: "https://12lnng07q2.execute-api.ap-northeast-2.amazonaws.com/prod/records", method: .POST, authTokenRequired: true)
            .map { $0.set(body: ApiRequestBody(payload: .TrackingEvent(event))) }
            .flatMap { $0.buildAndFireWithRawJSONResponseType() }
            .flatMap { response -> AnyPublisher<String, Error> in
                if let data = response.data(using: .utf8) as Data?,
                   let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let response = json["message"]
                {
                    if let auth = try? Notifly.main.auth,
                       response as! String == "The incoming token has expired"
                    {
                        return auth.refreshAuth()
                            .flatMap { _ in
                                self.retryTrackEvent(event)
                            }
                            .eraseToAnyPublisher()
                    }
                    Logger.error("Failed to track event with error: \(response)")
                }

                return Just(response)
                    .setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    func retryTrackEvent(_ event: TrackingEvent) -> AnyPublisher<String, Error> {
        request(to: "https://12lnng07q2.execute-api.ap-northeast-2.amazonaws.com/prod/records", method: .POST, authTokenRequired: true)
            .map { $0.set(body: ApiRequestBody(payload: .TrackingEvent(event))) }
            .flatMap { $0.buildAndFireWithRawJSONResponseType() }
            .flatMap { response -> AnyPublisher<String, Error> in
                if let data = response.data(using: .utf8) as Data?,
                   let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let response = json["message"]
                {
                    Logger.error("Failed to track event with error: \(response)")
                }
                return Just(response)
                    .setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    func requestSyncState(projectID: String, notiflyUserID: String, notiflyDeviceID: String) -> AnyPublisher<String, Error> {
        let endpoint = "https://api.notifly.tech/user-state/" + projectID + "/" + notiflyUserID + "?deviceId=" + notiflyDeviceID + "&channel=in-app-message"
        return request(to: endpoint, method: .GET, authTokenRequired: true)
            .map { $0.set(bearer: true) }
            .flatMap { $0.buildAndFireWithRawJSONResponseType() }
            .eraseToAnyPublisher()
    }
    
    // MARK: Private Methods
    private func request(to uri: String,
                         method: RequestMethod,
                         authTokenRequired: Bool) -> AnyPublisher<RequestBuilder, Error>
    {
        let request = RequestBuilder()
            .set(url: URL(string: uri))
            .set(method: method)

        if let notifly = try? Notifly.main,
           authTokenRequired
        {
            return notifly.auth.authorizationPub.tryMap {
                return request.set(authorizationToken: $0)
            }
            .eraseToAnyPublisher()
        } else {
            return Just(request)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
    }
}
