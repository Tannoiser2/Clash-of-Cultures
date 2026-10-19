extends SceneTree
## Prova di tutte le azioni speciali dell'espansione: per ogni Leader e con tutti gli avanzamenti di civiltà,
## l'IA esegue ogni azione speciale disponibile. godot --headless --path . -s res://tests/exp_specials.gd

func _initialize() -> void:
	var seen := {}
	var codes: Array = CivData.LEADERS.keys()
	codes.sort()
	for code in codes:
		var e = load("res://scripts/core/engine.gd").new()
		e.headless = true
		root.add_child(e)
		e.setup({"seats": [{"color": 0, "ai": true, "name": "A"}, {"color": 1, "ai": true, "name": "B"}], "seed": 77, "opts": {"civ": true}})
		var pl: Dictionary = e.players[0]
		for ck in CivData.CIVS:
			for ca in CivData.CIVS[ck]["adv"]:
				pl["adv"].append(ca[0])
		for a in ["Tactics", "Myths", "Writing", "Bartering", "Arts", "Math", "Fishing", "Draft", "Taxation", "Roads", "Engineering", "Rituals", "Siegecraft", "Irrigation", "State Religion"]:
			if not pl["adv"].has(a):
				pl["adv"].append(a)
		pl["hand"].append("e56")
		pl["adv"].erase("Sanitation")
		pl["res"] = {"food": 7, "wood": 7, "ore": 7, "idea": 7, "gold": 7}
		pl["mood"] = 9
		pl["culture"] = 9
		pl["captives"] = 4
		pl["won"] = ["great_wall", "great_gardens"]
		var home: String = pl["home"]
		var c: Dictionary = e.city_at(home)
		c["mood"] = 2 if code in ["l38", "l21", "l15", "l13", "l43", "l14", "l06"] else 1
		c["b"]["temple"] = 1
		var added := 0
		for k in e.hexes:
			if added < (1 if code in ["l01", "l09"] else 4) and e.is_land(k) and e.city_at(k).is_empty() and e.hdist(k, home) >= 2 and e.units_at(k).is_empty():
				e.new_city(0, k, 1)
				added += 1
		pl["leader"] = code
		e.new_unit(0, "leader", home)
		e.new_unit(0, "settler", home)
		e.new_unit(0, "infantry", home)
		if not e.hexes.keys().any(func(x): return e.is_sea(x)):
			for x in e.neighbors(home):
				if e.is_land(x) and e.city_at(x).is_empty() and e.units_at(x).is_empty():
					e.hexes[x]["ter"] = "sea"
					break
		for k in e.hexes:
			if not e.is_sea(k) or not e.ships_at(k).is_empty():
				continue
			if not e.neighbors(k).any(func(x): return e.is_land(x) and e.city_at(x).is_empty()):
				continue
			var sh: Dictionary = e.new_unit(0, "ship", k)
			if code == "l44" or code == "l08":
				e.leader_unit(0)["on"] = sh["id"]
				e.leader_unit(0)["h"] = k
			break
		e.new_unit(1, "infantry", e.neighbors(home)[0])
		e.new_turn_state(0)
		e.cur = 0
		e.T["actions"] = 30
		if code == "l09":
			for x in e.hexes:
				if e.can_found_at(0, x) and e.hdist(x, home) >= 2:
					e.leader_unit(0)["h"] = x
					e.new_unit(0, "settler", x)
					break
		print(code, " opzioni: ", e.free_options(0))
		var tried := {}
		for x in ["x_sacrifice", "x_hegemony", "x_calendar", "x_bands", "x_tallies", "x_nomads", "x_aqueducts"]:
			if not ((code == "l01" and x != "x_hegemony") or (code == "l02" and x == "x_hegemony")):
				tried[x] = true
		for guard in 40:
			var w := ""
			for x in e.free_options(0):
				if x.begins_with("x_") and not tried.has(x):
					w = x
					break
			if w == "":
				break
			tried[w] = true
			var ok = await e.apply_move(0, {"t": "free", "what": w})
			seen[w] = seen.get(w, 0) + (1 if ok else 0)
			print("%s %s -> %s" % [code, w, ok])
		e.queue_free()
	print("FATTE: ", seen)
	print("MANCANO: ", e_missing(seen))
	quit()


func D_all() -> Array:
	return preload("res://scripts/data/coc_data.gd").all_advances()


func e_missing(seen: Dictionary) -> Array:
	var out := []
	for w in load("res://scripts/core/engine.gd").new().XNAME:
		if not seen.has(w):
			out.append(w)
	return out
