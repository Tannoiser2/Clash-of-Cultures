extends Control
## Vista di gioco: la mappa 3D al centro, le civiltà a sinistra, cronaca e dettagli della casella
## a destra, le azioni in basso. Si clicca una casella per vederla e agire: città (raccogli,
## costruisci, recluta, meraviglie), coloni (fonda), unità (muovi).

const D = preload("res://scripts/data/coc_data.gd")
const LW := 340.0
const RX := 1570.0
const RW := 340.0

var main
var config: Dictionary
var engine
var online = null
var humans: Array = []
var pending: Dictionary = {}
var board: Board3D
var sel := ""
var move_sel := []          # unità scelte per il movimento
var last_human := -1

var top_lbl: Label
var turn_lbl: RichTextLabel
var rows_box: VBoxContainer
var chron: RichTextLabel
var info_box: VBoxContainer
var bar: PanelContainer
var bar_title: RichTextLabel
var bar_btns: HFlowContainer
var modal: Control
var toast_box: VBoxContainer
var dice_panel: PanelContainer
var online_lbl: Label
var tip: PanelContainer
var tip_lbl: Label
var hex_choice := {}        # casella -> indice dell'opzione nella scelta in corso
var refresh_queued := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	online = config.get("online", null)
	engine = load("res://scripts/core/engine.gd").new()
	add_child(engine)
	engine.setup(config)
	engine.ai_delay = config.get("ai_delay", 0.6)
	if online != null:
		humans = [online.seat]
		online.view = self
		add_child(online)
		engine.online = online
		if online.role != "host":
			online.heartbeat_loop()
	else:
		for p in engine.n:
			if not engine.players[p]["ai"]:
				humans.append(p)
	board = Board3D.new()
	board.eng = engine
	add_child(board)
	board.hex_clicked.connect(_on_hex)
	board.hex_hovered.connect(_on_hover)
	_build_top()
	_build_left()
	_build_right()
	_build_bar()
	_build_cam()
	toast_box = VBoxContainer.new()
	toast_box.position = Vector2(LW + 40, 80)
	toast_box.size = Vector2(500, 10)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_box)
	dice_panel = PanelContainer.new()
	dice_panel.add_theme_stylebox_override("panel", UI.stone(0.95, UI.GOLD))
	dice_panel.visible = false
	dice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dice_panel)
	modal = Control.new()
	modal.size = Vector2(1920, 1080)
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal)
	tip = PanelContainer.new()
	tip.add_theme_stylebox_override("panel", UI.flat(Color("#21170f"), UI.GOLD, 1, 4, 8))
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_lbl = UI.label("", 16, UI.LIGHT)
	tip.add_child(tip_lbl)
	tip.visible = false
	add_child(tip)
	_build_online_label()
	engine.changed.connect(_queue_refresh)
	engine.log_added.connect(_on_log)
	engine.decision_requested.connect(_on_decision)
	engine.fx.connect(_on_fx)
	engine.game_ended.connect(_on_game_end)
	refresh()
	_start.call_deferred()


func _start() -> void:
	if online != null and not online.backlog.is_empty():
		Audio.suspended = true
	await engine.run()


func _exit_tree() -> void:
	if engine != null:
		engine.abort = true


func _queue_refresh() -> void:
	if refresh_queued:
		return
	refresh_queued = true
	_do_refresh.call_deferred()


func _do_refresh() -> void:
	refresh_queued = false
	refresh()


func refresh() -> void:
	board.refresh()
	_refresh_top()
	_refresh_rows()
	_refresh_info()
	_refresh_bar()


# ------------------------------------------------------------------ costruzione dell'interfaccia

func _panel(pos: Vector2, sz: Vector2, alpha := 0.9) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.size = sz
	p.add_theme_stylebox_override("panel", UI.stone(alpha))
	add_child(p)
	return p


func _build_top() -> void:
	var p := _panel(Vector2(LW + 20, 8), Vector2(1920 - 2 * LW - 40 - 10, 60), 0.88)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	p.add_child(hb)
	top_lbl = UI.title("Era I", 24, UI.GOLD)
	top_lbl.custom_minimum_size = Vector2(260, 0)
	hb.add_child(top_lbl)
	turn_lbl = UI.rich(20)
	turn_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turn_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	hb.add_child(turn_lbl)
	for b in [["Regole", _show_rules], ["Diario", _show_log], ["Suoni", _toggle_audio], ["Menu", _ask_quit]]:
		var bt := UI.button(b[0], 90, 40, 16)
		bt.pressed.connect(b[1])
		hb.add_child(bt)


func _build_left() -> void:
	var p := _panel(Vector2(8, 8), Vector2(LW, 1064), 0.88)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(sc)
	rows_box = VBoxContainer.new()
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_box.add_theme_constant_override("separation", 8)
	sc.add_child(rows_box)


func _build_right() -> void:
	var p := _panel(Vector2(RX, 8), Vector2(RW, 470), 0.88)
	var vb := VBoxContainer.new()
	p.add_child(vb)
	vb.add_child(UI.title("Cronaca", 20))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	chron = UI.rich(15, UI.LIGHT)
	chron.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chron.custom_minimum_size = Vector2(RW - 40, 0)
	sc.add_child(chron)
	chron.set_meta("scroll", sc)
	var p2 := _panel(Vector2(RX, 488), Vector2(RW, 584), 0.9)
	var sc2 := ScrollContainer.new()
	sc2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p2.add_child(sc2)
	info_box = VBoxContainer.new()
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_box.add_theme_constant_override("separation", 6)
	sc2.add_child(info_box)


func _build_bar() -> void:
	bar = PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UI.stone(0.93, UI.GOLD))
	bar.position = Vector2(LW + 20, 948)
	bar.size = Vector2(RX - LW - 30, 124)
	add_child(bar)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	bar.add_child(vb)
	bar_title = UI.rich(19, UI.LIGHT)
	bar_title.custom_minimum_size = Vector2(RX - LW - 60, 0)
	vb.add_child(bar_title)
	bar_btns = HFlowContainer.new()
	bar_btns.add_theme_constant_override("h_separation", 8)
	bar_btns.add_theme_constant_override("v_separation", 8)
	vb.add_child(bar_btns)


func _build_cam() -> void:
	var hb := HBoxContainer.new()
	hb.position = Vector2(RX - 330, 896)
	hb.add_theme_constant_override("separation", 4)
	add_child(hb)
	for b in [["<", func(): board.rotate_by(-0.5)], [">", func(): board.rotate_by(0.5)], ["+", func(): board.zoom(0.85)],
			["-", func(): board.zoom(1.18)], ["Vista", func(): board.top_view()], ["Tutto", func(): board.reset_view()]]:
		var bt := UI.button(b[0], 44 if b[0].length() == 1 else 76, 40, 18)
		bt.pressed.connect(b[1])
		bt.tooltip_text = {"<": "Ruota", ">": "Ruota", "+": "Avvicina", "-": "Allontana", "Vista": "Dall'alto / di lato", "Tutto": "Inquadra tutta la mappa"}[b[0]]
		hb.add_child(bt)


func _build_online_label() -> void:
	online_lbl = UI.label("", 17, UI.GOLD, UI.font_bold)
	online_lbl.position = Vector2(LW + 30, 74)
	online_lbl.visible = online != null
	add_child(online_lbl)


# ------------------------------------------------------------------ aggiornamenti

static func roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI", "VII"][clampi(n, 0, 7)]


func _refresh_top() -> void:
	top_lbl.text = "Era %s · Round %d" % [roman(engine.age), engine.round_no]
	var p: int = engine.cur
	if engine.game_over:
		turn_lbl.text = "[b]Partita finita[/b]"
	elif p >= 0:
		var c: Color = UI.pcol(p)
		var acts := ""
		for i in maxi(0, engine.T.get("actions", 0)):
			acts += "◆ "
		turn_lbl.text = "Turno di [color=#%s][b]%s[/b][/color]   [color=#d8a84e]%s[/color] %s" % [c.lightened(0.3).to_html(false), engine.pname(p), acts, "azioni" if engine.T.get("actions", 0) != 1 else "azione"]
	else:
		turn_lbl.text = "Fase di status"


func _can_see(p: int) -> bool:
	if engine.game_over:
		return true
	if online != null:
		return p == online.seat
	return humans.size() == 1 and humans[0] == p or (humans.size() > 1 and p == last_human)


func _refresh_rows() -> void:
	for ch in rows_box.get_children():
		ch.queue_free()
	for p in engine.n:
		rows_box.add_child(_player_row(p))


