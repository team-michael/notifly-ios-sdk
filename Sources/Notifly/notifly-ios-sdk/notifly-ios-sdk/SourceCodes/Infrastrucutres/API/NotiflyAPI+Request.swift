import Combine
import Foundation

@available(iOSApplicationExtension, unavailable)
extension NotiflyAPI {
    enum RequestMethod: String {
        case GET
        case POST
    }

    class RequestBuilder {
        var url: URL?
        var method: RequestMethod?
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body: ApiRequestBody?

        func set(url: URL?) -> RequestBuilder {
            self.url = url
            return self
        }

        func set(method: RequestMethod) -> RequestBuilder {
            self.method = method
            return self
        }

        func set(authorizationToken: String) -> RequestBuilder {
            headers["Authorization"] = authorizationToken
            return self
        }

        func set(bearer: Bool) -> RequestBuilder {
            guard let authorizationToken = headers["Authorization"] as? String,
                  bearer
            else {
                return self
            }
            headers["Authorization"] = "Bearer " + authorizationToken
            return self
        }

        func set(body: ApiRequestBody?) -> RequestBuilder {
            self.body = body
            return self
        }

        func buildAndFire<T: Codable>() -> AnyPublisher<T, Error> {
            do {
                let request = try build()
                return URLSession.shared.dataTaskPublisher(for: request)
                .map(\.data)
                .decode(type: Response<T>.self, decoder: JSONDecoder())
                .receive(on: DispatchQueue.main)
                .tryCompactMap {
                    if let data = $0.data {
                        return data
                    } else {
                        throw NotiflyError.unexpectedNil("Response has empty payload")
                    }
                }
                .eraseToAnyPublisher()
            } catch {
                return Fail(outputType: T.self, failure: error)
                    .eraseToAnyPublisher()
            }
        }

        func buildAndFireWithRawJSONResponseType() -> AnyPublisher<String, Error> {
            do {
                let request = try build()
                return URLSession.shared.dataTaskPublisher(for: request)
                .map(\.data)
                .tryMap {
                    if let response = String(data: $0, encoding: .utf8) {
                        return response
                    } else {
                        throw NotiflyError.unexpectedNil("Response is corrupted.")
                    }
                }
                .eraseToAnyPublisher()
            } catch {
                return Fail(outputType: String.self, failure: error)
                    .eraseToAnyPublisher()
            }
        }

        private func build() throws -> URLRequest {
            guard let url = url else {
                throw NotiflyError.unexpectedNil("NotiflyAPI.RequestBuilder.url")
            }
            guard let method = method else {
                throw NotiflyError.unexpectedNil("NotiflyAPI.RequestBuilder.method")
            }

            var request = URLRequest(url: url)
            request.httpMethod = method.rawValue

            headers.forEach { key, value in
                request.setValue(value, forHTTPHeaderField: key)
            }

            if let body = body {
                request.httpBody = try? JSONEncoder().encode(body)
            }
            return request
        }
    }

    struct Response<T: Codable>: Codable {
        let data: T?
    }
}
