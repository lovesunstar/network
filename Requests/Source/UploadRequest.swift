//
//  Request.swift
//  Alamofire
//
//  Created by 孙江挺 on 2018/6/6.
//

import Foundation
import Alamofire

class UploadRequest: Requests.Request {
    
    internal var request: Alamofire.Request?
    
    internal let builder: UploadBuilder
    
    private var isCancelled = false
    
    internal override var httpBuilder: HTTPBuilder {
        return builder
    }
    
    internal var options: JSONSerialization.ReadingOptions = .allowFragments
    internal var completionHandler: ((URLRequest?, HTTPURLResponse?, Any?, NSError?) -> Void)?
    
    internal init(builder: UploadBuilder) {
        self.builder = builder
        super.init()
    }
    
    public override var urlString: String {
        if let url = request?.request?.url?.absoluteString, !url.isEmpty {
            return url
        }
        return httpBuilder.urlString
    }
    
    public override var timeoutInterval: TimeInterval {
        if let requestTimeoutInterval = request?.request?.timeoutInterval, requestTimeoutInterval > 0 {
            return requestTimeoutInterval
        }
        return httpBuilder.timeoutInterval
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
        isCancelled = true
        super.cancel()
    }
    
    internal func startUploading() {
        if let request = request, !isCancelled {
            responseJSONWithRequest(request, options: self.options, completionHandler: self.completionHandler)
        }
    }
    
    internal func notifyError(_ error: Error) {
        completionHandler?(nil, nil, nil, error as NSError)
    }
}
