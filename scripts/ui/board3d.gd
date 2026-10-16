class_name Board3D
extends Node3D
## La mappa in 3D: regioni esagonali con la grafica delle tessere del gioco, mare tutt'intorno,
## città con gli edifici e le meraviglie (modelli del modulo TTS), unità colorate, segnalini.
## Telecamera orbitale: trascina per ruotare, rotella o pizzico per lo zoom, tasto destro
## (o Maiusc + trascina) per spostare. Le caselle selezionabili si illuminano: basta un clic.

signal hex_clicked(key: String)
signal hex_hovered(key: String)

const D = preload("res://scripts/data/coc_data.gd")
const TOP := 0.12
const SEA_TOP := 0.06

var eng
var cam: Camera3D
var yaw := 0.0
var pitch := 0.95
var dist := 16.0
var target := Vector3.ZERO
var t_yaw := 0.0
var t_pitch := 0.95
var t_dist := 16.0
var t_target := Vector3.ZERO
var center2 := Vector2.ZERO
var hex_nodes := {}          # chiave -> MeshInstance3D
var hex_state := {}          # chiave -> firma (per ricostruire solo quando cambia)
var pieces: Node3D
var marks: Node3D
var meshes := {}
var mats := {}
var targets := {}            # chiave -> colore
var preview := {}            # regione -> {tile, oi}: anteprima dell'orientamento di una regione da scoprire
var selected := ""
var dragging := false
var drag_moved := 0.0
var panning := false
var last_mouse := Vector2.ZERO
var hover := ""
var touches := {}
var pinch_d := 0.0
var bounds := Rect2()


func _ready() -> void:
	_build_env()
	pieces = Node3D.new()
	add_child(pieces)
	marks = Node3D.new()
	add_child(marks)
	_build_hexes()
	reset_view()
	refresh()


func _process(delta: float) -> void:
	var k := clampf(delta * 8.0, 0.0, 1.0)
	yaw = lerp_angle(yaw, t_yaw, k)
	pitch = lerpf(pitch, t_pitch, k)
	dist = lerpf(dist, t_dist, k)
	target = target.lerp(t_target, k)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	cam.position = target + dir * dist
	cam.look_at(target, Vector3.UP)
	# pulsazione delle caselle evidenziate
	var a := 0.55 + 0.35 * sin(Time.get_ticks_msec() / 220.0)
	for m in marks.get_children():
		if m is MeshInstance3D and m.has_meta("pulse"):
			var mat: StandardMaterial3D = m.material_override
			var c: Color = m.get_meta("pulse")
			mat.albedo_color = Color(c.r, c.g, c.b, a)


# ------------------------------------------------------------------ ambiente

func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#0d1a20")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#d9c6a0")
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color("#16252b")
	env.fog_density = 0.012
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffe1b0")
	sun.light_energy = 0.8
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#8fb4d6")
	fill.light_energy = 0.15
	fill.rotation_degrees = Vector3(-30, 150, 0)
	add_child(fill)
	cam = Camera3D.new()
	cam.fov = 45.0
	cam.near = 0.1
	cam.far = 200.0
	add_child(cam)
	cam.current = true
	# mare sotto il tabellone
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(90, 90)
	sea.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = load("res://assets/board/sea.jpg")
	sm.uv1_scale = Vector3(14, 14, 1)
	sm.albedo_color = Color(0.62, 0.72, 0.78)
	sm.roughness = 0.35
	sm.metallic_specular = 0.6
	sea.material_override = sm
	sea.position = Vector3(0, -0.02, 0)
	add_child(sea)


# ------------------------------------------------------------------ esagoni

func world(k: String) -> Vector3:
	var p: Vector2 = eng.hpos(k) - center2
	return Vector3(p.x, 0, p.y)


func top_y(k: String) -> float:
	var t: String = eng.ter(k)
	if t == "":
		return TOP + 0.05
	if t == "sea":
		return SEA_TOP
	return TOP


func _build_hexes() -> void:
	var c := Vector2.ZERO
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for k in eng.hexes:
		var p: Vector2 = eng.hpos(k)
		c += p
		mn = mn.min(p)
		mx = mx.max(p)
	center2 = c / eng.hexes.size()
	bounds = Rect2(mn - center2, mx - mn)
	_refresh_hexes()


