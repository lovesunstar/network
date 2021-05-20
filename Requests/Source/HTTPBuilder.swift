//
//  HTTPBuilder.swift
//  Alamofire
//
//  Created by 孙江挺 on 2018/6/6.
//

import Foundation
import Alamofire

public class HTTPBuilder: NSObject {
    
    internal weak var session: Requests.Session?
    
    internal var querySorter: ((String, String)->Bool)?
    
    required init(url: String, session: Requests.Session) {
        urlString = url
        self.session = session
        super.init()
    }
    
    public override init() {
        fatalError()
    }
    
    @discardableResult
    open func method(_ method: Alamofire.HTTPMethod) -> Self {
        httpMethod = method
        return self
    }
    
    @discardableResult
    open func mark(_ mark: [String: Any]?) -> Self {
        requestExtra = mark
        return self
    }
    
    @discardableResult
    open func appendCommonParameters(_ append: Bool) -> Self {
        vappendCommonParameters = append
        return self
    }
    
    @discardableResult
    open func query(_ parameters: [String : Any]?) -> Self {
        queryParameters = parameters
        return self
    }
    
    @discardableResult
    open func post(_ parameters: [String : Any]?) -> Self {
        postParameters = parameters
        if let p = parameters , !p.isEmpty {
            let _ = method(.post)
        }
        return self
    }
    
    @discardableResult
    open func content(_ parameters: [String : Any]?) -> Self {
        postParameters = parameters
        return self
    }
    
    @discardableResult
    open func headers(_ headers: [String : String]?) -> Self {
        vheaders = headers
        return self
    }
    
    @discardableResult
    open func gzipEnabled(_ enabled: Bool) -> Self {
        vgzipEnabled = enabled
        return self
    }
    
    @discardableResult
    open func retry(_ retryTimes: UInt16) -> Self {
        self.retryTimes = retryTimes
        return self
    }
    
    @discardableResult
    open func timeout(_ timeout: TimeInterval) -> Self {
        timeoutInterval = timeout
        return self
    }
    
    @discardableResult
    open func cachePolicy(_ policy: NSURLRequest.CachePolicy) -> Self {
        vcachePolicy = policy
        return self
    }
    
    @discardableResult
    open func priority(_ priority: Session.Priority) -> Self {
        vpriority = priority
        return self
    }
    
    @discardableResult
    open func encoding(_ encoding: ParameterEncoding) -> Self {
        parameterEncoding = encoding
        return self
    }
    
    @discardableResult
    open func downloadProgress(on queue: DispatchQueue = DispatchQueue.main, callback:((Progress)->Void)?) -> Self {
        downloadProgressQueue = queue
        downloadProgressCallback = callback
        return self
    }
  
    func append(_ parameters: [String : Any]?, to absoluteString: String) -> String {
        guard let parameters = parameters , !parameters.isEmpty else {
            return absoluteString
        }
        var results = absoluteString
        var components: [(String, String)] = []
        let sorter: (String, String) -> Bool = querySorter ?? { (lhs: String, rhs: String) -> Bool in
            return lhs < rhs
        }
        for key in Array(parameters.keys).sorted(by: sorter) {
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
    
    internal var urlString: String
    internal var vheaders: [String : String]?
    internal var queryParameters: [String : Any]?
    internal var parameterEncoding: ParameterEncoding = .url
    internal var vappendCommonParameters = true
    internal var retryTimes: UInt16 = 0
    internal var timeoutInterval: TimeInterval = Session.client?.timeoutInterval ?? 15
    internal var vcachePolicy = NSURLRequest.CachePolicy.useProtocolCachePolicy
    internal var vpriority = Session.Priority.default
    
    internal var downloadProgressQueue: DispatchQueue?
    internal var downloadProgressCallback: ((Progress)->Void)?
    
    internal var vgzipEnabled = Session.client?.isGZipEnabled ?? false
    /// 发送请求的时间（unix时间戳）
    internal var requestTimestamp: TimeInterval = 0
    
    internal var httpMethod: AFMethod = .get
    internal var postParameters: [String : Any]?
    
    internal var requestExtra: [String : Any]?
}
