extends Node3D
## Static, batched scenery. No background simulation or extra render passes.
const PLACES := ["Recording studio", "Forest", "Mountain summit", "Stage", "Warehouse", "Desert", "Flowery field", "Empty space"]
var place_picker: OptionButton
var host
var scenery: Node3D
var place := 0
var hour := 14.0
var hour_label: Label
var config := ConfigFile.new()
var path := ""
var rng := RandomNumberGenerator.new()
var materials := {}

func setup(owner_host) -> void:
	host = owner_host
	# The desktop rack uses native negative-Y panel coordinates; VR uses a
	# real standing floor. Keep the desktop instrument above its scenery.
	if OS.get_environment("CARDINAL_3D_XR") != "1": position.y = -1.5
	var directory := OS.get_environment("CARDINAL_EMBEDDED_USER_DIR")
	path = directory.path_join("environment.cfg") if not directory.is_empty() else "user://environment.cfg"
	config.load(path)
	place = clampi(int(config.get_value("scene", "place", 0)), 0, PLACES.size() - 1)
	hour = clampf(float(config.get_value("scene", "hour", 14.0)), 0, 24)
	var heading := Label.new()
	heading.text = "Place & time of day"
	host.environment_column.add_child(heading)
	var picker := OptionButton.new()
	place_picker = picker
	for title in PLACES: picker.add_item(title)
	picker.select(place)
	picker.custom_minimum_size.y = 42
	picker.item_selected.connect(func(index: int): place = index; rebuild(); _save())
	host.environment_column.add_child(picker)
	hour_label = Label.new()
	host.environment_column.add_child(hour_label)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 24
	slider.step = 0.25
	slider.value = hour
	slider.custom_minimum_size.y = 42
	slider.value_changed.connect(func(value: float): hour = value; update_light(); _save())
	host.environment_column.add_child(slider)
	var quality := OptionButton.new()
	quality.add_item("Balanced quality · 2× edge smoothing")
	quality.add_item("Extra clarity · 4× edge smoothing")
	quality.add_item("Maximum speed · no edge smoothing")
	quality.custom_minimum_size.y = 42
	quality.selected = clampi(int(config.get_value("scene", "quality", 0)), 0, 2)
	_apply_quality(quality.selected)
	quality.item_selected.connect(func(index: int): _apply_quality(index); config.set_value("scene", "quality", index); _save())
	host.environment_column.add_child(quality)
	rebuild()

func _apply_quality(index: int) -> void:
	get_viewport().msaa_3d = [Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_DISABLED][index]

func _save() -> void:
	config.set_value("scene", "place", place)
	config.set_value("scene", "hour", hour)
	if config.save(path) != OK: push_error("Could not save environment settings")

func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.92
		materials[key] = material
	return materials[key]

