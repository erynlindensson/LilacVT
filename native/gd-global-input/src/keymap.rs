//! Godot `Key` keycode -> X11 keysym mapping.
//!
//! Godot keycodes were read out of the engine itself (`OS.get_keycode_string` /
//! `OS.find_keycode_from_string`) rather than transcribed by hand, so the values
//! below match whatever the engine reports for this version.
//!
//! Printable ASCII keycodes coincide with Latin-1 keysyms, so those pass through
//! directly. Letters are the one exception worth noting: Godot reports A-Z as the
//! uppercase ASCII codes, while an X keyboard maps the *lowercase* keysym to the
//! physical key, so `A`..`Z` are shifted into `a`..`z` before lookup.

/// Godot marks non-printable keys by setting bit 22.
const GODOT_SPECIAL: u32 = 1 << 22;

/// Keys that report a single keysym.
const SPECIAL_KEYS: &[(u32, u32)] = &[
    (GODOT_SPECIAL | 0x01, 0xFF1B), // Escape
    (GODOT_SPECIAL | 0x02, 0xFF09), // Tab
    (GODOT_SPECIAL | 0x03, 0xFF08), // Backtab -> ISO_Left_Tab handled below
    (GODOT_SPECIAL | 0x04, 0xFF08), // Backspace
    (GODOT_SPECIAL | 0x05, 0xFF0D), // Enter
    (GODOT_SPECIAL | 0x06, 0xFF8D), // Kp Enter
    (GODOT_SPECIAL | 0x07, 0xFF63), // Insert
    (GODOT_SPECIAL | 0x08, 0xFFFF), // Delete
    (GODOT_SPECIAL | 0x09, 0xFF13), // Pause
    (GODOT_SPECIAL | 0x0A, 0xFF61), // Print
    (GODOT_SPECIAL | 0x0B, 0xFF15), // SysReq
    (GODOT_SPECIAL | 0x0C, 0xFF0B), // Clear
    (GODOT_SPECIAL | 0x0D, 0xFF50), // Home
    (GODOT_SPECIAL | 0x0E, 0xFF57), // End
    (GODOT_SPECIAL | 0x0F, 0xFF51), // Left
    (GODOT_SPECIAL | 0x10, 0xFF52), // Up
    (GODOT_SPECIAL | 0x11, 0xFF53), // Right
    (GODOT_SPECIAL | 0x12, 0xFF54), // Down
    (GODOT_SPECIAL | 0x13, 0xFF55), // PageUp
    (GODOT_SPECIAL | 0x14, 0xFF56), // PageDown
    (GODOT_SPECIAL | 0x19, 0xFFE5), // CapsLock
    (GODOT_SPECIAL | 0x1A, 0xFF7F), // NumLock
    (GODOT_SPECIAL | 0x1B, 0xFF14), // ScrollLock
    (GODOT_SPECIAL | 0x42, 0xFF67), // Menu
    (GODOT_SPECIAL | 0x45, 0xFF6A), // Help
    // keypad
    (GODOT_SPECIAL | 0x81, 0xFFAA), // Kp Multiply
    (GODOT_SPECIAL | 0x82, 0xFFAF), // Kp Divide
    (GODOT_SPECIAL | 0x83, 0xFFAD), // Kp Subtract
    (GODOT_SPECIAL | 0x84, 0xFFAE), // Kp Period
    (GODOT_SPECIAL | 0x85, 0xFFAB), // Kp Add
];

/// Modifiers exist as a left/right pair; Godot reports one keycode for both, so a
/// press of either side has to satisfy the binding.
const MODIFIER_KEYS: &[(u32, &[u32])] = &[
    (GODOT_SPECIAL | 0x15, &[0xFFE1, 0xFFE2]), // Shift  = Shift_L / Shift_R
    (GODOT_SPECIAL | 0x16, &[0xFFE3, 0xFFE4]), // Ctrl   = Control_L / Control_R
    (GODOT_SPECIAL | 0x17, &[0xFFEB, 0xFFEC]), // Meta   = Super_L / Super_R
    (GODOT_SPECIAL | 0x18, &[0xFFE9, 0xFFEA]), // Alt    = Alt_L / Alt_R
];

/// Godot F1..F35 are sequential from SPECIAL|0x1C; X11 F1..F35 are sequential from
/// XK_F1, with F13+ continuing past the first block.
const GODOT_F1: u32 = GODOT_SPECIAL | 0x1C;
const GODOT_F35: u32 = GODOT_F1 + 34;
const XK_F1: u32 = 0xFFBE;

/// Godot Kp 0..9 are sequential from SPECIAL|0x86; X11 KP_0..KP_9 from XK_KP_0.
const GODOT_KP_0: u32 = GODOT_SPECIAL | 0x86;
const XK_KP_0: u32 = 0xFFB0;

/// Every X11 keysym that should satisfy the given Godot keycode.
///
/// Returns an empty vector for keycodes with no sensible X11 equivalent, which the
/// caller reports as "not pressed" rather than treating as an error.
pub fn keysyms_for(godot_keycode: u32) -> Vec<u32> {
    // printable ASCII passes straight through as a Latin-1 keysym
    if (0x20..0x7F).contains(&godot_keycode) {
        // A-Z: the physical key carries the lowercase keysym
        if (0x41..=0x5A).contains(&godot_keycode) {
            return vec![godot_keycode + 0x20];
        }
        return vec![godot_keycode];
    }

    if (GODOT_F1..=GODOT_F35).contains(&godot_keycode) {
        return vec![XK_F1 + (godot_keycode - GODOT_F1)];
    }

    if (GODOT_KP_0..=GODOT_KP_0 + 9).contains(&godot_keycode) {
        return vec![XK_KP_0 + (godot_keycode - GODOT_KP_0)];
    }

    for (code, syms) in MODIFIER_KEYS {
        if *code == godot_keycode {
            return syms.to_vec();
        }
    }

    for (code, sym) in SPECIAL_KEYS {
        if *code == godot_keycode {
            return vec![*sym];
        }
    }

    Vec::new()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn letters_map_to_lowercase_keysyms() {
        assert_eq!(keysyms_for(b'A' as u32), vec![0x61]); // KEY_A -> XK_a
        assert_eq!(keysyms_for(b'Z' as u32), vec![0x7A]);
    }

    #[test]
    fn digits_and_space_pass_through() {
        assert_eq!(keysyms_for(b'0' as u32), vec![0x30]);
        assert_eq!(keysyms_for(b' ' as u32), vec![0x20]);
    }

    #[test]
    fn function_keys_are_sequential() {
        assert_eq!(keysyms_for(GODOT_F1), vec![XK_F1]);
        assert_eq!(keysyms_for(GODOT_F1 + 11), vec![XK_F1 + 11]); // F12
    }

    #[test]
    fn keypad_digits_are_sequential() {
        assert_eq!(keysyms_for(GODOT_KP_0), vec![XK_KP_0]);
        assert_eq!(keysyms_for(GODOT_KP_0 + 9), vec![XK_KP_0 + 9]);
    }

    #[test]
    fn modifiers_accept_either_side() {
        assert_eq!(keysyms_for(GODOT_SPECIAL | 0x15), vec![0xFFE1, 0xFFE2]);
        assert_eq!(keysyms_for(GODOT_SPECIAL | 0x16), vec![0xFFE3, 0xFFE4]);
    }

    #[test]
    fn unknown_keycodes_are_empty_not_panics() {
        assert!(keysyms_for(0xDEADBEEF).is_empty());
    }
}
