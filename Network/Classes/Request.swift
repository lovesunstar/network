//
//  Request.swift
//  Alamofire
//
//  Created by 孙江挺 on 2018/6/6.
//

import Foundation
import Alamofire

public extension Network {
    
    public class Request {
        
        fileprivate static func isErrorEnabledToRetry(_ error: Error) -> Bool {
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
        
        internal var httpBuilder: HTTPBuilder {
            fatalError("Sub class must implemention")
        }
        
        internal init() {
            
        }
        
        public var didCancelCallback: ((Request) ->Void)?
        
        public internal(set) weak var network: Network?
        
        public var timeoutInterval: TimeInterval {
            return httpBuilder.timeoutInterval * TimeInterval(httpBuilder.retryTimes + 1)
        }
        
        fileprivate func canRetryWithError(_ error: Error) -> Bool {
            return Request.isErrorEnabledToRetry(error) && retriedTimes < maximumNumberOfRetryTimes
        }
        
        internal var retriedTimes: UInt16 = 0
        internal var maximumNumberOfRetryTimes: UInt16 = 0
        
        @discardableResult open func responseJSON(
            queue: DispatchQueue? = nil,
            options: JSONSerialization.ReadingOptions = .allowFragments,
            completionHandler: ((URLRequest?, HTTPURLResponse?, Any?, NSError?) -> Void)?)
            -> Self {
                return self
        }
        
        open func cancel() {
            didCancelCallback?(self)
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
                    let metrics: Any?
                    if #available(iOS 10, *) {
                        metrics = results.metrics
                    } else {
                        metrics = nil
                    }
                    let timestamp = self.httpBuilder.requestTimestamp
                    let duration = Date().timeIntervalSince1970 - timestamp
                    Network.client?.willProcessResponse(urlRequest, totalDuration: duration, responseData: result.value, error: result.error, urlResponse: response, timeline: results.timeline, metrics: metrics)
                }
                var cancelled = false
                if let error = result.error {
                    if self.canRetryWithError(error) {
                        if let request = self.httpBuilder.build() {
                            request.retriedTimes = (self.retriedTimes + 1)
                            self.httpBuilder.requestTimestamp = Date().timeIntervalSince1970
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

    public class NormalRequest: Network.Request {
        
        internal let request: Alamofire.Request
        internal let builder: RequestBuilder
        
        internal override var httpBuilder: HTTPBuilder {
            return builder
        }
        
        internal init(builder: RequestBuilder, request: Alamofire.Request) {
            self.builder = builder
            self.request = request
            super.init()
        }
        
        public override var timeoutInterval: TimeInterval {
            if let requestTimeoutInterval = request.request?.timeoutInterval {
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

    public class UploadRequest: Network.Request {
        
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
        
        public override var timeoutInterval: TimeInterval {
            if let requestTimeoutInterval = request?.request?.timeoutInterval {
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
}
