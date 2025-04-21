import Hummingbird
import HTTPTypes
import Logging
import RateLimiter

public protocol IPRequestContext: RemoteAddressRequestContext {
    var xForwardedFor: String? { get set }
}

public struct InMemoryRateLimitMiddleware<Context: IPRequestContext>: RouterMiddleware {

    let logger: Logger
    let rateLimiter: PublicApiRateLimiter

    public init(logger: Logger, configuration: PublicApiRateLimiter.Configuration = PublicApiRateLimiter.Configuration()) {
        self.logger = logger
        self.rateLimiter = PublicApiRateLimiter(logger: logger, configuration: configuration)
    }

    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        var context = context
        var ipAddress: String?

        // Try to get IP from X-Forwarded-For header
        if let httpFieldName = HTTPField.Name("X-Forwarded-For"),
            let xForwardedFor = request.headers[httpFieldName]
        {
            context.xForwardedFor = xForwardedFor
            ipAddress = xForwardedFor
        }

        // Fall back to remoteAddress if X-Forwarded-For is nil
        if ipAddress == nil,
            let ip = context.remoteAddress,
            let remoteIp = ip.ipAddress
        {
            ipAddress = remoteIp
        }

        // Throw error if we couldn't determine the IP address
        guard let ipToCheck = ipAddress else {
            throw RateLimitingError.missingIpAddress
        }

        do {
            try await rateLimiter.check(ipAddress: ipToCheck)
        } catch RateLimitingError.tooManyRequests {
            throw HTTPError(.tooManyRequests)
        } catch RateLimitingError.missingIpAddress {
            throw HTTPError(.badRequest)
        }

        return try await next(request, context)
    }
}
