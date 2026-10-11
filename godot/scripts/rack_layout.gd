extends Node
## Separate physical cases share one native patch and its unchanged DSP graph.
const RackCase := preload("res://scripts/rack_case.gd")
const SCALE := 0.002
var session
var host
var cases: Array = []
var membership := {}
var identities := {}
var layout_mode := false
var active_case := 0
var grabbed := -1
var grab_basis := Basis.IDENTITY
var grab_distance := 1.0
var grab_offset := Vector3.ZERO
var pointer_grab := false
var picker: OptionButton
var mode_button: CheckButton
var path := ""
var saved := {}
var delete_dialog: ConfirmationDialog
var delete_ids: Array = []
var delete_index := -1
var delete_request := -1
var layout_buttons: Array[Button] = []
var cable_preview: MeshInstance3D

func setup(owner_session) -> void:
	session = owner_session
	host = session.host
	var directory := OS.get_environment("CARDINAL_EMBEDDED_USER_DIR")
	path = directory.path_join("rack-layout.json") if not directory.is_empty() else "user://rack-layout.json"
	if FileAccess.file_exists(path):
		var decoded = JSON.parse_string(FileAccess.get_file_as_string(path))
		if decoded is Dictionary: saved = decoded
	_create_case(host.rack, host.rack_case, session.case_body)
	for index in range(1, mini(saved.get("cases", []).size(), 32)): _create_case()
	for index in range(mini(cases.size(), saved.get("cases", []).size())):
		var data: Dictionary = saved.cases[index]
		cases[index].root.position = _vector(data.get("position", [0, 0, 0]))
		cases[index].root.rotation = _vector(data.get("rotation", [0, 0, 0]))
		cases[index].offset = Vector2(float(data.get("offset", [0, 0])[0]), float(data.get("offset", [0, 0])[1]))
	membership = saved.get("membership", {})
	identities = saved.get("identities", {})
	_build_controls()
	host.bridge.message_received.connect(_deletion_ack)
	sync()

func _vector(value: Array) -> Vector3: return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _create_case(container: Node3D = null, cabinet: Node3D = null, body: StaticBody3D = null) -> void:
	var root := Node3D.new()
	session.spatial.add_child(root)
	root.position = Vector3(cases.size() * 1.2, 0, 0)
	if container == null:
		container = Node3D.new()
		root.add_child(container)
		cabinet = RackCase.new()
		root.add_child(cabinet)
		body = StaticBody3D.new()
		var collision := CollisionShape3D.new()
		collision.shape = BoxShape3D.new()
		body.add_child(collision)
		root.add_child(body)
	else:
		container.reparent(root, false)
		cabinet.reparent(root, false)
		body.reparent(root, false)
	body.set_meta("xr_case", true)
	body.set_meta("rack_id", cases.size())
	var label := Label3D.new()
	preload("res://scripts/clear_text.gd").apply(label)
	label.text = "Rack %d · Layout mode" % (cases.size() + 1)
	label.font_size = 32
	label.pixel_size = 0.001
	root.add_child(label)
	cases.append({"root": root, "modules": container, "case": cabinet, "body": body, "label": label, "offset": Vector2.ZERO})

