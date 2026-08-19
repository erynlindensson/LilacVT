//! Global (unfocused) keyboard state for Godot.
//!
//! Exposes a `GlobalInputServer` node with `is_key_pressed(keycode) -> bool`,
//! taking a Godot `Key` value. Godot's own `Input.is_key_pressed` only reports keys
//! while the window has focus; VTuber hotkeys have to fire while the user is in
//! another application, which is the entire reason this extension exists.
//!
//! The class is `GlobalInputServer`, not `GlobalInput`: the autoload is registered
//! under `GlobalInput`, and GDScript resolves a bare identifier to a ClassDB class
//! before an autoload singleton. Sharing the name makes `GlobalInput.is_key_pressed()`
//! parse as a static call on the class and fail.
//!
//! Scope is deliberately narrow: it polls current key state on demand. It does not
//! record, buffer, or forward keystrokes.

use godot::prelude::*;

mod keymap;

#[cfg(target_os = "linux")]
mod x11_backend;

struct GlobalInputExtension;

#[gdextension]
unsafe impl ExtensionLibrary for GlobalInputExtension {}

#[derive(GodotClass)]
#[class(base=Node)]
pub struct GlobalInputServer {
    base: Base<Node>,

    #[cfg(target_os = "linux")]
    backend: Option<x11_backend::X11Backend>,
}

#[godot_api]
impl INode for GlobalInputServer {
    fn init(base: Base<Node>) -> Self {
        #[cfg(target_os = "linux")]
        {
            let backend = x11_backend::X11Backend::connect();
            if backend.is_none() {
                godot_warn!(
                    "GlobalInput: no X11 display reachable; global hotkeys are disabled. \
                     Under a pure Wayland session, run the app via XWayland to enable them."
                );
            }
            Self { base, backend }
        }

        #[cfg(not(target_os = "linux"))]
        {
            godot_warn!("GlobalInput: no global key backend on this platform; hotkeys are disabled.");
            Self { base }
        }
    }
}

#[godot_api]
impl GlobalInputServer {
    /// True while the given Godot `Key` is physically held, regardless of focus.
    ///
    /// Unmappable or unsupported keycodes report `false` rather than erroring, so a
    /// stale binding degrades to "never triggers" instead of breaking the graph.
    #[func]
    pub fn is_key_pressed(&self, keycode: i64) -> bool {
        if keycode <= 0 {
            return false;
        }
        let keycode = keycode as u32;

        #[cfg(target_os = "linux")]
        {
            match &self.backend {
                Some(backend) => backend.is_key_pressed(keycode),
                None => false,
            }
        }

        #[cfg(not(target_os = "linux"))]
        {
            let _ = keycode;
            false
        }
    }

    /// Rebuilds the keysym index after a keyboard layout change.
    #[func]
    pub fn reload_layout(&mut self) {
        #[cfg(target_os = "linux")]
        if let Some(backend) = self.backend.as_mut() {
            if let Err(err) = backend.reload_mapping() {
                godot_warn!("GlobalInput: could not reload keyboard mapping: {err}");
            }
        }
    }

    /// Whether a working backend is available, for UI that wants to explain why
    /// hotkeys are inert.
    #[func]
    pub fn is_available(&self) -> bool {
        #[cfg(target_os = "linux")]
        {
            self.backend.is_some()
        }

        #[cfg(not(target_os = "linux"))]
        {
            false
        }
    }
}
