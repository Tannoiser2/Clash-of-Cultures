extends SceneTree
## Screenshot automatici dell'interfaccia (serve un display: xvfb-run).
## xvfb-run godot --path . -s res://tests/shot.gd -- <modo: menu|rules|game> [turni]

var main
var n := 0

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/shots")
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func shot(name: String) -> void:
	for i in 4:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	n += 1
	img.save_png(OS.get_user_data_dir() + "/shots/%02d_%s.png" % [n, name])
	print("shot ", name)


func wait(f := 10) -> void:
	for i in range(f):
		await process_frame


func gv():
	return main.current


func auto_answer() -> void:
	var g = gv()
	var req: Dictionary = g.pending
	if req.is_empty():
		return
	var r = g.engine.ais[int(req["seat"])].decide(g.engine, int(req["seat"]), req)
	g._provide(r)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "game"
	var turns := int(args[1]) if args.size() > 1 else 6
	await wait(5)
	await shot("menu")
	if mode == "menu":
		quit()
		return
	if mode == "rules":
		main.show_rules()
		await wait(5)
		await shot("rules")
		quit()
		return
	var seats := [{"color": 0, "ai": false, "name": "Roma", "level": 1}, {"color": 1, "ai": true, "name": "Persia", "level": 1},
		{"color": 2, "ai": true, "name": "Egitto", "level": 1}, {"color": 3, "ai": true, "name": "Cartagine", "level": 1}]
	main.start_game({"seats": seats, "seed": 77, "ai_delay": 0.0})
	await wait(30)
	await shot("start")
	var g = gv()
	# seleziona la propria capitale
	var home: String = g.engine.players[0]["home"]
	g._on_hex(home)
	await wait(5)
	await shot("city")
	g._show_advances(0, g.engine.buyable_advances(0), func(a): pass)
	await wait(5)
	await shot("advances")
	g._clear_modal()
	g._collect_dialog(0, g.engine.city_at(home), false)
	await wait(5)
	await shot("collect")
	g._clear_modal()
	g._recruit_dialog(0, g.engine.city_at(home))
	await wait(5)
	await shot("recruit")
	g._clear_modal()
	g._happy_dialog(0, false)
	await wait(5)
	await shot("happy")
	g._clear_modal()
	g._show_cards(0)
	await wait(5)
	await shot("cards0")
	g._clear_modal()
	# movimento come farebbe una persona: Muovi, clic sul colono, clic sulla destinazione
	g._provide({"t": "move"})
	await wait(10)
	g._on_hex(home)
	await wait(5)
	await shot("move_select")
	var tg: Dictionary = g.engine.move_targets(0, g.move_sel)
	print("bersagli ", tg.keys())
	if not tg.is_empty():
		g._on_hex(tg.keys()[0])
		await wait(10)
		await shot("moved")
	if g.pending.get("type", "") == "choice":
		auto_answer()
		await wait(5)
	if g.pending.get("type", "") == "move":
		g._provide({"done": true})
	var count := 0
	var t0 := Time.get_ticks_msec()
	while g.engine.turn_count < turns * 4 and not g.engine.game_over and Time.get_ticks_msec() - t0 < 400000:
		await wait(2)
		if not g.pending.is_empty():
			if g.pending["type"] == "choice" and count < 3:
				count += 1
				await shot("choice_%d" % count)
			auto_answer()
	await wait(20)
	if g.engine.game_over:
		await wait(90)
		await shot("end")
		g._clear_modal()
	g.board.focus(home)
	await wait(30)
	await shot("later")
	g._show_cards(0)
	await wait(5)
	await shot("cards")
	quit()
