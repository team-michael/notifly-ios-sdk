import Foundation
import Combine

extension NotiflyAPI {
    
    enum RequestMethod: String {
        case GET
        case POST
    }
    
    class RequestBuilder {
        
        var url: URL?
        var method: RequestMethod?
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body: Codable?
        
        func set(url: URL?) -> RequestBuilder {
            self.url = url
            return self
        }
        
        func set(method: RequestMethod) -> RequestBuilder {
            self.method = method
            return self
        }
        
        func set(authorizationToken: String) -> RequestBuilder {
            self.headers["Authorization"] = authorizationToken
            return self
        }
        
        func set(body: Codable?) -> RequestBuilder {
            self.body = body
            return self
        }
        
        func buildAndFire<T: Decodable>() -> AnyPublisher<T, Error> {
            do {
                let request = try build()
                return URLSession.shared.dataTaskPublisher(for: request)
                    .map(\.data)
                    .decode(type: T.self, decoder: JSONDecoder())
                    .eraseToAnyPublisher()
            } catch {
                return Fail(outputType: T.self, failure: error)
                    .eraseToAnyPublisher()
            }
        }
        
        private func build() throws -> URLRequest {
            guard let url = url else {
                throw NotiflyError.missingData("NotiflyAPI.RequestBuilder.url")
            }
            guard let method = method else {
                throw NotiflyError.missingData("NotiflyAPI.RequestBuilder.method")
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = method.rawValue
            
            headers.forEach({ (key, value) in
                request.setValue(value, forHTTPHeaderField: key)
            })
            
            if let body = body {
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            }
            return request
        }
    }
}
