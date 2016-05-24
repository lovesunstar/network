# Network

[![CI Status](http://img.shields.io/travis/Suen/Network.svg?style=flat)](https://travis-ci.org/Suen/Network)
[![Version](https://img.shields.io/cocoapods/v/Network.svg?style=flat)](http://cocoapods.org/pods/Network)
[![License](https://img.shields.io/cocoapods/l/Network.svg?style=flat)](http://cocoapods.org/pods/Network)
[![Platform](https://img.shields.io/cocoapods/p/Network.svg?style=flat)](http://cocoapods.org/pods/Network)

## Usage

### Making a Request

```swift
import Network

Network.request("http://httpbin.org/get").build()
Network.request("http://httpbin.org/get").method(.POST).build()
Network.request("http://httpbin.org/get").get(["foo": "bar"]).build()
Network.request("http://httpbin.org/post").post(["foo": "bar"]).encoding(.JSON).build()
Network.request("http://httpbin.org/post").post(["foo": "bar"]).encoding(.JSON).retry(1).build()
Network.request("http://httpbin.org/post").post(["foo": "bar"]).encoding(.JSON).retry(1).priority(Network.Priority.Low).build()

// Please take a look at Network.swift for more configuration 
```

### Response Handling

```swift

Network.request("http://httpbin.org/get").build().nt_responseJSON { request, response, responseValue, error in 

}

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
