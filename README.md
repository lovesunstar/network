# Network

[![CI Status](http://img.shields.io/travis/Suen/Network.svg?style=flat)](https://travis-ci.org/Suen/Network)
[![Version](https://img.shields.io/cocoapods/v/Network.svg?style=flat)](http://cocoapods.org/pods/Network)
[![License](https://img.shields.io/cocoapods/l/Network.svg?style=flat)](http://cocoapods.org/pods/Network)
[![Platform](https://img.shields.io/cocoapods/p/Network.svg?style=flat)](http://cocoapods.org/pods/Network)

## Usage

### Making a Request

```swift

import Network

Network.request("https://httpbin.org/get").build()
Network.request("https://httpbin.org/get").query(["foo": "bar"]).build()
Network.request("https://httpbin.org/get").headers(["Custom-Content-Type": "application/json; encrypted=1"]).build()
Network.request("https://httpbin.org/post").post(["foo": "bar"]).encoding(.URLEncodedInURL).build()
Network.request("https://httpbin.org/post").post(["foo": "bar"]).encoding(.JSON).retry(1).build()
Network.request("https://httpbin.org/post").post(["foo": "bar"]).encoding(.JSON).priority(Network.Priority.Low).build()

// Please take a look at Network.swift for more configuration 

```

### Response Handling

```swift

Network.request("https://httpbin.org/get").build()?.responseJSON { request, response, responseValue, error in 

}

let (response, responseData, error) = Network.request("https://httpbin.org/post").query(["foo": "bar"]).post(["encode": "json"]).encoding(.JSON).syncResponseJSON()

```
## Requirements

## Installation

Network is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod "Network"
```

## Author

Suen, lovesunstar@sina.com

## License

Network is available under the MIT license. See the LICENSE file for more info.
