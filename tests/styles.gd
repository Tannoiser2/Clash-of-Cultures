extends SceneTree
## Torneo fra gli stili dell'IA: in ogni partita 4 stili diversi, a rotazione su posti e mappe.
## godot --headless --path . -s res://tests/styles.gd -- <partite>   (COC_CIV=1 per Civiltà)

const AI = preload("res://scripts/core/ai.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 10
	var civ := OS.get_environment("COC_CIV") != ""
	var keys: Array = AI.STYLES.keys()
	var st := {}
	for k in keys:
		st[k] = {"g": 0, "w": 0, "pts": 0.0, "pvp": 0, "conq": 0, "won": 0, "units": 0, "ships": 0, "cities": 0, "pieces": 0.0, "adv": 0.0, "obj": 0.0}
	for g in games:
		var e = load("res://scripts/core/engine.gd").new()
		e.headless = true
		root.add_child(e)
		# 4 stili su 5, a rotazione
		var pick := []
		for i in 4:
			pick.append(keys[(g + i) % keys.size()])
		var seats := []
		for i in 4:
			seats.append({"color": i, "ai": true, "name": "IA%d" % i, "level": 1, "style": pick[(i + g) % 4]})
		e.setup({"seats": seats, "seed": 5000 + g, "opts": {"civ": civ}})
		e.log_added.connect(func(t: String):
			for p in 4:
				var nm: String = "IA%d" % p
				var k: String = e.players[p]["style"]
				if t.begins_with("Battaglia: " + nm + " attacca") and t.find("Barbari") < 0:
					st[k]["pvp"] += 1
				elif t.begins_with(nm + " conquista"):
					st[k]["conq"] += 1
				elif t.begins_with(nm + " costruisce") and t.ends_with("!"):
					st[k]["won"] += 1
		)
		await e.run()
		var winner: int = e.results[0]["p"]
		st[e.players[winner]["style"]]["w"] += 1
		for r in e.results:
			var k: String = e.players[r["p"]]["style"]
			st[k]["g"] += 1
			st[k]["pts"] += r["total"]
			for kk in ["pieces", "adv", "obj"]:
				st[k][kk] += float(r["score"][kk])
			st[k]["cities"] += e.cities_of(r["p"]).size()
			st[k]["units"] += e.units_of(r["p"]).filter(func(u): return e.is_army(u)).size()
			st[k]["ships"] += e.units_of(r["p"], "ship").size()
		e.queue_free()
	print("partite %d%s" % [games, " (Civiltà)" if civ else ""])
	for k in keys:
		var s: Dictionary = st[k]
		var n := float(maxi(1, s["g"]))
		print("%-14s partite %2d  vittorie %2d (%.0f%%)  punti %.1f  attacchi a giocatori %.1f  conquiste %.1f  meraviglie %.2f  eserciti %.1f  navi %.1f  città %.1f  (pezzi %.1f, avanz. %.1f, obiettivi %.1f)" % [AI.STYLES[k]["it"], s["g"], s["w"], 100.0 * s["w"] / n, s["pts"] / n, s["pvp"] / n, s["conq"] / n, s["won"] / n, s["units"] / n, s["ships"] / n, s["cities"] / n, s["pieces"] / n, s["adv"] / n, s["obj"] / n])
	quit()