func _build_controls() -> void:
	var column: VBoxContainer = host.racks_column
	mode_button = CheckButton.new()
	mode_button.text = "Layout mode · unlock rack positions"
	mode_button.toggled.connect(func(enabled: bool):
		session.cancel()
		layout_mode = enabled
		grabbed = -1
		for cabinet in cases: cabinet.label.visible = enabled
		for button in layout_buttons: button.disabled = not enabled)
	column.add_child(mode_button)
	var help := Label.new()
	help.text = "Hold a case edge and aim the pointer to position it. Stick up/down pushes/pulls the rack. Twist your wrist to turn it upright.\nSelect a module title, then choose its destination rack below."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 500
	column.add_child(help)
	picker = OptionButton.new()
	picker.custom_minimum_size.y = 42
	column.add_child(picker)
	picker.item_selected.connect(func(index: int): active_case = index)
	for entry in [
		["Add empty rack", add_case],
		["Delete selected rack…", request_delete],
		["Move selected module to this rack", transfer_selected],
		["Move selected module’s row to this rack", transfer_row],
		["Bring selected rack in front of me", bring_here],
		["Arrange racks in a line", func(): arrange(0)],
		["Arrange racks around me", func(): arrange(1)],
		["Stack racks vertically", func(): arrange(2)]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size.y = 42
		button.pressed.connect(entry[1])
		button.disabled = not layout_mode
		layout_buttons.append(button)
		column.add_child(button)
	_refresh_picker()
	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = "Delete rack?"
	delete_dialog.ok_button_text = "Delete rack"
	delete_dialog.cancel_button_text = "Keep rack"
	delete_dialog.confirmed.connect(_confirm_delete)
	host.settings_panel.add_child(delete_dialog)

func _refresh_picker() -> void:
	picker.clear()
	for index in range(cases.size()): picker.add_item("Rack %d" % (index + 1))
	picker.select(active_case)

func add_case() -> void:
	if not layout_mode or cases.size() >= 32: return
	var neighbor: Dictionary = cases[active_case]
	var transform: Transform3D = neighbor.root.global_transform
	var next_origin: Vector3 = transform.origin + transform.basis * Vector3(neighbor.case.bounds.end.x * SCALE + 0.25, 0, 0)
	_create_case()
	active_case = cases.size() - 1
	cases[active_case].root.global_transform = Transform3D(transform.basis, next_origin)
	_refresh_picker()
	sync()
	save()

func request_delete() -> void:
	if not layout_mode or delete_request >= 0: return
	delete_index = active_case
	delete_ids = []
	for id in host.modules:
		if int(membership.get(id, 0)) == delete_index: delete_ids.append(id)
	var cables := 0
	for cable in host.snapshot.get("cables", []):
		if str(cable.output_module) in delete_ids or str(cable.input_module) in delete_ids: cables += 1
	delete_dialog.dialog_text = "Delete Rack %d?\n\nThis removes %d modules and %d connected cables from this patch.\nUndo can restore the modules and cables; case placement is not restored.\n%s" % [delete_index + 1, delete_ids.size(), cables, "The last rack will remain as an empty case." if cases.size() == 1 else ""]
	delete_dialog.popup_centered(Vector2i(570, 250))

func _confirm_delete() -> void:
	if not layout_mode or delete_index < 0: return
	if delete_ids.is_empty(): _finish_delete(); return
	delete_request = host.bridge.send_command("remove_many", {"modules": delete_ids})

func _deletion_ack(message: Dictionary) -> void:
	if message.get("type") != "ack" or int(message.get("request", -2)) != delete_request: return
	delete_request = -1
	if message.get("ok", false): _finish_delete()
	else: delete_index = -1

func _finish_delete() -> void:
	var removed := delete_index
	for id in delete_ids: membership.erase(id)
	if cases.size() == 1:
		cases[0].offset = Vector2.ZERO
	elif removed == 0:
		for view in cases[1].modules.get_children(): view.reparent(cases[0].modules, false)
		cases[0].root.transform = cases[1].root.transform
		cases[0].offset = cases[1].offset
		cases[1].root.queue_free()
		cases.remove_at(1)
		for id in membership: membership[id] = maxi(0, int(membership[id]) - 1)
	else:
		cases[removed].root.queue_free()
		cases.remove_at(removed)
		for id in membership:
			if int(membership[id]) > removed: membership[id] = int(membership[id]) - 1
	active_case = mini(active_case, cases.size() - 1)
	for index in range(cases.size()):
		cases[index].body.set_meta("rack_id", index)
		cases[index].label.text = "Rack %d · Layout mode" % (index + 1)
	_refresh_picker()
	delete_index = -1
	delete_ids = []
	save()

func _assign(ids: Array) -> void:
	if not layout_mode or ids.is_empty(): return
	var cabinet: Dictionary = cases[active_case]
	var occupied := false
	for id in membership:
		if int(membership[id]) == active_case and host.modules.has(id): occupied = true
	if not occupied:
		var descriptor: Dictionary = host.modules[ids[0]].descriptor
		cabinet.offset = Vector2(float(descriptor.x), float(descriptor.y))
	for id in ids: membership[id] = active_case
	sync()
	save()

func transfer_selected() -> void:
	if session._valid_selection(): _assign([str(session.selected_module.view.descriptor.id)])

func transfer_row() -> void:
	if not session._valid_selection(): return
	var selected: Dictionary = session.selected_module.view.descriptor
	var source := int(membership.get(str(selected.id), 0))
	var ids := []
	for id in host.modules:
		if int(membership.get(id, 0)) == source and is_equal_approx(float(host.modules[id].descriptor.y), float(selected.y)): ids.append(id)
	_assign(ids)

func bring_here() -> void:
	if not layout_mode: return
	var facing := Basis(Vector3.UP, session.headset.global_rotation.y)
	cases[active_case].root.global_transform = Transform3D(facing, session.headset.global_position + facing * Vector3(-0.3, 0.15, -1.2))
	sync()
	save()

func arrange(style: int) -> void:
	if not layout_mode: return
	var facing := Basis(Vector3.UP, session.headset.global_rotation.y)
	var head: Vector3 = session.headset.global_position
	var width := 1.2
	var height := 0.9
	for cabinet in cases:
		width = maxf(width, cabinet.case.bounds.size.x * SCALE + 0.2)
		height = maxf(height, cabinet.case.bounds.size.y * SCALE + 0.15)
	for index in range(cases.size()):
		var offset := Vector3((index - (cases.size() - 1) * 0.5) * width, 0.1, -1.6)
		var basis := facing
		if style == 1:
			var angle := (index - (cases.size() - 1) * 0.5) * minf(0.85, TAU / maxf(cases.size(), 1))
			basis = facing * Basis(Vector3.UP, angle)
			offset = Basis(Vector3.UP, angle) * Vector3(-0.3, 0.1, -maxf(1.6, width))
		elif style == 2: offset = Vector3(-0.3, 0.1 + index * height, -1.6)
		cases[index].root.global_transform = Transform3D(basis, head + facing * offset)
	sync()
	save()

func begin_grab(index: int, sample: Dictionary) -> void:
	if not layout_mode: return
	grabbed = clampi(index, 0, cases.size() - 1)
	active_case = grabbed
	picker.select(active_case)
	grab_basis = sample.get("basis", Basis.IDENTITY)
	var root: Node3D = cases[grabbed].root
	pointer_grab = sample.has("origin") and sample.has("direction") and sample.has("grab_point")
	if pointer_grab:
		grab_distance = clampf(sample.origin.distance_to(sample.grab_point), 0.25, 5.0)
		grab_offset = root.global_position - (sample.origin + sample.direction.normalized() * grab_distance)
	root.global_basis = Basis(Vector3.UP, root.global_rotation.y)
	host.cables.hide()
	_update_cable_preview()

func drag(sample: Dictionary, previous: Vector3) -> void:
	if not layout_mode or grabbed < 0: return
	var root: Node3D = cases[grabbed].root
	# Godot's vertical axis is Y (the user's requested vertical/Z-only turn).
		# Restrict rotation only; translation below remains free on all three axes.
	if sample.has("basis"):
		var relative: Quaternion = (grab_basis.inverse() * sample.basis).get_rotation_quaternion()
		var yaw := wrapf(2.0 * atan2(relative.z, relative.w), -PI, PI)
		var rotation := Basis(Vector3.UP, yaw)
		root.global_basis = rotation * root.global_basis
		grab_basis = sample.basis
	if pointer_grab:
		var stick: Vector2 = sample.get("stick", Vector2.ZERO)
		if absf(stick.y) > 0.2:
			grab_distance = clampf(grab_distance + stick.y * get_physics_process_delta_time() * 1.5, 0.25, 5.0)
		root.global_position = sample.origin + sample.direction.normalized() * grab_distance + grab_offset
	else: root.global_position += sample.position - previous
	_update_cable_preview()

func end_grab() -> void:
	var moved := grabbed >= 0
	grabbed = -1
	if moved:
		if cable_preview != null: cable_preview.hide()
		host.cables.show()
		sync()
		save()

func _update_cable_preview() -> void:
	if cable_preview == null:
		cable_preview = MeshInstance3D.new()
		cable_preview.mesh = ImmediateMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		cable_preview.material_override = material
		host.add_child(cable_preview)
	var mesh: ImmediateMesh = cable_preview.mesh
	mesh.clear_surfaces()
	var endpoints := []
	for cable in host.snapshot.get("cables", []):
		var out_id := str(cable.output_module)
		var in_id := str(cable.input_module)
		if not host.modules.has(out_id) or not host.modules.has(in_id): continue
		endpoints.append([host.modules[out_id].port_position(int(cable.output_port), "output"), host.modules[in_id].port_position(int(cable.input_port), "input"), Color(str(cable.get("color", "#dd9456")))])
	if not endpoints.is_empty():
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for wire in endpoints:
			mesh.surface_set_color(wire[2])
			for index in range(16):
				for t in [index / 16.0, (index + 1) / 16.0]:
					mesh.surface_add_vertex(wire[0].lerp(wire[1], t) + Vector3(0, -sin(t * PI) * 0.15, 0.035))
		mesh.surface_end()
	cable_preview.show()

func sync() -> void:
	var descriptions := []
	var changed := false
	for cabinet in cases: descriptions.append([])
	for id in host.modules:
		var view: CardinalModuleView = host.modules[id]
		var identity := str(view.descriptor.plugin) + "/" + str(view.descriptor.model)
		if identities.get(id, identity) != identity: membership.erase(id)
		identities[id] = identity
		if not membership.has(id):
			membership[id] = active_case
			var occupied := false
			for other_id in host.modules:
				if other_id != id and membership.has(other_id) and int(membership[other_id]) == active_case: occupied = true
			if not occupied and active_case > 0:
				cases[active_case].offset = Vector2(float(view.descriptor.x), float(view.descriptor.y))
			changed = true
		var index := clampi(int(membership.get(id, 0)), 0, cases.size() - 1)
		membership[id] = index
		var cabinet: Dictionary = cases[index]
		view.set_meta("rack_offset", cabinet.offset)
		if view.get_parent() != cabinet.modules: view.reparent(cabinet.modules, false)
		var descriptor: Dictionary = view.descriptor.duplicate()
		descriptor.x = float(descriptor.x) - cabinet.offset.x
		descriptor.y = float(descriptor.y) - cabinet.offset.y
		view.position = Vector3(descriptor.x * SCALE, -descriptor.y * SCALE, 0)
		descriptions[index].append(descriptor)
	for index in range(cases.size()):
		var cabinet: Dictionary = cases[index]
		var data: Array = descriptions[index]
		# Empty cases remain visible/selectable in layout mode.
		if data.is_empty(): data = [{"x": 0, "y": 0, "width": 360, "height": 380}]
		cabinet.case.sync(data)
		var bounds: Rect2 = cabinet.case.bounds
		var collision: CollisionShape3D = cabinet.body.get_child(0)
		(collision.shape as BoxShape3D).size = Vector3(bounds.size.x * SCALE, bounds.size.y * SCALE, 0.06)
		cabinet.body.position = Vector3(bounds.get_center().x * SCALE, -bounds.get_center().y * SCALE, -0.045)
		cabinet.label.position = Vector3(bounds.get_center().x * SCALE, -bounds.position.y * SCALE + 0.05, 0)
		cabinet.label.visible = layout_mode
	host._rebuild_cables(host.snapshot.get("cables", []))
	if changed: save()

func restore_from(patch_path: String) -> void:
	session.cancel()
	mode_button.button_pressed = false
	var data := {}
	var sidecar := patch_path + ".3d.json"
	if FileAccess.file_exists(sidecar):
		var decoded = JSON.parse_string(FileAccess.get_file_as_string(sidecar))
		if decoded is Dictionary: data = decoded
	_restore(data)

func reset_for_new_patch() -> void:
	_restore({})
	var facing := Basis(Vector3.UP, session.headset.global_rotation.y)
	cases[0].root.global_transform = Transform3D(facing, session.headset.global_position + facing * Vector3(-0.15, 0.15, -1.2))
	sync()
	save()

func _restore(data: Dictionary) -> void:
	session.cancel()
	mode_button.button_pressed = false
	grabbed = -1
	saved = data
	# Keep module objects and their live controls while replacing case frames.
	for view in host.modules.values():
		if view.get_parent() != cases[0].modules: view.reparent(cases[0].modules, false)
	for index in range(1, cases.size()): cases[index].root.queue_free()
	cases.resize(1)
	cases[0].root.transform = Transform3D.IDENTITY
	cases[0].offset = Vector2.ZERO
	for index in range(1, mini(data.get("cases", []).size(), 32)): _create_case()
	for index in range(mini(cases.size(), data.get("cases", []).size())):
		var entry: Dictionary = data.cases[index]
		cases[index].root.position = _vector(entry.get("position", [0, 0, 0]))
		cases[index].root.rotation = _vector(entry.get("rotation", [0, 0, 0]))
		cases[index].offset = Vector2(float(entry.get("offset", [0, 0])[0]), float(entry.get("offset", [0, 0])[1]))
	membership = data.get("membership", {})
	identities = data.get("identities", {})
	active_case = 0
	_refresh_picker()
	sync()
	save()

func save(destination := "") -> void:
	var data := {"version": 1, "cases": [], "membership": membership, "identities": identities}
	for cabinet in cases:
		var root: Node3D = cabinet.root
		data.cases.append({"position": [root.position.x, root.position.y, root.position.z], "rotation": [root.rotation.x, root.rotation.y, root.rotation.z], "offset": [cabinet.offset.x, cabinet.offset.y]})
	var file := FileAccess.open(path if destination.is_empty() else destination, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(data, "\t"))
	else: push_error("Could not save rack layout")