func _refresh_hexes() -> void:
	for k in eng.hexes:
		var h: Dictionary = eng.hexes[k]
		var reg: Dictionary = eng.regions[h["reg"]]
		var pv: Dictionary = preview.get(h["reg"], {})
		var sig := "%s|%s|%s|%s" % [h["ter"], reg["tile"], str(h["exhausted"]), str(pv)]
		if hex_state.get(k, "") == sig:
			continue
		hex_state[k] = sig
		if hex_nodes.has(k):
			hex_nodes[k].queue_free()
		var mi := MeshInstance3D.new()
		var tex_path := "res://assets/tiles/back.jpg"
		var theta := 0.0
		if reg["revealed"] or not pv.is_empty():
			var slots: Dictionary = reg["slots"] if pv.is_empty() else reg["orients"][pv["oi"]]["slots"]
			var tile: String = reg["tile"] if pv.is_empty() else pv["tile"]
			var slot := ""
			for s in slots:
				if slots[s] == k:
					slot = s
			tex_path = "res://assets/tiles/%s_%s.jpg" % [tile, slot]
			theta = reg["theta"] if pv.is_empty() else reg["orients"][pv["oi"]]["theta"]
		mi.mesh = _hex_mesh(top_y(k), theta)
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(tex_path)
		m.roughness = 0.85 if h["ter"] != "sea" else 0.3
		if h["ter"] == "sea":
			m.metallic_specular = 0.7
		if not reg["revealed"] and pv.is_empty():
			m.albedo_color = Color(0.82, 0.74, 0.6)
		elif h["ter"] == "plains" or (not pv.is_empty()):
			m.albedo_color = Color(0.86, 0.86, 0.8)
		mi.material_override = m
		mi.position = world(k)
		add_child(mi)
		hex_nodes[k] = mi


## Prisma esagonale (punta piatta). La faccia superiore prende la texture ruotata di theta.
func _hex_mesh(h: float, theta: float) -> ArrayMesh:
	var key := "%.3f|%.4f" % [h, theta]
	if meshes.has(key):
		return meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := 0.985
	var pts := []
	for i in 6:
		var a := deg_to_rad(60.0 * i)
		pts.append(Vector2(cos(a), sin(a)) * r)
	var ct := cos(-theta)
	var sn := sin(-theta)
	var uv_of := func(p: Vector2) -> Vector2:
		var q := Vector2(p.x * ct - p.y * sn, p.x * sn + p.y * ct)
		return q / 2.0 + Vector2(0.5, 0.5)
	for i in 6:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % 6]
		st.set_normal(Vector3.UP)
		st.set_uv(uv_of.call(Vector2.ZERO))
		st.add_vertex(Vector3(0, h, 0))
		st.set_uv(uv_of.call(a))
		st.add_vertex(Vector3(a.x, h, a.y))
		st.set_uv(uv_of.call(b))
		st.add_vertex(Vector3(b.x, h, b.y))
		# fianco
		var nrm := Vector3((a.x + b.x) / 2.0, 0, (a.y + b.y) / 2.0).normalized()
		st.set_normal(nrm)
		st.set_uv(Vector2(0.02, 0.02))
		st.add_vertex(Vector3(a.x, h, a.y))
		st.add_vertex(Vector3(b.x, 0, b.y))
		st.add_vertex(Vector3(b.x, h, b.y))
		st.add_vertex(Vector3(a.x, h, a.y))
		st.add_vertex(Vector3(a.x, 0, a.y))
		st.add_vertex(Vector3(b.x, 0, b.y))
	var m := st.commit()
	meshes[key] = m
	return m


# ------------------------------------------------------------------ pezzi

func _model(name: String) -> Mesh:
	if not meshes.has(name):
		meshes[name] = load("res://assets/models/%s.obj" % name)
	return meshes[name]


func _mat(name: String, col: Color, tinted := true) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [name, col.to_html(), str(tinted)]
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/models/%s.jpg" % name)
	if tinted:
		m.albedo_color = col.lightened(0.15)
	m.roughness = 0.55
	mats[key] = m
	return m


## Istanza di un modello, scalata all'altezza voluta e appoggiata a terra.
func piece(name: String, col: Color, height: float, tinted := true) -> Node3D:
	var root := Node3D.new()
	var mesh := _model(name)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(name, col, tinted)
	var bb := mesh.get_aabb()
	var s := height / maxf(0.001, bb.size.y)
	var maxw := maxf(bb.size.x, bb.size.z) * s
	if maxw > height * 1.6:
		s *= height * 1.6 / maxw
	mi.scale = Vector3(s, s, s)
	mi.position = -Vector3(bb.position.x + bb.size.x / 2.0, bb.position.y, bb.position.z + bb.size.z / 2.0) * s
	root.add_child(mi)
	return root


func _sprite(path: String, size: float) -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = load(path)
	sp.pixel_size = size / maxf(1.0, float(sp.texture.get_width()))
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.no_depth_test = false
	sp.shaded = false
	return sp


