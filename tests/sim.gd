extends SceneTree
## Partite IA contro IA senza grafica, per provare le regole e tarare l'IA.
## godot --headless --path . -s res://tests/sim.gd -- <partite> <giocatori> [livelli es. 1,1,2] [log]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 3
	var np := int(args[1]) if args.size() > 1 else 3
	var levels := [1, 1, 1, 1]
	if args.size() > 2:
		var parts: PackedStringArray = args[2].split(",")
		for i in parts.size():
			levels[i] = int(parts[i])
	var show_log := args.size() > 3
	var wins := [0, 0, 0, 0]
	var tot := [0.0, 0.0, 0.0, 0.0]
	var t0 := Time.get_ticks_msec()
	for g in games:
		var e = load("res://scripts/core/engine.gd").new()
		e.headless = true
		root.add_child(e)
		var seats := []
		for i in np:
			seats.append({"color": i, "ai": true, "name": "IA%d" % i, "level": levels[i]})
		e.setup({"seats": seats, "seed": 1000 + g})
		await e.run()
		wins[e.results[0]["p"]] += 1
		for r in e.results:
			tot[r["p"]] += r["total"]
		if show_log and g == 0:
			for l in e.log_lines:
				print(l)
		var line := "partita %d:" % g
		for r in e.results:
			var s: Dictionary = r["score"]
			line += "  %s %.1f (città %d, pezzi %d, av %.1f, ob %d, mer %.1f)" % [e.pname(r["p"]), r["total"], e.cities_of(r["p"]).size(), s["pieces"], s["adv"], s["obj"], s["wonders"]]
		print(line)
		e.queue_free()
	print("vittorie: ", wins.slice(0, np), "  media punti: ", tot.slice(0, np).map(func(x): return snappedf(x / games, 0.1)))
	print("tempo %d ms" % (Time.get_ticks_msec() - t0))
	quit()
