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

typealias AFRequest = Alamofire.Request
typealias AFManager = Alamofire.Manager
typealias AFMethod = Alamofire.Method

let ConnectionFailedErrorCode = -99999999

public func ==(lhs: Network.ProxyItem, rhs: Network.ProxyItem) -> Bool {
    return lhs.host == rhs.host && lhs.port == rhs.port
}

public protocol NetworkClientProtocol: NSObjectProtocol {
    
    static var commonParameters: [String: AnyObject]? { get }
    static var requestHeaders: [String: AnyObject]? { get }
    
    /**
     - returns: compressed
    */
    static func compressDataUsingGZip(inout data: NSData) -> Bool
    
    static func willProcessRequestWithURL(inout URLString: String, inout headers: [String: AnyObject])
    
    static func willProcessResponseWithRequest(request: NSURLRequest, timestamp: NSTimeInterval, duration: NSTimeInterval, responseData: AnyObject?, error: ErrorType?, URLResponse: NSHTTPURLResponse?)
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
        let HTTPOnly = true
        
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
    
    public static var client: NetworkClientProtocol.Type?
    
    private static var manager = AFManager.sharedInstance
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
public class RequestBuilder: NSObject {
    
    static var manager = AFManager.sharedInstance
    static func resetManager() {
        manager = AFManager.sharedInstance
    }
    
    var completionHandler: ((AnyObject) -> Void)?
    
    private init(URL: String) {
        URLString = URL
        super.init()
    }
    
    func method(method: Alamofire.Method) -> Self {
        HTTPMethod = method
        return self
    }
    
    func appendCommonParameters(append: Bool) -> Self {
        vappendCommonParameters = append
        return self
    }
    
    func get(parameters: [String : AnyObject]?) -> Self {
        getParameters = parameters
        return self
    }
    
    func post(parameters: [String : AnyObject]?) -> Self {
        postParameters = parameters
        if let p = parameters where !p.isEmpty {
            method(.POST)
        }
        return self
    }
    
    func headers(headers: [String : String]?) -> Self {
        vheaders = headers
        return self
    }
    
    func encoding(encoding: ParameterEncoding) -> Self {
        parameterEncoding = encoding
        return self
    }
    
    func gzipEnabled(enabled: Bool) -> Self {
        vgzipEnabled = enabled
        return self
    }
    
    func retry(retryTimes: UInt16) -> Self {
        self.retryTimes = retryTimes
        return self
    }
    
    func timeout(timeout: NSTimeInterval) -> Self {
        timeoutInterval = timeout
        return self
    }
    
    func cachePolicy(policy: NSURLRequestCachePolicy) -> Self {
        vcachePolicy = policy
        return self
    }
    
    func priority(priority: Network.Priority) -> Self {
        vpriority = priority
        return self
    }
    
