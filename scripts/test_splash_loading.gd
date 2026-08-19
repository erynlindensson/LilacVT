extends Node
## Headless test verifying the startup splash screen loading bar and transition.
##
## Tests:
##   1. StudioSplash node and UI components (ProgressBar, StatusLabel, PercentLabel).
##   2. Progress setter and label synchronization.
##   3. Loading completion and transition signal.

const StudioSplash = preload("res://studio/splash.gd")
const SplashScene = preload("res://studio/splash.tscn")

func _ready() -> void:
	_run()

func _run() -> void:
	# 1. Test Splash scene instantiation & component structure
	var splash_instance: StudioSplash = SplashScene.instantiate() as StudioSplash
	add_child(splash_instance)

	await get_tree().process_frame

	if splash_instance.progress_bar == null:
		_fail("%ProgressBar not found in Splash")
		return

	if splash_instance.status_label == null:
		_fail("%StatusLabel not found in Splash")
		return

	if splash_instance.percent_label == null:
		_fail("%PercentLabel not found in Splash")
		return

	# 2. Test Progress updates and labels
	splash_instance.set_progress(0.45, "Loading test models...", 0.0)
	if not is_equal_approx(splash_instance.progress_bar.value, 45.0):
		_fail("progress_bar.value expected 45.0, got %f" % splash_instance.progress_bar.value)
		return

	if splash_instance.status_label.text != "Loading test models...":
		_fail("status_label.text expected 'Loading test models...', got '%s'" % splash_instance.status_label.text)
		return

	if splash_instance.percent_label.text != "45%":
		_fail("percent_label.text expected '45%', got '%s'" % splash_instance.percent_label.text)
		return

	# 3. Test completion signal & cleanup
	var completed_emitted: Array = [false]
	splash_instance.loading_completed.connect(func(): completed_emitted[0] = true)

	splash_instance.complete_and_fade(0.0)
	await get_tree().process_frame

	if not completed_emitted[0]:
		_fail("loading_completed signal was not emitted")
		return

	print("splash_loading_ok")
	get_tree().quit(0)

func _fail(msg: String) -> void:
	printerr("FAIL %s" % msg)
	get_tree().quit(1)