func _player_row(p: int) -> Control:
	var pl: Dictionary = engine.players[p]
	var pc := PanelContainer.new()
	var col: Color = UI.pcol(p)
	var st := UI.flat(Color(0.16, 0.11, 0.07, 0.95), col if engine.cur == p else col.darkened(0.4), 3 if engine.cur == p else 2, 8, 10)
	pc.add_theme_stylebox_override("panel", st)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var dot := ColorRect.new()
	dot.color = col
	dot.custom_minimum_size = Vector2(16, 16)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(dot)
	var nm := UI.label(" " + pl["name"] + ("  (IA)" if pl["ai"] else ""), 19, col.lightened(0.45), UI.font_bold)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	hb.add_child(nm)
	if engine.first == p:
		var fp := TextureRect.new()
		fp.texture = UI.tex("res://assets/tokens/first.png")
		fp.custom_minimum_size = Vector2(26, 26)
		fp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fp.tooltip_text = "Primo giocatore"
		hb.add_child(fp)
	var sc: Dictionary = engine.score(p)
	var vp := UI.label("%s PV" % _num(sc["total"]), 19, UI.GOLD, UI.font_bold)
	vp.tooltip_text = "Pezzi di città %d · Avanzamenti %s · Obiettivi %d · Meraviglie %s · Eventi %s" % [sc["pieces"], _num(sc["adv"]), sc["obj"], _num(sc["wonders"]), _num(sc["events"])]
	vp.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.add_child(vp)
	if engine.exp:
		var ck: String = pl.get("civ", "")
		var ld: String = pl.get("leader", "")
		var cl := UI.label("%s · %s" % [CivData.CIVS[ck]["it"], ("Capo: " + CivData.LEADERS[ld][0]) if ld != "" else "nessun Capo"], 15, UI.GOLD)
		cl.clip_text = true
		vb.add_child(cl)
	var rf := HFlowContainer.new()
	rf.add_theme_constant_override("h_separation", 4)
	rf.add_theme_constant_override("v_separation", 4)
	vb.add_child(rf)
	for r in ["food", "wood", "ore", "idea", "gold"]:
		var lim: int = engine.res_limit(p, r)
		rf.add_child(_chip(r, "%d" % pl["res"][r] + ("/%d" % lim if r == "food" and lim < 7 else "")))
	rf.add_child(_chip("mood", str(pl["mood"])))
	rf.add_child(_chip("culture", str(pl["culture"])))
	var info := UI.label("Città %d · Avanzamenti %d · Carte %d · Obiettivi %d (fatti %d)%s" % [engine.cities_of(p).size(), pl["adv"].size(),
		pl["hand"].size(), pl["obj"].size(), pl["done"].size(), (" · Meraviglie in mano %d" % pl["won"].size()) if pl["won"].size() > 0 else ""], 14, UI.PARCH)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(info)
	var trk := UI.label("Segnaeventi: %s" % "■ ".repeat(pl["tracker"]).strip_edges(), 13, UI.PARCH.darkened(0.2))
	trk.tooltip_text = "Quando compri l'avanzamento che svuota il segnaeventi, peschi un Evento."
	trk.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.add_child(trk)
	var hb2 := HBoxContainer.new()
	vb.add_child(hb2)
	var b1 := UI.button("Avanzamenti", 150, 32, 13)
	b1.pressed.connect(func(): _show_advances(p, [], Callable()))
	hb2.add_child(b1)
	if _can_see(p):
		var b2 := UI.button("Carte", 90, 32, 13)
		b2.pressed.connect(func(): _show_cards(p))
		hb2.add_child(b2)
	var b3 := UI.button("Fatti", 70, 32, 13)
	b3.tooltip_text = "Obiettivi completati"
	b3.pressed.connect(func(): _show_done(p))
	hb2.add_child(b3)
	if engine.exp:
		var b4 := UI.button("Civiltà", 90, 32, 13)
		b4.tooltip_text = "Avanzamenti di civiltà e Capi"
		b4.pressed.connect(func(): _show_civ(p))
		hb2.add_child(b4)
	return pc


## Plancia della civiltà: i 4 avanzamenti propri e i 3 Capi.
func _show_civ(p: int) -> void:
	var pl: Dictionary = engine.players[p]
	var ck: String = pl["civ"]
	var civ: Dictionary = CivData.CIVS[ck]
	var vb := _open_modal("%s — %s" % [civ["it"], engine.pname(p)], 1500)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	vb.add_child(hb)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(520, 0)
	left.add_theme_constant_override("separation", 8)
	hb.add_child(left)
	left.add_child(UI.title("Avanzamenti di civiltà", 20, UI.INK))
	var note := UI.label("Si ottengono gratis quando ottieni l'avanzamento indicato fra parentesi.", 14, UI.INK2)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(note)
	for a in civ["adv"]:
		var owned: bool = pl["adv"].has(a[0])
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", UI.flat(Color("#c99a43") if owned else Color("#3a2614"), UI.GOLD_DARK, 1, 6, 8))
		var bvb := VBoxContainer.new()
		box.add_child(bvb)
		var req: String = "un avanzamento di governo" if a[2] == "gov" else D.adv_it(a[2])
		bvb.add_child(UI.label("%s  (%s)%s" % [a[1], req, "  ✓" if owned else ""], 17, UI.DARK if owned else UI.GOLD, UI.font_bold))
		var tx := UI.label(a[3], 14, UI.DARK if owned else UI.PARCH)
		tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tx.custom_minimum_size = Vector2(500, 0)
		bvb.add_child(tx)
		left.add_child(box)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	hb.add_child(right)
	right.add_child(UI.title("Capi", 20, UI.INK))
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 12)
	right.add_child(lrow)
	for code in civ["leaders"]:
		var L: Array = CivData.LEADERS[code]
		var st := "disponibile"
		if pl.get("leader", "") == code:
			st = "in gioco"
		elif not pl.get("leaders_avail", []).has(code):
			st = "perduto"
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(290, 0)
		var img := _card_img(code, 150)
		img.modulate = Color(1, 1, 1, 1) if st != "perduto" else Color(0.5, 0.5, 0.5)
		col.add_child(img)
		col.add_child(UI.label("%s (%s)" % [L[0], st], 16, UI.INK, UI.font_bold))
		for i in 2:
			var t := UI.label("%s: %s" % [L[3 + i * 2], L[4 + i * 2]], 13, UI.INK)
			t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			t.custom_minimum_size = Vector2(285, 0)
			col.add_child(t)
		lrow.add_child(col)
	var extra := []
	if pl.get("killed_leaders", []).size() > 0:
		extra.append("Capi nemici uccisi: %s (2 PV ciascuno)" % ", ".join(pl["killed_leaders"].map(func(x): return CivData.LEADERS[x][0])))
	if int(pl.get("captives", 0)) > 0:
		extra.append("Prigionieri: %d (½ PV ciascuno)" % pl["captives"])
	if not pl.get("erik", []).is_empty():
		extra.append("Regioni rivendicate da Erik il Rosso: %d (1 PV ciascuna)" % pl["erik"].size())
	if int(pl.get("anarchy", 0)) > 0:
		extra.append("Avanzamenti di governo sulla carta Anarchia: %d (1 PV ciascuno)" % pl["anarchy"])
	if int(pl.get("architect", 0)) > 0:
		extra.append("Grande architetto: %d Cultura per la prossima Meraviglia" % pl["architect"])
	if not extra.is_empty():
		var el := UI.label("\n".join(extra), 15, UI.INK)
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(el)
	_close_button(vb)


func _num(x: float) -> String:
	return str(int(x)) if absf(x - roundf(x)) < 0.01 else "%.1f" % x


func _chip(r: String, v: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 2)
	var ic := TextureRect.new()
	ic.texture = UI.tex("res://assets/icons/%s.png" % r)
	ic.custom_minimum_size = Vector2(26, 26)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hb.add_child(ic)
	hb.add_child(UI.label(v, 17, UI.LIGHT, UI.font_bold))
	hb.tooltip_text = D.RES_NAME[r]
	hb.mouse_filter = Control.MOUSE_FILTER_PASS
	return hb


# ------------------------------------------------------------------ cronaca e notifiche

func _on_log(t: String) -> void:
	var line := t
	if t.begins_with("—"):
		line = "\n[color=#d8a84e][b]%s[/b][/color]" % t
	chron.append_text(line + "\n")
	var sc: ScrollContainer = chron.get_meta("scroll")
	await get_tree().process_frame
	sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)


