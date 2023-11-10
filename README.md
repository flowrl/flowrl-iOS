# flowrl-iOS

This is a flowRL implementation for Swift. It has support for automatic configuration parsing, logging and sending events, caching, and more.

## Requirements

- iOS 13.0

## Installation
Available as a Swift Package via Swift Package Manager at
```html
https://github.com/flowrl/flowrl-iOS/
```

## Usage

### Initialization

After installing, you need to import the module
```swift
import FlowRL
```

Then, you need to configure the SDK with your API Key and the user id at the earliest possible stage. Depending on your implementation, it might be the `application(_:didFinishLaunchingWithOptions:)` method of the `AppDelegate`, or the `.onAppear` of the main view.

```swift
.onAppear {
    FlowRL.instance.configure(userId: "current-user-id", apiKey: "your-api-key")
}
```

### Configuring Personalization

To enable personalization, you need to place your views in flowRL provided containers, and assign each of them an identifier to match the one set up previously in the admin panel.

```swift
PickVariant("test-id", defaultVariant: "variant-1") {
    Variant("variant-1") {
        Variant1View()
    }
    Variant("variant-2") {
        Variant2View()
    }
    Variant("variant-3) {
        Variant3View()
    }
}
```

Then, depending on the configuration received from server, one of the variants will be presented to the user. In cases of network interruptions/misconfiguration issues, flowRL falls back to the default variant that you specify in the PickVariant wrapper. flowRL also has built-in caching, so your users shouldn't expect the UI to change on a whim once the network connection is lost.

### Sending Events

For flowRL models to start training and serving optimized UI configuration to users, you need to supply event data. In order to do that with the SDK, you use the following method:
```swift
Button("Purchase") {
    FlowRL.instance.logEvent(actionName: "purchase", categoryName: "conversion-events", screenName: "product-page")
}
```

Generally, you should log events in the same places that you do in your other analytics software. The more meaningful interaction data you provide, the more accurate will our models' predictions be.
