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
    static func compressDataUsingGZip(inout data: NSData) -> Bool
    
    static func willProcessRequestWithURL(inout URLString: String, inout headers: [String: String], inout parameters: [String: AnyObject]?)
    
    static func willProcessResponseWithRequest(request: NSURLRequest, timestamp: NSTimeInterval, duration: NSTimeInterval, responseData: AnyObject?, error: ErrorType?, URLResponse: NSHTTPURLResponse?)
}


private func isErrorEnabledToRetry(error: ErrorType) -> Bool {
    let nsError = error as NSError
    if nsError.code == NSURLErrorCancelled {
        return false
    }
    let weakConnects = [NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet]
    return weakConnects.contains(nsError.code)
}

public class Request {
    
    private var httpBuilder: HTTPBuilder {
        fatalError("Sub class must implemention")
    }
    
    private init() {
        
    }
    
    private func canRetryWithError(error: ErrorType) -> Bool {
        return isErrorEnabledToRetry(error) && retriedTimes < maximumNumberOfRetryTimes
    }
    
    private var retriedTimes: UInt16 = 0
    private var maximumNumberOfRetryTimes: UInt16 = 0
    
    public func responseJSON(
        queue queue: dispatch_queue_t? = nil,
        options: NSJSONReadingOptions = .AllowFragments,
        completionHandler: ((NSURLRequest?, NSHTTPURLResponse?, AnyObject?, NSError?) -> Void)?)
        -> Self {
            return self
    }
    
    public func cancel() {
        
    }
    
    private func responseJSONWithRequest(
        request: Alamofire.Request,
        queue: dispatch_queue_t? = nil,
        options: NSJSONReadingOptions,
        completionHandler: ((NSURLRequest?, NSHTTPURLResponse?, AnyObject?, NSError?) -> Void)?) {
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

public class NormalRequest: Request {
    
    private let request: Alamofire.Request
    private let builder: RequestBuilder
    
    private override var httpBuilder: HTTPBuilder {
        return builder
    }
    
    private init(builder: RequestBuilder, request: Alamofire.Request) {
        self.builder = builder
        self.request = request
        super.init()
    }
    
    override public func responseJSON(
        queue queue: dispatch_queue_t? = nil,
        options: NSJSONReadingOptions,
        completionHandler: ((NSURLRequest?, NSHTTPURLResponse?, AnyObject?, NSError?) -> Void)?) -> Self {
            responseJSONWithRequest(request, queue: queue, options: options, completionHandler: completionHandler)
        return self
    }
    
    public override func cancel() {
        request.cancel()
    }
}

public class UploadRequest: Request {
    
    private var request: Alamofire.Request?
    
    private let builder: UploadBuilder
    
    private override var httpBuilder: HTTPBuilder {
        return builder
    }
    
    private var options: NSJSONReadingOptions = .AllowFragments
    private var completionHandler: ((NSURLRequest?, NSHTTPURLResponse?, AnyObject?, NSError?) -> Void)?
    
    private init(builder: UploadBuilder) {
        self.builder = builder
        super.init()
    }
    
    public override func responseJSON(
        queue queue: dispatch_queue_t? = nil,
        options: NSJSONReadingOptions,
        completionHandler: ((NSURLRequest?, NSHTTPURLResponse?, AnyObject?, NSError?) -> Void)?) -> Self {
        if let request = request {
            responseJSONWithRequest(request, options: options, completionHandler: completionHandler)
        } else {
            self.options = options
            self.completionHandler = completionHandler
        }
        return self
    }
    
    public override func cancel() {
        request?.cancel()
    }
    
    private func startUploading() {
        if let request = request {
            responseJSONWithRequest(request, options: self.options, completionHandler: self.completionHandler)
        }
    }
    
    private func notifyError(error: ErrorType) {
        completionHandler?(nil, nil, nil, error as NSError)
    }
}

public struct Network {
    
    public enum Priority: Float {
        case Background = 0
        case Low = 0.25
        case Default = 0.5
        case High = 0.75
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
                    var proxyConfiguration = [NSObject: AnyObject]()
                    proxyConfiguration[kCFNetworkProxiesHTTPProxy] = item.host
                    proxyConfiguration[kCFNetworkProxiesHTTPPort] = port
                    proxyConfiguration[kCFNetworkProxiesHTTPEnable] = 1
                    let sessionConfiguration = AFManager.sharedInstance.session.configuration
                    sessionConfiguration.connectionProxyDictionary = proxyConfiguration
                    manager = AFManager(configuration: sessionConfiguration)
                }
            } else {
                manager = AFManager.sharedInstance
            }
        }
    }
    
    public static func request(URL: String) -> RequestBuilder {
        return RequestBuilder(URL: URL)
    }
    
    public static func upload(URL: String) -> UploadBuilder {
        return UploadBuilder(URL: URL)
    }
    
    public static var client: NetworkClientProtocol.Type?
    
    private static var manager = AFManager.sharedInstance
}