func toast(text: String, img := "", dur := 3.0) -> void:
	if online != null and online.catchup:
		return
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.stone(0.95, UI.GOLD))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	pc.add_child(hb)
	if img != "":
		var tr := TextureRect.new()
		tr.texture = UI.tex(img)
		tr.custom_minimum_size = Vector2(150, 210)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hb.add_child(tr)
	var l := UI.label(text, 19, UI.LIGHT, UI.font_bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(l)
	toast_box.add_child(pc)
	while toast_box.get_child_count() > 3:
		toast_box.get_child(0).queue_free()
		await get_tree().process_frame
	await get_tree().create_timer(dur).timeout
	if is_instance_valid(pc):
		var tw := create_tween()
		tw.tween_property(pc, "modulate:a", 0.0, 0.4)
		await tw.finished
		if is_instance_valid(pc):
			pc.queue_free()


func _on_fx(kind: String, data: Dictionary) -> void:
	match kind:
		"dice":
			_show_dice(data)
			Audio.play("dice")
		"event":
			var e: Array = D.EVENTS[data["id"]]
			toast("Evento per %s:\n%s\n\n%s" % [engine.pname(data["p"]), e[0], D.event_text(data["id"])], D.card_image(data["id"]), 5.0)
			Audio.play("bell")
		"card":
			toast("%s gioca «%s»" % [engine.pname(data["p"]), D.card_title(data["id"])], D.card_image(data["id"]), 3.0)
		"wonder":
			toast("%s costruisce %s!" % [engine.pname(int(engine.city_at(data["h"]).get("o", 0))), D.WONDERS[data["w"]]["it"]], D.card_image(data["w"]), 4.0)
			Audio.play("win")
		"objective":
			toast("%s completa l'obiettivo «%s» (+2 PV)" % [engine.pname(data["p"]), D.OBJ[data["key"]][0]], "", 3.0)
			Audio.play("coin")
		"advance":
			Audio.play("turn", -8.0)
		"build", "found", "recruit":
			Audio.play("pawn")
		"capture":
			Audio.play("cannon")
		"collect":
			Audio.play("coin", -6.0)
		"barbarians":
			Audio.play("cannon", -4.0)
		"turn":
			if humans.has(data["p"]) and humans.size() == 1:
				Audio.play("bell", -6.0)
		"reveal":
			Audio.play("splash", -4.0)
		"status":
			toast("Fase di status dell'era %s" % roman(data["age"]), "", 2.5)
	_queue_refresh()


func _show_dice(d: Dictionary) -> void:
	if online != null and online.catchup:
		return
	for ch in dice_panel.get_children():
		ch.queue_free()
	var vb := VBoxContainer.new()
	dice_panel.add_child(vb)
	for side in [["att", "p", "cva"], ["def", "q", "cvd"]]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		vb.add_child(hb)
		var who: int = d[side[1]]
		var nm := UI.label(engine.pname(who), 20, UI.pcol(who).lightened(0.4), UI.font_bold)
		nm.custom_minimum_size = Vector2(170, 0)
		hb.add_child(nm)
		for v in d[side[0]]:
			hb.add_child(_die(v))
		var cv: int = d[side[2]]
		var canc := 0
		for x in d[side[0]]:
			if x is Array and x.size() > 2 and x[1] == "E" and x[2]:
				canc += 1
		hb.add_child(UI.label("  = %d  →  %d colpi%s" % [cv, cv / 5, ("  (annulla %d)" % canc) if canc > 0 else ""], 20, UI.GOLD, UI.font_bold))
	dice_panel.position = Vector2(700, 90)
	dice_panel.size = Vector2(10, 10)
	dice_panel.visible = true
	dice_panel.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(dice_panel, "modulate:a", 0.0, 0.5)


## Un dado: [valore, icona, abilità attivata, ritirato dal Capo]. Sotto il numero l'iniziale dell'icona.
func _die(d) -> Control:
	var v: int = int(d[0]) if d is Array else int(d)
	var icon: String = str(d[1]) if d is Array else ""
	var active: bool = d is Array and d.size() > 2 and bool(d[2])
	var rer: bool = d is Array and d.size() > 3 and bool(d[3])
	var pc := PanelContainer.new()
	var col := Color("#e8c26a") if active else Color("#f3e6c8")
	pc.add_theme_stylebox_override("panel", UI.flat(col, Color("#7a4f28") if active else Color("#5a3a1e"), 2, 6, 4))
	pc.custom_minimum_size = Vector2(44, 52)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -4)
	pc.add_child(vb)
	var shown := v
	if active and icon == "E":
		shown = 0
	var l := UI.label(str(shown) if not (active and icon == "E") else "x", 22, UI.INK, UI.font_bold)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	var ic := UI.label({"I": "Fant", "C": "Cav", "E": "Elef", "L": "Capo"}.get(icon, ""), 11, UI.INK2, UI.font_bold)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ic)
	var tip: String = {"I": "Fanteria: +1 se in battaglia c'è una Fanteria", "C": "Cavalleria: +2 se in battaglia c'è una Cavalleria",
		"E": "Elefante: se c'è un Elefante il dado non conta ma annulla un colpo", "L": "Capo: con un Capo in battaglia si ritira"}.get(icon, "")
	if active:
		tip += "\n(abilità attivata)"
	if rer:
		tip += "\n(ritirato dal Capo)"
	pc.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return pc


# ------------------------------------------------------------------ pannello della casella

func _on_hover(k: String) -> void:
	if k == "" or not engine.hexes.has(k):
		tip.visible = false
		return
	var t: String = D.TER_NAME[engine.ter(k)]
	var c: Dictionary = engine.city_at(k)
	if not c.is_empty():
		t = "Città di %s · dim. %d · %s" % [engine.pname(c["o"]), engine.city_size(c), D.MOOD_NAME[c["mood"]]]
	var us: Array = engine.units_at(k)
	if not us.is_empty():
		var cnt := {}
		for u in us:
			var key := "%s %s" % [D.U_NAME[u["t"]], engine.pname(u["o"])]
			cnt[key] = cnt.get(key, 0) + 1
		for key in cnt:
			t += "\n%d × %s" % [cnt[key], key]
	if engine.hexes[k]["exhausted"]:
		t += "\nTerra esausta"
	if hex_choice.has(k):
		t += "\n» clic per scegliere"
	tip_lbl.text = t
	tip.visible = true
	tip.size = Vector2(10, 10)
	var mp := get_viewport().get_mouse_position()
	tip.position = mp + Vector2(18, 18)


func _on_hex(k: String) -> void:
	if hex_choice.has(k) and not pending.is_empty():
		var i: int = hex_choice[k]
		_provide(i)
		return
	if pending.get("type", "") == "move" and not move_sel.is_empty():
		var tg: Dictionary = engine.move_targets(pending["seat"], move_sel)
		if tg.has(k):
			_provide({"units": move_sel.duplicate(), "to": k, "roads": move_roads})
			return
	sel = k
	board.set_selected(k)
	move_sel = []
	if pending.get("type", "") == "move":
		_auto_move_sel()
	_refresh_info()
	_refresh_move_targets()


var move_roads := false


func _auto_move_sel() -> void:
	var p: int = pending["seat"]
	move_sel = []
	var land := []
	var ships := []
	for u in engine.units_at(sel):
		if u["o"] != p or engine.group_info(p, [u["id"]]).is_empty():
			continue
		if u["t"] == "ship":
			ships.append(u["id"])
		elif u["on"] == -1:
			land.append(u["id"])
	if not land.is_empty():
		move_sel = land
	elif not ships.is_empty():
		move_sel = ships


func _refresh_move_targets() -> void:
	if pending.get("type", "") != "move" or move_sel.is_empty():
		if pending.get("type", "") != "choice":
			board.set_targets({})
		return
	var tg: Dictionary = engine.move_targets(pending["seat"], move_sel)
	var marks := {}
	for k in tg:
		var info: Dictionary = tg[k]
		var c := Color("#6fd36f")
		if info.get("battle", false):
			c = Color("#ff4b3a")
		elif info["kind"] in ["explore", "explore_sea"]:
			c = Color("#c58cff")
		elif info["kind"] == "embark":
			c = Color("#4fb4ff")
		elif info.get("roads", false):
			c = Color("#ffd24a")
		marks[k] = c
	board.set_targets(marks)


func _refresh_info() -> void:
	for ch in info_box.get_children():
		ch.queue_free()
	if sel == "" or not engine.hexes.has(sel):
		info_box.add_child(UI.title("Mappa", 20))
		var l := UI.label("Clicca una casella per vederne il contenuto e agire.\n\nTrascina per ruotare la vista, rotella per lo zoom, tasto destro (o Maiusc) per spostarti.", 16, UI.PARCH)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_box.add_child(l)
		return
	var k := sel
	var me: int = pending.get("seat", -1)
	var my_turn: bool = pending.get("type", "") == "turn"
	info_box.add_child(UI.title(D.TER_NAME[engine.ter(k)], 22))
	var tr: String = D.TER_RES[engine.ter(k)] if engine.ter(k) != "" else ""
	if tr != "":
		info_box.add_child(UI.label("Produce: %s" % D.RES_NAME[tr], 15, UI.PARCH))
	if engine.hexes[k]["exhausted"]:
		info_box.add_child(UI.label("Terra esausta: niente raccolta né città.", 15, UI.TERRA))
	var c: Dictionary = engine.city_at(k)
	if not c.is_empty():
		var col: Color = UI.pcol(c["o"])
		info_box.add_child(UI.label("Città di %s" % engine.pname(c["o"]), 20, col.lightened(0.4), UI.font_bold))
		info_box.add_child(UI.label("Dimensione %d · %s%s" % [engine.city_size(c), D.MOOD_NAME[c["mood"]],
			(" · attivata %d volte" % c["act"]) if c["act"] > 0 and engine.cur == c["o"] else ""], 16, UI.LIGHT))
		var parts := []
		for b in c["b"]:
			parts.append(D.B_NAME[b] + ("" if c["b"][b] == c["o"] else " (di %s)" % engine.pname(c["b"][b])))
		for w in c["w"]:
			parts.append(D.WONDERS[w]["it"])
		if int(c.get("cleo", 0)) > 0:
			parts.append("Cultura di Cleopatra: %d" % c["cleo"])
		if c.has("druid"):
			parts.append("influenza druidica di %s" % engine.pname(c["druid"]))
		if not parts.is_empty():
			var bl := UI.label("Edifici: " + ", ".join(parts), 15, UI.PARCH)
			bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info_box.add_child(bl)
		if my_turn and c["o"] == me and engine.T["actions"] > 0:
			_city_actions(me, c)
	var us: Array = engine.units_at(k)
	if not us.is_empty():
		info_box.add_child(UI.label("Unità", 18, UI.GOLD, UI.font_title))
		for u in us:
			var un: String = D.U_NAME[u["t"]]
			if u["t"] == "leader" and u["o"] >= 0 and engine.players[u["o"]].get("leader", "") != "":
				un = "Capo %s" % CivData.LEADERS[engine.players[u["o"]]["leader"]][0]
			elif u["o"] == -2:
				un = "Nave pirata"
			var t := "%s di %s%s" % [un, engine.pname(u["o"]), " (a bordo)" if u["on"] != -1 else ""]
			if u["o"] == -2:
				t = un
			if u["o"] == me and pending.get("type", "") == "move":
				var cb := CheckBox.new()
				cb.text = t
				cb.disabled = engine.group_info(me, [u["id"]]).is_empty()
				cb.button_pressed = move_sel.has(u["id"])
				cb.add_theme_color_override("font_color", UI.pcol(u["o"]).lightened(0.4))
				var uid: int = u["id"]
				cb.toggled.connect(func(on):
					if on and not move_sel.has(uid):
						move_sel.append(uid)
					elif not on:
						move_sel.erase(uid)
					if not move_sel.is_empty() and engine.group_info(me, move_sel).is_empty():
						move_sel = [uid] if on else []
						_refresh_info.call_deferred()
					_refresh_move_targets())
				info_box.add_child(cb)
			else:
				info_box.add_child(UI.label("• " + t, 16, UI.pcol(u["o"]).lightened(0.4)))
		if my_turn and engine.T["actions"] > 0:
			for u in us:
				if u["o"] == me and u["t"] == "settler" and u["on"] == -1 and engine.can_found_at(me, k):
					var bf := UI.primary(UI.button("Fonda una città", 260, 42, 16))
					var uid2: int = u["id"]
					bf.pressed.connect(func(): _provide({"t": "found", "u": uid2}))
					info_box.add_child(bf)
					break
	if pending.get("type", "") == "move" and not move_sel.is_empty():
		var tg: Dictionary = engine.move_targets(me, move_sel)
		var any_opt := false
		for x in tg:
			if tg[x].get("roads_opt", false):
				any_opt = true
		if any_opt:
			var cbr := CheckBox.new()
			cbr.text = "Usa le Strade (1 Cibo + 1 Minerale)"
			cbr.button_pressed = move_roads
			cbr.toggled.connect(func(on): move_roads = on)
			info_box.add_child(cbr)
		var hint := UI.label("Clicca una casella illuminata: verde muovi, rosso battaglia, viola esplora, azzurro imbarca, giallo con le Strade." if not tg.is_empty() else "Queste unità non possono muovere.", 15, UI.PARCH)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_box.add_child(hint)


