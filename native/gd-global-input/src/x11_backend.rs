//! X11 backend for global keyboard state.
//!
//! `QueryKeymap` returns the whole 256-bit physical-key bitmap for the server, not
//! just keys routed to our window, which is what makes hotkeys work while the app
//! is unfocused.
//!
//! Wayland caveat: under XWayland this reports the X server's view, so keys sent to
//! native Wayland clients are not visible. There is no portable global-key API on
//! Wayland by design; an evdev backend would be the fix, but it needs the user in
//! the `input` group, so it is deliberately not the default.

use std::collections::HashMap;

use x11rb::connection::Connection;
use x11rb::protocol::xproto::{ConnectionExt, Keycode};
use x11rb::rust_connection::RustConnection;

use crate::keymap;

pub struct X11Backend {
    conn: RustConnection,
    /// keysym -> every physical keycode that can produce it
    keycodes_by_keysym: HashMap<u32, Vec<Keycode>>,
}

impl X11Backend {
    /// Returns `None` when there is no reachable X display, which is the normal
    /// case for headless runs and pure-Wayland sessions.
    pub fn connect() -> Option<Self> {
        let (conn, _screen) = x11rb::connect(None).ok()?;
        let mut backend = Self {
            conn,
            keycodes_by_keysym: HashMap::new(),
        };
        backend.reload_mapping().ok()?;
        Some(backend)
    }

    /// Builds the keysym -> keycode index. Called at startup and whenever the
    /// layout changes, since keycodes are layout dependent.
    pub fn reload_mapping(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        let setup = self.conn.setup();
        let min: u8 = setup.min_keycode;
        let max: u8 = setup.max_keycode;
        let count = max - min + 1;

        let mapping = self
            .conn
            .get_keyboard_mapping(min, count)?
            .reply()?;

        let per_code = mapping.keysyms_per_keycode as usize;
        let mut index: HashMap<u32, Vec<Keycode>> = HashMap::new();

        for (i, chunk) in mapping.keysyms.chunks(per_code).enumerate() {
            let keycode = min + i as u8;
            for sym in chunk {
                if *sym == 0 {
                    continue;
                }
                index.entry(*sym).or_default().push(keycode);
            }
        }

        self.keycodes_by_keysym = index;
        Ok(())
    }

    /// True when any physical key producing this Godot keycode is currently held.
    pub fn is_key_pressed(&self, godot_keycode: u32) -> bool {
        let keysyms = keymap::keysyms_for(godot_keycode);
        if keysyms.is_empty() {
            return false;
        }

        let Ok(cookie) = self.conn.query_keymap() else {
            return false;
        };
        let Ok(reply) = cookie.reply() else {
            return false;
        };
        let bitmap = reply.keys;

        for sym in keysyms {
            let Some(codes) = self.keycodes_by_keysym.get(&sym) else {
                continue;
            };
            for code in codes {
                let idx = (*code as usize) / 8;
                let bit = (*code as usize) % 8;
                if idx < bitmap.len() && (bitmap[idx] >> bit) & 1 == 1 {
                    return true;
                }
            }
        }
        false
    }
}
