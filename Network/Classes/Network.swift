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
private typealias AFManager = Alamofire.Manager
private typealias AFMethod = Alamofire.Method

let ConnectionFailedErrorCode = -99999999

public func ==(lhs: Network.ProxyItem, rhs: Network.ProxyItem) -> Bool {
    return lhs.host == rhs.host && lhs.port == rhs.port
}

public protocol NetworkClientProtocol: NSObjectProtocol {
    
    static var commonParameters: [String: AnyObject]? { get }
    static var requestHeaders: [String: String]? { get }
    
    /**
     - returns: compressed
    */
    static func compressDataUsingGZip(_ data: inout Data) -> Bool
    
    static func willProcessRequestWithURL(_ URLString: inout String, headers: inout [String: String], parameters: inout [String: AnyObject]?)
    
    static func willProcessResponseWithRequest(_ request: URLRequest, timestamp: TimeInterval, duration: TimeInterval, responseData: AnyObject?, error: Error?, URLResponse: HTTPURLResponse?)
}


private func isErrorEnabledToRetry(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.code == NSURLErrorCancelled {
        return false
    }
    let weakConnects = [NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet]
    return weakConnects.contains(nsError.code)
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
    
    open func responseJSON(
        queue: DispatchQueue? = nil,
        options: JSONSerialization.ReadingOptions = .allowFragments,
        completionHandler: ((URLRequest?, HTTPURLResponse?, AnyObject?, NSError?) -> Void)?)
        -> Self {
            return self
    }
    
    open func cancel() {
        
    }
    
    fileprivate func responseJSONWithRequest(
        _ request: Alamofire.Request,
        queue: DispatchQueue? = nil,
        options: JSONSerialization.ReadingOptions,
        completionHandler: ((URLRequest?, HTTPURLResponse?, AnyObject?, NSError?) -> Void)?) {
        request.responseJSON(queue: queue, options: options) { (results) in
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
                        request.responseJSON(options: options, completionHandler: completionHandler)
                        return
                    }
                }
                if let err = result.error {
                    if err.code == NSURLErrorCancelled {
                        cancelled = true
                    }
                }
            }
            if !cancelled {
                completionHandler?(request, response, result.value, result.error)
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
        completionHandler: ((URLRequest?, HTTPURLResponse?, AnyObject?, NSError?) -> Void)?) -> Self {
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
    fileprivate var completionHandler: ((URLRequest?, HTTPURLResponse?, AnyObject?, NSError?) -> Void)?
    
    fileprivate init(builder: UploadBuilder) {
        self.builder = builder
        super.init()
    }
    
    open override func responseJSON(
        queue: DispatchQueue? = nil,
        options: JSONSerialization.ReadingOptions,
        completionHandler: ((URLRequest?, HTTPURLResponse?, AnyObject?, NSError?) -> Void)?) -> Self {
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
        let HTTPOnly: Bool
        
        public init(host: String, port: String, HTTPOnly: Bool = true) {
            self.host = host
            self.port = port
            self.HTTPOnly = HTTPOnly
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
                    let sessionConfiguration = AFManager.sharedInstance.session.configuration
                    sessionConfiguration.connectionProxyDictionary = proxyConfiguration
                    manager = AFManager(configuration: sessionConfiguration)
                }
            } else {
                manager = AFManager.sharedInstance
            }
        }
    }
    
    public static func request(_ URL: String) -> RequestBuilder {
        return RequestBuilder(URL: URL)
    }
    
    public static func upload(_ URL: String) -> UploadBuilder {
        return UploadBuilder(URL: URL)
    }
    
    public static var client: NetworkClientProtocol.Type?
    
    fileprivate static var manager = AFManager.sharedInstance
}

open class HTTPBuilder: NSObject {
    
    fileprivate init(URL: String) {
        URLString = URL
        super.init()
    }
    
    open func method(_ method: Alamofire.Method) -> Self {
        HTTPMethod = method
        return self
    }
    
    open func appendCommonParameters(_ append: Bool) -> Self {
        vappendCommonParameters = append
        return self
    }
    
    open func query(_ parameters: [String : AnyObject]?) -> Self {
        queryParameters = parameters
        return self
    }
    
