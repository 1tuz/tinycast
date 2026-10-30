import Carbon.HIToolbox
import Foundation

extension HotKeyAction {
    /// Fresh installs start with the user's established shortcut layout. Existing bindings win.
    static let defaultBindings: [HotKeyAction: HotKeyBinding] = {
        let hyper = controlKey | optionKey | shiftKey | cmdKey
        func combo(_ keyCode: Int, _ modifiers: Int) -> HotKeyBinding {
            .combo(KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: modifiers))
        }
        var bindings: [HotKeyAction: HotKeyBinding] = [
            .togglePalette: combo(49, cmdKey)
        ]
        let commandBindings: [(String, Int, Int)] = [
            ("command:ai-chat", 34, hyper),
            ("command:clipboard-history", 8, controlKey | shiftKey),
            ("command:create-note", 45, hyper),
            ("command:settings", 44, hyper),
        ]
        for (rawID, keyCode, modifiers) in commandBindings {
            if let id = CommandID(rawValue: rawID) {
                bindings[.command(id)] = combo(keyCode, modifiers)
            }
        }
        let windowBindings: [(String, Int)] = [
            ("almost-maximize", 126), ("bottom-half", 7),
            ("bottom-left-quarter", 6), ("bottom-right-quarter", 8),
            ("center", 49), ("center-half", 23), ("center-third", 19),
            ("first-third", 18), ("first-three-fourths", 33), ("first-two-thirds", 21),
            ("last-third", 20), ("last-three-fourths", 30), ("last-two-thirds", 22),
            ("left-half", 0), ("make-larger", 24), ("make-smaller", 27),
            ("maximize", 1), ("next-display", 124), ("previous-display", 123),
            ("reasonable-size", 15), ("restore", 125), ("right-half", 2),
            ("toggle-fullscreen", 3), ("top-half", 13),
            ("top-left-quarter", 12), ("top-right-quarter", 14),
        ]
        for (rawID, keyCode) in windowBindings {
            if let id = WindowCommand.ID(rawValue: rawID) {
                bindings[.windowCommand(id: id)] = combo(keyCode, hyper)
            }
        }
        assert(Set(bindings.values).count == bindings.count, "Default hotkeys must not conflict")
        return bindings
    }()
}