func refresh() -> void:
	if eng == null:
		return
	_refresh_hexes()
	for ch in pieces.get_children():
		ch.queue_free()
	# città
	for id in eng.cities:
		var c: Dictionary = eng.cities[id]
		var base := world(c["h"]) + Vector3(0, top_y(c["h"]), 0)
		var col: Color = UI.pcol(c["o"])
		var st := piece("settlement", col, 0.6)
		st.position = base + Vector3(0, 0, 0.05)
		pieces.add_child(st)
		# posti attorno all'insediamento per edifici e meraviglie (il porto va verso il mare)
		var ring_slots := []
		for i in 6:
			var a := -PI * 0.5 - 0.6 + i * TAU / 6.0
			ring_slots.append(Vector3(cos(a), 0, sin(a)) * 0.46)
		var si := 0
		for b in c["b"]:
			var bc: Color = UI.pcol(c["b"][b])
			var off: Vector3 = Vector3.ZERO
			if b != "port":
				off = ring_slots[si % 6]
				si += 1
			if b == "port" and c["port"] != "":
				var d: Vector3 = (world(c["port"]) - world(c["h"])).normalized()
				off = d * 0.72
			var bp := piece(b, bc, 0.48)
			bp.position = base + off
			if b == "port" and c["port"] != "":
				bp.position.y = SEA_TOP
				bp.look_at_from_position(bp.position, bp.position + (world(c["port"]) - world(c["h"])), Vector3.UP)
			pieces.add_child(bp)
		for i in c["w"].size():
			var wp := piece(c["w"][i], Color.WHITE, 0.75, false)
			wp.position = base + ring_slots[(si + i) % 6] * 1.1
			pieces.add_child(wp)
		if c["mood"] != 1:
			var sp := _sprite("res://assets/tokens/%s.png" % ("happy" if c["mood"] == 2 else "angry"), 0.32)
			sp.position = base + Vector3(0, 0.75, 0.05)
			pieces.add_child(sp)
		# anello del colore del proprietario
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.24
		tm.outer_radius = 0.29
		ring.mesh = tm
		var rm := StandardMaterial3D.new()
		rm.albedo_color = col
		rm.emission_enabled = true
		rm.emission = col * 0.4
		ring.material_override = rm
		ring.position = base + Vector3(0, 0.01, 0.05)
		pieces.add_child(ring)
	# segnalini terra esausta
	for k in eng.hexes:
		if eng.hexes[k]["exhausted"]:
			var sp2 := Sprite3D.new()
			sp2.texture = load("res://assets/tokens/exhausted.png")
			sp2.pixel_size = 0.5 / sp2.texture.get_width()
			sp2.rotation_degrees = Vector3(-90, 0, 0)
			sp2.position = world(k) + Vector3(0.45, top_y(k) + 0.01, 0.3)
			pieces.add_child(sp2)
	# unità
	var by_hex := {}
	for id in eng.units:
		var u: Dictionary = eng.units[id]
		if not by_hex.has(u["h"]):
			by_hex[u["h"]] = []
		by_hex[u["h"]].append(u)
	for k in by_hex:
		var lst: Array = by_hex[k]
		lst.sort_custom(func(a, b): return a["id"] < b["id"])
		var has_city: bool = not eng.city_at(k).is_empty()
		var n := lst.size()
		var base2 := world(k) + Vector3(0, top_y(k), 0)
		for i in n:
			var u: Dictionary = lst[i]
			var ang := TAU * i / maxf(1, n) + 0.5
			var rad := 0.0 if (n == 1 and not has_city) else (0.62 if has_city else 0.38)
			var off := Vector3(cos(ang), 0, sin(ang)) * rad
			var model: String = u["t"]
			var hgt: float = {"settler": 0.5, "infantry": 0.55, "ship": 0.5, "cavalry": 0.6, "elephant": 0.62, "leader": 0.66}.get(model, 0.55)
			var pc := piece(model, UI.pcol(u["o"]), hgt)
			pc.position = base2 + off
			if u["on"] != -1:
				pc.position.y += 0.12
				pc.scale = Vector3(0.8, 0.8, 0.8)
			pc.rotation.y = ang
			pieces.add_child(pc)
	_refresh_marks()


# ------------------------------------------------------------------ evidenziazioni

## t: chiave -> colore
func set_targets(t: Dictionary) -> void:
	targets = t
	_refresh_marks()


func set_preview(pv: Dictionary) -> void:
	preview = pv
	_refresh_hexes()


func set_selected(k: String) -> void:
	selected = k
	_refresh_marks()


