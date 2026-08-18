#!/usr/bin/env bash
# Run the headless test suite.
#
#   ./scripts/run_tests.sh              # uses godot4-ayagami from PATH
#   GODOT=/path/to/godot ./scripts/run_tests.sh
#
# The engine MUST be a Godot build carrying the Ayagami custom blend-mode patch
# (thirdparty/ayagami/patches/). Stock Godot cannot run these: the BlendRegistry
# autoload calls RenderingServer.register_blend_mode(), which only the patch
# adds, so every scene-based test dies at startup.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot4-ayagami}"

if ! command -v "${GODOT}" >/dev/null 2>&1 && [[ ! -x "${GODOT}" ]]; then
	echo "error: godot binary not found: ${GODOT}" >&2
	echo "set GODOT=/path/to/patched/godot" >&2
	exit 127
fi

# Tests that run as a MainLoop. Note --script does NOT instantiate autoloads, so
# anything reaching Registry / GlobalInput / BlueprintManager belongs below.
SCRIPT_TESTS=(
	test_cpu_features
	test_l2d_physics_controls
	test_license_txt
	test_mediapipe_tracker
	test_osf_process
	test_osf_smoothing
	test_parameter_grouping
	test_serializers_color
	test_spinbox_updown_composite
	test_terms_popup
	test_theme_install_path
	test_theme_manager
	test_theme_remap_coverage
	test_theme_spinbox_icons
	test_transparent_aa_compositing
	test_vrm_catalog
	test_vrm_seed_san
)

# Tests that need autoloads, so they run as a scene.
SCENE_TESTS=(
	test_blueprint_ui_state
	test_graph_frames
	test_blueprint_editor_smoke
)

# Excluded from automation: these need local fixtures or network and are red on
# any clean machine. Run them by hand when working on those areas.
#   test_live2d_catalog        fetches the remote catalog
#   test_model_import          needs an AvatarSample VRM in the user data dir
#   test_vrm_load              needs an AvatarSample VRM in the user data dir
#   test_vrm_tracking          needs an AvatarSample VRM in the user data dir
#   test_osf_tracker_lifecycle needs a working OpenSeeFace venv and process

pass=0
fail=0
failed_names=()

run_test() {
	local name="$1"
	shift
	local out
	out="$("${GODOT}" --headless --path "${ROOT}" "$@" 2>&1)"
	local code=$?
	# Godot does not always propagate quit(1), so treat printed failure as fatal.
	if [[ ${code} -ne 0 ]] || grep -qi "^FAIL\|FAIL " <<<"${out}"; then
		echo "FAIL ${name}"
		grep -i "FAIL" <<<"${out}" | head -3
		fail=$((fail + 1))
		failed_names+=("${name}")
	else
		echo "ok   ${name}"
		pass=$((pass + 1))
	fi
}

echo "engine: $("${GODOT}" --version 2>/dev/null | tail -1)"
echo

for t in "${SCRIPT_TESTS[@]}"; do
	run_test "${t}" --script "scripts/${t}.gd"
done

for t in "${SCENE_TESTS[@]}"; do
	run_test "${t}" "res://scripts/${t}.tscn"
done

echo
echo "passed ${pass}, failed ${fail}"
if [[ ${fail} -gt 0 ]]; then
	printf 'failed: %s\n' "${failed_names[*]}"
	exit 1
fi
