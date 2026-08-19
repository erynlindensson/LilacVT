debug:
	cargo build
	cp target/debug/libgd_global_input.so addons/global_input/lib/libgd_global_input.debug.so

release:
	cargo build --release
	cp target/release/libgd_global_input.so addons/global_input/lib/libgd_global_input.release.so

package: debug | release
