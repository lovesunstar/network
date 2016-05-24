//
//  NetworkTests.swift
//  NetworkTests
//
//  Created by SunJiangting on 16/5/24.
//  Copyright © 2016年 Suen. All rights reserved.
//

import XCTest
@testable import Network

class NetworkHook: NSObject, NetworkClientProtocol {
    
    static var commonParameters: [String: AnyObject]? {
        return ["foo": "bar"]
    }
    
    static var requestHeaders: [String : AnyObject]? {
        return ["User-Agent": "TestNetwork"]
    }
    
    static func compressDataUsingGZip(inout data: NSData) -> Bool {
        return false
    }
    
    static func willProcessRequestWithURL(inout URLString: String, inout headers: [String : AnyObject]) {
        
    }
    static func willProcessResponseWithRequest(request: NSURLRequest, timestamp: NSTimeInterval, duration: NSTimeInterval, responseData: AnyObject?, error: ErrorType?, URLResponse: NSHTTPURLResponse?) {
        
    }
}

class NetworkTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        Network.client = NetworkHook.self
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testCommonParameters() {
        let request = Network.request("http://suenblog.duapp.com").build()
        assert(request?.request?.URLString.containsString("foo=bar") ?? false)
    }
    
    func testGetParameters() {
        let request = Network.request("http://suenblog.duapp.com").get(["abc":"bcd"]).build()
        assert(request?.request?.URLString.containsString("abc=bcd") ?? false)
    }
    
    func testCommonMergeGetParameters() {
        let request = Network.request("http://suenblog.duapp.com").get(["foo":"rab"]).build()
        assert(request?.request?.URLString.containsString("foo=rab") ?? false)
    }
    
    func testUserAgent() {
        let request = Network.request("http://suenblog.duapp.com").build()
        assert(request?.request?.allHTTPHeaderFields?["User-Agent"] == "TestNetwork")
    }
    
    func testHeaders() {
        let request = Network.request("http://suenblog.duapp.com").headers(["Accept-Language": "en"]).build()
        assert(request?.request?.allHTTPHeaderFields?["Accept-Language"] == "en")
    }
    
    func testCustomUserAgent() {
        let request = Network.request("http://suenblog.duapp.com").headers(["User-Agent": "HEHEHE"]).build()
        assert(request?.request?.allHTTPHeaderFields?["User-Agent"] == "HEHEHE")
    }
    
    func testPostJSONEncoding() {
        let parameters = ["foo": "bar"]
        let request = Network.request("http://suenblog.duapp.com").post(parameters).encoding(.JSON).build()
        let JSONData = try? NSJSONSerialization.dataWithJSONObject(parameters as NSDictionary, options: NSJSONWritingOptions())
        assert(request?.request?.allHTTPHeaderFields?["Content-Type"] == "application/json")
        assert(request?.request?.HTTPBody == JSONData)
    }
    
}