func _ring_mesh() -> ArrayMesh:
	if meshes.has("_ring"):
		return meshes["_ring"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 6:
		var a0 := deg_to_rad(60.0 * i)
		var a1 := deg_to_rad(60.0 * (i + 1))
		var o0 := Vector3(cos(a0), 0, sin(a0)) * 0.97
		var o1 := Vector3(cos(a1), 0, sin(a1)) * 0.97
		var i0 := o0 * 0.82
		var i1 := o1 * 0.82
		st.set_normal(Vector3.UP)
		st.add_vertex(o0)
		st.add_vertex(i1)
		st.add_vertex(o1)
		st.add_vertex(o0)
		st.add_vertex(i0)
		st.add_vertex(i1)
	var m := st.commit()
	meshes["_ring"] = m
	return m


func _refresh_marks() -> void:
	for ch in marks.get_children():
		ch.queue_free()
	for k in targets:
		_mark(k, targets[k], true)
	if selected != "" and eng.hexes.has(selected):
		_mark(selected, Color("#fff4c8"), false)


func _mark(k: String, col: Color, pulse: bool) -> void:
	if not eng.hexes.has(k):
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 2
	mi.material_override = m
	mi.position = world(k) + Vector3(0, top_y(k) + 0.02, 0)
	if pulse:
		mi.set_meta("pulse", col)
	marks.add_child(mi)


# ------------------------------------------------------------------ input e telecamera

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			touches[ev.index] = ev.position
		else:
			touches.erase(ev.index)
		if touches.size() == 2:
			var v: Array = touches.values()
			pinch_d = (v[0] as Vector2).distance_to(v[1])
		return
	if ev is InputEventScreenDrag:
		touches[ev.index] = ev.position
		if touches.size() == 2:
			var v2: Array = touches.values()
			var d := (v2[0] as Vector2).distance_to(v2[1])
			if pinch_d > 0:
				t_dist = clampf(t_dist * pinch_d / d, 5.0, 40.0)
			pinch_d = d
		return
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			t_dist = clampf(t_dist * 0.9, 5.0, 40.0)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			t_dist = clampf(t_dist * 1.1, 5.0, 40.0)
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				dragging = true
				drag_moved = 0.0
				panning = ev.shift_pressed
				last_mouse = ev.position
			else:
				if dragging and drag_moved < 8.0 and touches.size() < 2:
					var k := pick(ev.position)
					if k != "":
						hex_clicked.emit(k)
				dragging = false
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			panning = ev.pressed
			dragging = ev.pressed
			drag_moved = 99.0
			last_mouse = ev.position
	elif ev is InputEventMouseMotion:
		if dragging and touches.size() < 2:
			var dlt: Vector2 = ev.position - last_mouse
			last_mouse = ev.position
			drag_moved += dlt.length()
			if drag_moved < 8.0:
				return
			if panning:
				var right := cam.global_transform.basis.x
				var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
				t_target += (-right * dlt.x + fwd * dlt.y) * t_dist * 0.0018
				t_target.x = clampf(t_target.x, bounds.position.x - 2, bounds.end.x + 2)
				t_target.z = clampf(t_target.z, bounds.position.y - 2, bounds.end.y + 2)
			else:
				t_yaw -= dlt.x * 0.006
				t_pitch = clampf(t_pitch + dlt.y * 0.004, 0.35, 1.45)
		else:
			var k2 := pick(ev.position)
			if k2 != hover:
				hover = k2
				hex_hovered.emit(k2)


func pick(pos: Vector2) -> String:
	var from := cam.project_ray_origin(pos)
	var dir := cam.project_ray_normal(pos)
	if absf(dir.y) < 1e-4:
		return ""
	var t := -(from.y - TOP) / dir.y
	var p := from + dir * t
	var best := ""
	var bd := 1.0
	for k in eng.hexes:
		var w := world(k)
		var d := Vector2(w.x - p.x, w.z - p.z).length()
		if d < bd:
			bd = d
			best = k
	return best


func reset_view() -> void:
	t_target = Vector3(0.3, 0, 1.4)
	t_yaw = 0.0
	t_pitch = 0.92
	t_dist = maxf(bounds.size.x, bounds.size.y) * 1.0 + 2.0
	yaw = t_yaw
	pitch = t_pitch
	dist = t_dist
	target = t_target


func zoom(f: float) -> void:
	t_dist = clampf(t_dist * f, 5.0, 40.0)


func rotate_by(a: float) -> void:
	t_yaw += a


func top_view() -> void:
	t_pitch = 1.45 if t_pitch < 1.3 else 0.95


func focus(k: String) -> void:
	if eng.hexes.has(k):
		t_target = world(k)
		t_dist = minf(t_dist, 12.0)


## Posizione sullo schermo di una casella (per i fumetti dell'interfaccia).
func screen_pos(k: String) -> Vector2:
	if not eng.hexes.has(k):
		return Vector2(-1000, -1000)
	return cam.unproject_position(world(k) + Vector3(0, 0.5, 0))
