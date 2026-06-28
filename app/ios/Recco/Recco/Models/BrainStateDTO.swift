import Foundation

/// The single shared reactive state for the whole app. Mirrors `BrainState`
/// from `docs/API_CONTRACTS.md`. Both the camera overlays (Person C) and the
/// Brain graph (Person D) read from this exact object so they stay in sync.
struct BrainStateDTO: Codable, Equatable {
    var activeFilter: FilterCommandDTO
    var highlightedPersonId: String?
    var selectedPersonId: String?
    var visiblePersonIds: [String]
    var dimmedPersonIds: [String]
    var lastTranscript: String?
    var lastMatch: FaceMatchResultDTO?
    var isThinking: Bool
    var updatedAt: Double

    init(
        activeFilter: FilterCommandDTO = .reset,
        highlightedPersonId: String? = nil,
        selectedPersonId: String? = nil,
        visiblePersonIds: [String] = [],
        dimmedPersonIds: [String] = [],
        lastTranscript: String? = nil,
        lastMatch: FaceMatchResultDTO? = nil,
        isThinking: Bool = false,
        updatedAt: Double = Date().timeIntervalSince1970 * 1000
    ) {
        self.activeFilter = activeFilter
        self.highlightedPersonId = highlightedPersonId
        self.selectedPersonId = selectedPersonId
        self.visiblePersonIds = visiblePersonIds
        self.dimmedPersonIds = dimmedPersonIds
        self.lastTranscript = lastTranscript
        self.lastMatch = lastMatch
        self.isThinking = isThinking
        self.updatedAt = updatedAt
    }

    /// Fast membership checks for the views.
    func isVisible(_ personId: String) -> Bool { visiblePersonIds.contains(personId) }
    func isDimmed(_ personId: String) -> Bool { dimmedPersonIds.contains(personId) }

    /// True when a real filter is narrowing the roster (not reset/all-visible).
    var hasActiveFilter: Bool {
        !dimmedPersonIds.isEmpty || !activeFilter.includeTags.isEmpty
    }
}
