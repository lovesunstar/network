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

typealias AFSession = Alamofire.Session
typealias AFMethod = Alamofire.HTTPMethod
typealias AFRequest = Alamofire.Request

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
}


public class Network {
    
    public enum Priority: Float {
        case background = 0
        case low = 0.25
        case `default` = 0.5
        case high = 0.75
    }
    
    
    public static func request(_ url: String) -> RequestBuilder {
        let builder = shared.request(url)
        return builder
    }
    
    public static func upload(_ url: String) -> UploadBuilder {
        let builder = shared.upload(url)
        return builder
    }
    
    public static let shared = Network(configuration: AFSession.default.session.configuration)
    
    public static var client: NetworkClientProtocol.Type? {
        get {
            return shared.client
        }
        set {
            shared.client = newValue
        }
    }
    
    public static var configuration: URLSessionConfiguration {
        get {
            return shared.configuration
        }
        set {
            shared.configuration = newValue
        }
    }
    
    public static var proxyItem: ProxyItem? {
        get {
            return shared.proxyItem
        }
        set {
            shared.proxyItem = newValue
        }
    }
    
    public static var serverTrustManager: ServerTrustManager? {
        didSet {
            shared.reset()
        }
    }
    
    public var client: NetworkClientProtocol.Type? = nil
    
    public var configuration: URLSessionConfiguration = URLSessionConfiguration.default {
        didSet {
            if let item = proxyItem {
                let port = Int(item.port) ?? 8888
                var proxyConfiguration = [AnyHashable: Any]()
                proxyConfiguration[kCFNetworkProxiesHTTPProxy as AnyHashable] = item.host
                proxyConfiguration[kCFNetworkProxiesHTTPPort as AnyHashable] = port
                proxyConfiguration[kCFNetworkProxiesHTTPEnable as AnyHashable] = 1
                configuration.connectionProxyDictionary = proxyConfiguration
            }
            afSession = AFSession(configuration: configuration, serverTrustManager: Network.serverTrustManager)
        }
    }
    
    public var proxyItem: ProxyItem? {
        didSet {
            if let item = proxyItem {
                if proxyItem != oldValue {
                    let port = Int(item.port) ?? 8888
                    var proxyConfiguration = [AnyHashable: Any]()
                    proxyConfiguration[kCFNetworkProxiesHTTPProxy as AnyHashable] = item.host
                    proxyConfiguration[kCFNetworkProxiesHTTPPort as AnyHashable] = port
                    proxyConfiguration[kCFNetworkProxiesHTTPEnable as AnyHashable] = 1
                    let sessionConfiguration = AFSession.default.session.configuration
                    sessionConfiguration.connectionProxyDictionary = proxyConfiguration
                    afSession = AFSession(configuration: sessionConfiguration, serverTrustManager: Network.serverTrustManager)
                }
            } else {
                afSession = AFSession(configuration: AFSession.default.session.configuration, serverTrustManager: Network.serverTrustManager)
            }
        }
    }
    
    internal var afSession: AFSession
    
    public init(configuration: URLSessionConfiguration) {
        afSession = AFSession(configuration: configuration, serverTrustManager: Network.serverTrustManager)
        self.configuration = configuration
    }
    
    public func reset() {
        afSession = AFSession(configuration: configuration, serverTrustManager: Network.serverTrustManager)
    }
    
    public func request(_ url: String) -> RequestBuilder {
        let builder = Network.RequestBuilder(url: url, session: afSession, network: self)
        builder.querySorter = self.client?.commonParametersSorter
        return builder
    }
    
    public func upload(_ url: String) -> UploadBuilder {
        let builder = Network.UploadBuilder(url: url, session: afSession, network: self)
        builder.querySorter = self.client?.commonParametersSorter
        return builder
    }
    
}

extension Network {
    
    public struct ProxyItem: Equatable, Hashable {
        let host: String
        let port: String
        let httpOnly: Bool
        
        public init(host: String, port: String, httpOnly: Bool = true) {
            self.host = host
            self.port = port
            self.httpOnly = httpOnly
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(host.hashValue)
            hasher.combine(port.hashValue)
        }
        
        public static func == (lhs: Network.ProxyItem, rhs: Network.ProxyItem) -> Bool {
            return lhs.host == rhs.host && lhs.port == rhs.port
        }
    }
    
}

extension Network {
    
    public enum ParameterEncoding {
        case url, json(JSONSerialization.WritingOptions)
        
        func asAFParameterEncoding() -> Alamofire.ParameterEncoding {
            switch self {
            case .url:
                return Alamofire.URLEncoding(destination: .httpBody)
            case .json(let options):
                return Alamofire.JSONEncoding(options: options)
            }
        }
    }
}

func +=<KeyType, ValueType>(lhs: inout Dictionary<KeyType, ValueType>, rhs: Dictionary<KeyType, ValueType>?) {
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

func -=<KeyType, ValueType>(lhs: inout Dictionary<KeyType, ValueType>, rhs: Dictionary<KeyType, ValueType>?) {
    if let rhs = rhs {
        for (k, _) in rhs {
            lhs.removeValue(forKey: k)
        }
    }
}

func -<KeyType, ValueType>(lhs: [KeyType : ValueType], rhs: [KeyType : ValueType]?) -> [KeyType : ValueType] {
    var results = lhs
    if let rhs = rhs {
        for (k, _) in rhs {
            results.removeValue(forKey: k)
        }
    }
    return results
}

