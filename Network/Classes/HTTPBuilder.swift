//
//  HTTPBuilder.swift
//  Alamofire
//
//  Created by 孙江挺 on 2018/6/6.
//

import Foundation
import Alamofire

public extension Network {
    
    public class HTTPBuilder: NSObject {
        
        internal let manager: AFManager
        
        internal init(url: String, manager: AFManager) {
            urlString = url
            self.manager = manager
            super.init()
        }
        
        @discardableResult
        open func method(_ method: Alamofire.HTTPMethod) -> Self {
            httpMethod = method
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
        
        internal var urlString: String
        internal var vheaders: [String : String]?
        internal var queryParameters: [String : Any]?
        internal var parameterEncoding: ParameterEncoding = .url
        internal var vappendCommonParameters = true
        internal var retryTimes: UInt16 = 0
        internal var timeoutInterval: TimeInterval = 30
        internal var vcachePolicy = NSURLRequest.CachePolicy.useProtocolCachePolicy
        internal var vpriority = Network.Priority.default
        internal var vgzipEnabled = true
        /// 发送请求的时间（unix时间戳）
        internal var requestTimestamp: TimeInterval = 0
        
        internal var httpMethod: AFMethod = .get
        internal var postParameters: [String : Any]?
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
    public class RequestBuilder: HTTPBuilder {

        @discardableResult
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
            let afRequest = manager.request(encodedURLRequest)
            afRequest.task?.priority = vpriority.rawValue
            let resultRequest = Network.NormalRequest(builder: self, request: afRequest)
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
        
        private class File: Part {
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
            let request = Network.UploadRequest(builder: self)
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
        
        private func append(_ data: Data, to multipartFormData: Alamofire.MultipartFormData) {
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
        
        private func append(_ file: File, to multipartFormData: Alamofire.MultipartFormData) {
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
        
        private var dataParts = [Data]()
        private var fileParts = [File]()
    }
}

