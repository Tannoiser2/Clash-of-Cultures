extends Control
## Menu principale: il dipinto della scatola, le civiltà al tavolo (Umano / IA / Assente) con il
## livello e lo stile dell'IA, le opzioni, il gioco online e le regole.

const D = preload("res://scripts/data/coc_data.gd")
const MODES := ["Umano", "IA", "Assente"]
const LEVELS := ["Facile", "Normale", "Difficile"]
const AI = preload("res://scripts/core/ai.gd")
## stili dell'IA: "random" li sceglie a caso all'inizio della partita
const STYLE_KEYS := ["random", "balanced", "aggressive", "defensive", "builder", "seafarer"]
const NAMES := ["Roma", "Persia", "Egitto", "Cartagine"]

var main
var seat_mode := [0, 1, 1, 2]
var levels := [1, 1, 1, 1]
var styles := ["random", "random", "random", "random"]
var names := NAMES.duplicate()
var speed := 1
var mods := {}
var msg: Label
var rows: VBoxContainer

const MOD_LIST := [
	["civ", "Espansione Civiltà", "Ogni giocatore guida una civiltà (Roma, Egitto, Cina…) con 4 avanzamenti propri e 3 Leader. Aggiunge Cavalleria, Elefanti, Mercati, Obelischi, Osservatori, i Pirati, 20 eventi e 6 obiettivi."],
	["short", "Partita breve (4 ere)", "Variante del regolamento: 4 ere invece di 6, due avanzamenti gratuiti in ogni fase di status."],
	["no_events", "Eventi solo con le icone", "Variante del regolamento: delle carte Evento si applica solo l'icona in alto (oro, terreno improduttivo, barbari), non il testo."],
]


func _ready() -> void:
	size = Vector2(1920, 1080)
	if main.menu_state.has("seat_mode"):
		seat_mode = main.menu_state["seat_mode"].duplicate()
		levels = main.menu_state["levels"].duplicate()
		styles = main.menu_state.get("styles", styles).duplicate()
		names = main.menu_state["names"].duplicate()
		speed = main.menu_state["speed"]
		mods = main.menu_state.get("mods", {}).duplicate()
	var bg := TextureRect.new()
	bg.texture = UI.tex("res://assets/ui/stone.jpg")
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.size = Vector2(1920, 1080)
	add_child(bg)
	var art := TextureRect.new()
	art.texture = UI.tex("res://assets/ui/cover.jpg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.position = Vector2(900, 0)
	art.size = Vector2(1020, 1080)
	add_child(art)
	var fade := TextureRect.new()
	var fg := GradientTexture2D.new()
	var g2 := Gradient.new()
	g2.set_color(0, Color(0.1, 0.07, 0.045, 1.0))
	g2.set_color(1, Color(0.1, 0.07, 0.045, 0.0))
	fg.gradient = g2
	fg.fill_from = Vector2(0, 0)
	fg.fill_to = Vector2(1, 0)
	fade.texture = fg
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.position = Vector2(900, 0)
	fade.size = Vector2(380, 1080)
	add_child(fade)
	var t := UI.label("Clash of Cultures", 76, UI.GOLD, UI.font_deco)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	t.add_theme_constant_override("shadow_offset_x", 3)
	t.add_theme_constant_override("shadow_offset_y", 3)
	t.position = Vector2(70, 26)
	add_child(t)
	var tag := UI.label("Lo scontro delle civiltà antiche — Monumental Edition", 26, UI.PARCH, UI.font_italic)
	tag.position = Vector2(80, 128)
	add_child(tag)

	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.paper(30))
	box.position = Vector2(70, 190)
	box.custom_minimum_size = Vector2(800, 0)
	add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	box.add_child(vb)
	vb.add_child(UI.title("Le civiltà al tavolo", 30, UI.INK))
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	vb.add_child(rows)
	_refresh_rows()
	var sp := HBoxContainer.new()
	sp.add_theme_constant_override("separation", 8)
	sp.add_child(UI.label("Velocità dell'IA:", 20, UI.INK, UI.font_bold))
	for i in 4:
		var b := UI.button(["Calma", "Normale", "Rapida", "Lampo"][i], 120, 40, 15)
		if i == speed:
			UI.primary(b)
		var ii := i
		b.pressed.connect(func():
			speed = ii
			_store()
			main.show_menu())
		sp.add_child(b)
	vb.add_child(sp)
	for m in MOD_LIST:
		var cb := CheckBox.new()
		cb.text = m[1]
		cb.tooltip_text = m[2]
		cb.button_pressed = mods.get(m[0], false)
		cb.add_theme_color_override("font_color", UI.INK)
		cb.add_theme_color_override("font_hover_color", UI.TERRA)
		cb.add_theme_color_override("font_pressed_color", UI.INK)
		cb.add_theme_font_size_override("font_size", 19)
		var key: String = m[0]
		cb.toggled.connect(func(on): mods[key] = on)
		vb.add_child(cb)
	msg = UI.label("", 19, UI.TERRA, UI.font_bold)
	vb.add_child(msg)

	var btns := VBoxContainer.new()
	btns.position = Vector2(70, 830)
	btns.add_theme_constant_override("separation", 12)
	add_child(btns)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 14)
	btns.add_child(row1)
	var play := _big_button("Gioca", 260, true)
	play.pressed.connect(_on_start)
	row1.add_child(play)
	var onl := _big_button("Gioca online", 300)
	onl.pressed.connect(_online_panel)
	row1.add_child(onl)
	var rul := _big_button("Regole", 220)
	rul.pressed.connect(func():
		_store()
		main.show_rules())
	row1.add_child(rul)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 14)
	btns.add_child(row2)
	row2.add_child(Audio.toggle_button("music", 170, 42))
	row2.add_child(Audio.toggle_button("sfx", 170, 42))
	var cr := UI.label("Clash of Cultures © Christian Marcussen / Lautapelit.fi. Adattamento per uso personale.", 15, UI.PARCH.darkened(0.2))
	row2.add_child(cr)
	var ses: Dictionary = main.get_net().load_session()
	if str(ses.get("room", "")) != "":
		_online_panel()


