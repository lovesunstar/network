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


public func request(_ url: String) -> NormalBuilder {
    let builder = Requests.Session.shared.request(url)
    return builder
}

public func upload(_ url: String) -> UploadBuilder {
    let builder = Requests.Session.shared.upload(url)
    return builder
}

public class Session {
    
    public enum Priority: Float {
        case background = 0
        case low = 0.25
        case `default` = 0.5
        case high = 0.75
    }
    
    public static let shared = Session(configuration: AFSession.default.session.configuration)
    
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
    
    static let trustManager = HTTPServerTrustManager()
    
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
            afSession = AFSession(configuration: configuration, serverTrustManager: Session.trustManager)
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
                    afSession = AFSession(configuration: sessionConfiguration, serverTrustManager: Session.trustManager)
                }
            } else {
                afSession = AFSession(configuration: AFSession.default.session.configuration, serverTrustManager: Session.trustManager)
            }
        }
    }
    
    internal var afSession: AFSession
    
    public init(configuration: URLSessionConfiguration) {
        afSession = AFSession(configuration: configuration, serverTrustManager: Session.trustManager)
        self.configuration = configuration
    }
    
    public func reset() {
        afSession = AFSession(configuration: configuration, serverTrustManager: Session.trustManager)
    }
    
    public func request(_ url: String) -> NormalBuilder {
        let builder = NormalBuilder(url: url, session: self)
        builder.querySorter = self.client?.commonParametersSorter
        return builder
    }
    
    public func upload(_ url: String) -> UploadBuilder {
        let builder = UploadBuilder(url: url, session: self)
        builder.querySorter = self.client?.commonParametersSorter
        return builder
    }
    
}

public enum ParameterEncoding {
    
    case url, json, jsonPrettyPrinted
    
    func asAFParameterEncoding() -> Alamofire.ParameterEncoding {
        switch self {
        case .url:
            return Alamofire.URLEncoding(destination: .httpBody)
        case .json:
            return Alamofire.JSONEncoding(options: JSONSerialization.WritingOptions(rawValue: 0))
        case .jsonPrettyPrinted:
            return Alamofire.JSONEncoding(options: JSONSerialization.WritingOptions.prettyPrinted)
        }
    }
}
