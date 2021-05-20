//
//  ProxyItem.swift
//  Network
//
//  Created by 江挺孙 on 2021/5/20.
//

import Foundation

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
    
    public static func == (lhs: ProxyItem, rhs: ProxyItem) -> Bool {
        return lhs.host == rhs.host && lhs.port == rhs.port
    }
}