func _refresh_rows() -> void:
	for ch in rows.get_children():
		ch.queue_free()
	for i in 4:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		var dot := ColorRect.new()
		dot.color = D.COLORS[i]["col"]
		dot.custom_minimum_size = Vector2(26, 26)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(dot)
		var le := LineEdit.new()
		le.text = names[i]
		le.max_length = 16
		le.custom_minimum_size = Vector2(190, 42)
		var ii := i
		le.text_changed.connect(func(t2): names[ii] = t2)
		le.editable = seat_mode[i] != 2
		hb.add_child(le)
		for m in 3:
			var b := UI.button(MODES[m], 100, 42, 15)
			if seat_mode[i] == m:
				UI.primary(b)
			var mm := m
			b.pressed.connect(func():
				seat_mode[ii] = mm
				_refresh_rows())
			hb.add_child(b)
		if seat_mode[i] == 1:
			var lv := UI.button(LEVELS[levels[i]], 120, 42, 15)
			lv.tooltip_text = "Livello dell'IA (clicca per cambiarlo)"
			lv.pressed.connect(func():
				levels[ii] = (levels[ii] + 1) % 3
				_refresh_rows())
			hb.add_child(lv)
			var sk: String = styles[i]
			var st := UI.button("Stile casuale" if sk == "random" else AI.STYLES[sk]["it"], 170, 42, 15)
			st.tooltip_text = ("Stile dell'IA (clicca per cambiarlo): " + ("ne sceglie uno a caso all'inizio della partita." if sk == "random" else AI.STYLE_TEXT[sk]))
			st.pressed.connect(func():
				styles[ii] = STYLE_KEYS[(STYLE_KEYS.find(styles[ii]) + 1) % STYLE_KEYS.size()]
				_refresh_rows())
			hb.add_child(st)
		rows.add_child(hb)


func _store() -> void:
	main.menu_state = {"seat_mode": seat_mode.duplicate(), "levels": levels.duplicate(), "styles": styles.duplicate(), "names": names.duplicate(),
		"speed": speed, "mods": mods.duplicate()}


func _big_button(text: String, w: float, primary := false) -> Button:
	var b := UI.button(text, w, 64, 26)
	if primary:
		UI.primary(b)
	return b


## Configurazione scelta nel menu (anche quella che, online, viaggia agli altri).
func _config() -> Dictionary:
	var seats := []
	for i in 4:
		var m: int = seat_mode[i]
		if m == 2:
			continue
		var nm: String = names[i].strip_edges()
		if nm == "":
			nm = D.COLORS[i]["name"]
		seats.append({"color": i, "ai": m == 1, "name": nm, "level": levels[i], "style": styles[i]})
	var speeds := [1.1, 0.6, 0.2, 0.0]
	var o := {}
	for m in MOD_LIST:
		if mods.get(m[0], false):
			o[m[0]] = true
	return {"seats": seats, "ai_delay": speeds[speed], "opts": o}


