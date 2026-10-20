extends SceneTree
## Nuova IA contro la versione precedente (tests/ai_old.gd): metà posti ciascuna; ogni mappa si gioca due volte
## scambiando i posti, così la posizione non conta.
## godot --headless --path . -s res://tests/duel.gd -- <partite> [giocatori]   (COC_CIV=1 per Civiltà)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 8
	var np := int(args[1]) if args.size() > 1 else 4
	var civ := OS.get_environment("COC_CIV") != ""
	var wins := {"nuova": 0, "vecchia": 0}
	var pts := {"nuova": 0.0, "vecchia": 0.0}
	var det := {}
	for g in games:
		var e = load("res://scripts/core/engine.gd").new()
		e.headless = true
		root.add_child(e)
		var seats := []
		for i in np:
			seats.append({"color": i, "ai": true, "name": "IA%d" % i, "level": 1})
		e.setup({"seats": seats, "seed": int(OS.get_environment("DUEL_SEED")) + 3000 + g / 2, "opts": {"civ": civ}})
		var who := {}
		for p in np:
			var old: bool = (p + g) % 2 == 0
			who[p] = "vecchia" if old else "nuova"
			if old or OS.get_environment("DUEL_SAME") != "":
				var a = load("res://tests/ai_old.gd").new()
				a.level = 1
				a.rng.seed = 77 + g * 13 + p
				e.ais[p] = a
		var cur := {"who": who, "e": e}
		e.log_added.connect(func(t: String):
			for p in np:
				var nm: String = "IA%d" % p
				if t.begins_with("Battaglia: " + nm + " attacca"):
					var kk: String = who[p] + ("_att_barb" if t.find("Barbari") >= 0 else "_att_pvp")
					det[kk] = det.get(kk, 0.0) + 1.0
				elif t.begins_with(nm + " vince la battaglia"):
					det[who[p] + "_vinte"] = det.get(who[p] + "_vinte", 0.0) + 1.0
				elif t.begins_with(nm + " conquista la città"):
					det[who[p] + "_conq_pvp"] = det.get(who[p] + "_conq_pvp", 0.0) + 1.0
				elif t.begins_with(nm + " conquista una città barbara"):
					det[who[p] + "_conq_barb"] = det.get(who[p] + "_conq_barb", 0.0) + 1.0
				elif t.begins_with(nm + " ottiene ") and t.find("civiltà") < 0:
					det[who[p] + "_avz"] = det.get(who[p] + "_avz", 0.0) + 1.0
				elif t.begins_with(nm + " raccoglie"):
					det[who[p] + "_racc"] = det.get(who[p] + "_racc", 0.0) + 1.0
				elif t.begins_with(nm + " costruisce"):
					det[who[p] + "_costr"] = det.get(who[p] + "_costr", 0.0) + 1.0
				elif t.begins_with(nm + " muove"):
					det[who[p] + "_muove"] = det.get(who[p] + "_muove", 0.0) + 1.0
				elif t.begins_with(nm + " recluta"):
					det[who[p] + "_recl"] = det.get(who[p] + "_recl", 0.0) + 1.0
		)
		await e.run()
		wins[who[e.results[0]["p"]]] += 1
		for r in e.results:
			pts[who[r["p"]]] += r["total"]
			var sc: Dictionary = r["score"]
			for k in ["pieces", "adv", "obj", "wonders", "events"]:
				var kk: String = who[r["p"]] + "_" + k
				det[kk] = det.get(kk, 0.0) + float(sc.get(k, 0))
			det[who[r["p"]] + "_città"] = det.get(who[r["p"]] + "_città", 0.0) + e.cities_of(r["p"]).size()
		e.queue_free()
	print("vittorie: nuova %d, vecchia %d — punti medi: nuova %.1f, vecchia %.1f" % [wins["nuova"], wins["vecchia"], pts["nuova"] / (games * np / 2.0), pts["vecchia"] / (games * np / 2.0)])
	var half := games * np / 2.0
	for side in ["nuova", "vecchia"]:
		var parts := []
		for k in ["città", "pieces", "adv", "obj", "wonders", "events", "att_pvp", "att_barb", "vinte", "conq_pvp", "conq_barb", "recl", "avz", "racc", "costr", "muove"]:
			parts.append("%s %.1f" % [k, det.get(side + "_" + k, 0.0) / half])
		print(side, ": ", ", ".join(parts))
	quit()