func _mesh(mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.material_override = _material(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scenery.add_child(node)
	return node

func _box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(mesh, at, color)

func _batch(mesh: Mesh, transforms: Array, color: Color) -> void:
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = mesh
	instances.instance_count = transforms.size()
	for index in range(transforms.size()): instances.set_instance_transform(index, transforms[index])
	var node := MultiMeshInstance3D.new()
	node.multimesh = instances
	node.material_override = _material(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scenery.add_child(node)

func _cone(radius: float, height: float, tip := 0.0) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = tip
	mesh.height = height
	mesh.radial_segments = 12
	return mesh

func rebuild() -> void:
	if scenery != null:
		remove_child(scenery)
		scenery.queue_free()
	scenery = Node3D.new()
	add_child(scenery)
	if place == 7:
		update_light()
		return
	rng.seed = 73191
	if place in [0, 3, 4]: _interior()
	else: _outdoor()
	update_light()

func empty_space() -> void:
	place = 7
	place_picker.select(place)
	rebuild()
	_save()

func _interior() -> void:
	var warehouse := place == 4
	var stage := place == 3
	var width := 14.0 if warehouse else 10.0
	var height := 7.0 if warehouse else 4.0
	_box(Vector3(width * 2, 0.2, width * 2), Vector3(0, -0.12, 0), Color("363337") if warehouse else Color("40332c"))
	_box(Vector3(width * 2, 0.18, width * 2), Vector3(0, height, 0), Color("252c32"))
	for side in [-1, 1]:
		_box(Vector3(0.2, height, width * 2), Vector3(side * width, height / 2, 0), Color("6b6861") if warehouse else Color("252d36"))
		_box(Vector3(width * 2, height, 0.2), Vector3(0, height / 2, side * width), Color("6b6861") if warehouse else Color("252d36"))
	if place == 0:
		for side in [-1, 1]:
			for z in range(-8, 9, 2):
				_box(Vector3(0.16, 1.5, 0.9), Vector3(side * 9.82, 2, z), Color("864932") if z % 4 == 0 else Color("424d60"))
		for x in range(-8, 9, 2): _box(Vector3(0.9, 1.5, 0.16), Vector3(x, 2, -9.82), Color("424d60"))
		_box(Vector3(4, 0.6, 1.2), Vector3(0, 0.7, -6), Color("302b28"))
		for x in [-3, 3]:
			_box(Vector3(0.6, 1.2, 0.5), Vector3(x, 1.2, -6), Color("151b20"))
			_mesh(_cone(0.17, 0.04, 0.17), Vector3(x, 1.4, -5.73), Color("a29d8f")).rotation.x = PI / 2
		_box(Vector3(3.4, 1.2, 0.12), Vector3(0, 2, -9.8), Color("557c83"))
	elif stage:
		_box(Vector3(10, 0.4, 6), Vector3(0, -0.21, 0), Color("191e26"))
		for x in [-4.5, 4.5]:
			_box(Vector3(0.9, 2, 0.7), Vector3(x, 1, -3), Color("0e131b"))
			_box(Vector3(0.15, 3.8, 0.15), Vector3(x, 1.9, -4), Color("99a2aa"))
		_box(Vector3(9, 0.2, 0.2), Vector3(0, 3.7, -4), Color("99a2aa"))
		for x in range(-4, 5): _box(Vector3(0.22, 0.25, 0.25), Vector3(x, 3.4, -4), Color("70659c") if x % 2 == 0 else Color("406e94"))
		for x in range(-8, 9): _box(Vector3(0.25, 3.5, 0.2), Vector3(x * 0.55, 1.75, -6), Color("4b2032"))
	else:
		for x in range(-12, 13, 4):
			for z in [-12, 12]: _box(Vector3(0.25, 7, 0.25), Vector3(x, 3.5, z), Color("3c444b"))
			_box(Vector3(0.25, 0.3, 28), Vector3(x, 6.5, 0), Color("3c444b"))
		for x in [-10, 10]:
			for z in [-8, -4, 4, 8]:
				_box(Vector3(1.2, 0.8, 1.2), Vector3(x, 0.4, z), Color("8f7050"))
	for x in [-3, 3]:
		_box(Vector3(1.6, 0.05, 0.25), Vector3(x, height - 0.18, 0), Color("d8d8bd"))
	# Lighting stays two directional lights, independent of scenery complexity.

func _outdoor() -> void:
	var ground := Color("576640")
	if place == 2: ground = Color("6d7378")
	if place == 5: ground = Color("c49a69")
	_box(Vector3(180, 0.3, 180), Vector3(0, -0.22, 0), ground)
	if place == 1:
		var trunks := []
		var crowns := []
		for index in range(150):
			var angle := rng.randf() * TAU
			var radius := rng.randf_range(7, 55)
			var at := Vector3(sin(angle) * radius, 0, cos(angle) * radius)
			var height := rng.randf_range(4, 8)
			trunks.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1, height, 1)), at + Vector3(0, height / 2, 0)))
			crowns.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1, height / 5, 1)), at + Vector3(0, height * 0.65, 0)))
		_batch(_cone(0.16, 1, 0.1), trunks, Color("58442e"))
		_batch(_cone(2, 5, 0.15), crowns, Color("31583c"))
	elif place == 2:
		for index in range(18):
			var angle := TAU * index / 18.0
			var height := rng.randf_range(18, 45)
			var at := Vector3(sin(angle) * 65, height / 2 - 8, cos(angle) * 65)
			_mesh(_cone(rng.randf_range(13, 24), height), at, Color("78838f"))
			_mesh(_cone(6, height * 0.3), at + Vector3(0, height * 0.35, 0), Color("e4e8e5"))
		for index in range(12):
			var rock := SphereMesh.new()
			rock.radius = rng.randf_range(0.5, 1.3)
			rock.height = rock.radius * 1.1
			rock.radial_segments = 12
			rock.rings = 6
			_mesh(rock, Vector3(rng.randf_range(-12, 12), -0.2, rng.randf_range(8, 15)), Color("626a73"))
	elif place == 5:
		for index in range(24):
			var dune := SphereMesh.new()
			dune.radius = rng.randf_range(10, 20)
			dune.height = rng.randf_range(5, 10)
			dune.radial_segments = 32
			dune.rings = 12
			var angle := rng.randf() * TAU
			_mesh(dune, Vector3(sin(angle) * 50, -2, cos(angle) * 50), Color("cea570"))
	elif place == 6:
		var stems := []
		var petals := [[], [], [], []]
		for index in range(1600):
			var at := Vector3(rng.randf_range(-45, 45), 0, rng.randf_range(-45, 45))
			if Vector2(at.x, at.z).length() < 5: continue
			var height := rng.randf_range(0.18, 0.5)
			stems.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1, height, 1)), at + Vector3(0, height / 2, 0)))
			petals[index % 4].append(Transform3D(Basis.IDENTITY, at + Vector3(0, height, 0)))
		_batch(_cone(0.008, 1, 0.006), stems, Color("3f6638"))
		var flower := SphereMesh.new()
		flower.radius = 0.055
		flower.height = 0.025
		flower.radial_segments = 8
		flower.rings = 4
		for index in range(4): _batch(flower, petals[index], [Color("e8b7d0"), Color("e3c153"), Color("a68dc6"), Color("f1ede1")][index])

