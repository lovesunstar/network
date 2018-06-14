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

typealias AFManager = Alamofire.SessionManager
typealias AFMethod = Alamofire.HTTPMethod
typealias AFRequest = Alamofire.Request

public protocol NetworkClientProtocol: NSObjectProtocol {
    
    static var commonParameters: [String: Any]? { get }
    static var requestHeaders: [String: String]? { get }
    
    /**
     - returns: compressed
     */
    static func compressDataUsingGZip(_ data: inout Data) -> Bool
    
    static func willProcessRequest(_ URLString: inout String, headers: inout [String: String], parameters: inout [String: Any]?)
    
    static func willProcessResponse(_ request: URLRequest, totalDuration: TimeInterval, responseData: Any?, error: Error?, urlResponse: HTTPURLResponse?, timeline: Alamofire.Timeline)
}

public class Network {
    
    public enum Priority: Float {
        case background = 0
        case low = 0.25
        case `default` = 0.5
        case high = 0.75
    }
    
    public static func request(_ url: String) -> RequestBuilder {
        return shared.request(url)
    }
    
    public static func upload(_ url: String) -> UploadBuilder {
        return shared.upload(url)
    }
    
    public static let shared = Network(configuration: AFManager.default.session.configuration)
    
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
            manager = AFManager(configuration: configuration)
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
                    let sessionConfiguration = AFManager.default.session.configuration
                    sessionConfiguration.connectionProxyDictionary = proxyConfiguration
                    manager = AFManager(configuration: sessionConfiguration)
                }
            } else {
                manager = AFManager.default
            }
        }
    }
    
    internal var manager: AFManager
    
    public init(configuration: URLSessionConfiguration) {
        manager = AFManager(configuration: configuration)
        self.configuration = configuration
    }
    
    public func request(_ url: String) -> RequestBuilder {
        return Network.RequestBuilder(url: url, manager: manager)
    }
    
    public func upload(_ url: String) -> UploadBuilder {
        return Network.UploadBuilder(url: url, manager: manager)
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
        
        public var hashValue: Int {
            return host.hashValue ^ port.hashValue
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