func _city_actions(p: int, c: Dictionary) -> void:
	if not engine.can_activate(c):
		info_box.add_child(UI.label("Città arrabbiata già attivata in questo turno.", 15, UI.TERRA))
		return
	if c["act"] > 0:
		var w := UI.label("Attivarla di nuovo ne peggiora l'umore.", 15, UI.TERRA)
		info_box.add_child(w)
	var b1 := UI.button("Raccogli risorse", 280, 40, 15)
	b1.pressed.connect(func(): _collect_dialog(p, c, false))
	info_box.add_child(b1)
	var b2 := UI.button("Recluta unità", 280, 40, 15)
	b2.pressed.connect(func(): _recruit_dialog(p, c))
	info_box.add_child(b2)
	for b in engine.bld_list():
		var why: String = engine.can_build(p, c, b)
		if why == "" and not engine.can_pay(p, engine.build_cost(p, b, c)):
			why = "servono %s" % engine.cost_text(engine.build_cost(p, b, c))
		if why == "c'è già":
			continue
		if why.begins_with("serve ") and b in D.EXP_BUILDINGS:
			continue
		var bb := UI.button("Costruisci %s" % D.B_NAME[b], 280, 40, 15)
		bb.tooltip_text = (D.B_TEXT[b] + "\nCosto: " + engine.cost_text(engine.build_cost(p, b, c))) + ("" if why == "" else "\nNon ora: " + why)
		bb.disabled = why != ""
		var bk: String = b
		bb.pressed.connect(func(): _provide({"t": "build", "c": c["id"], "b": bk}))
		info_box.add_child(bb)
	for w in engine.players[p]["won"]:
		var why2: String = engine.can_build_wonder(p, c, w)
		var bw := UI.gold(UI.button("Costruisci %s" % D.WONDERS[w]["it"], 280, 40, 14))
		bw.tooltip_text = D.WONDERS[w]["text"] + "\nCosto: " + engine.cost_text(D.WONDERS[w]["cost"]) + "\nServe: " + D.adv_it(D.WONDERS[w]["req"]) + ("" if why2 == "" else "\nNon ora: " + why2)
		bw.disabled = why2 != ""
		var wk: String = w
		bw.pressed.connect(func(): _provide({"t": "wonder", "c": c["id"], "w": wk}))
		info_box.add_child(bw)


# ------------------------------------------------------------------ barra delle azioni

func _clear_bar() -> void:
	for ch in bar_btns.get_children():
		ch.queue_free()


func _bar_button(text: String, cb: Callable, enabled := true, tipx := "", kind := "") -> Button:
	var b := UI.button(text, 0, 44, 16)
	b.custom_minimum_size = Vector2(maxf(120, text.length() * 11 + 30), 44)
	if kind == "primary":
		UI.primary(b)
	elif kind == "gold":
		UI.gold(b)
	b.disabled = not enabled
	b.tooltip_text = tipx
	b.pressed.connect(cb)
	bar_btns.add_child(b)
	return b


func _refresh_bar() -> void:
	_clear_bar()
	var t: String = pending.get("type", "")
	if pending.is_empty() or t == "choice":
		if t == "choice":
			bar.visible = false
			return
		bar.visible = true
		var p: int = engine.cur
		if engine.game_over:
			bar_title.text = "[b]La partita è finita.[/b]"
		elif p >= 0:
			bar_title.text = "[color=#%s][b]%s[/b][/color] sta giocando…" % [UI.pcol(p).lightened(0.4).to_html(false), engine.pname(p)]
		else:
			bar_title.text = "…"
		return
	bar.visible = true
	var p2: int = pending["seat"]
	if t == "move":
		bar_title.text = "[b]Movimento[/b]: puoi muovere ancora [color=#d8a84e]%d[/color] gruppi. Clicca una casella con le tue unità, scegli quali muovere, poi la destinazione." % pending["left"]
		_bar_button("Fine movimento", func(): _provide({"done": true}), true, "", "primary")
		return
	var acts: int = engine.T["actions"]
	bar_title.text = "[b]Tocca a te[/b]: %s. Clicca una tua città o un tuo colono sulla mappa, oppure scegli qui." % (
		("%d azioni" % acts) if acts != 1 else "1 azione") if acts > 0 else "[b]Azioni finite[/b]: puoi ancora usare le azioni gratuite, poi chiudi il turno."
	var buy: Array = engine.buyable_advances(p2)
	# Pace e poesia (India): se manca il Cibo, 1 Umore paga l'avanzamento
	var pp: bool = engine.civ_adv(p2, "Peace & Poetry") and not engine.T.get("pp", false) and engine.res(p2, "mood") >= 1
	if pp:
		for a0 in D.all_advances():
			if engine.can_buy_adv(p2, a0) and not buy.has(a0):
				buy.append(a0)
	_bar_button("Avanzamento", func(): _show_advances(p2, buy, func(a): _provide({"t": "advance", "a": a,
		"pp": pp and not engine.can_pay(p2, {"food": engine.adv_food_cost(p2, a)}, ["idea"])})), acts > 0 and not buy.is_empty(),
		"Compra un avanzamento: 2 Cibo (Idee e Oro valgono come Cibo).")
	_bar_button("Muovi", func(): _provide({"t": "move"}), acts > 0, "Muovi fino a 3 unità o gruppi.")
	var any_happy: bool = engine.cities_of(p2).any(func(c): return c["mood"] < 2)
	_bar_button("Felicità", func(): _happy_dialog(p2, false), acts > 0 and any_happy and engine.res(p2, "mood") > 0 or acts > 0 and any_happy and engine.has_adv(p2, "Rituals"),
		"Paga Umore (quanto la dimensione della città) per migliorarne l'umore di un passo.")
	var inf: Array = engine.influence_options(p2)
	_bar_button("Influenza", func(): _influence_dialog(p2, false), acts > 0 and not inf.is_empty(),
		"Influenza la cultura di una città: con 5 o 6 un suo edificio passa al tuo colore.")
	var pc: Array = engine.playable_cards(p2)
	_bar_button("Carte (%d)" % engine.players[p2]["hand"].size(), func(): _show_cards(p2), true, "Le tue carte Azione, gli Obiettivi e le Meraviglie.", "gold" if not pc.is_empty() else "")
	var fo: Array = engine.free_options(p2)
	if not fo.is_empty():
		_bar_button("Speciali (%d)" % fo.size(), func(): _specials_dialog(p2), true, "Azioni gratuite e speciali dei tuoi avanzamenti e delle meraviglie.")
	_bar_button("Fine turno", func(): _end_turn(acts), true, "", "primary")


func _end_turn(acts: int) -> void:
	if acts > 0:
		var vb := _open_modal("Chiudere il turno?", 520)
		var l := UI.label("Hai ancora %d %s: andranno perse." % [acts, "azioni" if acts > 1 else "azione"], 18, UI.INK)
		vb.add_child(l)
		var hb := HBoxContainer.new()
		vb.add_child(hb)
		var b1 := UI.primary(UI.button("Chiudi il turno", 220, 46))
		b1.pressed.connect(func():
			_clear_modal()
			_provide({"t": "end"}))
		hb.add_child(b1)
		var b2 := UI.button("Annulla", 160, 46)
		b2.pressed.connect(_clear_modal)
		hb.add_child(b2)
		return
	_provide({"t": "end"})


# ------------------------------------------------------------------ decisioni

