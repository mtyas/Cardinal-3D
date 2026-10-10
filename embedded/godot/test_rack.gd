extends SceneTree

func _initialize():
	_run.call_deferred()

func _run():
	var scene = load("res://main.tscn").instantiate()
	get_root().add_child(scene)
	await create_timer(0.4).timeout
	assert(scene.bridge.connected, "Embedded backend must initialize")
	assert(scene.modules.size() == 6, "Native starter must appear in 3D: " + str(scene.modules.size()))
	assert(scene.snapshot.cables.size() == 5)
	for view in scene.modules.values():
		assert(view.face != null and view.texture != null, "Each starter panel must have original artwork")
	assert(scene.bridge.peer.get_status() == StreamPeerTCP.STATUS_NONE, "Embedded rack must not open TCP")
	assert(scene.bridge.audio_playback.get_playback_position() > 0.05)
	assert(scene.bridge.shutdown())
	print("PASS: embedded 3D starter rack; six original panels; cables; native audio; no TCP")
	get_root().remove_child(scene)
	scene.queue_free()
	await process_frame
	quit(0)
