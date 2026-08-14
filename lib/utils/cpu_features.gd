extends Object

## CPU feature probes. MediaPipe wheels are AVX-only and SIGILL otherwise.

static func has_avx() -> bool:
	var cpuinfo := FileAccess.open("/proc/cpuinfo", FileAccess.READ)
	if cpuinfo == null:
		return false
	while not cpuinfo.eof_reached():
		var line := cpuinfo.get_line()
		if line.begins_with("flags") or line.begins_with("Features"):
			return (" " + line.strip_edges() + " ").contains(" avx ")
	return false
