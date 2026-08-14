extends "../camera_tracker.gd"

const UdpTracker = preload("res://lib/tracking/net/udp_tracker.gd")
const MpProcess = preload("./mp_process.gd")
const OneEuro = preload("res://lib/utils/oneeuro_filter.gd")

var blink_sync: bool = false
var camera_id: int = 0
var port: int = 11574
var server: UdpTracker
var process: MpProcess = MpProcess.new()

@export_range(0.0, 1.0) var tracking_smoothing: float = 0.35 :
	set(v):
		tracking_smoothing = clampf(v, 0.0, 1.0)
		_filters.clear()

var _filters: Dictionary = {}

const PARAM_KEYS: PackedStringArray = [
	"FacePositionX", "FacePositionY", "FacePositionZ",
	"FaceAngleX", "FaceAngleY", "FaceAngleZ",
	"MouthOpen", "MouthSmile", "MouthX",
	"Brows", "BrowLeftY", "BrowRightY",
	"EyeOpenLeft", "EyeOpenRight",
	"EyeLeftX", "EyeLeftY", "EyeRightX", "EyeRightY",
	"CheekPuff", "TongueOut",
]

func _ready():
	super._ready()
	smoothing = 0.3
	server = UdpTracker.new()
	server.name = "MediaPipeSocket"
	server.host = "*"
	server.port = port
	server.packet_received.connect(_packet_received)
	add_child(server)

func _exit_tree() -> void:
	stop_tracking()

func create_config() -> Node:
	var panel = preload("./mp_config.tscn").instantiate()
	panel.tracker = self
	return panel

func start_tracking() -> bool:
	server.port = port
	if not process.start(port, camera_id):
		_alert(process.last_error)
		return false
	if not server.start():
		process.stop()
		_alert("Could not bind MediaPipe UDP port %d" % port)
		return false
	return true

func stop_tracking() -> void:
	if server != null:
		server.stop()
	process.stop()

func restart_tracking() -> bool:
	stop_tracking()
	return start_tracking()

func is_process_running() -> bool:
	return process.is_running()

func apply_packet(data: Dictionary) -> void:
	var packet := {}
	for key in PARAM_KEYS:
		if data.has(key):
			packet[key] = float(data[key])
	if blink_sync and packet.has("EyeOpenRight"):
		packet["EyeOpenLeft"] = packet["EyeOpenRight"]
	for key in packet.keys():
		packet[key] = _smooth_param(String(key), float(packet[key]))
	if not packet.is_empty():
		update(packet)

func _alert(message: String) -> void:
	if message.is_empty():
		return
	push_warning(message)
	var tree := get_tree()
	if tree == null:
		return
	var toast = tree.get_first_node_in_group("system:alert")
	if toast:
		toast.alert(message)

func _packet_received(bytes: PackedByteArray) -> void:
	var text := bytes.get_string_from_utf8()
	if text.is_empty():
		return
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		apply_packet(parsed)

func _smooth_param(key: String, value: float) -> float:
	if tracking_smoothing <= 0.001:
		return value
	if not _filters.has(key):
		_filters[key] = OneEuro.new(
			lerpf(1.2, 0.35, tracking_smoothing),
			lerpf(0.01, 0.001, tracking_smoothing)
		)
	return _filters[key].filter(value)
