//
//  HTTPBuilder.swift
//  Alamofire
//
//  Created by 孙江挺 on 2018/6/6.
//

import Foundation
import Alamofire

public class UploadBuilder: HTTPBuilder {
    
    private class Part {
        var name: String
        var fileName: String?
        var mimeType: String?
        
        init(name: String) {
            self.name = name
        }
    }
    
    internal var uploadProgressQueue: DispatchQueue?
    internal var uploadProgressCallback: ((Progress)->Void)?
    
    private class Data: Part {
        
        var data: Foundation.Data
        
        init(name: String, data: Foundation.Data) {
            self.data = data
            super.init(name: name)
        }
    }
    
    required init(url: String, session: Requests.Session) {
        super.init(url: url, session: session)
        timeoutInterval = 180
    }
    
    @discardableResult
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
    
    @discardableResult
    open func append(file fileURL: URL, name: String, fileName: String, mimeType: String? = nil) -> Self {
        let part = File(name: name, fileURL: fileURL)
        part.fileName = fileName
        part.mimeType = mimeType
        fileParts.append(part)
        return self
    }
    
    @discardableResult
    open func uploadProgress(on queue: DispatchQueue = DispatchQueue.main, callback:((Progress)->Void)?) -> Self {
        uploadProgressQueue = queue
        uploadProgressCallback = callback
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
            if let commonParameters = Session.client?.commonParameters {
                let restCommonParameters = commonParameters - queryParameters
                absoluteString = append(restCommonParameters, to: absoluteString)
            }
        }
        var headers = [String : String]()
        if let defaultHeaders = Session.client?.requestHeaders {
            headers += defaultHeaders
        }
        headers += vheaders
        var postParameters = self.postParameters
        Session.client?.willProcessRequest(&absoluteString, headers: &headers, parameters: &postParameters)
        
        let dataParts = self.dataParts
        let fileParts = self.fileParts
        let postParts = postParameters
        
        guard let url = URL(string: absoluteString) else { return nil }
        var urlRequest = URLRequest(url: url)
        for (headerField, headerValue) in headers {
            urlRequest.setValue(headerValue, forHTTPHeaderField: headerField)
        }
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutInterval
        
        let uploadRequest = (session?.afSession ?? AF).upload(multipartFormData: { (multipartFormData) in
            postParts?.forEach({ k, v in
                if let data = ((v as? String) ?? "\(v)").data(using: .utf8) {
                    multipartFormData.append(data, withName: k)
                }
            })
            dataParts.forEach({self.append($0, to: multipartFormData)})
            fileParts.forEach({self.append($0, to: multipartFormData)})
            }, with: urlRequest, usingThreshold: 2_000_000)
        self.requestTimestamp = NSDate().timeIntervalSince1970
        if let pq = uploadProgressCallback {
            uploadRequest.uploadProgress(queue: uploadProgressQueue ?? DispatchQueue.main, closure: pq)
        }
        if let dc = downloadProgressCallback {
            uploadRequest.downloadProgress(queue: downloadProgressQueue ?? DispatchQueue.main, closure: dc)
        }
        uploadRequest.task?.priority = vpriority.rawValue
        request.request = uploadRequest
        request.maximumNumberOfRetryTimes = self.retryTimes
        request.startUploading()
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