func _on_decision(req: Dictionary) -> void:
	var p: int = req["seat"]
	if humans.size() > 1 and online == null and p != last_human:
		last_human = p
		await _curtain(p)
	last_human = p
	pending = req
	hex_choice = {}
	match req["type"]:
		"turn":
			board.set_targets({})
			# niente più da fare: il turno si chiude da solo
			if engine.T["actions"] <= 0 and engine.free_options(p).is_empty() and engine.playable_cards(p).is_empty():
				pending = req
				refresh()
				await get_tree().create_timer(0.6).timeout
				if pending == req:
					_provide({"t": "end"})
				return
		"move":
			move_sel = []
			if sel != "":
				_auto_move_sel()
		"choice":
			_choice_ui(req)
	refresh()
	_refresh_move_targets()


func _provide(r) -> void:
	if pending.is_empty():
		return
	pending = {}
	hex_choice = {}
	move_sel = []
	board.set_targets({})
	_clear_modal()
	_refresh_bar()
	engine.provide_decision(r)


func _curtain(p: int) -> void:
	_clear_modal()
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.96)
	dim.size = Vector2(1920, 1080)
	modal.add_child(dim)
	var vb := VBoxContainer.new()
	vb.position = Vector2(560, 400)
	vb.size = Vector2(800, 300)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	modal.add_child(vb)
	var t := UI.title("Tocca a %s" % engine.pname(p), 48, UI.pcol(p).lightened(0.4))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var l := UI.label("Passa il dispositivo: le carte in mano sono segrete.", 22, UI.PARCH)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	var b := UI.primary(UI.button("Sono pronto", 260, 56, 22))
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(b)
	await b.pressed
	_clear_modal()
	_refresh_rows()


func _choice_ui(req: Dictionary) -> void:
	var p: int = req["seat"]
	var opts: Array = req.get("options", [])
	if req.has("advances"):
		var lst: Array = req["advances"]
		_show_advances(p, lst, func(a): _provide(lst.find(a)), req.get("title", ""), false)
		return
	var hx: Array = req.get("hexes", [])
	var marks := {}
	for i in hx.size():
		if hx[i] != "" and engine.hexes.has(hx[i]):
			hex_choice[hx[i]] = i
			marks[hx[i]] = Color("#ffd24a")
	if req.get("explore", false):
		var ri: int = req["ri"]
		for k in engine.regions[ri]["hexes"]:
			marks[k] = Color("#c58cff")
	board.set_targets(marks)
	var with_map := not marks.is_empty()
	var w := 760.0
	var vb := _open_modal(req.get("title", "Scegli"), w, with_map)
	if req.get("explore", false):
		vb.add_child(UI.label("Passa sopra a un orientamento per vederlo sulla mappa.", 16, UI.INK2))
	if req.has("spy"):
		_spy_preview(vb, req["spy"])
	if with_map and not req.get("explore", false):
		vb.add_child(UI.label("Clicca una casella illuminata sulla mappa oppure scegli qui:", 16, UI.INK2))
	if req.has("leaders"):
		var lr := HBoxContainer.new()
		lr.add_theme_constant_override("separation", 12)
		vb.add_child(lr)
		var lst: Array = req["leaders"]
		for i in lst.size():
			var L: Array = CivData.LEADERS[lst[i]]
			var col := VBoxContainer.new()
			col.custom_minimum_size = Vector2(230, 0)
			col.add_child(_card_img(lst[i], 130))
			col.add_child(UI.label(L[0], 16, UI.INK, UI.font_bold))
			for j in 2:
				var t := UI.label("%s: %s" % [L[3 + j * 2], L[4 + j * 2]], 12, UI.INK)
				t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				t.custom_minimum_size = Vector2(225, 0)
				col.add_child(t)
			var bsel := UI.primary(UI.button("Scegli", 160, 38, 15))
			var li := i
			bsel.pressed.connect(func(): _provide(li))
			col.add_child(bsel)
			lr.add_child(col)
		return
	var cards: Array = req.get("cards", [])
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(w - 40, mini(420, 50 * opts.size() + 10))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	sc.add_child(list)
	for i in opts.size():
		var b := UI.button(str(opts[i]), w - 60, 44, 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.tooltip_text = str(opts[i])
		if i < cards.size() and cards[i] != "":
			b.icon = UI.card_tex(cards[i])
			b.expand_icon = true
			b.custom_minimum_size = Vector2(w - 60, 70)
		var idx := i
		b.pressed.connect(func():
			board.set_preview({})
			_provide(idx))
		if req.get("explore", false):
			var pv := {req["ri"]: {"tile": req["tile"], "oi": req["oi"][i]}}
			b.mouse_entered.connect(func(): board.set_preview(pv))
			if i == 0:
				board.set_preview(pv)
		if i < hx.size() and hx[i] != "":
			var hk: String = hx[i]
			b.mouse_entered.connect(func(): board.set_selected(hk))
		list.add_child(b)


func _explore_preview(vb: VBoxContainer, req: Dictionary) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	vb.add_child(hb)
	var reg: Dictionary = engine.regions[req["ri"]]
	var tile: String = req["tile"]
	var tt: Dictionary = engine.get_meta("tile_ter")[tile]
	for j in req["oi"].size():
		var oi: int = req["oi"][j]
		var sl: Dictionary = reg["orients"][oi]["slots"]
		var box := VBoxContainer.new()
		box.add_child(UI.label("Orientamento %d" % (j + 1), 18, UI.INK, UI.font_bold))
		for s in ["T", "L", "R", "B"]:
			box.add_child(UI.label("%s → %s" % [engine._hex_label(sl[s]).split(" [")[0] if engine.revealed(sl[s]) else "casella " + sl[s], D.TER_NAME[tt[s]]], 15, UI.INK2))
		hb.add_child(box)


func _spy_preview(vb: VBoxContainer, q: int) -> void:
	var hb := HFlowContainer.new()
	vb.add_child(hb)
	for id in engine.players[q]["hand"] + engine.players[q]["obj"] + engine.players[q]["won"]:
		hb.add_child(_card_img(id, 110))


# ------------------------------------------------------------------ finestre

func _clear_modal() -> void:
	for ch in modal.get_children():
		ch.queue_free()
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Finestra su pergamena. map_visible: la finestra sta in basso e lascia vedere la mappa.
func _open_modal(title_text: String, w := 700.0, map_visible := false) -> VBoxContainer:
	_clear_modal()
	if not map_visible:
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.45)
		dim.size = Vector2(1920, 1080)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		modal.add_child(dim)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.paper(22))
	modal.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.custom_minimum_size = Vector2(w, 0)
	pc.add_child(vb)
	var t := UI.title(title_text, 24, UI.INK)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(w, 0)
	vb.add_child(t)
	_place_modal.call_deferred(pc, map_visible)
	return vb


func _place_modal(pc: PanelContainer, map_visible: bool) -> void:
	if not is_instance_valid(pc):
		return
	pc.size = Vector2(10, 10)
	await get_tree().process_frame
	if not is_instance_valid(pc):
		return
	pc.size = pc.get_combined_minimum_size()
	await get_tree().process_frame
	if not is_instance_valid(pc):
		return
	pc.size = pc.get_combined_minimum_size()
	var s := pc.size
	if map_visible:
		pc.position = Vector2((LW + RX) / 2.0 - s.x / 2.0, 1072 - s.y)
	else:
		pc.position = Vector2(960 - s.x / 2.0, maxf(20, 540 - s.y / 2.0))


func _close_button(vb: VBoxContainer, text := "Chiudi") -> void:
	var b := UI.button(text, 200, 44, 16)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.pressed.connect(_clear_modal)
	vb.add_child(b)


func _card_img(id: String, w := 160.0) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = UI.card_tex(id)
	tr.custom_minimum_size = Vector2(w, w * 1.39)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.tooltip_text = _card_tip(id)
	return tr


func _card_tip(id: String) -> String:
	if id.begins_with("a"):
		var a: Array = D.action_card(id)
		var top: Dictionary = D.ACTION_TOPS[a[1]]
		var tac: Dictionary = D.tactic(a[2])
		return "%s\n%s\n\nTattica: %s\n%s" % [top["it"], top["text"], tac["it"], tac["text"]]
	if id.begins_with("e"):
		return "%s\n%s" % [D.EVENTS[id][0], D.event_text(id)]
	if id.begins_with("o"):
		var o: Array = D.objective_card(id)
		return "%s — %s\n%s\n\n%s — %s\n%s" % [D.OBJ[o[1]][0], "fase di status" if D.OBJ[o[1]][1] == "status" else "subito", D.OBJ[o[1]][2],
			D.OBJ[o[2]][0], "fase di status" if D.OBJ[o[2]][1] == "status" else "subito", D.OBJ[o[2]][2]]
	if D.WONDERS.has(id):
		var w: Dictionary = D.WONDERS[id]
		return "%s\nCosto: %s · Serve %s\n%s" % [w["it"], engine.cost_text(w["cost"]), D.adv_it(w["req"]), w["text"]]
	return id