func _on_start() -> void:
	var cfg := _config()
	if cfg["seats"].size() < 2:
		msg.text = "Clash of Cultures si gioca da 2 a 4: metti al tavolo almeno 2 civiltà."
		return
	_store()
	main.start_game(cfg)


# =================================================================== online

var on_panel: Control
var on_name: LineEdit
var on_code: LineEdit
var on_lbl: Label
var on_start: Button


func _online_panel() -> void:
	if is_instance_valid(on_panel):
		on_panel.queue_free()
	on_panel = Control.new()
	on_panel.size = Vector2(1920, 1080)
	on_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(on_panel)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.12, 0.13, 0.78)
	shade.size = on_panel.size
	on_panel.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.paper(34))
	box.position = Vector2(560, 130)
	box.custom_minimum_size = Vector2(800, 0)
	on_panel.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	box.add_child(vb)
	vb.add_child(UI.title("Gioca online", 44, UI.INK))
	var info := UI.label("Chi crea la stanza sceglie prima nel menu le civiltà, le opzioni e il livello dell'IA: i colori su Umano diventano i posti per gli amici (il primo è il suo). Gli amici entrano con il codice. I posti rimasti liberi li gioca l'IA.", 21, UI.INK2)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(760, 0)
	vb.add_child(info)
	var ses: Dictionary = main.get_net().load_session()
	on_name = _line("Il tuo nome", 20)
	on_name.text = str(ses.get("name", ""))
	vb.add_child(on_name)
	var b_create := Button.new()
	b_create.text = "Crea una stanza"
	UI.primary(b_create)
	b_create.custom_minimum_size = Vector2(0, 60)
	b_create.add_theme_font_size_override("font_size", 24)
	b_create.pressed.connect(_online_create)
	vb.add_child(b_create)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	on_code = _line("Codice", 4)
	on_code.custom_minimum_size.x = 220
	on_code.text_changed.connect(func(t):
		on_code.text = t.to_upper()
		on_code.caret_column = t.length())
	row.add_child(on_code)
	var b_join := Button.new()
	b_join.text = "Entra"
	UI.primary(b_join)
	b_join.custom_minimum_size = Vector2(200, 60)
	b_join.add_theme_font_size_override("font_size", 24)
	b_join.pressed.connect(_online_join)
	row.add_child(b_join)
	vb.add_child(row)
	on_lbl = UI.label("", 21, UI.INK)
	on_lbl.custom_minimum_size = Vector2(760, 120)
	on_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(on_lbl)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	on_start = _big_button("Si comincia!", 360, true)
	on_start.pressed.connect(_online_start)
	on_start.visible = main.lobby.get("role", "") == "host"
	row2.add_child(on_start)
	var b_close := _big_button("Indietro", 260)
	b_close.pressed.connect(func():
		on_panel.queue_free())
	row2.add_child(b_close)
	vb.add_child(row2)
	if not main.lobby.is_empty():
		on_code.text = main.lobby["code"]
		on_lbl.text = "Stanza %s…" % main.lobby["code"]
	elif str(ses.get("room", "")) != "":
		on_code.text = str(ses["room"])
		on_lbl.text = "Eri nella stanza %s: premi Entra per rientrare." % ses["room"]


func _line(ph: String, maxlen: int) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = ph
	le.max_length = maxlen
	le.custom_minimum_size = Vector2(0, 60)
	le.add_theme_font_size_override("font_size", 24)
	return le


func _say(t: String) -> void:
	if is_instance_valid(on_lbl):
		on_lbl.text = t


func _seat_list() -> Array:
	return _config()["seats"]


func _seats_text(room: Dictionary) -> String:
	var seats := Net._as_dict(room.get("seats", {}))
	var list := _seat_list()
	var parts := []
	for idx in room.get("open", []):
		var k := str(int(idx))
		var who := str(seats[k].get("name", "?")) if seats.has(k) and seats[k] is Dictionary else "libero"
		var cname: String = list[int(idx)]["name"] if int(idx) < list.size() else "posto %d" % (int(idx) + 1)
		parts.append("%s: %s" % [cname, who])
	return ", ".join(parts)


func _online_create() -> void:
	var nm := on_name.text.strip_edges()
	if nm == "":
		_say("Scrivi il tuo nome.")
		return
	var seats := []
	var list := _seat_list()
	for i in list.size():
		if not list[i]["ai"]:
			seats.append(i)
	if list.size() < 2 or seats.size() < 2:
		_say("Servono almeno 2 civiltà su Umano: la prima è la tua, le altre sono i posti per gli amici.")
		return
	_store()
	_say("Creo la stanza…")
	var net: Net = main.get_net()
	var code := await net.create_room(nm, seats)
	if code == "":
		_say("Non riesco a creare la stanza.\n%s" % net.last_error)
		return
	main.lobby = {"role": "host", "code": code, "seat": seats[0]}
	net.remember_room(code, seats[0])
	net._save({"name": nm})
	if is_instance_valid(on_code):
		on_code.text = code
	if is_instance_valid(on_start):
		on_start.visible = true
	_lobby_poll(code)