public class HTTPBuilder: NSObject {
    
    private init(URL: String) {
        URLString = URL
        super.init()
    }
    
    public func method(method: Alamofire.Method) -> Self {
        HTTPMethod = method
        return self
    }
    
    public func appendCommonParameters(append: Bool) -> Self {
        vappendCommonParameters = append
        return self
    }
    
    public func query(parameters: [String : AnyObject]?) -> Self {
        queryParameters = parameters
        return self
    }
    
    public func post(parameters: [String : AnyObject]?) -> Self {
        postParameters = parameters
        if let p = parameters where !p.isEmpty {
            method(.POST)
        }
        return self
    }
    
    public func headers(headers: [String : String]?) -> Self {
        vheaders = headers
        return self
    }

    public func gzipEnabled(enabled: Bool) -> Self {
        vgzipEnabled = enabled
        return self
    }
    
    public func retry(retryTimes: UInt16) -> Self {
        self.retryTimes = retryTimes
        return self
    }
    
    public func timeout(timeout: NSTimeInterval) -> Self {
        timeoutInterval = timeout
        return self
    }
    
    public func cachePolicy(policy: NSURLRequestCachePolicy) -> Self {
        vcachePolicy = policy
        return self
    }
    
    public func priority(priority: Network.Priority) -> Self {
        vpriority = priority
        return self
    }
    
    private func appendQueryParameters(parameters: [String : AnyObject]?, toString absoluteString: NSMutableString) {
        guard let parameters = parameters where !parameters.isEmpty else {
            return
        }
        var components: [(String, String)] = []
        for key in Array(parameters.keys).sort(<) {
            let value = parameters[key]!
            components += Alamofire.ParameterEncoding.URLEncodedInURL.queryComponents(key, value)
        }
        let query = (components.map { "\($0)=\($1)" } as [String]).joinWithSeparator("&")
        if !query.isEmpty {
            if absoluteString.containsString("?") {
                absoluteString.appendString("&")
            } else {
                absoluteString.appendString("?")
            }
            absoluteString.appendString(query)
        }
    }
    
    public func build() -> Request? {
        return nil
    }
    
    private var URLString: String
    private var vheaders: [String : String]?
    private var queryParameters: [String : AnyObject]?
    private var parameterEncoding: ParameterEncoding = .URL
    private var vappendCommonParameters = true
    private var retryTimes: UInt16 = 0
    private var timeoutInterval: NSTimeInterval = 30
    private var vcachePolicy = NSURLRequestCachePolicy.UseProtocolCachePolicy
    private var vpriority = Network.Priority.Default
    private var vgzipEnabled = true
    /// 发送请求的时间（unix时间戳）
    private var requestTimestamp: NSTimeInterval = 0
    
    private var HTTPMethod: AFMethod = .GET
    private var postParameters: [String : AnyObject]?
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
public class RequestBuilder: HTTPBuilder {
    
    override init(URL: String) {
        super.init(URL: URL)
    }
    
    private static var manager = AFManager.sharedInstance
    private static func resetManager() {
        manager = AFManager.sharedInstance
    }
    
    public func encoding(encoding: ParameterEncoding) -> Self {
        parameterEncoding = encoding
        return self
    }
    