    func build() -> AFRequest? {
        if self.URLString.utf16.count == 0 {
            return nil
        }
        let absoluteString = NSMutableString(string: self.URLString)
        
        func appendQueryParameters(parameters: [String : AnyObject]?) {
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
        appendQueryParameters(getParameters)
        if vappendCommonParameters {
            // 从CommonParams中删除 getParameters
            if let commonParameters = Network.client?.commonParameters {
                let restCommonParameters = commonParameters - getParameters
                appendQueryParameters(restCommonParameters)
            }
        }
        var headers = [String : AnyObject]()
        if let defaultHeaders = Network.client?.requestHeaders {
            headers += defaultHeaders
        }
        headers += vheaders
        var URLString = absoluteString as String
        Network.client?.willProcessRequestWithURL(&URLString, headers: &headers)
        
        guard let mutableURLRequest = mutableRequestWithURLString(URLString, method: HTTPMethod, headers: headers) else {
            return nil
        }
        requestTimestamp = NSDate().timeIntervalSince1970
        if timeoutInterval != 0 {
            mutableURLRequest.timeoutInterval = timeoutInterval
        }
        mutableURLRequest.cachePolicy = vcachePolicy
        let encodedURLRequest = parameterEncoding.encode(mutableURLRequest, parameters: self.postParameters).0
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
        afRequest.nt_maximumNumberOfRetryTimes = retryTimes
        afRequest.nt_request = self
        return afRequest
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
    
    private var HTTPMethod: AFMethod = .GET
    private var URLString: String
    private var vheaders: [String : String]?
    
    private var getParameters: [String : AnyObject]?
    private var postParameters: [String : AnyObject]?
    private var parameterEncoding: ParameterEncoding = .URL
    private var vappendCommonParameters = true
    private var retryTimes: UInt16 = 0
    private var timeoutInterval: NSTimeInterval = 30
    private var vcachePolicy = NSURLRequestCachePolicy.UseProtocolCachePolicy
    private var vpriority = Network.Priority.Default
    private var vgzipEnabled = true
    /// 发送请求的时间（unix时间戳）
    private var requestTimestamp: NSTimeInterval = 0
}

/**
*    代码中 nt 开头的表示 network 的缩写
*/
extension Alamofire.Request {

    private struct NetworkAFRequestStatic {
        static var retriedTimesKey = "NewsMasterAFRetriedTimesKey"
        static var maxRetryTimesKey = "NewsMasterAFMaxRetryTimesKey"
        static var requestKey = "NewsMasterAFMaxRetryTimesKey"
    }

    private var nt_retriedTimes: UInt16 {
        get {
            if let value = objc_getAssociatedObject(self, &NetworkAFRequestStatic.retriedTimesKey) as? NSNumber {
                return value.unsignedShortValue
            }
            return 0
        }
        set {
            objc_setAssociatedObject(self, &NetworkAFRequestStatic.retriedTimesKey, NSNumber(unsignedShort:  newValue), objc_AssociationPolicy.OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
    }

    private var nt_maximumNumberOfRetryTimes: UInt16 {
        get {
            if let value = objc_getAssociatedObject(self, &NetworkAFRequestStatic.maxRetryTimesKey) as? NSNumber {
                return value.unsignedShortValue
            }
            return 0
        }
        set {
            objc_setAssociatedObject(self, &NetworkAFRequestStatic.maxRetryTimesKey, NSNumber(unsignedShort:  newValue), objc_AssociationPolicy.OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
    }

    private var nt_request: RequestBuilder? {
        get {
            return objc_getAssociatedObject(self, &NetworkAFRequestStatic.requestKey) as? RequestBuilder
        }
        set {
            objc_setAssociatedObject(self, &NetworkAFRequestStatic.requestKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    private func nt_isErrorEnabledToRetry(error: ErrorType) -> Bool {
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled {
            return false
        }
        let weakConnects = [NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet]
        return weakConnects.contains(nsError.code)
    }

    private func nt_canRetryWithError(error: ErrorType) -> Bool {
        return nt_isErrorEnabledToRetry(error) && nt_retriedTimes < nt_maximumNumberOfRetryTimes
    }

    public func nt_responseJSON(completionHandler: (NSURLRequest?, NSHTTPURLResponse?, AnyObject?, ErrorType?) -> Void) -> Self {
        responseJSON(options: .AllowFragments) { (request, response, result) -> Void in
            if let ponRequest = self.nt_request, urlRequest = request {
                //
                let timestamp = ponRequest.requestTimestamp
                let duration = NSDate().timeIntervalSince1970 - ponRequest.requestTimestamp
                Network.client?.willProcessResponseWithRequest(urlRequest, timestamp: timestamp, duration: duration, responseData: result.value, error: result.error, URLResponse: response)
            }
            var cancelled = false
            if let error = result.error {
                if self.nt_canRetryWithError(error) {
                    if let prequest = self.nt_request, afRequest = prequest.build() {
                        // retry
                        afRequest.nt_maximumNumberOfRetryTimes = prequest.retryTimes
                        afRequest.nt_retriedTimes = (afRequest.nt_retriedTimes + 1)
                        afRequest.nt_responseJSON(completionHandler)
                        return
                    }
                }
                if let err = result.error as? NSError {
                    if err.code == NSURLErrorCancelled {
                        cancelled = true
                    }
                }
            }
            if !cancelled {
                completionHandler(request, response, result.value, result.error)
            }
        }
        return self
    }
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

