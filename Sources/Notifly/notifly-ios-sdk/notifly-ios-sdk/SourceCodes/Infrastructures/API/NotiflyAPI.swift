import Combine
import Foundation

@available(iOSApplicationExtension, unavailable)
class NotiflyAPI {
    // MARK: Public Methods

    func authorizeSession(credentials: Auth.Credentials) -> AnyPublisher<String, Error> {
        return request(to: NotiflyConstant.EndPoint.authorizationEndPoint, method: .POST, authTokenRequired: false)
            .map { $0.set(body: ApiRequestBody(payload: .AuthCredentials(credentials))) }
            .flatMap { (builder: RequestBuilder) -> AnyPublisher<String, Error> in builder.buildAndFire() }
            .eraseToAnyPublisher()
    }

    func trackEvent(_ event: TrackingEvent) -> AnyPublisher<String, Error> {
        return request(to: NotiflyConstant.EndPoint.trackEventEndPoint, method: .POST, authTokenRequired: true)
            .map { $0.set(body: ApiRequestBody(payload: .TrackingEvent(event))) }
            .flatMap { $0.buildAndFireWithRawJSONResponseType() }
            .flatMap { response -> AnyPublisher<String, Error> in
                if let data = response.data(using: .utf8) as Data?,
                   let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let response = json["message"]
                {
                    if response as! String == "The incoming token has expired",
                       let authorization = try? Notifly.main.auth
                    {
                        return authorization.refreshAuth()
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
        request(to: NotiflyConstant.EndPoint.trackEventEndPoint, method: .POST, authTokenRequired: true)
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
        let endpoint = "\(NotiflyConstant.EndPoint.syncStateEndPoint)/\(projectID)/\(notiflyUserID)?deviceID=\(notiflyDeviceID)&channel=in-app-message"

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

        if authTokenRequired {
            guard let authorization = try? Notifly.main.auth else {
                Logger.error("Not Authorized.")
                return Fail(outputType: RequestBuilder.self, failure: NotiflyError.notAuthorized)
                    .eraseToAnyPublisher()
            }

            return authorization.authorizationPub.tryMap {
                request.set(authorizationToken: $0)
            }
            .eraseToAnyPublisher()
        }
        return Just(request)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
}