func _online_join() -> void:
	var code := on_code.text.strip_edges().to_upper()
	var nm := on_name.text.strip_edges()
	if nm == "" or code.length() != 4:
		_say("Scrivi il tuo nome e il codice di 4 lettere.")
		return
	_say("Entro nella stanza %s…" % code)
	var net: Net = main.get_net()
	var seat := await net.join_room(code, nm)
	if seat == -2:
		_say("Stanza %s non trovata, oppure la partita è già iniziata.%s" % [code, ("\n" + net.last_error) if net.last_error != "" else ""])
		return
	if seat == -1:
		_say("Nella stanza %s non ci sono posti liberi." % code)
		return
	var room: Dictionary = net.last_room
	main.lobby = {"role": "host" if room.get("host", "") == net.uid else "guest", "code": code, "seat": seat}
	net.remember_room(code, seat)
	net._save({"name": nm})
	if room.get("status", "") in ["playing", "over"] and room.has("game"):
		_say("Rientro nella partita della stanza %s…" % code)
		_begin(room["game"], true)
		return
	if is_instance_valid(on_start):
		on_start.visible = main.lobby["role"] == "host"
	_lobby_poll(code)


func _lobby_poll(code: String) -> void:
	var net: Net = main.get_net()
	while is_inside_tree() and main.lobby.get("code", "") == code:
		var room := await net.room(code)
		if not is_inside_tree() or main.lobby.get("code", "") != code:
			return
		if room.is_empty():
			_say("La stanza %s non esiste più." % code)
			main.lobby = {}
			return
		if main.lobby["role"] == "host":
			_say("Stanza [ %s ]: dai il codice ai tuoi amici.\nPosti: %s.\nQuando ci siete tutti premi Si comincia!: i posti liberi li gioca l'IA." % [code, _seats_text(room)])
		else:
			if room.get("status", "") == "playing" and room.has("game"):
				_begin(room["game"], false)
				return
			_say("Sei nella stanza [ %s ] (posto %d).\nPosti: %s.\nAspetta che chi l'ha creata avvii la partita." % [code, int(main.lobby["seat"]) + 1, _seats_text(room)])
		await get_tree().create_timer(2.0).timeout


## Chi ha creato la stanza avvia: colori, opzioni e seme valgono per tutti.
func _online_start() -> void:
	var code: String = main.lobby["code"]
	var net: Net = main.get_net()
	var room := await net.room(code)
	if room.is_empty():
		_say("La stanza %s non esiste più." % code)
		main.lobby = {}
		return
	var seats_db := Net._as_dict(room.get("seats", {}))
	var cfg := _config()
	var my_seat := int(main.lobby["seat"])
	if my_seat >= cfg["seats"].size() or not seats_db.has(str(my_seat)) or cfg["seats"][my_seat]["ai"]:
		_say("Hai cambiato i colori dopo aver creato la stanza: creane una nuova.")
		return
	for i in cfg["seats"].size():
		var k := str(i)
		if seats_db.has(k) and seats_db[k] is Dictionary and not cfg["seats"][i]["ai"]:
			cfg["seats"][i]["name"] = "%s" % str(seats_db[k].get("name", cfg["seats"][i]["name"]))
		else:
			cfg["seats"][i]["ai"] = true
	cfg["seed"] = 1 + randi() % 2000000000
	var g := {"cfg": var_to_str(cfg)}
	if not await net.start_room(code, g):
		_say("Non riesco ad avviare la partita (%s)." % net.last_error)
		return
	_begin(g, false)


## Avvio (o rientro) della partita online.
func _begin(g: Dictionary, rejoin: bool) -> void:
	var net: Net = main.get_net()
	var lob: Dictionary = main.lobby
	var backlog: Array = []
	if rejoin:
		backlog = await net.get_acts(lob["code"])
		net.set_away(lob["code"], int(lob["seat"]), false)
	var cfg = str_to_var(str(g.get("cfg", "")))
	if not (cfg is Dictionary):
		_say("Configurazione della partita non valida.")
		return
	var ses := OnlineSession.new()
	ses.setup(net, lob["code"], int(lob["seat"]), lob["role"], backlog)
	cfg["online"] = ses
	main.lobby = {}
	main.start_game(cfg)
