import Foundation
import Logging

public actor PublicApiRateLimiter {
    private let limitPerSecond = 15
    private var memory: [String: [TimeInterval]] = [:]

    // Make config properties nonisolated constants if they don't change
    // This allows access from the detached task without awaiting the actor.
    private nonisolated let cleanupInterval: TimeInterval = 60.0  // Clean up every 60 seconds
    private nonisolated let entryTTL: TimeInterval = 300.0  // Remove IPs inactive for 5 minutes

    // Task handle - now initialized lazily
    private var cleanupTask: Task<Void, Never>?
    // Flag to ensure task is only started once
    private var isCleanupTaskStarted = false

    let logger: Logger

    public init(logger: Logger) {
        self.logger = logger
    }

    deinit {
        logger.debug("Rate limiter deinit - cancelling cleanup task.")
        cleanupTask?.cancel()
    }

    // Function to start the task, called internally
    private func startCleanupTaskIfNeeded() {
        // Use the flag to ensure it only runs once
        guard !isCleanupTaskStarted else { return }
        isCleanupTaskStarted = true

        logger.info(
            "Starting rate limiter cleanup task.",
            metadata: [
                "interval": .stringConvertible(cleanupInterval),
                "ttl": .stringConvertible(entryTTL),
            ]
        )

        // Create the detached task here, *after* init has completed.
        // Accessing self properties (like logger, performCleanup) is now safe.
        cleanupTask = Task.detached { [weak self] in
            // Need to capture constants explicitly if self becomes nil
            let interval = self?.cleanupInterval ?? 60.0
            guard let self else {
                self?.logger.error("Rate limiter instance deallocated before cleanup task could run.")
                return
            }

            while !Task.isCancelled {
                do {
                    // Use the captured interval constant
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    // Handle potential Task.sleep errors (like cancellation)
                    logger.error("Cleanup task sleep interrupted. \(error)")
                    break  // Exit loop if sleep fails significantly
                }

                // Check cancellation *before* performing work
                if Task.isCancelled {
                    logger.info("Cleanup task cancelled.")
                    break
                }

                // Call the isolated cleanup function
                await self.performCleanup()
            }
            logger.info("Rate limiter cleanup task finished.")
        }
    }

    public func check(ipAddress: String) throws {
        // Start the cleanup task on the first check
        startCleanupTaskIfNeeded()

        var memoryForKey = memory[ipAddress] ?? []
        let now = Date.now.timeIntervalSince1970

        // 1. Filter out timestamps older than 1 second
        memoryForKey = memoryForKey.filter { now - $0 <= 1.0 }

        // 2. Check limit (use >= for clarity)
        if memoryForKey.count >= limitPerSecond {
            // Append and store to keep the entry "active" for TTL cleanup
            memoryForKey.append(now)
            memory[ipAddress] = memoryForKey  // Update memory even on rejection
            logger.warning("Rate limit exceeded", metadata: ["ip": .string(ipAddress), "count": .stringConvertible(memoryForKey.count)])
            throw RateLimitingError.tooManyRequests(ip: ipAddress)
        }

        // 3. Add current request timestamp
        memoryForKey.append(now)
        memory[ipAddress] = memoryForKey  // Store the updated array back
        logger.trace("Request permitted", metadata: ["ip": .string(ipAddress), "count": .stringConvertible(memoryForKey.count)])
    }

    // This method is implicitly isolated to the actor
    private func performCleanup() {
        let now = Date.now.timeIntervalSince1970
        var removedCount = 0
        let initialCount = memory.count

        // Use the nonisolated entryTTL constant directly
        memory = memory.filter { ip, timestamps in
            guard let lastTimestamp = timestamps.last else {
                // Remove entries with empty timestamp arrays if they somehow occur
                removedCount += 1
                return false
            }
            // Check if the *last* seen time is older than the TTL
            let shouldKeep = (now - lastTimestamp) <= entryTTL
            if !shouldKeep {
                removedCount += 1
            }
            return shouldKeep
        }

        if removedCount > 0 {
            logger.debug(
                "Rate limiter cleanup finished.",
                metadata: [
                    "removed": .stringConvertible(removedCount),
                    "remaining": .stringConvertible(memory.count),
                    "initial": .stringConvertible(initialCount),
                ]
            )
        } else if initialCount > 0 {
            logger.trace(
                "Rate limiter cleanup finished. No inactive entries found.",
                metadata: [
                    "remaining": .stringConvertible(memory.count)
                ]
            )
        }
        // No log if initialCount was 0 and removedCount was 0 (nothing to do)
    }
}

public enum RateLimitingError: Error {
    case tooManyRequests(ip: String)
    case missingIpAddress
}