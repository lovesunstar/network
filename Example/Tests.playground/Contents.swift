//: Playground - noun: a place where people can play

import UIKit
import Network



Network.request("http://127.0.0.1:8000/api/v1/feed?status=404").post(["foo": "bar"]).method(.post).encoding(.json(JSONSerialization.WritingOptions(rawValue: 0))).build()?.responseJSON(completionHandler: { (_, _, data, error) in
    print(data as Any)
    print("----")
    print(error as Any)
})