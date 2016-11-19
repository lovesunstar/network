//
//  Network.swift
//  Network
//
//  Created by SunJiangting on 16/5/24.
//  Copyright © 2016年 Suen. All rights reserved.
//

import Foundation
import CoreFoundation
import Alamofire

private typealias AFRequest = Alamofire.Request
private typealias AFMethod = Alamofire.HTTPMethod
private typealias AFManager = Alamofire.SessionManager

let ConnectionFailedErrorCode = -99999999

public func ==(lhs: Network.ProxyItem, rhs: Network.ProxyItem) -> Bool {
    return lhs.host == rhs.host && lhs.port == rhs.port
}

public protocol NetworkClientProtocol: NSObjectProtocol {
    
    static var commonParameters: [String: Any]? { get }
    static var requestHeaders: [String: String]? { get }
    
    /**
     - returns: compressed
     */
    static func compressDataUsingGZip(_ data: inout Data) -> Bool
    
    static func willProcessRequestWithURL(_ URLString: inout String, headers: inout [String: String], parameters: inout [String: Any]?)
    
    static func willProcessResponseWithRequest(_ request: URLRequest, timestamp: TimeInterval, duration: TimeInterval, responseData: Any?, error: Error?, URLResponse: HTTPURLResponse?)
}


private func isErrorEnabledToRetry(_ error: Error) -> Bool {
    guard let urlError = error as? URLError else {
        return false
    }
    switch urlError.code {
    case .cancelled:
        return false
    case .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost, .notConnectedToInternet:
        return true
    default:
        return false
    }
}

public enum ParameterEncoding {
    case url, json(JSONSerialization.WritingOptions)
    
    fileprivate func asAFParameterEncoding() -> Alamofire.ParameterEncoding {
        switch self {
        case .url:
            return Alamofire.URLEncoding(destination: .httpBody)
        case .json(let options):
            return Alamofire.JSONEncoding(options: options)
        }
    }
}

open class Request {
    
    fileprivate var httpBuilder: HTTPBuilder {
        fatalError("Sub class must implemention")
    }
    
    fileprivate init() {
        
    }
    
    fileprivate func canRetryWithError(_ error: Error) -> Bool {
        return isErrorEnabledToRetry(error) && retriedTimes < maximumNumberOfRetryTimes
    }
    
    fileprivate var retriedTimes: UInt16 = 0
    fileprivate var maximumNumberOfRetryTimes: UInt16 = 0
    
    @discardableResult open func responseJSON(
        queue: DispatchQueue? = nil,
        options: JSONSerialization.ReadingOptions = .allowFragments,
        completionHandler: ((URLRequest?, HTTPURLResponse?, Any?, NSError?) -> Void)?)
        -> Self {
            return self
    }
    
    open func cancel() {
        
    }
    
    fileprivate func responseJSONWithRequest(
        _ request: Alamofire.Request,
        queue: DispatchQueue? = nil,
        options: JSONSerialization.ReadingOptions,
        completionHandler: ((URLRequest?, HTTPURLResponse?, Any?, NSError?) -> Void)?) {
        (request as? Alamofire.DataRequest)?.responseJSON(queue: queue, options: options) { (results) in
            let request = results.request, response = results.response, result = results.result
            if let urlRequest = request {
                //
                let timestamp = self.httpBuilder.requestTimestamp
                let duration = NSDate().timeIntervalSince1970 - self.httpBuilder.requestTimestamp
                Network.client?.willProcessResponseWithRequest(urlRequest, timestamp: timestamp, duration: duration, responseData: result.value, error: result.error, URLResponse: response)
            }
            var cancelled = false
            if let error = result.error {
                if self.canRetryWithError(error) {
                    if let request = self.httpBuilder.build() {
                        request.retriedTimes = (self.retriedTimes + 1)
                        self.httpBuilder.requestTimestamp = NSDate().timeIntervalSince1970
                        let _ = request.responseJSON(options: options, completionHandler: completionHandler)
                        return
                    }
                }
                if let urlError = error as? URLError , urlError.code == URLError.cancelled {
                    cancelled = true
                }
            }
            if !cancelled {
                completionHandler?(request, response, result.value, result.error as NSError?)
            }
        }
    }
}

