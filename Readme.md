# RateLimiter

A Swift package providing rate limiting capabilities, suitable for various server-side applications. Includes integration middleware for the Hummingbird framework.

## Basic Usage (Core Library)

Import `RateLimiter` and create an instance of `PublicApiRateLimiter`. You'll typically need a `Logger` instance.

```swift
import RateLimiter
import Logging // You'll need swift-log

// Assuming you have a logger configured
let logger = Logger(label: "com.example.MyApp.RateLimiter")

// Create the rate limiter (it's an actor)
let rateLimiter = PublicApiRateLimiter(logger: logger)

// Somewhere in your request handling logic:
let clientIP = "192.168.1.100" // Get the client IP address

do {
    try await rateLimiter.check(ipAddress: clientIP)
    // Request allowed, proceed with handling
    print("Request from \(clientIP) allowed.")
} catch RateLimitingError.tooManyRequests {
    // Request denied due to rate limiting
    print("Rate limit exceeded for \(clientIP).")
    // Return an appropriate error response (e.g., HTTP 429 Too Many Requests)
} catch {
    // Handle other potential errors
    print("An unexpected error occurred: \(error)")
}

```

The `PublicApiRateLimiter` uses an in-memory store (a dictionary) and limits requests to 15 per second per IP address by default, which can be configured in the initialization. It automatically cleans up stale entries.

## Usage with Hummingbird

First, ensure your `RequestContext` conforms to `IPRequestContext`. This protocol requires you to provide a way to access the client's remote IP address.

```swift
import Hummingbird
import RateLimiterHummingbird // Import the Hummingbird integration
import Logging
import NIOCore            // For SocketAddress

// Example Request Context
struct AppRequestContext: IPRequestContext {
    var coreContext: CoreRequestContextStorage
    // Required by Hummingbird.RemoteAddressRequestContext
    var remoteAddress: SocketAddress? { coreContext.channel.remoteAddress }
    // Required by IPRequestContext: Provide a way to get the remote address
    var xForwardedFor: String?

    init(channel: Channel, logger: Logger) {
        self.coreContext = .init(channel: channel, logger: logger)
        self.xForwardedFor = nil // Or parse from headers if applicable
    }
}
```

Then, add the `InMemoryRateLimitMiddleware` to your Hummingbird application router.

```swift
let logger = Logger(label: "my-hummingbird-app")
let router = Router(context: AppRequestContext.self)

// Add the rate limiting middleware
router.add(middleware: InMemoryRateLimitMiddleware(
    logger: logger,
    configuration: .init(
        limitPerSecond: 10,
        cleanupInterval: 60.0,
        entryTTL: 300.0
    )
))

// ... add your routes ...

let app = Application(
    router: router,
    context: AppRequestContext.init,
    logger: logger
)
try await app.runService()

```

The `InMemoryRateLimitMiddleware` uses the `PublicApiRateLimiter` internally and automatically checks first the `X-Forwarded-For` header, if nil then `remoteAddress` from your `IPRequestContext`. If the limit is exceeded, it throws an `HTTPError(.tooManyRequests)`.

## Installation

Add the `RateLimiter` package to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/your-username/RateLimiter.git", from: "0.0.1")
]
```

And add `RateLimiter` to your target's dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "RateLimiter", package: "RateLimiter"),
        // ... other dependencies
    ]
),
```

If you are using the Hummingbird integration, also add `RateLimiterHummingbird`:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "RateLimiterHummingbird", package: "RateLimiter"),
        .product(name: "Hummingbird", package: "hummingbird"),
        // ... other dependencies
    ]
),
```