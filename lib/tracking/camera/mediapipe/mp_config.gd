extends Control

const SocketTracker = preload("res://lib/tracking/net/socket_tracker.gd")

var tracker

func _ready() -> void:
	%CameraId.value = tracker.camera_id
	if tracker.get("tracking_smoothing") != null:
		%Smoothing.value = float(tracker.tracking_smoothing) * 100.0
	tracker.server.connection_status.connect(_on_connection_status)
	_refresh_status(SocketTracker.ConnectionStatus.WAIT if tracker.is_process_running() else SocketTracker.ConnectionStatus.OFF)

func _process(_delta: float) -> void:
	%FpsCounter.text = "FPS: %d" % max(0, tracker.fps)

func _on_connection_status(status) -> void:
	_refresh_status(status)

func _refresh_status(status) -> void:
	var running: bool = tracker.is_process_running()
	var on: bool = status == SocketTracker.ConnectionStatus.ON
	var waiting: bool = status == SocketTracker.ConnectionStatus.WAIT or (running and not on)

	if on:
		%ActiveIndicator.text = "On"
		%ActiveIndicator.modulate = Color.RED
	elif waiting:
		%ActiveIndicator.text = "Wait"
		%ActiveIndicator.modulate = Color.YELLOW
	else:
		%ActiveIndicator.text = "Off"
		%ActiveIndicator.modulate = Color.WHITE

	%Connect.disabled = on
	%Disconnect.disabled = not running and status == SocketTracker.ConnectionStatus.OFF

func _on_blink_sync_toggled(toggled_on: bool) -> void:
	tracker.blink_sync = toggled_on

func _on_smoothing_value_changed(value: float) -> void:
	if tracker != null and "tracking_smoothing" in tracker:
		tracker.tracking_smoothing = value / 100.0

func _on_connect_pressed() -> void:
	tracker.camera_id = int(%CameraId.value)
	_refresh_status(SocketTracker.ConnectionStatus.WAIT)
	if not tracker.restart_tracking():
		_refresh_status(SocketTracker.ConnectionStatus.OFF)

func _on_disconnect_pressed() -> void:
	tracker.stop_tracking()
	_refresh_status(SocketTracker.ConnectionStatus.OFF)
