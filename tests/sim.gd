extends SceneTree
## Partite IA contro IA senza grafica, per provare le regole e tarare l'IA.
## godot --headless --path . -s res://tests/sim.gd -- <partite> <giocatori> [livelli es. 1,1,2] [log]
## Variabile d'ambiente COC_CIV=1: partite con l'espansione Civiltà; AI_STYLE=aggressive (o un altro stile, o random).

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
	var stat_b := 0
	var stat_n := 0
	var stat_w := 0
	var stat_c := 0
	for g in games:
		var e = load("res://scripts/core/engine.gd").new()
		e.headless = true
		root.add_child(e)
		var seats := []
		for i in np:
			seats.append({"color": i, "ai": true, "name": "IA%d" % i, "level": levels[i], "style": OS.get_environment("AI_STYLE") if OS.get_environment("AI_STYLE") != "" else "balanced"})
		var civ := OS.get_environment("COC_CIV") != ""
		e.setup({"seats": seats, "seed": 1000 + g, "opts": {"civ": civ}})
		if civ and OS.get_environment("COC_FUZZ") != "":
			# prova di resistenza: tutti hanno tutti gli avanzamenti di civiltà e Leader di ogni civiltà
			var all_l: Array = CivData.LEADERS.keys()
			all_l.sort()
			e.shuffle(all_l)
			for p in np:
				for ck in CivData.CIVS:
					for ca in CivData.CIVS[ck]["adv"]:
						if not e.players[p]["adv"].has(ca[0]):
							e.players[p]["adv"].append(ca[0])
				e.players[p]["leaders_avail"] = all_l.slice(p * 11, p * 11 + 11)
		await e.run()
		wins[e.results[0]["p"]] += 1
		for r in e.results:
			tot[r["p"]] += r["total"]
		if show_log and g == 0:
			for l in e.log_lines:
				print(l)
		var line := "partita %d (era %d):" % [g, e.age]
		if civ:
			for p in np:
				line += " [%s %s]" % [e.pname(p), e.players[p]["civ"]]
		for r in e.results:
			var s: Dictionary = r["score"]
			line += "  %s %.1f (città %d, pezzi %d, av %.1f, ob %d, mer %.1f)" % [e.pname(r["p"]), r["total"], e.cities_of(r["p"]).size(), s["pieces"], s["adv"], s["obj"], s["wonders"]] + (" ev %.1f" % s["events"])
		print(line)
		for r in e.results:
			var s2: Dictionary = r["score"]
			stat_b += s2["pieces"] - e.cities_of(r["p"]).size()
			stat_c += e.cities_of(r["p"]).size()
			stat_n += 1
		stat_w += e.wonder_builder.size()
		e.queue_free()
	print("vittorie: ", wins.slice(0, np), "  media punti: ", tot.slice(0, np).map(func(x): return snappedf(x / games, 0.1)))
	print("città medie %.1f, edifici medi per giocatore %.1f, meraviglie per partita %.2f" % [float(stat_c) / maxi(1, stat_n), float(stat_b) / maxi(1, stat_n), float(stat_w) / games])
	print("tempo %d ms" % (Time.get_ticks_msec() - t0))
	quit()