open class NormalRequest: Request {
    
    fileprivate let request: Alamofire.Request
    fileprivate let builder: RequestBuilder
    
    fileprivate override var httpBuilder: HTTPBuilder {
        return builder
    }
    
    fileprivate init(builder: RequestBuilder, request: Alamofire.Request) {
        self.builder = builder
        self.request = request
        super.init()
    }
    
    override open func responseJSON(
        queue: DispatchQueue? = nil,
        options: JSONSerialization.ReadingOptions,
        completionHandler: ((URLRequest?, HTTPURLResponse?, Any?, NSError?) -> Void)?) -> Self {
        responseJSONWithRequest(request, queue: queue, options: options, completionHandler: completionHandler)
        return self
    }
    
    open override func cancel() {
        request.cancel()
    }
}

open class UploadRequest: Request {
    
    fileprivate var request: Alamofire.Request?
    
    fileprivate let builder: UploadBuilder
    
    fileprivate override var httpBuilder: HTTPBuilder {
        return builder
    }
    
    fileprivate var options: JSONSerialization.ReadingOptions = .allowFragments
    fileprivate var completionHandler: ((URLRequest?, HTTPURLResponse?, Any?, NSError?) -> Void)?
    
    fileprivate init(builder: UploadBuilder) {
        self.builder = builder
        super.init()
    }
    
    open override func responseJSON(
        queue: DispatchQueue? = nil,
        options: JSONSerialization.ReadingOptions,
        completionHandler: ((URLRequest?, HTTPURLResponse?, Any?, NSError?) -> Void)?) -> Self {
        if let request = request {
            responseJSONWithRequest(request, options: options, completionHandler: completionHandler)
        } else {
            self.options = options
            self.completionHandler = completionHandler
        }
        return self
    }
    
    open override func cancel() {
        request?.cancel()
    }
    
    fileprivate func startUploading() {
        if let request = request {
            responseJSONWithRequest(request, options: self.options, completionHandler: self.completionHandler)
        }
    }
    
    fileprivate func notifyError(_ error: Error) {
        completionHandler?(nil, nil, nil, error as NSError)
    }
}

public struct Network {
    
    public enum Priority: Float {
        case background = 0
        case low = 0.25
        case `default` = 0.5
        case high = 0.75
    }
    
    public struct ProxyItem: Equatable, Hashable {
        let host: String
        let port: String
        let httpOnly: Bool
        
        public init(host: String, port: String, httpOnly: Bool = true) {
            self.host = host
            self.port = port
            self.httpOnly = httpOnly
        }
        
        public var hashValue: Int {
            return host.hashValue ^ port.hashValue
        }
    }
    
    public static var proxyItem: ProxyItem? {
        didSet {
            if let item = proxyItem {
                if proxyItem != oldValue {
                    let port = Int(item.port) ?? 8888
                    var proxyConfiguration = [AnyHashable: Any]()
                    proxyConfiguration[kCFNetworkProxiesHTTPProxy as AnyHashable] = item.host
                    proxyConfiguration[kCFNetworkProxiesHTTPPort as AnyHashable] = port
                    proxyConfiguration[kCFNetworkProxiesHTTPEnable as AnyHashable] = 1
                    let sessionConfiguration = AFManager.default.session.configuration
                    sessionConfiguration.connectionProxyDictionary = proxyConfiguration
                    manager = AFManager(configuration: sessionConfiguration)
                }
            } else {
                manager = AFManager.default
            }
        }
    }
    
    public static func request(_ url: String) -> RequestBuilder {
        return RequestBuilder(url: url)
    }
    
    public static func upload(_ url: String) -> UploadBuilder {
        return UploadBuilder(url: url)
    }
    
    public static var client: NetworkClientProtocol.Type?
    
    fileprivate static var manager = AFManager.default
}

open class HTTPBuilder: NSObject {
    
    fileprivate init(url: String) {
        urlString = url
        super.init()
    }
    
    open func method(_ method: Alamofire.HTTPMethod) -> Self {
        httpMethod = method
        return self
    }
    
