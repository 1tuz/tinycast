import Foundation
import Observation

@MainActor
@Observable
final class EventEditorSession {
    enum Field: CaseIterable, Hashable {
        case quickEntry
        case title, start, duration
    }

    var draft: EventDraft
    var quickEntry = ""
    var focusedField: Field = .quickEntry

    init(draft: EventDraft = EventDraft()) {
        self.draft = draft
    }

    func parseQuickEntry() {
        guard var parsed = EventDraft.parse(quickEntry) else { return }
        parsed.durationMinutes = draft.durationMinutes
        draft = parsed
    }

    func advanceFocus(backwards: Bool) {
        let fields = Field.allCases
        let index = fields.firstIndex(of: focusedField) ?? 0
        focusedField = fields[(index + (backwards ? fields.count - 1 : 1)) % fields.count]
    }
}
