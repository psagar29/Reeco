import CoreGraphics
import Foundation

/// Per-track throttle + cache policy enforcing the frozen rules in
/// `docs/API_CONTRACTS.md` ("Camera recognition rules"):
///
///   - Max **one** recognition request per track per **0.8-1.5 s**.
///   - **Cache** a strong match for **>= 10 s** while the track is stable.
///   - **Retry** when the face moves significantly, the track resets, or the
///     last result was not a confident match.
///
/// The clock is injected (`now:` parameters) so the whole policy is pure and
/// deterministically testable without waiting in real time.
final class RecognitionPolicy {

    /// Minimum gap between requests for a single track (seconds). Chosen inside
    /// the contract's 0.8-1.5 s window.
    let minRequestInterval: TimeInterval
    /// How long a strong match is trusted before we re-verify (seconds).
    let cacheTTL: TimeInterval
    /// Normalized center movement that counts as "moved significantly".
    let moveThreshold: CGFloat

    init(minRequestInterval: TimeInterval = 1.0,
         cacheTTL: TimeInterval = 10.0,
         moveThreshold: CGFloat = 0.12) {
        self.minRequestInterval = minRequestInterval
        self.cacheTTL = cacheTTL
        self.moveThreshold = moveThreshold
    }

    /// Mutable per-track bookkeeping.
    private struct TrackState {
        var lastRequestAt: TimeInterval?
        var lastBoxCenter: CGPoint?
        var cachedPersonId: String?
        var cachedScore: Double?
        var cachedAt: TimeInterval?
    }

    private var states: [String: TrackState] = [:]

    /// Decide whether a recognition request should be sent for `trackId` now.
    ///
    /// Sends when ANY of these hold:
    ///   - the track has never been requested, OR
    ///   - the cached strong match has expired (> `cacheTTL`), OR
    ///   - the face moved more than `moveThreshold` since the last request,
    /// AND the minimum request interval has elapsed (rate limit always wins).
    func shouldRequest(trackId: String, boxCenter: CGPoint, now: TimeInterval) -> Bool {
        var s = states[trackId] ?? TrackState()
        defer { states[trackId] = s }

        // Rate limit: never exceed one request per `minRequestInterval`.
        if let last = s.lastRequestAt, now - last < minRequestInterval {
            return false
        }

        let hasFreshCache: Bool = {
            guard s.cachedPersonId != nil, let at = s.cachedAt else { return false }
            return now - at < cacheTTL
        }()

        let movedSignificantly: Bool = {
            guard let prev = s.lastBoxCenter else { return true } // first sighting
            let d = (pow(boxCenter.x - prev.x, 2) + pow(boxCenter.y - prev.y, 2)).squareRoot()
            return d > moveThreshold
        }()

        let send = !hasFreshCache || movedSignificantly
        if send {
            s.lastRequestAt = now
            s.lastBoxCenter = boxCenter
        }
        return send
    }

    /// Record the outcome of a request. Only strong matches populate the cache;
    /// anything else clears it so the track keeps retrying.
    func record(trackId: String, personId: String?, score: Double?, isStrongMatch: Bool, now: TimeInterval) {
        var s = states[trackId] ?? TrackState()
        if isStrongMatch, let personId {
            s.cachedPersonId = personId
            s.cachedScore = score
            s.cachedAt = now
        } else {
            s.cachedPersonId = nil
            s.cachedScore = nil
            s.cachedAt = nil
        }
        states[trackId] = s
    }

    /// The currently cached strong match for a track, if it has not expired.
    func cachedMatch(trackId: String, now: TimeInterval) -> (personId: String, score: Double?)? {
        guard let s = states[trackId],
              let id = s.cachedPersonId,
              let at = s.cachedAt,
              now - at < cacheTTL else { return nil }
        return (id, s.cachedScore)
    }

    /// Forget a track entirely (Vision dropped it). Frees its cache + timing.
    func forget(trackId: String) {
        states[trackId] = nil
    }

    /// Track ids the policy is currently aware of (for debug HUD / pruning).
    var knownTrackIds: [String] { Array(states.keys) }
}