## Tabellone degli avanzamenti. pick: avanzamenti selezionabili; cb riceve il nome scelto.
func _show_advances(p: int, pick: Array, cb: Callable, title_text := "", closable := true) -> void:
	var vb := _open_modal(title_text if title_text != "" else "Avanzamenti di %s" % engine.pname(p), 1500)
	var leg := UI.label("Oro = posseduto · bordo chiaro = si può comprare · bordo giallo/blu = dà +1 Umore / +1 Cultura. Passa sopra per leggere l'effetto.", 15, UI.INK2)
	vb.add_child(leg)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)
	for cat in D.CATEGORIES:
		var box := PanelContainer.new()
		var gov: bool = cat in D.GOVERNMENTS
		box.add_theme_stylebox_override("panel", UI.flat(Color("#3a2614") if not gov else Color("#5a3a10"), UI.GOLD_DARK, 1, 6, 6))
		var bvb := VBoxContainer.new()
		bvb.add_theme_constant_override("separation", 4)
		box.add_child(bvb)
		var ttl := UI.label(D.CAT_NAME[cat] + ("  (serve %s)" % D.adv_it(D.GOV_REQ[cat]) if gov else ""), 15, UI.GOLD, UI.font_title)
		bvb.add_child(ttl)
		for a in D.ADV[cat]:
			var name: String = a[0]
			var owned: bool = engine.players[p]["adv"].has(name)
			var b := Button.new()
			b.text = a[1]
			b.custom_minimum_size = Vector2(228, 34)
			b.add_theme_font_override("font", UI.font_bold)
			b.add_theme_font_size_override("font_size", 15)
			var border := Color("#e0c45a") if a[2] == "m" else (Color("#6fa0ff") if a[2] == "c" else Color("#6b5030"))
			var can: bool = pick.has(name)
			var bg := Color("#c99a43") if owned else (Color("#7a5228") if can else Color("#2a1c10"))
			var stl := UI.flat(bg, border, 3 if a[2] != "" else 1, 5, 4)
			b.add_theme_stylebox_override("normal", stl)
			b.add_theme_stylebox_override("hover", UI.flat(bg.lightened(0.15), UI.GOLD, 3, 5, 4))
			b.add_theme_stylebox_override("pressed", stl)
			b.add_theme_stylebox_override("disabled", stl)
			b.add_theme_color_override("font_color", UI.DARK if owned else UI.LIGHT)
			b.add_theme_color_override("font_disabled_color", UI.DARK if owned else Color(0.62, 0.55, 0.45))
			var cost := ""
			if can and not owned and engine.cur == p:
				var fc: int = engine.adv_food_cost(p, name)
				cost = "\nCosto: %s" % ("gratis" if fc == 0 else "2 Cibo (o Idee/Oro)")
			b.tooltip_text = "%s\n%s%s" % [a[1], a[3], cost]
			b.disabled = not can
			var nm := name
			b.pressed.connect(func():
				_clear_modal()
				cb.call(nm))
			bvb.add_child(b)
		grid.add_child(box)
	if closable:
		_close_button(vb)


func _show_done(p: int) -> void:
	var vb := _open_modal("Obiettivi completati da %s" % engine.pname(p), 900)
	var done: Array = engine.players[p]["done"]
	if done.is_empty():
		vb.add_child(UI.label("Ancora nessuno.", 18, UI.INK))
	var hb := HFlowContainer.new()
	vb.add_child(hb)
	for d in done:
		var box := VBoxContainer.new()
		box.add_child(_card_img(d["card"], 150))
		box.add_child(UI.label(D.OBJ[d["obj"]][0], 15, UI.INK, UI.font_bold))
		hb.add_child(box)
	var ev: Array = engine.players[p]["events"]
	if not ev.is_empty():
		vb.add_child(UI.label("Eventi tenuti: " + ", ".join(ev.map(func(e): return D.EVENTS[e][0])), 16, UI.INK))
	_close_button(vb)


func _show_cards(p: int) -> void:
	var vb := _open_modal("Carte di %s" % engine.pname(p), 1300)
	var my_turn: bool = pending.get("type", "") == "turn" and pending.get("seat", -1) == p
	var playable: Array = engine.playable_cards(p) if my_turn else []
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1300, 700)
	vb.add_child(sc)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.custom_minimum_size = Vector2(1270, 0)
	sc.add_child(inner)
	for sect in [["Carte Azione e grandi personaggi", engine.players[p]["hand"]], ["Obiettivi", engine.players[p]["obj"]], ["Meraviglie", engine.players[p]["won"]]]:
		inner.add_child(UI.title(sect[0], 20, UI.INK))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 12)
		inner.add_child(flow)
		if sect[1].is_empty():
			inner.add_child(UI.label("Nessuna.", 16, UI.INK2))
		for id in sect[1]:
			var box := VBoxContainer.new()
			box.custom_minimum_size = Vector2(190, 0)
			box.add_child(_card_img(id, 190))
			var nm := UI.label(D.card_title(id), 15, UI.INK, UI.font_bold)
			nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			nm.custom_minimum_size = Vector2(190, 0)
			box.add_child(nm)
			if playable.has(id):
				var b := UI.primary(UI.button("Gioca", 190, 38, 15))
				var cid: String = id
				b.pressed.connect(func(): _provide({"t": "card", "id": cid}))
				box.add_child(b)
			flow.add_child(box)
	vb.add_child(UI.label("Le tattiche (metà inferiore delle carte Azione) si giocano in battaglia: serve Tattica.", 15, UI.INK2))
	_close_button(vb)


# ---- raccolta

func _collect_dialog(p: int, c: Dictionary, free: bool, what := "econlib") -> void:
	var info: Dictionary = engine.collect_options(c)
	var picks: Array = engine.auto_collect(c)
	var state := {}
	for pk in picks:
		state[pk[0]] = pk[1]
	var cards := []
	for id in engine.players[p]["hand"]:
		var k: String = engine.card_kind(id)
		if k in ["mass_collection", "focused_collection"]:
			cards.append(id)
	var vb := _open_modal("Raccolta: città di dimensione %d (%s)" % [engine.city_size(c), D.MOOD_NAME[c["mood"]]], 820, true)
	var cnt_lbl := UI.label("", 18, UI.INK, UI.font_bold)
	vb.add_child(cnt_lbl)
	var card_sel := {"id": ""}
	var metal := {"on": engine.has_adv(p, "Metallurgy")}
	var rows := VBoxContainer.new()
	vb.add_child(rows)
	var confirm := UI.primary(UI.button("Raccogli", 220, 46))
	var upd := func():
		var lim: int = info["count"] + (2 if card_sel["id"] != "" and engine.card_kind(card_sel["id"]) == "mass_collection" else 0) + (1 if metal.get("bc", false) else 0)
		cnt_lbl.text = "Risorse scelte: %d su %d (una per casella; il mare al massimo una volta)" % [state.size(), lim]
		var pk2 := []
		for k in state:
			pk2.append([k, state[k]])
		if metal.get("bc", false):
			engine.T["bc_city"] = c["id"]
		confirm.disabled = not engine.valid_collect(c, pk2, card_sel["id"])
		engine.T.erase("bc_city")
		var marks := {}
		for k in state:
			marks[k] = Color("#6fd36f")
		board.set_targets(marks)
	for s in info["slots"] + info["far"]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		var lb := UI.label("%s%s" % [D.TER_NAME[engine.ter(s["h"])], " (2 caselle)" if s["far"] else ""], 16, UI.INK)
		lb.custom_minimum_size = Vector2(220, 0)
		hb.add_child(lb)
		var group := []
		for r in s["opts"]:
			var b := Button.new()
			b.toggle_mode = true
			if r == "captive":
				b.text = "Prig."
				b.tooltip_text = "Un Prigioniero (Impero tributario): togli un'unità barbara"
			else:
				b.icon = UI.tex("res://assets/icons/%s.png" % r)
				b.expand_icon = true
				b.tooltip_text = D.RES_NAME[r]
			b.custom_minimum_size = Vector2(46, 40)
			b.button_pressed = state.get(s["h"], "") == r
			b.add_theme_stylebox_override("pressed", UI.flat(Color("#e8c26a"), UI.INK, 2, 6, 3))
			b.add_theme_stylebox_override("normal", UI.flat(Color("#d8c8a0"), UI.INK2, 1, 6, 3))
			b.add_theme_stylebox_override("hover", UI.flat(Color("#efe0b8"), UI.INK, 1, 6, 3))
			var key: String = s["h"]
			var rr: String = r
			group.append(b)
			b.toggled.connect(func(on):
				if on:
					state[key] = rr
					for o in group:
						if o != b:
							o.set_pressed_no_signal(false)
				elif state.get(key, "") == rr:
					state.erase(key)
				upd.call())
			hb.add_child(b)
		hb.mouse_entered.connect(func(): board.set_selected(s["h"]))
		rows.add_child(hb)
	for id in cards:
		var cb := CheckBox.new()
		cb.text = "Gioca «%s»: %s" % [D.card_title(id), D.ACTION_TOPS[engine.card_kind(id)]["text"]]
		cb.add_theme_color_override("font_color", UI.INK)
		cb.toggled.connect(func(on):
			card_sel["id"] = id if on else ""
			upd.call())
		vb.add_child(cb)
	if not free and engine.civ_adv(p, "Ballcourts") and engine.res(p, "mood") >= 1 and c["mood"] > 0:
		var cbb := CheckBox.new()
		cbb.text = "Campi da pelota: paga 1 Umore, la città conta 1 in più"
		cbb.add_theme_color_override("font_color", UI.INK)
		cbb.toggled.connect(func(on):
			metal["bc"] = on
			upd.call())
		vb.add_child(cbb)
	if engine.has_adv(p, "Metallurgy"):
		var cm := CheckBox.new()
		cm.text = "Metallurgia: con almeno 2 Minerale, uno diventa Oro"
		cm.button_pressed = true
		cm.add_theme_color_override("font_color", UI.INK)
		cm.toggled.connect(func(on): metal["on"] = on)
		vb.add_child(cm)
	var hb2 := HBoxContainer.new()
	hb2.add_theme_constant_override("separation", 10)
	vb.add_child(hb2)
	confirm.pressed.connect(func():
		var pk3 := []
		for k in state:
			pk3.append([k, state[k]])
		if free:
			_provide({"t": "free", "what": what, "c": c["id"], "picks": pk3, "metal": metal["on"]})
		else:
			_provide({"t": "collect", "c": c["id"], "picks": pk3, "card": card_sel["id"], "metal": metal["on"], "bc": metal.get("bc", false)}))
	hb2.add_child(confirm)
	var canc := UI.button("Annulla", 160, 46)
	canc.pressed.connect(func():
		_clear_modal()
		board.set_targets({}))
	hb2.add_child(canc)
	upd.call()


