//
//  ViewController.swift
//  Network
//
//  Created by Suen on 05/24/2016.
//  Copyright (c) 2016 Suen. All rights reserved.
//

import UIKit
import Network
import Alamofire

class ViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        print("Begin synchronized request1")
        print(Network(configuration: URLSessionConfiguration.default).request("https://httpbin.org/post").query(["key1": "value1"]).post(["foo": "bar"]).syncResponseJSON())
        print("Begin synchronized request2")
        print(Network.request("https://httpbin.org/post").query(["key2": "value2"]).post(["encode": "json"]).encoding(.json(JSONSerialization.WritingOptions())).syncResponseJSON())
        
        let request = Network.request("https://httpbin.org/get").query(["foo": "bar"]).build()
        
        request?.responseJSON(completionHandler: { (_, urlResponse, jsonData, error) -> Void in
            print("Request3", urlResponse ?? "", jsonData ?? "", error ?? "")
        })
        
        request?.cancel()
        
        Network.request("https://httpbin.org/post").query(["foo": "bar"]).post(["foo_p": "bar_p"]).build()?.responseJSON(completionHandler: { (_, urlResponse, jsonData, error) -> Void in
            print("Request4", urlResponse ?? "", jsonData ?? "", error ?? "")
        })
        
        Network.request("https://httpbin.org/post").query(["foo": "bar"]).post(["foo_p": "bar_p"]).encoding(.json(JSONSerialization.WritingOptions())).build()?.responseJSON(completionHandler: { (_, urlResponse, jsonData, error) -> Void in
            print("Request5", urlResponse ?? "", jsonData ?? "", error ?? "")
        })
        
        Network.request("https://httpbin.org/user-agent").headers(["User-Agent": "(Network 0.1.1; Foo bar)"]).build()?.responseJSON(completionHandler: { (_, urlResponse, jsonData, error) -> Void in
            print(urlResponse ?? "", jsonData ?? "", error ?? "")
        })
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
}