    /// NOTE: never use this way on main thread
    public func syncResponseJSON(options options: NSJSONReadingOptions = .AllowFragments) -> (NSURLResponse?, AnyObject?, NSError?) {
        if let request = build() {
            var response: NSURLResponse?
            var responseData: AnyObject?
            var responseError: NSError?
            let semaphore = dispatch_semaphore_create(0)
            request.responseJSON(queue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), options: options, completionHandler: { (_, URLResponse, data, error) -> Void in
                response = URLResponse
                responseData = data
                responseError = error
                dispatch_semaphore_signal(semaphore)
            })
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
            return (response, responseData, responseError)
        }
        return (nil, nil, nil)
    }
    
    public override func build() -> Request? {
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
        requestTimestamp = NSDate().timeIntervalSince1970
        if timeoutInterval != 0 {
            mutableURLRequest.timeoutInterval = timeoutInterval
        }
        mutableURLRequest.cachePolicy = vcachePolicy
        let encodedURLRequest = parameterEncoding.encode(mutableURLRequest, parameters: postParameters).0
        // GZIP Compress
        if vgzipEnabled {
            if let HTTPBody = encodedURLRequest.HTTPBody, client = Network.client {
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
    
    private func mutableRequestWithURLString(URLString: String, method: AFMethod, headers: [String : AnyObject]?) -> NSMutableURLRequest? {
        guard let URL = NSURL(string: URLString) else {
            return nil
        }
        let mutableURLRequest = NSMutableURLRequest(URL: URL)
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

public class UploadBuilder: HTTPBuilder {
    
    private class Part {
        var name: String
        var fileName: String?
        var mimeType: String?
        
        init(name: String) {
            self.name = name
        }
    }
    
    private class Data: Part {
        
        var data: NSData
        
        init(name: String, data: NSData) {
            self.data = data
            super.init(name: name)
        }
    }
    
    public func append(data data: NSData, name: String, fileName: String? = nil, mimeType: String? = nil) -> Self {
        let part = Data(name: name, data: data)
        part.fileName = fileName
        part.mimeType = mimeType
        dataParts.append(part)
        return self
    }
    
    private class File: Part {
        var fileURL: NSURL
        
        init(name: String, fileURL: NSURL) {
            self.fileURL = fileURL
            super.init(name: name)
        }
    }
    
    public func append(file fileURL: NSURL, name: String, fileName: String, mimeType: String? = nil) -> Self {
        let part = File(name: name, fileURL: fileURL)
        part.fileName = fileName
        part.mimeType = mimeType
        fileParts.append(part)
        return self
    }

    public override func build() -> Request? {
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

    private func appendData(data: Data, toMultipartFormData multipartFormData: Alamofire.MultipartFormData) {
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
    
    private func appendFile(file: File, toMultipartFormData multipartFormData: Alamofire.MultipartFormData) {
        if let mimeType = file.mimeType {
            if let fileName = file.fileName {
                multipartFormData.appendBodyPart(fileURL: file.fileURL, name: file.name, fileName: fileName, mimeType: mimeType)
            } else {
                multipartFormData.appendBodyPart(fileURL: file.fileURL, name: file.name, fileName: "\(NSDate().timeIntervalSince1970)", mimeType: mimeType)
            }
        } else {
            multipartFormData.appendBodyPart(fileURL: file.fileURL, name: file.name)
        }
    }
    
    private var dataParts = [Data]()
    private var fileParts = [File]()
}

func +=<KeyType, ValueType>(inout lhs: Dictionary<KeyType, ValueType>, rhs: Dictionary<KeyType, ValueType>?) {
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

func -=<KeyType, ValueType>(inout lhs: Dictionary<KeyType, ValueType>, rhs: Dictionary<KeyType, ValueType>?) {
    if let rhs = rhs {
        for (k, _) in rhs {
            lhs.removeValueForKey(k)
        }
    }
}

func -<KeyType, ValueType>(lhs: [KeyType : ValueType], rhs: [KeyType : ValueType]?) -> [KeyType : ValueType] {
    var results = lhs
    if let rhs = rhs {
        for (k, _) in rhs {
            results.removeValueForKey(k)
        }
    }
    return results
}

