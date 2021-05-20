//
//  HTTPBuilder.swift
//  Alamofire
//
//  Created by 孙江挺 on 2018/6/6.
//

import Foundation
import Alamofire

/**
网络请求
<br />
Usage:
<br />
Network.request(url)
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
public class NormalBuilder: HTTPBuilder {

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
            if let commonParameters = Requests.Session.client?.commonParameters {
                let restCommonParameters = commonParameters - queryParameters
                absoluteString = append(restCommonParameters, to: absoluteString)
            }
        }
        var headers = [String : String]()
        if let defaultHeaders = Requests.Session.client?.requestHeaders {
            headers += defaultHeaders
        }
        headers += vheaders
        var newURLString = absoluteString as String
        var postParameters = self.postParameters
        Requests.Session.client?.willProcessRequest(&newURLString, headers: &headers, parameters: &postParameters)
        guard var mutableURLRequest = mutableRequest(newURLString, method: httpMethod, headers: headers) else {
            return nil
        }
        requestTimestamp = Date().timeIntervalSince1970
        if timeoutInterval != 0 {
            mutableURLRequest.timeoutInterval = timeoutInterval
        }
        mutableURLRequest.cachePolicy = vcachePolicy
        guard var encodedURLRequest = try? parameterEncoding.asAFParameterEncoding().encode(mutableURLRequest, with: postParameters) else { return nil }
        if let HTTPBody = encodedURLRequest.httpBody, let client = Requests.Session.client {
            var newHTTPBody = HTTPBody
            var additionalHeaders = [String: String]()
            let processed = client.preprocessRequestBody(&newHTTPBody, mark: requestExtra, additionalHeaders: &additionalHeaders)
            if processed && newHTTPBody.count > 0 {
                encodedURLRequest.httpBody = newHTTPBody
                if !additionalHeaders.isEmpty {
                    for (k, v) in additionalHeaders {
                        encodedURLRequest.setValue(v, forHTTPHeaderField: k)
                    }
                }
            }
        }
        // GZIP Compress
        if vgzipEnabled {
            if let HTTPBody = encodedURLRequest.httpBody, let client = Requests.Session.client {
                var newHTTPBody = HTTPBody
                let compressed = client.compressBodyUsingGZip(&newHTTPBody)
                if newHTTPBody.count > 0 && compressed {
                    encodedURLRequest.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
                    encodedURLRequest.httpBody = newHTTPBody
                }
            }
        }
        let afRequest = (session?.afSession ?? AFSession.default).request(encodedURLRequest)
        afRequest.task?.priority = vpriority.rawValue
        if let dc = downloadProgressCallback {
            afRequest.downloadProgress(queue: downloadProgressQueue ?? DispatchQueue.main, closure: dc)
        }
        let resultRequest = Requests.NormalRequest(builder: self, request: afRequest)
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