    open func appendCommonParameters(_ append: Bool) -> Self {
        vappendCommonParameters = append
        return self
    }
    
    open func query(_ parameters: [String : Any]?) -> Self {
        queryParameters = parameters
        return self
    }
    
    open func post(_ parameters: [String : Any]?) -> Self {
        postParameters = parameters
        if let p = parameters , !p.isEmpty {
            let _ = method(.post)
        }
        return self
    }
    
    open func headers(_ headers: [String : String]?) -> Self {
        vheaders = headers
        return self
    }
    
    open func gzipEnabled(_ enabled: Bool) -> Self {
        vgzipEnabled = enabled
        return self
    }
    
    open func retry(_ retryTimes: UInt16) -> Self {
        self.retryTimes = retryTimes
        return self
    }
    
    open func timeout(_ timeout: TimeInterval) -> Self {
        timeoutInterval = timeout
        return self
    }
    
    open func cachePolicy(_ policy: NSURLRequest.CachePolicy) -> Self {
        vcachePolicy = policy
        return self
    }
    
    open func priority(_ priority: Network.Priority) -> Self {
        vpriority = priority
        return self
    }
    
    fileprivate func append(_ parameters: [String : Any]?, to absoluteString: String) -> String {
        guard let parameters = parameters , !parameters.isEmpty else {
            return absoluteString
        }
        var results = absoluteString
        var components: [(String, String)] = []
        for key in Array(parameters.keys).sorted(by: <) {
            let value = parameters[key]!
            components += Alamofire.URLEncoding.queryString.queryComponents(fromKey: key, value: value)
        }
        let query = (components.map { "\($0)=\($1)" } as [String]).joined(separator: "&")
        if !query.isEmpty {
            if absoluteString.contains("?") {
                results.append("&")
            } else {
                results.append("?")
            }
            results.append(query)
        }
        return results
    }
    
    open func build() -> Request? {
        return nil
    }
    
    fileprivate var urlString: String
    fileprivate var vheaders: [String : String]?
    fileprivate var queryParameters: [String : Any]?
    fileprivate var parameterEncoding: ParameterEncoding = .url
    fileprivate var vappendCommonParameters = true
    fileprivate var retryTimes: UInt16 = 0
    fileprivate var timeoutInterval: TimeInterval = 30
    fileprivate var vcachePolicy = NSURLRequest.CachePolicy.useProtocolCachePolicy
    fileprivate var vpriority = Network.Priority.default
    fileprivate var vgzipEnabled = true
    /// 发送请求的时间（unix时间戳）
    fileprivate var requestTimestamp: TimeInterval = 0
    
    fileprivate var httpMethod: AFMethod = .get
    fileprivate var postParameters: [String : Any]?
}

/**
 网络请求
 <br />
 Usage:
 <br />
 NewsMaster.Network.request(url)
 .method([GET|POST|HEAD|PATCH|DELETE...])?<br />
 .get([String:Any])?<br />
 .post([String:Any])?<br />
 .retry(retryTimes)?<br />
 .headers(["Accept": "xxx"])?<br />
 .encoding(FormData|Mutilpart|JSON|...)?<br />
 .priority(Network.Default)?<br />
 .timeout(seconds)?<br />
 .append(commonParameters)?<br />
 .pack() unwrap?.pon_response { _, _, results, error in logic }
 */
open class RequestBuilder: HTTPBuilder {
    
    override init(url: String) {
        super.init(url: url)
    }
    
    fileprivate static var manager = AFManager.default
    fileprivate static func resetManager() {
        manager = AFManager.default
    }
    
    open func encoding(_ encoding: ParameterEncoding) -> Self {
        parameterEncoding = encoding
        return self
    }
    
    /// NOTE: never use this way on main thread
    open func syncResponseJSON(options: JSONSerialization.ReadingOptions = .allowFragments) -> (URLResponse?, Any?, NSError?) {
        if let request = build() {
            var response: URLResponse?
            var responseData: Any?
            var responseError: NSError?
            let semaphore = DispatchSemaphore(value: 0)
            let _ = request.responseJSON(queue: DispatchQueue.global(qos: .default), options: options, completionHandler: { (_, URLResponse, data, error) -> Void in
                response = URLResponse
                responseData = data
                responseError = error
                semaphore.signal()
            })
            let _ = semaphore.wait(timeout: DispatchTime.distantFuture)
            return (response, responseData, responseError)
        }
        return (nil, nil, nil)
    }
    