# ---- reclutamento

func _recruit_dialog(p: int, c: Dictionary) -> void:
	var comp := {}
	for t0 in engine.unit_list():
		comp[t0] = 0
	var flags := {"sanit": false, "draft": false, "bc": false, "shogun": false}
	var vb := _open_modal("Reclutamento: al massimo %d unità" % engine.eff_size(c), 680)
	var msg := UI.label("", 17, UI.TERRA, UI.font_bold)
	var cost_l := UI.label("", 17, UI.INK)
	var confirm := UI.primary(UI.button("Recluta", 200, 46))
	var upd := func():
		if flags["bc"]:
			engine.T["bc_city"] = c["id"]
		var why: String = engine.valid_recruit(p, c, comp, flags["sanit"], flags["draft"])
		engine.T.erase("bc_city")
		msg.text = why
		cost_l.text = "Costo: " + engine.cost_text(engine.recruit_cost(p, comp, flags["sanit"], flags["draft"], c))
		confirm.disabled = why != ""
	for t in engine.unit_list():
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		var lb := UI.label("%s (%s)" % [D.U_NAME[t], engine.cost_text(D.U_COST[t])], 18, UI.INK)
		lb.custom_minimum_size = Vector2(300, 0)
		hb.add_child(lb)
		var val := UI.label("0", 22, UI.INK, UI.font_bold)
		val.custom_minimum_size = Vector2(36, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var tt: String = t
		var minus := UI.button("-", 44, 40, 20)
		minus.pressed.connect(func():
			comp[tt] = maxi(0, comp[tt] - 1)
			val.text = str(comp[tt])
			upd.call())
		var plus := UI.button("+", 44, 40, 20)
		plus.pressed.connect(func():
			comp[tt] += 1
			val.text = str(comp[tt])
			upd.call())
		if t == "ship" and not c["b"].has("port"):
			plus.disabled = true
			lb.text += " — serve un Porto"
		elif t in D.EXP_UNITS and not engine.can_recruit_type(p, c, t):
			plus.disabled = true
			lb.text += " — " + engine.recruit_block(p, c, t)
		if t == "leader":
			lb.tooltip_text = "Scegli uno dei tuoi Capi: un solo Capo alla volta (reclutarne un altro scarta il vecchio)."
			lb.mouse_filter = Control.MOUSE_FILTER_PASS
		hb.add_child(minus)
		hb.add_child(val)
		hb.add_child(plus)
		vb.add_child(hb)
	if engine.has_adv(p, "Sanitation"):
		var cs := CheckBox.new()
		cs.text = "Igiene: un Colono per 1 Umore"
		cs.add_theme_color_override("font_color", UI.INK)
		cs.toggled.connect(func(on):
			flags["sanit"] = on
			upd.call())
		vb.add_child(cs)
	if engine.has_adv(p, "Draft"):
		var cd := CheckBox.new()
		cd.text = "Leva: una Fanteria per %d Umore" % (2 if engine.has_adv(p, "Civil Liberties") else 1)
		cd.add_theme_color_override("font_color", UI.INK)
		cd.toggled.connect(func(on):
			flags["draft"] = on
			upd.call())
		vb.add_child(cd)
	if engine.civ_adv(p, "Ballcourts") and engine.res(p, "mood") >= 1 and c["mood"] > 0:
		var cbb := CheckBox.new()
		cbb.text = "Campi da pelota: paga 1 Umore, la città conta 1 in più"
		cbb.add_theme_color_override("font_color", UI.INK)
		cbb.toggled.connect(func(on):
			flags["bc"] = on
			upd.call())
		vb.add_child(cbb)
	if engine.civ_adv(p, "Shogunate") and engine.has_adv(p, "Draft") and not engine.T.get("shogun_d", false):
		var csh := CheckBox.new()
		csh.text = "Shogunato: la Fanteria della Leva diventa una carta Azione"
		csh.add_theme_color_override("font_color", UI.INK)
		csh.toggled.connect(func(on): flags["shogun"] = on)
		vb.add_child(csh)
	vb.add_child(cost_l)
	vb.add_child(msg)
	var hb2 := HBoxContainer.new()
	vb.add_child(hb2)
	confirm.pressed.connect(func(): _provide({"t": "recruit", "c": c["id"], "comp": comp.duplicate(), "sanit": flags["sanit"], "draft": flags["draft"], "bc": flags["bc"], "shogun": flags["shogun"]}))
	hb2.add_child(confirm)
	var canc := UI.button("Annulla", 160, 46)
	canc.pressed.connect(_clear_modal)
	hb2.add_child(canc)
	upd.call()


# ---- felicità

func _happy_dialog(p: int, voting: bool) -> void:
	var steps := {}
	var vb := _open_modal("Aumenta la felicità" + (" (Voto: +1 Umore)" if voting else ""), 640)
	vb.add_child(UI.label("Ogni passo costa tanti Umore quanto la dimensione della città%s." % (" (con Riti anche risorse)" if engine.has_adv(p, "Rituals") else ""), 16, UI.INK2))
	var cost_l := UI.label("", 18, UI.INK, UI.font_bold)
	var confirm := UI.primary(UI.button("Conferma", 200, 46))
	var upd := func():
		var tot: int = engine.happy_cost(p, steps)
		cost_l.text = "Costo: %d Umore (ne hai %d)" % [tot + (1 if voting else 0), engine.res(p, "mood")]
		confirm.disabled = tot <= 0 or not engine.can_pay_mood(p, tot + (1 if voting else 0))
	for c in engine.cities_of(p):
		if c["mood"] >= 2:
			continue
		var hb := HBoxContainer.new()
		var lb := UI.label("%s · dim. %d · %s" % [D.TER_NAME[engine.ter(c["h"])], engine.city_size(c), D.MOOD_NAME[c["mood"]]], 17, UI.INK)
		lb.custom_minimum_size = Vector2(360, 0)
		hb.add_child(lb)
		var cid: int = c["id"]
		var maxs: int = 2 - c["mood"]
		for st in range(0, maxs + 1):
			var b := UI.button(["nessuno", "+1", "+2"][st], 90, 38, 15)
			var s2: int = st
			b.pressed.connect(func():
				if s2 == 0:
					steps.erase(cid)
				else:
					steps[cid] = s2
				upd.call())
			hb.add_child(b)
		hb.mouse_entered.connect(func(): board.set_selected(c["h"]))
		vb.add_child(hb)
	vb.add_child(cost_l)
	var hb2 := HBoxContainer.new()
	vb.add_child(hb2)
	confirm.pressed.connect(func():
		if voting:
			_provide({"t": "free", "what": "voting", "steps": steps.duplicate()})
		else:
			_provide({"t": "happy", "steps": steps.duplicate()}))
	hb2.add_child(confirm)
	var canc := UI.button("Annulla", 160, 46)
	canc.pressed.connect(_clear_modal)
	hb2.add_child(canc)
	upd.call()


# ---- influenza

func _influence_dialog(p: int, arts: bool) -> void:
	var opts: Array = engine.influence_options(p)
	var vb := _open_modal("Influenza la cultura" + (" (Arti)" if arts else ""), 820, true)
	vb.add_child(UI.label("Tiro di un dado: con 5 o 6 l'edificio passa al tuo colore (vale per i tuoi punti). La Cultura allunga il raggio e, dopo il tiro, aggiunge +1 per segnalino.", 15, UI.INK2))
	var marks := {}
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(800, mini(400, 52 * opts.size() * 2))
	vb.add_child(sc)
	var list := VBoxContainer.new()
	sc.add_child(list)
	for o in opts:
		var th: String = o["to_h"]
		marks[th] = Color("#c58cff")
		for b in o["b"]:
			var txt := "%s (da: %s%s)" % [engine.infl_target_text(o, b), o["label"],
				(", +%d raggio: %d Cultura" % [o["need"], o["need"]]) if o["need"] > 0 else ""]
			var bt := UI.button(txt, 780, 42, 15)
			bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var m := {"t": "free", "what": "arts", "from": o["from"], "to": o["to"], "b": b} if arts else {"t": "influence", "from": o["from"], "to": o["to"], "b": b}
			bt.pressed.connect(func(): _provide(m))
			bt.mouse_entered.connect(func(): board.set_selected(th))
			list.add_child(bt)
	board.set_targets(marks)
	var canc := UI.button("Annulla", 160, 46)
	canc.pressed.connect(func():
		_clear_modal()
		board.set_targets({}))
	vb.add_child(canc)


# ---- azioni speciali

func _specials_dialog(p: int) -> void:
	var vb := _open_modal("Azioni speciali", 720)
	for w in engine.free_options(p):
		var b := UI.button(engine.free_name(w), 680, 44, 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var ww: String = w
		b.pressed.connect(func(): _special(p, ww))
		vb.add_child(b)
	_close_button(vb)


func _special(p: int, w: String) -> void:
	match w:
		"voting":
			_happy_dialog(p, true)
		"econlib":
			var cs: Array = engine.cities_of(p).filter(func(c): return engine.can_activate(c))
			var vb := _open_modal("Libertà economica: quale città raccoglie?", 600)
			for c in cs:
				var b := UI.button("%s (dim. %d)" % [engine._hex_label(c["h"]), engine.city_size(c)], 560, 42, 15)
				var cc: Dictionary = c
				b.pressed.connect(func(): _collect_dialog(p, cc, true))
				vb.add_child(b)
			_close_button(vb, "Annulla")
		"arts":
			_influence_dialog(p, true)
		"drama":
			var vb2 := _open_modal("Teatro e musica", 520)
			var b1 := UI.button("1 Umore → 1 Cultura", 400, 44)
			b1.disabled = engine.res(p, "mood") < 1
			b1.pressed.connect(func(): _provide({"t": "free", "what": "drama", "dir": "m2c"}))
			vb2.add_child(b1)
			var b2 := UI.button("1 Cultura → 1 Umore", 400, 44)
			b2.disabled = engine.res(p, "culture") < 1
			b2.pressed.connect(func(): _provide({"t": "free", "what": "drama", "dir": "c2m"}))
			vb2.add_child(b2)
			_close_button(vb2, "Annulla")
		"bartering":
			var vb3 := _open_modal("Baratto: quale carta scarti?", 1100)
			var flow := HFlowContainer.new()
			vb3.add_child(flow)
			for id in engine.players[p]["hand"] + engine.players[p]["obj"]:
				var box := VBoxContainer.new()
				box.add_child(_card_img(id, 140))
				var cid: String = id
				var bg := UI.button("per 1 Oro", 140, 34, 14)
				bg.pressed.connect(func(): _provide({"t": "free", "what": "bartering", "card": cid, "get": "gold"}))
				box.add_child(bg)
				var bc := UI.button("per 1 Cultura", 140, 34, 14)
				bc.pressed.connect(func(): _provide({"t": "free", "what": "bartering", "card": cid, "get": "culture"}))
				box.add_child(bc)
				flow.add_child(box)
			_close_button(vb3, "Annulla")
		"taxation":
			var k: int = engine.cities_of(p).size()
			var get := {"food": k, "ore": 0, "wood": 0, "gold": 0}
			var vb4 := _open_modal("Tassazione: %d risorse da distribuire" % k, 560)
			var lbls := {}
			var kinds := ["food", "ore", "wood"] + (["gold"] if engine.has_adv(p, "Currency") else [])
			for r in kinds:
				var hb := HBoxContainer.new()
				var lb := UI.label(D.RES_NAME[r], 18, UI.INK)
				lb.custom_minimum_size = Vector2(160, 0)
				hb.add_child(lb)
				var val := UI.label(str(get[r]), 20, UI.INK, UI.font_bold)
				lbls[r] = val
				var rr: String = r
				var mi := UI.button("-", 44, 38)
				mi.pressed.connect(func():
					if get[rr] > 0:
						get[rr] -= 1
						get["food" if rr != "food" else "ore"] += 1
						for x in lbls:
							lbls[x].text = str(get[x]))
				var pl := UI.button("+", 44, 38)
				pl.pressed.connect(func():
					for x in kinds:
						if x != rr and get[x] > 0:
							get[x] -= 1
							get[rr] += 1
							break
					for x in lbls:
						lbls[x].text = str(get[x]))
				hb.add_child(mi)
				hb.add_child(val)
				hb.add_child(pl)
				vb4.add_child(hb)
			var ok := UI.primary(UI.button("Riscuoti (1 Umore, 1 azione)", 360, 46))
			ok.pressed.connect(func():
				var g2 := {}
				for x in get:
					if get[x] > 0:
						g2[x] = get[x]
				_provide({"t": "free", "what": "taxation", "get": g2}))
			vb4.add_child(ok)
			_close_button(vb4, "Annulla")
		"circus":
			var vb5 := _open_modal("Circo e giochi: quale città?", 640)
			for c in engine.cities_of(p):
				if c["mood"] >= 2:
					continue
				var hb2 := HBoxContainer.new()
				hb2.add_child(UI.label("%s · %s" % [engine._hex_label(c["h"]), D.MOOD_NAME[c["mood"]]], 16, UI.INK))
				for st in range(1, 3 - c["mood"]):
					var b := UI.button("+%d (%d Cultura)" % [st, st], 170, 38, 14)
					b.disabled = engine.res(p, "culture") < st
					var cid: int = c["id"]
					var s2: int = st
					b.pressed.connect(func(): _provide({"t": "free", "what": "circus", "c": cid, "steps": s2}))
					hb2.add_child(b)
				vb5.add_child(hb2)
			_close_button(vb5, "Annulla")
		"statue":
			var vb6 := _open_modal("Grande Statua: scarta un Obiettivo per un'azione in più", 1000)
			var flow2 := HFlowContainer.new()
			vb6.add_child(flow2)
			for id in engine.players[p]["obj"]:
				var box2 := VBoxContainer.new()
				box2.add_child(_card_img(id, 140))
				var b := UI.button("Scarta", 140, 34, 14)
				var oid: String = id
				b.pressed.connect(func(): _provide({"t": "free", "what": "statue", "card": oid}))
				box2.add_child(b)
				flow2.add_child(box2)
			_close_button(vb6, "Annulla")
		"x_l01":
			_collect_dialog(p, engine.leader_city(p), true, "x_l01")
		"library":
			var lst := []
			for a in D.all_advances():
				var info: Dictionary = D.adv_info(a)
				if not info["cat"] in D.GOVERNMENTS and not engine.players[p]["adv"].has(a):
					lst.append(a)
			_show_advances(p, lst, func(a): _provide({"t": "free", "what": "library", "a": a}), "Grande Biblioteca: quale avanzamento usi in questo turno?")
		_:
			_provide({"t": "free", "what": w})


# ------------------------------------------------------------------ altre finestre

func _show_log() -> void:
	var vb := _open_modal("Diario della partita", 1000)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(980, 700)
	vb.add_child(sc)
	var r := UI.rich(16, UI.INK)
	r.custom_minimum_size = Vector2(950, 0)
	r.text = "\n".join(engine.log_lines)
	sc.add_child(r)
	_close_button(vb)


func _show_rules() -> void:
	var vb := _open_modal("Regole in breve", 1100)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1080, 760)
	vb.add_child(sc)
	var r := UI.rich(17, UI.INK)
	r.custom_minimum_size = Vector2(1050, 0)
	r.text = preload("res://scripts/ui/rules_view.gd").RULES
	sc.add_child(r)
	_close_button(vb)


func _toggle_audio() -> void:
	Audio.toggle_all()


func _ask_quit() -> void:
	var vb := _open_modal("Tornare al menu?", 520)
	vb.add_child(UI.label("La partita in corso andrà persa%s." % (" (online potrai rientrare con il codice)" if online != null else ""), 18, UI.INK))
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var b1 := UI.primary(UI.button("Torna al menu", 220, 46))
	b1.pressed.connect(func():
		engine.abort = true
		if online != null:
			online.alive = false
		main.show_menu())
	hb.add_child(b1)
	var b2 := UI.button("Continua", 160, 46)
	b2.pressed.connect(_clear_modal)
	hb.add_child(b2)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		if modal.get_child_count() > 0 and pending.get("type", "") != "choice":
			_clear_modal()
			board.set_targets({})


func _on_game_end(results: Array) -> void:
	await get_tree().create_timer(1.0).timeout
	Audio.play("win")
	if online != null:
		online.finish()
	var vb := _open_modal("Fine della partita", 1000)
	var win: int = results[0]["p"]
	var t := UI.title("Vince %s!" % engine.pname(win), 36, UI.pcol(win).darkened(0.1))
	vb.add_child(t)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 22)
	vb.add_child(grid)
	for h in ["Civiltà", "Pezzi", "Avanzamenti", "Obiettivi", "Meraviglie", "Eventi", "Totale"]:
		grid.add_child(UI.label(h, 18, UI.INK, UI.font_title))
	for r in results:
		var s: Dictionary = r["score"]
		grid.add_child(UI.label(engine.pname(r["p"]), 18, UI.pcol(r["p"]).darkened(0.2), UI.font_bold))
		grid.add_child(UI.label(str(s["pieces"]), 18, UI.INK))
		grid.add_child(UI.label(_num(s["adv"]), 18, UI.INK))
		grid.add_child(UI.label(str(s["obj"]), 18, UI.INK))
		grid.add_child(UI.label(_num(s["wonders"]), 18, UI.INK))
		grid.add_child(UI.label(_num(s["events"]), 18, UI.INK))
		grid.add_child(UI.label(_num(s["total"]), 20, UI.INK, UI.font_bold))
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var b1 := UI.primary(UI.button("Torna al menu", 240, 50))
	b1.pressed.connect(func(): main.show_menu())
	hb.add_child(b1)
	var b2 := UI.button("Guarda la mappa", 240, 50)
	b2.pressed.connect(_clear_modal)
	hb.add_child(b2)


# ------------------------------------------------------------------ online

func online_status(t: String) -> void:
	online_lbl.text = t


func online_waiting(seat: int, is_slow: bool) -> void:
	if seat < 0:
		online_lbl.text = ""
	else:
		online_lbl.text = "In attesa di %s…%s" % [engine.pname(seat), " (sembra lento: se non torna entro un minuto gioca l'IA)" if is_slow else ""]


func online_caught_up() -> void:
	Audio.suspended = false
	online_lbl.text = "Partita ripresa."
	refresh()


func online_cancel_decision(t: String) -> void:
	pending = {}
	_clear_modal()
	online_lbl.text = t
	refresh()
