extends "../camera_tracker.gd"

const OpenSeeData = preload("./osf_data.gd")
const UdpTracker = preload("res://lib/tracking/net/udp_tracker.gd")
const OsfProcess = preload("./osf_process.gd")
const OneEuro = preload("res://lib/utils/oneeuro_filter.gd")

# controls
var blink_sync: bool = false
var camera_id: int = 0
var port: int = 11573
var server: UdpTracker
var process: OsfProcess = OsfProcess.new()
## 0 = raw packets, 1 = heavy 1€ filtering on noisy face/eye channels.
@export_range(0.0, 1.0) var tracking_smoothing: float = 0.45 :
	set(v):
		tracking_smoothing = clampf(v, 0.0, 1.0)
		_filters.clear()

var _filters: Dictionary = {}

const SMOOTHED_KEYS: PackedStringArray = [
	"FacePositionX", "FacePositionY", "FacePositionZ",
	"FaceAngleX", "FaceAngleY", "FaceAngleZ",
	"MouthOpen", "MouthSmile",
	"EyeOpenLeft", "EyeOpenRight",
	"EyeLeftX", "EyeLeftY", "EyeRightX", "EyeRightY",
]

signal data_received(data: OpenSeeData)

func _ready():
	super._ready()
	smoothing = 0.35
	server = UdpTracker.new()
	server.name = "OSFSocket"
	server.host = "*"
	server.port = port
	server.packet_received.connect(_packet_received)
	data_received.connect(_data_received)
	add_child(server)
	# Tracking starts only when the user presses Start Tracking.

func _exit_tree() -> void:
	stop_tracking()

func create_config() -> Node:
	var panel = preload("./osf_config.tscn").instantiate()
	panel.tracker = self
	return panel

func start_tracking() -> bool:
	server.port = port
	if not process.start(port, camera_id):
		_alert(process.last_error)
		return false
	if not server.start():
		process.stop()
		_alert("Could not bind OpenSeeFace UDP port %d" % port)
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

func _packet_received(data: PackedByteArray):
	var osf_data = OpenSeeData.new()
	osf_data.read_osf_data(data)
	
	data_received.emit(osf_data)

func _data_received(data: OpenSeeData):
	var eyeLeft = data.eyeLeftXY
	var eyeRight = data.eyeRightXY
	
	# sync blinking (disables winking)
	var leftOpen = data.leftEyeOpen
	var rightOpen = data.rightEyeOpen
	if blink_sync:
		leftOpen = rightOpen

	var packet := {
		"FacePositionX": clampf(data.translation.x, -15, 15),
		"FacePositionY": clampf(data.translation.y, -15, 15),
		"FacePositionZ": clampf(data.translation.z, -10, 10),
		"FaceAngleX": clampf(data.rotation.y, -30, 30),
		"FaceAngleY": clampf(-data.rotation.x, -30, 30),
		"FaceAngleZ": clampf(data.rotation.z, -30, 30),
		"MouthOpen": clampf(data.mouthOpen, 0.0, 1.0),
		"MouthSmile": clampf(data.mouthWide, 0.0, 1.0),
		"EyeOpenLeft": leftOpen,
		"EyeOpenRight": rightOpen,
		"EyeLeftX": eyeLeft.x,
		"EyeLeftY": eyeLeft.y,
		"EyeRightX": eyeRight.x,
		"EyeRightY": eyeRight.y,
	}
	for key in SMOOTHED_KEYS:
		if packet.has(key):
			packet[key] = _smooth_param(String(key), float(packet[key]))
	update(packet)

func _smooth_param(key: String, value: float) -> float:
	if tracking_smoothing <= 0.001:
		return value
	if not _filters.has(key):
		_filters[key] = OneEuro.new(
			lerpf(1.2, 0.35, tracking_smoothing),
			lerpf(0.01, 0.001, tracking_smoothing)
		)
	return _filters[key].filter(value)
