extends SceneTree

var frontend: Node3D
var stage := 0
var elapsed := 0.0
var next_gesture := 0.0
var frames: Array[float] = []
var cpu_peak := 0.0
var gestures := 0
var loading_generation := ""

func _initialize() -> void:
	frontend = load("res://scripts/main.gd").new()
	root.add_child(frontend)

func _process(delta: float) -> bool:
	if frontend.bridge == null or frontend.snapshot.is_empty():
		return false
	var state: Dictionary = frontend.snapshot
	if stage == 0:
		loading_generation = str(state["generation"])
		frontend.bridge.send_command("load", {"path": OS.get_environment("CARDINAL_3D_BLANK_PATCH")})
		stage = 1
	elif stage == 1 and str(state["generation"]) != loading_generation and state["modules"].is_empty():
		frontend.bridge.send_command("escape")
		frontend.bridge.send_command("starter")
		stage = 2
	elif stage == 2 and state["modules"].size() == 6:
		stage = 3
	elif stage == 3:
		elapsed += delta
		if elapsed > 2:
			frames.append(delta)
		cpu_peak = maxf(cpu_peak, float(state.get("audio_cpu_max", 0)))
		if elapsed >= next_gesture:
			next_gesture = elapsed + 0.4
			for module: Dictionary in state["modules"]:
				if module["model"] != "VCO": continue
				for control: Dictionary in module["controls"]:
					if control["kind"] != "knob" or int(control["id"]) != 2: continue
					var y := float(control["y"])
					for phase in ["down", "motion", "up"]:
						frontend.bridge.send_command("pointer", {"module": module["id"], "x": control["x"], "y": y if phase == "down" else y + (4 if gestures % 2 else -4), "phase": phase, "button": 0, "mods": 0})
					gestures += 1
		if elapsed >= 62:
			frames.sort()
			var total := 0.0
			for sample in frames: total += sample
			var report := {"seconds": elapsed, "frames": frames.size(), "mean_fps": frames.size() / total, "p95_frame_ms": frames[int(frames.size() * 0.95)] * 1000, "gestures": gestures, "modules": state["modules"].size(), "cables": state["cables"].size(), "audio_cpu_peak": cpu_peak, "audio_underruns": null, "underrun_counter_available": false}
			var file := FileAccess.open(OS.get_environment("CARDINAL_3D_BENCHMARK_REPORT"), FileAccess.WRITE)
			file.store_string(JSON.stringify(report, "  "))
			quit(0 if report["mean_fps"] >= 60 else 1)
	return false
