//
//  Request.swift
//  Alamofire
//
//  Created by 孙江挺 on 2018/6/6.
//

import Foundation
import Alamofire

class NormalRequest: Requests.Request {
    
    internal let request: Alamofire.Request
    internal let builder: NormalBuilder
    
    internal override var httpBuilder: HTTPBuilder {
        return builder
    }
    
    internal init(builder: NormalBuilder, request: Alamofire.Request) {
        self.builder = builder
        self.request = request
        super.init()
    }
    
    public override var urlString: String {
        if let url = request.request?.url?.absoluteString, !url.isEmpty {
            return url
        }
        return httpBuilder.urlString
    }
    
    public override var timeoutInterval: TimeInterval {
        if let requestTimeoutInterval = request.request?.timeoutInterval, requestTimeoutInterval > 0 {
            return requestTimeoutInterval
        }
        return httpBuilder.timeoutInterval
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
        super.cancel()
    }
}
