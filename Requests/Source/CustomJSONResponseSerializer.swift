//
//  CustomJSONResponseSerializer.swift
//  Network
//
//  Created by 江挺孙 on 2020/6/29.
//

import Alamofire

class CustomJSONResponseSerializer: ResponseSerializer {
    
    public let dataPreprocessor: DataPreprocessor
    public let emptyResponseCodes: Set<Int>
    public let emptyRequestMethods: Set<HTTPMethod>
    /// `JSONSerialization.ReadingOptions` used when serializing a response.
    public let options: JSONSerialization.ReadingOptions

    /// Creates an instance with the provided values.
    ///
    /// - Parameters:
    ///   - dataPreprocessor:    `DataPreprocessor` used to prepare the received `Data` for serialization.
    ///   - emptyResponseCodes:  The HTTP response codes for which empty responses are allowed. `[204, 205]` by default.
    ///   - emptyRequestMethods: The HTTP request methods for which empty responses are allowed. `[.head]` by default.
    ///   - options:             The options to use. `.allowFragments` by default.
    public init(dataPreprocessor: DataPreprocessor = JSONResponseSerializer.defaultDataPreprocessor,
                emptyResponseCodes: Set<Int> = JSONResponseSerializer.defaultEmptyResponseCodes,
                emptyRequestMethods: Set<HTTPMethod> = JSONResponseSerializer.defaultEmptyRequestMethods,
                options: JSONSerialization.ReadingOptions = .allowFragments) {
        self.dataPreprocessor = dataPreprocessor
        self.emptyResponseCodes = emptyResponseCodes
        self.emptyRequestMethods = emptyRequestMethods
        self.options = options
    }

    public func serialize(request: URLRequest?, response: HTTPURLResponse?, data rd: Data?, error: Error?) throws -> Any {
        guard error == nil else { throw error! }
        guard let client = Session.client else {
            return try JSONResponseSerializer(dataPreprocessor: dataPreprocessor, options: options).serialize(request: request, response: response, data: rd, error: error)
        }
        guard var data = rd, !data.isEmpty else {
            guard emptyResponseAllowed(forRequest: request, response: response) else {
                throw AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength)
            }
            return NSNull()
        }
        var newData = data
        if client.preprocessResponseBody(&newData, response: response) {
            data = newData
        }
        do {
            return try JSONSerialization.jsonObject(with: data, options: options)
        } catch {
            throw AFError.responseSerializationFailed(reason: .jsonSerializationFailed(error: error))
        }
    }
}


extension DataRequest {
    /// Adds a handler to be called once the request has finished.
    ///
    /// - Parameters:
    ///   - queue:             The queue on which the completion handler is dispatched. `.main` by default.
    ///   - options:           The JSON serialization reading options. `.allowFragments` by default.
    ///   - completionHandler: A closure to be executed once the request has finished.
    ///
    /// - Returns:             The request.
    @discardableResult
    public func responseCustomJSON(queue: DispatchQueue = .main,
                             options: JSONSerialization.ReadingOptions = .allowFragments,
                             completionHandler: @escaping (AFDataResponse<Any>) -> Void) -> Self {
        return response(queue: queue,
                        responseSerializer: CustomJSONResponseSerializer(options: options),
                        completionHandler: completionHandler)
    }
}

extension DownloadRequest {
    /// Adds a handler to be called once the request has finished.
    ///
    /// - Parameters:
    ///   - queue:             The queue on which the completion handler is dispatched. `.main` by default.
    ///   - options:           The JSON serialization reading options. `.allowFragments` by default.
    ///   - completionHandler: A closure to be executed once the request has finished.
    ///
    /// - Returns:             The request.
    @discardableResult
    public func responseCustomJSON(queue: DispatchQueue = .main,
                             options: JSONSerialization.ReadingOptions = .allowFragments,
                             completionHandler: @escaping (AFDownloadResponse<Any>) -> Void)
        -> Self {
        return response(queue: queue,
                        responseSerializer: CustomJSONResponseSerializer(options: options),
                        completionHandler: completionHandler)
    }
}