func update_light() -> void:
	if hour_label != null: hour_label.text = "Time · %02d:%02d" % [int(hour) % 24, int(round(fmod(hour, 1.0) * 60))]
	var daylight := clampf(sin((hour - 6.0) / 12.0 * PI), 0, 1)
	var sunset := pow(1.0 - daylight, 3.0)
	var interior := place in [0, 3, 4]
	host.environment.background_mode = Environment.BG_SKY
	var sky: ProceduralSkyMaterial = host.environment.sky.sky_material
	sky.sky_top_color = Color("091427").lerp(Color("658da8"), daylight)
	sky.sky_horizon_color = Color("25253b").lerp(Color("c0d0d5"), daylight).lerp(Color("bb7960"), sunset * daylight * 2)
	sky.ground_horizon_color = sky.sky_horizon_color
	sky.ground_bottom_color = Color("202c29")
	host.key_light.rotation_degrees = Vector3(-maxf(8, daylight * 75), (hour - 12) * 15, 0)
	host.key_light.light_color = Color("ffb878").lerp(Color("fff7e8"), daylight)
	host.key_light.light_energy = (0.7 + daylight * 0.5 if interior else 0.1 + daylight * 1.2) * host.brightness
	host.environment.ambient_light_color = Color("74829e").lerp(Color("bfccd0"), daylight)
	host.environment.ambient_light_energy = (0.65 if interior else 0.25 + daylight * 0.5) * host.brightness
	host.fill_light.light_color = Color("bb8fe0") if place == 3 else Color("b9d3ee")
	host.fill_light.light_energy = (0.5 if interior else 0.15) * host.brightness
