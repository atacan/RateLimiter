
### Usage with Hummingbird

Conform your request context to IPRequestContext

```swift
struct AppRequestContext: IPRequestContext {
    var coreContext: CoreRequestContextStorage
    let channel: any Channel
    var xForwardedFor: String?

    init(source: Source) {
        self.coreContext = .init(source: source)
        self.channel = source.channel
        self.xForwardedFor = nil
    }

    /// Extract Remote IP from Channel
    var remoteAddress: SocketAddress? { self.channel.remoteAddress }
}
```

Then 

```swift
let logger = Logger(label: "my-server")
let router = Router(context: AppRequestContext.self)
router.add(middleware: InMemoryRateLimitMiddleware(logger: logger))
```