    open override func build() -> Request? {
        if self.urlString.isEmpty {
            return nil
        }
        var absoluteString = append(queryParameters, to: self.urlString)
        if vappendCommonParameters {
            // 从CommonParams中删除 getParameters
            if let commonParameters = Network.client?.commonParameters {
                let restCommonParameters = commonParameters - queryParameters
                absoluteString = append(restCommonParameters, to: absoluteString)
            }
        }
        var headers = [String : String]()
        if let defaultHeaders = Network.client?.requestHeaders {
            headers += defaultHeaders
        }
        headers += vheaders
        var URLString = absoluteString as String
        var postParameters = self.postParameters
        Network.client?.willProcessRequestWithURL(&URLString, headers: &headers, parameters: &postParameters)
        
        guard var mutableURLRequest = mutableRequest(URLString, method: httpMethod, headers: headers) else {
            return nil
        }
        requestTimestamp = Date().timeIntervalSince1970
        if timeoutInterval != 0 {
            mutableURLRequest.timeoutInterval = timeoutInterval
        }
        mutableURLRequest.cachePolicy = vcachePolicy
        guard var encodedURLRequest = try? parameterEncoding.asAFParameterEncoding().encode(mutableURLRequest, with: postParameters) else { return nil }
        // GZIP Compress
        if vgzipEnabled {
            if let HTTPBody = encodedURLRequest.httpBody, let client = Network.client {
                var newHTTPBody = HTTPBody
                let compressed = client.compressDataUsingGZip(&newHTTPBody)
                if newHTTPBody.count > 0 && compressed {
                    encodedURLRequest.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
                    encodedURLRequest.httpBody = newHTTPBody
                }
            }
        }
        let afRequest = Network.manager.request(encodedURLRequest)
        afRequest.task?.priority = vpriority.rawValue
        let resultRequest = NormalRequest(builder: self, request: afRequest)
        resultRequest.maximumNumberOfRetryTimes = retryTimes
        return resultRequest
    }
    
    fileprivate func mutableRequest(_ URLString: String, method: AFMethod, headers: [String : String]?) -> URLRequest? {
        guard let URL = URL(string: URLString) else {
            return nil
        }
        var request = URLRequest(url: URL)
        request.httpMethod = method.rawValue
        if let headers = headers {
            for (headerField, headerValue) in headers {
                request.setValue(headerValue, forHTTPHeaderField: headerField)
            }
        }
        return request
    }
}

open class UploadBuilder: HTTPBuilder {
    
    fileprivate class Part {
        var name: String
        var fileName: String?
        var mimeType: String?
        
        init(name: String) {
            self.name = name
        }
    }
    
    fileprivate class Data: Part {
        
        var data: Foundation.Data
        
        init(name: String, data: Foundation.Data) {
            self.data = data
            super.init(name: name)
        }
    }
    
    open func append(data: Foundation.Data, name: String, fileName: String? = nil, mimeType: String? = nil) -> Self {
        let part = Data(name: name, data: data)
        part.fileName = fileName
        part.mimeType = mimeType
        dataParts.append(part)
        return self
    }
    
    fileprivate class File: Part {
        var fileURL: URL
        
        init(name: String, fileURL: URL) {
            self.fileURL = fileURL
            super.init(name: name)
        }
    }
    
    open func append(file fileURL: URL, name: String, fileName: String, mimeType: String? = nil) -> Self {
        let part = File(name: name, fileURL: fileURL)
        part.fileName = fileName
        part.mimeType = mimeType
        fileParts.append(part)
        return self
    }
    
