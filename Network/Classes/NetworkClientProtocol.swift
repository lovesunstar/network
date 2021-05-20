//
//  HTTPBuilder.swift
//  Alamofire
//
//  Created by 孙江挺 on 2018/6/6.
//

import Foundation
import Alamofire

public protocol NetworkClientProtocol: NSObjectProtocol {
    
    static var commonParameters: [String: Any]? { get }
    
    static var commonParametersSorter: ((String, String)->Bool)? { get }
    
    static var requestHeaders: [String: String]? { get }
    
    static var isGZipEnabled: Bool { get }
    static var timeoutInterval: TimeInterval { get }
    
    /**
     - returns: compressed
     */
    static func compressBodyUsingGZip(_ data: inout Data) -> Bool
    
    
    /**
     * - Parameter data: 原始的 http-body
     * - Parameter mark: 附带的额外信息
     * - Parameter additionalHeaders: 产生的额外的 header
     * - Returns: processed
     */
    static func preprocessRequestBody(_ data: inout Data, mark: [String: Any]?, additionalHeaders: inout [String: String]) -> Bool
    static func preprocessResponseBody(_ data: inout Data, response: URLResponse?) -> Bool
    
    static func willProcessRequest(_ URLString: inout String, headers: inout [String: String], parameters: inout [String: Any]?)
    
    static func willProcessResponse(_ request: URLRequest, totalDuration: TimeInterval, responseData: Any?, error: Error?, urlResponse: HTTPURLResponse?, metrics: URLSessionTaskMetrics?)
    
    static func serverTrustEvaluator(forHost host: String) -> ServerTrustEvaluating?
}
