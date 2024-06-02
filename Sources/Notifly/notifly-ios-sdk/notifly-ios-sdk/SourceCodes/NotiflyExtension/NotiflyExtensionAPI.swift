//
//  NotiflyExtensionAPI.swift
//  notifly-ios-sdk
//
//  Created by 김대성 on 2023/10/05.
//

import Combine
import Foundation

enum ExtensionRequestMethod: String {
    case GET
    case POST
}

enum APIError: Error {
    case requestFailed
    case invalidResponse
    case invalidData
    case jsonParsingFailed
}

class NotiflyExtensionAPI {
    private var authToken: String?

    private func cleanAuth() {
        authToken = nil
        NotiflyCustomUserDefaults.authTokenInUserDefaults = nil
    }

    func track(payload: TrackingRecord, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        getAuth { result in
            switch result {
            case let .success(token):
                guard let request = self.constructTrackingRequest(auth: token, payload: payload) else {
                    completion(.failure(NotiflyError.unexpectedNil("Fail to contruct push_delivered event.")))
                    return
                }
                self.buildAndFireRequest(request: request, retry: true) { res in
                    switch res {
                    case let .success(res):
                        completion(.success(res))
                    case let .failure(err):
                        completion(.failure(err))
                    }
                }
            case .failure:
                completion(.failure(NotiflyError.notAuthorized))
            }
        }
    }

    private func getAuth(completion: @escaping (Result<String, Error>) -> Void) {
        if let tokenInCache = authToken {
            completion(.success(tokenInCache))
            return
        } else if let tokenInUserDefaults = NotiflyCustomUserDefaults.authTokenInUserDefaults {
            completion(.success(tokenInUserDefaults))
            return
        }
        authorize { result in
            switch result {
            case let .success(token):
                self.authToken = token
                NotiflyCustomUserDefaults.authTokenInUserDefaults = token
                completion(.success(token))
                return
            case let .failure(error):
                completion(.failure(error))
                return
            }
        }
    }

    private func authorize(completion: @escaping (Result<String, Error>) -> Void) {
        guard let username = NotiflyCustomUserDefaults.usernameInUserDefaults,
              let password = NotiflyCustomUserDefaults.passwordInUserDefaults
        else {
            Logger.error("ExtensionAPI: Fail to Authorize - username and password error")
            completion(.failure(NotiflyError.notAuthorized))
            return
        }

        guard let url = URL(string: NotiflyConstant.EndPoint.authorizationEndPoint),
              let request = try? ExtensionRequestBuilder()
              .set(url: url)
              .set(method: .POST)
              .set(body: ApiRequestBody(payload: .AuthCredentials(Credentials(userName: username, password: password))))
        else {
            Logger.error("ExtensionAPI: Fail to Authorize.")
            completion(.failure(APIError.invalidData))
            return
        }

        DispatchQueue.global(qos: .background).async {
            self.buildAndFireRequest(request: request, retry: false) { result in
                switch result {
                case let .success(json):
                    if let token = json["data"] as? String {
                        completion(.success(token))
                    }
                case let .failure(error):
                    Logger.error("ExtensionAPI: Fail to Authorize - \(error)")
                    completion(.failure(NotiflyError.notAuthorized))
                }
            }
        }
    }

    class ExtensionRequestBuilder {
        var url: URL?
        var method: ExtensionRequestMethod?
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body: ApiRequestBody?

        func set(url: URL?) -> ExtensionRequestBuilder {
            self.url = url
            return self
        }

        func set(method: ExtensionRequestMethod) -> ExtensionRequestBuilder {
            self.method = method
            return self
        }

        func set(authorizationToken: String) -> ExtensionRequestBuilder {
            headers["Authorization"] = authorizationToken
            return self
        }

        func set(bearer: Bool) -> ExtensionRequestBuilder {
            guard let authorizationToken = headers["Authorization"],
                  bearer
            else {
                return self
            }
            headers["Authorization"] = "Bearer " + authorizationToken
            return self
        }

        func set(body: ApiRequestBody?) -> ExtensionRequestBuilder {
            self.body = body
            return self
        }

        func build() throws -> URLRequest {
            guard let url = url else {
                throw NotiflyError.unexpectedNil("NotiflyAPI.RequestBuilder.url")
            }
            guard let method = method else {
                throw NotiflyError.unexpectedNil("NotiflyAPI.RequestBuilder.method")
            }

            var request = URLRequest(url: url)
            request.httpMethod = method.rawValue

            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }

            if let body = body {
                request.httpBody = try? JSONEncoder().encode(body)
            }
            return request
        }
    }

    func constructTrackingRequest(auth: String, payload: TrackingRecord) -> ExtensionRequestBuilder? {
        guard let url = URL(string: NotiflyConstant.EndPoint.trackEventEndPoint) else {
            return nil
        }
        return ExtensionRequestBuilder()
            .set(url: url)
            .set(method: .POST)
            .set(authorizationToken: auth)
            .set(body: ApiRequestBody(payload: .TrackingEvent(TrackingEvent(records: [payload]))))
    }

    func buildAndFireRequest(request: ExtensionRequestBuilder, retry: Bool, completion: @escaping (Result<[String: Any], APIError>) -> Void) {
        guard let apiRequest = try? request.build() else {
            completion(.failure(.requestFailed))
            return
        }
        URLSession.shared.dataTask(with: apiRequest) { data, response, error in
            if error != nil {
                completion(.failure(.requestFailed))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }

            if httpResponse.statusCode == 200 {
                if let responseData = data {
                    if let json = try? JSONSerialization.jsonObject(with: responseData, options: []) as? [String: Any] {
                        completion(.success(json))
                    } else {
                        completion(.failure(.jsonParsingFailed))
                    }
                } else {
                    completion(.failure(.invalidData))
                }
            } else if httpResponse.statusCode == 401, retry {
                self.retryTrack(request: request, completion: completion)
                return
            } else {
                completion(.failure(.requestFailed))
            }
        }
        .resume()
    }

    func retryTrack(request: ExtensionRequestBuilder, completion: @escaping (Result<[String: Any], APIError>) -> Void) {
        cleanAuth()
        getAuth { result in
            switch result {
            case let .success(newAuth):
                self.buildAndFireRequest(request: request.set(authorizationToken: newAuth), retry: false, completion: completion)
                return
            case .failure:
                completion(.failure(.requestFailed))
                return
            }
        }
    }
}