    open override func build() -> Request? {
        if self.urlString.isEmpty {
            return nil
        }
        let request = UploadRequest(builder: self)
        request.maximumNumberOfRetryTimes = retryTimes
        
        var absoluteString = append(queryParameters, to: self.urlString)
        if vappendCommonParameters {
            // 从CommonParams中删除 getParameters
            if let commonParameters = Network.client?.commonParameters {
                let restCommonParameters = commonParameters - queryParameters
                absoluteString = append(restCommonParameters, to: absoluteString)
            }
        }
        var headers = [String : String]()
        if let defaultHeaders = Network.client?.requestHeaders {
            headers += defaultHeaders
        }
        headers += vheaders
        var postParameters = self.postParameters
        Network.client?.willProcessRequestWithURL(&absoluteString, headers: &headers, parameters: &postParameters)
        
        let dataParts = self.dataParts
        let fileParts = self.fileParts
        let postParts = postParameters
        
        guard let url = URL(string: absoluteString) else { return nil }
        var urlRequest = URLRequest(url: url)
        for (headerField, headerValue) in headers {
            urlRequest.setValue(headerValue, forHTTPHeaderField: headerField)
        }
        
        Alamofire.upload(multipartFormData: { (multipartFormData) in
            postParts?.forEach({ k, v in
                if let data = ((v as? String) ?? "\(v)").data(using: .utf8) {
                    multipartFormData.append(data, withName: k)
                }
            })
            dataParts.forEach({self.append($0, to: multipartFormData)})
            fileParts.forEach({self.append($0, to: multipartFormData)})
        }, usingThreshold:UInt64(2_000_000), with: urlRequest) { (encodingResult) in
            switch encodingResult {
            case .success(let upload, _, _):
                upload.task?.priority = self.vpriority.rawValue
                self.requestTimestamp = NSDate().timeIntervalSince1970
                request.request = upload
                request.startUploading()
            case .failure(let encodingError):
                request.notifyError(encodingError)
            }
        }
        request.maximumNumberOfRetryTimes = self.retryTimes
        return request
    }
    
    fileprivate func append(_ data: Data, to multipartFormData: Alamofire.MultipartFormData) {
        if let mimeType = data.mimeType {
            if let fileName = data.fileName {
                multipartFormData.append(data.data, withName: data.name, fileName: fileName, mimeType: mimeType)
            } else {
                multipartFormData.append(data.data, withName: data.name, mimeType: mimeType)
            }
        } else {
            multipartFormData.append(data.data, withName: data.name)
        }
    }
    
    fileprivate func append(_ file: File, to multipartFormData: Alamofire.MultipartFormData) {
        if let mimeType = file.mimeType {
            if let fileName = file.fileName {
                multipartFormData.append(file.fileURL, withName: file.name, fileName: fileName, mimeType: mimeType)
            } else {
                multipartFormData.append(file.fileURL, withName: file.name, fileName: "\(Date().timeIntervalSince1970)", mimeType: mimeType)
            }
        } else {
            multipartFormData.append(file.fileURL, withName: file.name)
        }
    }
    
    fileprivate var dataParts = [Data]()
    fileprivate var fileParts = [File]()
}

func +=<KeyType, ValueType>(lhs: inout Dictionary<KeyType, ValueType>, rhs: Dictionary<KeyType, ValueType>?) {
    if let rhs = rhs {
        for (k, v) in rhs {
            lhs[k] = v
        }
    }
}

func +<KeyType, ValueType>(lhs: [KeyType : ValueType], rhs: [KeyType : ValueType]?) -> [KeyType : ValueType] {
    var results = lhs
    if let rhs = rhs {
        for (k, v) in rhs {
            results[k] = v
        }
    }
    return results
}

func -=<KeyType, ValueType>(lhs: inout Dictionary<KeyType, ValueType>, rhs: Dictionary<KeyType, ValueType>?) {
    if let rhs = rhs {
        for (k, _) in rhs {
            lhs.removeValue(forKey: k)
        }
    }
}

func -<KeyType, ValueType>(lhs: [KeyType : ValueType], rhs: [KeyType : ValueType]?) -> [KeyType : ValueType] {
    var results = lhs
    if let rhs = rhs {
        for (k, _) in rhs {
            results.removeValue(forKey: k)
        }
    }
    return results
}

