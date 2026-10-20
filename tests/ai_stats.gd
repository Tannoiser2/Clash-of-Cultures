extends SceneTree
## Statistiche sul comportamento dell'IA: reclutamenti per tipo, battaglie fra giocatori, meraviglie,
## risorse ferme in magazzino. godot --headless --path . -s res://tests/ai_stats.gd -- <partite> <giocatori>
## COC_CIV=1 per l'espansione Civiltà.

const D = preload("res://scripts/data/coc_data.gd")
var e
var samples := 0
var stock := 0.0
var capped := 0.0
var rec := {}
var pvp := 0
var pvp_city := 0
var barb := 0
var conquests := 0
var lost_res := 0


func _on_log(t: String) -> void:
	if t.begins_with("— Turno di"):
		for p in e.n:
			samples += 1
			for r in ["food", "wood", "ore", "idea", "gold"]:
				var v: int = e.res(p, r)
				stock += v
				if v >= e.res_limit(p, r):
					capped += 1
	elif t.find(" recluta ") >= 0:
		var rest := t.substr(t.find(" recluta ") + 9).trim_suffix(".")
		for part in rest.split(", "):
			var bits := part.split(" ", false, 1)
			if bits.size() == 2:
				var k := bits[1]
				rec[k] = rec.get(k, 0) + int(bits[0])
	elif t.begins_with("Battaglia:"):
		if t.find("Barbari") >= 0 or t.find("Pirati") >= 0:
			barb += 1
		else:
			pvp += 1
			if t.find("in città") >= 0:
				pvp_city += 1
	elif t.find("conquista la città") >= 0:
		conquests += 1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 4
	var np := int(args[1]) if args.size() > 1 else 4
	var civ := OS.get_environment("COC_CIV") != ""
	var won := 0
	var cities := 0
	var blds := 0
	var units_end := {}
	var bk := {}
	var t0 := Time.get_ticks_msec()
	for g in games:
		e = load("res://scripts/core/engine.gd").new()
		e.headless = true
		root.add_child(e)
		var seats := []
		for i in np:
			seats.append({"color": i, "ai": true, "name": "IA%d" % i, "level": 1})
		e.setup({"seats": seats, "seed": 2000 + g, "opts": {"civ": civ}})
		e.log_added.connect(_on_log)
		await e.run()
		won += e.wonder_builder.size()
		if OS.get_environment("WONDBG") != "":
			for p in np:
				for w in e.players[p]["won"]:
					print("MER p%d %s ing %s req %s cul %d felici %d città %d" % [p, w, e.has_adv(p, "Engineering"), e.has_adv(p, D.WONDERS[w]["req"]), e.res(p, "culture"), e.cities_of(p).filter(func(c): return c["mood"] == 2).size(), e.cities_of(p).size()])
		for p in np:
			cities += e.cities_of(p).size()
			for c in e.cities_of(p):
				blds += c["b"].size()
				for b in c["b"]:
					bk[b] = bk.get(b, 0) + 1
			for u in e.units_of(p):
				units_end[u["t"]] = units_end.get(u["t"], 0) + 1
		e.queue_free()
	var pg := float(games)
	print("partite %d, giocatori %d%s" % [games, np, " (Civiltà)" if civ else ""])
	print("reclutati per partita: ", rec.keys().map(func(k): return "%s %.1f" % [k, rec[k] / pg]))
	print("unità a fine partita per giocatore: ", units_end.keys().map(func(k): return "%s %.1f" % [k, units_end[k] / pg / np]))
	print("battaglie per partita: fra giocatori %.1f (contro città %.1f), contro barbari/pirati %.1f, città conquistate %.1f" % [pvp / pg, pvp_city / pg, barb / pg, conquests / pg])
	print("città per giocatore %.1f, edifici per giocatore %.1f, meraviglie per partita %.2f" % [cities / pg / np, blds / pg / np, won / pg])
	print("edifici per tipo per partita: ", bk.keys().map(func(k): return "%s %.1f" % [k, bk[k] / pg]))
	print("risorse ferme in media %.1f (su 5 tipi), tipi al limite %.2f" % [stock / maxi(1, samples), capped / maxi(1, samples)])
	print("tempo %d ms" % (Time.get_ticks_msec() - t0))
	quit()
