//
//  HTTPBuilder.swift
//  Alamofire
//
//  Created by 孙江挺 on 2018/6/6.
//

import Foundation
import Alamofire

class HTTPServerTrustManager: ServerTrustManager {
    
    init() {
        super.init(allHostsMustBeEvaluated: true, evaluators: [:])
    }

    override func serverTrustEvaluator(forHost host: String) throws -> ServerTrustEvaluating? {
        guard let c = Requests.Session.client else {
            return nil
        }
        return c.serverTrustEvaluator(forHost: host)
    }
}