    open func post(_ parameters: [String : AnyObject]?) -> Self {
        postParameters = parameters
        if let p = parameters , !p.isEmpty {
            method(.POST)
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
    
    fileprivate func appendQueryParameters(_ parameters: [String : AnyObject]?, toString absoluteString: NSMutableString) {
        guard let parameters = parameters , !parameters.isEmpty else {
            return
        }
        var components: [(String, String)] = []
        for key in Array(parameters.keys).sorted(by: <) {
            let value = parameters[key]!
            components += Alamofire.ParameterEncoding.URLEncodedInURL.queryComponents(key, value)
        }
        let query = (components.map { "\($0)=\($1)" } as [String]).joined(separator: "&")
        if !query.isEmpty {
            if absoluteString.contains("?") {
                absoluteString.append("&")
            } else {
                absoluteString.append("?")
            }
            absoluteString.append(query)
        }
    }
    
    open func build() -> Request? {
        return nil
    }
    
    fileprivate var URLString: String
    fileprivate var vheaders: [String : String]?
    fileprivate var queryParameters: [String : AnyObject]?
    fileprivate var parameterEncoding: ParameterEncoding = .URL
    fileprivate var vappendCommonParameters = true
    fileprivate var retryTimes: UInt16 = 0
    fileprivate var timeoutInterval: TimeInterval = 30
    fileprivate var vcachePolicy = NSURLRequest.CachePolicy.useProtocolCachePolicy
    fileprivate var vpriority = Network.Priority.default
    fileprivate var vgzipEnabled = true
    /// 发送请求的时间（unix时间戳）
    fileprivate var requestTimestamp: TimeInterval = 0
    
    fileprivate var HTTPMethod: AFMethod = .GET
    fileprivate var postParameters: [String : AnyObject]?
}

/**
 网络请求
 <br />
 Usage:
 <br />
 NewsMaster.Network.request(url)
 .method([GET|POST|HEAD|PATCH|DELETE...])?<br />
 .get([String:AnyObject])?<br />
 .post([String:AnyObject])?<br />
 .retry(retryTimes)?<br />
 .headers(["Accept": "xxx"])?<br />
 .encoding(FormData|Mutilpart|JSON|...)?<br />
 .priority(Network.Default)?<br />
 .timeout(seconds)?<br />
 .append(commonParameters)?<br />
 .pack() unwrap?.pon_response { _, _, results, error in logic }
 */
open class RequestBuilder: HTTPBuilder {
    
    override init(URL: String) {
        super.init(URL: URL)
    }
    
    fileprivate static var manager = AFManager.sharedInstance
    fileprivate static func resetManager() {
        manager = AFManager.sharedInstance
    }
    
    open func encoding(_ encoding: ParameterEncoding) -> Self {
        parameterEncoding = encoding
        return self
    }
    
    /// NOTE: never use this way on main thread
    open func syncResponseJSON(options: JSONSerialization.ReadingOptions = .allowFragments) -> (URLResponse?, AnyObject?, NSError?) {
        if let request = build() {
            var response: URLResponse?
            var responseData: AnyObject?
            var responseError: NSError?
            let semaphore = DispatchSemaphore(value: 0)
            request.responseJSON(queue: DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default), options: options, completionHandler: { (_, URLResponse, data, error) -> Void in
                response = URLResponse
                responseData = data
                responseError = error
                semaphore.signal()
            })
            semaphore.wait(timeout: DispatchTime.distantFuture)
            return (response, responseData, responseError)
        }
        return (nil, nil, nil)
    }
    
    open override func build() -> Request? {
        if self.URLString.utf16.count == 0 {
            return nil
        }
        let absoluteString = NSMutableString(string: self.URLString)
        appendQueryParameters(queryParameters, toString: absoluteString)
        if vappendCommonParameters {
            // 从CommonParams中删除 getParameters
            if let commonParameters = Network.client?.commonParameters {
                let restCommonParameters = commonParameters - queryParameters
                appendQueryParameters(restCommonParameters, toString: absoluteString)
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
        
        guard let mutableURLRequest = mutableRequestWithURLString(URLString, method: HTTPMethod, headers: headers) else {
            return nil
        }
        requestTimestamp = Date().timeIntervalSince1970
        if timeoutInterval != 0 {
            mutableURLRequest.timeoutInterval = timeoutInterval
        }
        mutableURLRequest.cachePolicy = vcachePolicy
        let encodedURLRequest = parameterEncoding.encode(mutableURLRequest, parameters: postParameters).0
        // GZIP Compress
        if vgzipEnabled {
            if let HTTPBody = encodedURLRequest.HTTPBody, let client = Network.client {
                var newHTTPBody = HTTPBody
                let compressed = client.compressDataUsingGZip(&newHTTPBody)
                if newHTTPBody.length > 0 && compressed {
                    encodedURLRequest.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
                    encodedURLRequest.HTTPBody = newHTTPBody
                }
            }
        }
        let afRequest = Network.manager.request(encodedURLRequest)
        afRequest.task.priority = vpriority.rawValue
        let resultRequest = NormalRequest(builder: self, request: afRequest)
        resultRequest.maximumNumberOfRetryTimes = retryTimes
        return resultRequest
    }
    
    fileprivate func mutableRequestWithURLString(_ URLString: String, method: AFMethod, headers: [String : AnyObject]?) -> NSMutableURLRequest? {
        guard let URL = URL(string: URLString) else {
            return nil
        }
        let mutableURLRequest = NSMutableURLRequest(url: URL)
        mutableURLRequest.HTTPMethod = method.rawValue
        if let headers = headers {
            for (headerField, headerValue) in headers {
                if let headerValue = headerValue as? String {
                    mutableURLRequest.setValue(headerValue, forHTTPHeaderField: headerField)
                }
            }
        }
        return mutableURLRequest
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
        if self.URLString.utf16.count == 0 {
            return nil
        }
        let request = UploadRequest(builder: self)
        request.maximumNumberOfRetryTimes = retryTimes
        
        let absoluteString = NSMutableString(string: self.URLString)
        appendQueryParameters(queryParameters, toString: absoluteString)
        if vappendCommonParameters {
            // 从CommonParams中删除 getParameters
            if let commonParameters = Network.client?.commonParameters {
                let restCommonParameters = commonParameters - queryParameters
                appendQueryParameters(restCommonParameters, toString: absoluteString)
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
        
        let dataParts = self.dataParts
        let fileParts = self.fileParts
        let postParts = postParameters
        
        Alamofire.upload(
            .POST,
            URLString,
            headers: headers,
            multipartFormData: { (multipartFormData) -> Void in
                postParts?.forEach({ k, v in
                    if let data = ((v as? NSString) ?? ("\(v)" as NSString)).dataUsingEncoding(NSUTF8StringEncoding) { multipartFormData.appendBodyPart(data: data, name: k)
                    }
                })
                dataParts.forEach({self.appendData($0, toMultipartFormData: multipartFormData)})
                fileParts.forEach({self.appendFile($0, toMultipartFormData: multipartFormData)})
            }, encodingMemoryThreshold: UInt64(2_000_000)) { (encodingResult) -> Void in
                switch encodingResult {
                case .Success(let upload, _, _):
                    upload.task.priority = self.vpriority.rawValue
                    self.requestTimestamp = NSDate().timeIntervalSince1970
                    request.request = upload
                    request.startUploading()
                case .Failure(let encodingError):
                    request.notifyError(encodingError)
                }
        }
        request.maximumNumberOfRetryTimes = self.retryTimes
        return request
    }

    fileprivate func appendData(_ data: Data, toMultipartFormData multipartFormData: Alamofire.MultipartFormData) {
        if let mimeType = data.mimeType {
            if let fileName = data.fileName {
                multipartFormData.appendBodyPart(data: data.data, name: data.name, fileName: fileName, mimeType: mimeType)
            } else {
                multipartFormData.appendBodyPart(data: data.data, name: data.name, mimeType: mimeType)
            }
        } else {
            multipartFormData.appendBodyPart(data: data.data, name: data.name)
        }
    }
    
    fileprivate func appendFile(_ file: File, toMultipartFormData multipartFormData: Alamofire.MultipartFormData) {
        if let mimeType = file.mimeType {
            if let fileName = file.fileName {
                multipartFormData.appendBodyPart(fileURL: file.fileURL, name: file.name, fileName: fileName, mimeType: mimeType)
            } else {
                multipartFormData.appendBodyPart(fileURL: file.fileURL, name: file.name, fileName: "\(Date().timeIntervalSince1970)", mimeType: mimeType)
            }
        } else {
            multipartFormData.appendBodyPart(fileURL: file.fileURL, name: file.name)
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

