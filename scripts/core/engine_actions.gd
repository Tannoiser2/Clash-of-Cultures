extends "res://scripts/core/engine_state.gd"
## Preparazione della partita e azioni del turno: avanzamenti, fondazione, attivazione delle città
## (raccolta, costruzione, reclutamento, meraviglie), felicità, influenza culturale, esplorazione.

const LAYOUT_FOR := {2: "1", 3: "2", 4: "0"}

# ------------------------------------------------------------------ preparazione

## config: {"seats":[{"color","ai","name","level","style"}], "seed", "opts":{}}
## style: personalità dell'IA ("balanced", "aggressive", "defensive", "builder", "seafarer" o "random").
func setup(config: Dictionary) -> void:
	if config.has("seed"):
		rng.seed = int(config["seed"])
	else:
		rng.randomize()
	opts = config.get("opts", {}).duplicate()
	exp = bool(opts.get("civ", false))
	ai_delay = float(config.get("ai_delay", 0.0))
	players.clear()
	for st in config["seats"]:
		players.append({"color": int(st["color"]), "ai": bool(st["ai"]), "name": str(st["name"]),
			"level": int(st.get("level", 1)), "style": str(st.get("style", "balanced")), "res": {"food": 2, "wood": 0, "ore": 0, "idea": 0, "gold": 0},
			"mood": 0, "culture": 0, "adv": ["Farming", "Mining"], "tracker": 3, "hand": [], "obj": [],
			"won": [], "done": [], "vp_extra": 0.0, "home": "", "events": [], "gov_cubes": 0})
	n = players.size()
	if exp:
		# espansione Civiltà: una civiltà a caso per giocatore, con i suoi 3 leader
		var civs: Array = CivData.CIVS.keys()
		civs.sort()
		shuffle(civs)
		for p in n:
			var ck: String = civs[p]
			players[p]["civ"] = ck
			players[p]["leaders_avail"] = CivData.CIVS[ck]["leaders"].duplicate()
			players[p]["leader"] = ""
			players[p]["leaders_ever"] = 0
			players[p]["killed_leaders"] = []
			players[p]["captives"] = 0
			players[p]["no_leader"] = false
			# i nomi predefiniti del menu diventano quelli della civiltà assegnata
			if players[p]["name"] in ["Roma", "Persia", "Egitto", "Cartagine", ""]:
				players[p]["name"] = CivData.CIVS[ck]["it"]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/tiles.json"))
	var lay: Array = data["layouts"][LAYOUT_FOR[n]]
	var tiles: Array = data["tiles"]
	var tile_ter := {}
	for t in tiles:
		tile_ter[t["id"]] = t["terrain"]
	set_meta("tile_ter", tile_ter)
	hexes.clear()
	regions.clear()
	var starts := []
	for i in lay.size():
		var reg: Dictionary = lay[i]
		var keys := []
		for h in reg["hexes"]:
			var k := hk(int(h[0]), int(h[1]))
			keys.append(k)
			hexes[k] = {"c": int(h[0]), "r": int(h[1]), "reg": i, "ter": "", "exhausted": false}
		var r := {"hexes": keys, "tile": "", "revealed": false, "theta": 0.0, "slots": {}, "start": bool(reg["start"]),
			"orients": _orients(keys)}
		regions.append(r)
		if r["start"]:
			starts.append(i)
	tile_bag.clear()
	for t in tiles:
		if t["id"] != "start":
			tile_bag.append(t["id"])
	shuffle(tile_bag)
	# centro del tabellone, per orientare le regioni di partenza
	var cen := Vector2.ZERO
	for k in hexes:
		cen += hpos(k)
	cen /= hexes.size()
	set_meta("center", cen)
	var order := range(n)
	shuffle(starts)
	for p in n:
		var ri: int = starts[p]
		var reg: Dictionary = regions[ri]
		var best := 0
		var bd := INF
		for oi in 2:
			var tk: String = reg["orients"][oi]["slots"]["T"]
			var d := hpos(tk).distance_to(cen)
			if d < bd:
				bd = d
				best = oi
		var stile := "start"
		if exp:
			var alt: String = CivData.CIVS[players[p]["civ"]]["tile"]
			if alt != "" and tile_ter.has(alt):
				stile = alt
		_reveal_region(ri, stile, best)
		var home: String = reg["slots"]["T"]
		players[p]["home"] = home
		var c := new_city(p, home, 2)
		new_unit(p, "settler", home)
		if opts.get("short", false):
			new_unit(p, "settler", home)
	# mazzi
	for a in D.ACTIONS:
		decks["action"].append(a[0])
	for o in D.OBJECTIVES:
		decks["objective"].append("o%d" % o[0])
	if exp:
		for o in D.OBJECTIVES_EXP:
			decks["objective"].append("o%d" % o[0])
	for e in D.EVENTS:
		if exp or int(e.substr(1)) <= 38:
			decks["event"].append(e)
	for w in D.WONDERS:
		decks["wonder"].append(w)
	for k in decks:
		shuffle(decks[k])
	for p in n:
		draw_action(p)
		draw_objective(p)
	first = rng.randi() % n
	for p in n:
		var a = load("res://scripts/core/ai.gd").new()
		a.level = players[p]["level"]
		if players[p]["ai"]:
			var keys: Array = a.STYLES.keys()
			if players[p]["style"] == "random" or not keys.has(players[p]["style"]):
				players[p]["style"] = keys[rng.randi() % keys.size()] if players[p]["style"] == "random" else "balanced"
			a.style = players[p]["style"]
		a.rng.seed = rng.seed + 7919 * (p + 1)
		ais[p] = a


## Le due orientazioni possibili di una regione: quali caselle fanno da T, L, R, B.
func _orients(keys: Array) -> Array:
	var far := []
	for i in 4:
		for j in range(i + 1, 4):
			if hdist(keys[i], keys[j]) == 2:
				far = [keys[i], keys[j]]
	var mids := []
	for k in keys:
		if not k in far:
			mids.append(k)
	var cen := Vector2.ZERO
	for k in keys:
		cen += hpos(k)
	cen /= 4.0
	var out := []
	for flip in 2:
		var L: String = far[flip]
		var R: String = far[1 - flip]
		var d := (hpos(R) - hpos(L)).normalized()
		var up := Vector2(d.y, -d.x)
		var m0: String = mids[0]
		var m1: String = mids[1]
		var t := m0 if (hpos(m0) - cen).dot(up) > (hpos(m1) - cen).dot(up) else m1
		var b := m1 if t == m0 else m0
		out.append({"theta": atan2(d.y, d.x), "slots": {"T": t, "L": L, "R": R, "B": b}})
	return out


func _reveal_region(ri: int, tile: String, oi: int) -> void:
	var reg: Dictionary = regions[ri]
	var tt: Dictionary = get_meta("tile_ter")[tile]
	reg["tile"] = tile
	reg["revealed"] = true
	reg["theta"] = reg["orients"][oi]["theta"]
	reg["slots"] = reg["orients"][oi]["slots"]
	for s in reg["slots"]:
		hexes[reg["slots"][s]]["ter"] = tt[s]


func region_of(k: String) -> int:
	return hexes[k]["reg"] if hexes.has(k) else -1


## Caselle sul bordo del tabellone (con almeno un vicino fuori mappa).
func on_edge(k: String) -> bool:
	return neighbors(k).size() < 6


## Esplora una regione. entered: casella in cui entra l'unità di terra ("" per le navi).
## from_sea: casella di mare della nave che esplora. Restituisce l'orientamento scelto.
func explore(p: int, ri: int, entered: String, from_sea := "") -> void:
	var reg: Dictionary = regions[ri]
	if reg["revealed"]:
		return
	if tile_bag.is_empty():
		return
	var tile: String = tile_bag.pop_back()
	var tt: Dictionary = get_meta("tile_ter")[tile]
	var legal := []
	for oi in 2:
		var sl: Dictionary = reg["orients"][oi]["slots"]
		var ter_of := {}
		for s in sl:
			ter_of[sl[s]] = tt[s]
		if entered != "" and ter_of.get(entered, "") == "sea":
			continue
		legal.append({"oi": oi, "ter": ter_of})
	if legal.is_empty():
		legal = [{"oi": 0, "ter": {}}]
	var pref := legal
	if from_sea != "":
		# nave: se possibile i mari della regione devono essere raggiungibili dalla nave
		var reach: Dictionary = sea_reach(from_sea, p, false)
		var good := []
		for o in legal:
			for k in o["ter"]:
				if o["ter"][k] == "sea":
					for x in neighbors(k):
						if reach.has(x):
							good.append(o)
							break
					if good.has(o):
						break
		if not good.is_empty():
			pref = good
	if pref.size() > 1:
		var good2 := []
		for o in pref:
			for k in o["ter"]:
				if o["ter"][k] == "sea":
					var ok := false
					for x in neighbors(k):
						if region_of(x) != ri and is_sea(x):
							ok = true
					if ok:
						good2.append(o)
						break
		if not good2.is_empty():
			pref = good2
		else:
			var good3 := []
			for o in pref:
				for k in o["ter"]:
					if o["ter"][k] == "sea" and on_edge(k):
						good3.append(o)
						break
			if not good3.is_empty():
				pref = good3
	var pick: Dictionary = pref[0]
	if pref.size() > 1:
		var labels := []
		for o in pref:
			var parts := []
			for s in ["T", "L", "R", "B"]:
				parts.append(D.TER_NAME[tt[s]])
			labels.append("Orientamento %d" % (labels.size() + 1))
		set_meta("explore_preview", {"ri": ri, "tile": tile, "options": pref.map(func(o): return o["oi"])})
		var i := await choose(p, "Scegli come orientare la regione scoperta", labels, {"explore": true, "ri": ri, "tile": tile, "oi": pref.map(func(o): return o["oi"])})
		pick = pref[i]
		remove_meta("explore_preview")
	_reveal_region(ri, tile, pick["oi"])
	log_msg("%s esplora una nuova regione." % pname(p))
	fx.emit("reveal", {"ri": ri})
	changed.emit()


# ------------------------------------------------------------------ turno: utilità

func new_turn_state(p: int) -> void:
	T = {"p": p, "actions": 3, "act_city": {}, "angry_act": {}, "mv": {}, "infl_ok": false,
		"husbandry": false, "pubed": false, "statrel": false, "arts": false, "drama": false, "bartering": false,
		"absolute": false, "priesthood": false, "econlib": false, "collects": 0, "draft_recruits": 0,
		"won_army": false, "captured": false, "captured_from": [], "battles": [], "battle_wins": 0,
		"library": "", "library_used": false, "statue": false, "taxation": false, "forced": false, "played": [],
		"ships_moved": false, "nav_used": false, "warlord_bonus": false}
	for c in cities_of(p):
		c["act"] = 0


func eff_size(c: Dictionary) -> int:
	var s := city_size(c)
	var m: int = c["mood"]
	if exp and c["o"] >= 0:
		var o: int = c["o"]
		# Ballcourts (Maya): 1 Umore per una città non Arrabbiata di 1 più grande
		if T.get("bc_city", -1) == c["id"] and m > 0:
			s += 1
		# Attila: le città Felici o Neutrali di dimensione 1 in cui si trova valgono 1 in più
		if leader_is(o, "l22") and leader_at(o, c["h"]) and city_size(c) == 1 and m > 0:
			s += 1
		# Bleda: la sua città funziona come Felice alla prima attivazione
		if leader_is(o, "l23") and leader_at(o, c["h"]) and c["act"] == 0:
			m = 2
	if m == 0 and T.get("forced", false) and c["o"] == T.get("p", -1):
		m = 1
	if m == 2:
		return s + 1
	if m == 0:
		return 1
	return s


func can_activate(c: Dictionary) -> bool:
	if exp and c["o"] >= 0 and c["act"] >= 1 and leader_is(c["o"], "l23") and leader_at(c["o"], c["h"]):
		return false
	if c["mood"] == 0 and T["angry_act"].has(c["id"]):
		return false
	if c["mood"] == 0 and c["act"] > 0 and not T["angry_act"].has(c["id"]):
		# città diventata arrabbiata in questo turno: può ancora attivarsi una volta
		return true
	return true


func activate(c: Dictionary) -> void:
	if c["mood"] == 0:
		T["angry_act"][c["id"]] = true
	c["act"] += 1


## Dopo l'azione: ogni attivazione in più nello stesso turno peggiora l'umore.
func after_activation(c: Dictionary) -> void:
	var p: int = c["o"]
	if exp and p >= 0:
		# Imhotep: +1 Idea quando la sua città si attiva per altro che raccogliere
		if leader_is(p, "l17") and leader_at(p, c["h"]) and not T.get("act_collect", false):
			gain(p, "idea", 1)
		# Città Stato (Grecia): una volta per turno un'altra città si considera attivata al posto di questa
		if c["act"] > 1 and civ_adv(p, "City-States") and not T.get("citystates", false):
			for x in cities_of(p):
				if x["id"] != c["id"] and x["act"] == 0 and city_size(x) >= city_size(c) and x["mood"] >= c["mood"]:
					T["citystates"] = true
					c["act"] -= 1
					x["act"] += 1
					log_msg("Città Stato: %s evita il calo d'umore." % pname(p))
					break
	if c["act"] > 1:
		change_mood(c, -1)
		log_msg("La città di %s si è attivata di nuovo: l'umore peggiora (%s)." % [pname(c["o"]), D.MOOD_NAME[c["mood"]]])


func spend_action(free: bool) -> void:
	if not free and T.get("free_next", false):
		# Shogunato / Alessandro: questa carta «come azione» non costa un'azione
		T["free_next"] = false
		return
	if not free:
		T["actions"] -= 1


# ------------------------------------------------------------------ avanzamenti

func can_buy_adv(p: int, a: String) -> bool:
	var info := D.adv_info(a)
	if info.is_empty() or players[p]["adv"].has(a) or info["cat"] == "Civ":
		return false
	var cat: String = info["cat"]
	var top: String = D.ADV[cat][0][0]
	if a != top and not players[p]["adv"].has(top):
		return false
	if cat in D.GOVERNMENTS:
		var g := gov_of(p)
		if g != "" and g != cat:
			return false
		if a == top and not players[p]["adv"].has(D.GOV_REQ[cat]):
			return false
	return true


func adv_food_cost(p: int, a: String) -> int:
	var info := D.adv_info(a)
	if a in ["Engineering", "Roads"] and has_adv(p, "Math"):
		return 0
	if a in ["Navigation", "Cartography"] and has_adv(p, "Astronomy"):
		return 0
	if info["cat"] == "Science" and has_adv(p, "Priesthood") and not T.get("priesthood", false):
		return 0
	if a == "Sanitation" and civ_adv(p, "Aqueducts"):
		return 0
	if info["cat"] == "Spirituality" and civ_adv(p, "Ballcourts") and not T.get("ballcourts", false):
		return 1
	return 2


func buyable_advances(p: int) -> Array:
	var out := []
	for a in D.all_advances():
		if can_buy_adv(p, a) and can_pay(p, {"food": adv_food_cost(p, a)}, ["idea"]):
			out.append(a)
	return out


## Ottiene un avanzamento. from_tracker: cubetto dal segnaeventi (può scatenare un evento).
func gain_advance(p: int, a: String, from_tracker := true) -> void:
	if players[p]["adv"].has(a):
		return
	players[p]["adv"].append(a)
	var info := D.adv_info(a)
	log_msg("%s ottiene %s." % [pname(p), info["it"]])
	if info["border"] == "m":
		gain(p, "mood", 1)
	elif info["border"] == "c":
		gain(p, "culture", 1)
	match a:
		"Writing":
			draw_action(p)
			draw_objective(p)
		"Engineering", "Monuments":
			draw_wonder(p)
		"Philosophy":
			gain(p, "idea", 1)
		"Dogma":
			players[p]["res"]["idea"] = mini(players[p]["res"]["idea"], 2)
	if info["cat"] == "Science" and has_adv(p, "Philosophy") and a != "Philosophy":
		gain(p, "idea", 1)
	if exp and info["cat"] != "Civ":
		_grant_civ_advances(p, a, info["cat"] in D.GOVERNMENTS)
	if exp and info["cat"] in D.GOVERNMENTS and int(players[p].get("anarchy", 0)) > 0:
		players[p]["anarchy"] -= 1
	fx.emit("advance", {"p": p, "a": a})
	changed.emit()
	if from_tracker:
		players[p]["tracker"] -= 1
		if players[p]["tracker"] <= 0:
			players[p]["tracker"] = 3
			await resolve_event(p)


## Espansione: gli avanzamenti di civiltà collegati arrivano subito (cubetto dalla riserva, nessun evento).
func _grant_civ_advances(p: int, a: String, gov: bool) -> void:
	var ck: String = players[p].get("civ", "")
	if ck == "":
		return
	for ca in CivData.CIVS[ck]["adv"]:
		if players[p]["adv"].has(ca[0]):
			continue
		if ca[2] == a or (ca[2] == "gov" and gov):
			players[p]["adv"].append(ca[0])
			log_msg("%s ottiene l'avanzamento di civiltà %s." % [pname(p), ca[1]])
			fx.emit("advance", {"p": p, "a": ca[0]})
			if ca[0] == "Ziggurats":
				pass


func do_advance(p: int, a: String, free_food := false, from_tracker := true) -> bool:
	if not can_buy_adv(p, a):
		return false
	var fc := 0 if free_food else adv_food_cost(p, a)
	if fc == 0 and not free_food and D.adv_info(a)["cat"] == "Science" and has_adv(p, "Priesthood") and not (a in ["Engineering", "Roads", "Navigation", "Cartography"]):
		T["priesthood"] = true
	if fc == 1 and not free_food and civ_adv(p, "Ballcourts") and D.adv_info(a)["cat"] == "Spirituality":
		T["ballcourts"] = true
	var paid := {}
	if fc > 0:
		if not can_pay(p, {"food": fc}, ["idea"]):
			return false
		# si pagano prima le Idee (servono solo per gli avanzamenti), poi il Cibo
		var ui := mini(fc, res(p, "idea"))
		paid = pay(p, {"idea": ui, "food": fc - ui}, ["idea"])
	await gain_advance(p, a, from_tracker)
	if has_adv(p, "Free Education") and (paid.get("idea", 0) > 0 or paid.get("gold", 0) > 0) and a != "Free Education" and res(p, "idea") > 0:
		if await yes_no(p, "Istruzione Gratuita: cambiare 1 Idea in 1 Umore?", "Sì, cambia", "No"):
			lose(p, "idea", 1)
			gain(p, "mood", 1)
	return true


# ------------------------------------------------------------------ fondazione

## Predoni (Unni): i coloni nemici entro 2 caselle da un esercito unno, se soli, non fondano né commerciano.
func raided(p: int, k: String) -> bool:
	if not city_at(k).is_empty() or not armies_at(k, p).is_empty():
		return false
	for q in n:
		if q == p or not civ_adv(q, "Raiders"):
			continue
		for u in units_of(q):
			if is_army(u) and hdist(u["h"], k) <= 2:
				return true
	return false


func can_found_at(p: int, k: String) -> bool:
	if not is_land(k) or hexes[k]["exhausted"]:
		return false
	if ter(k) == "barren" and not civ_adv(p, "Flood Plains"):
		return false
	if exp and raided(p, k):
		return false
	if not city_at(k).is_empty():
		return false
	for u in units_at(k):
		if u["o"] != p:
			return false
	return supply_left(p, "settlement") > 0


func foundable_settlers(p: int) -> Array:
	var out := []
	for u in units_of(p, "settler"):
		if u["on"] == -1 and can_found_at(p, u["h"]):
			out.append(u)
	return out


func do_found(p: int, uid: int) -> bool:
	if not units.has(uid):
		return false
	var u: Dictionary = units[uid]
	if u["o"] != p or u["t"] != "settler" or u["on"] != -1 or not can_found_at(p, u["h"]):
		return false
	var k: String = u["h"]
	units.erase(uid)
	new_city(p, k, 1)
	# Boudicca, grandi numeri: 1 Cibo per tenere il Colono
	if lcode(p) == "l10" and leader_at(p, k) and res(p, "food") >= 1 and supply_left(p, "settler") > 0:
		if await yes_no(p, "Boudicca: paghi 1 Cibo per tenere il Colono?"):
			lose(p, "food", 1)
			new_unit(p, "settler", k)
	log_msg("%s fonda una città (%s)." % [pname(p), D.TER_NAME[ter(k)]])
	if civ_adv(p, "Aztec Gold"):
		gain(p, "gold", 1)
		# per ogni Montagna adiacente si può cambiare 1 risorsa, Umore o Cultura in Oro
		for x in neighbors(k):
			if ter(x) != "mountain":
				continue
			var kinds: Array = (["food", "wood", "ore", "idea", "mood", "culture"] as Array).filter(func(r): return res(p, r) > 0)
			if kinds.is_empty():
				break
			var j := await choose(p, "Oro Azteco: cambi qualcosa in 1 Oro?", ["No"] + kinds.map(func(r): return D.RES_NAME[r]), {"force": true})
			if j == 0:
				break
			lose(p, kinds[j - 1], 1)
			gain(p, "gold", 1)
	if civ_adv(p, "Stelas"):
		gain(p, "culture", 1)
	fx.emit("found", {"h": k})
	changed.emit()
	await check_now(p, "found", {"h": k})
	return true


# ------------------------------------------------------------------ raccolta

## Caselle e risorse raccoglibili da una città: [{h, opts:[risorse]}], più i limiti.
func collect_options(c: Dictionary) -> Dictionary:
	var p: int = c["o"]
	var slots := []
	var keys := [c["h"]] + neighbors(c["h"])
	var gardens: bool = "great_gardens" in c["w"]
	for k in keys:
		var o := _collect_res(p, k, c, gardens)
		if not o.is_empty():
			slots.append({"h": k, "opts": o, "far": false})
	var far := []
	if has_adv(p, "Husbandry") and not T.get("husbandry", false):
		for k in within(c["h"], 2, false):
			if hdist(k, c["h"]) == 2 and is_land(k):
				var o2 := _collect_res(p, k, c, false)
				if not o2.is_empty():
					far.append({"h": k, "opts": o2, "far": true})
	# Tributi all'Impero (Aztechi): anche dalle caselle con città nemiche entro 2 (le barbare danno anche Prigionieri)
	if civ_adv(p, "Tribute Empire"):
		for k in within(c["h"], 2, false):
			var oc := city_at(k)
			if oc.is_empty() or oc["o"] == p:
				continue
			var t := ter(k)
			var o3: Array = []
			match t:
				"plains":
					o3 = ["food"]
				"forest":
					o3 = ["wood"]
				"mountain":
					o3 = ["ore"]
				"barren":
					o3 = ["food"] if has_adv(p, "Irrigation") or civ_adv(p, "Flood Plains") else []
			if oc["o"] == -1 and not armies_at(k, -1).is_empty() and int(players[p].get("captives", 0)) < 4:
				o3.append("captive")
			if not o3.is_empty():
				slots.append({"h": k, "opts": o3, "far": false})
	return {"slots": slots, "far": far, "count": eff_size(c), "far_max": 2 if has_adv(p, "Roads") else 1}


func _collect_res(p: int, k: String, c: Dictionary, gardens: bool) -> Array:
	if not revealed(k) or hexes[k]["exhausted"]:
		return []
	for u in units_at(k):
		if u["o"] != p:
			return []
	var oc := city_at(k)
	if not oc.is_empty() and oc["id"] != c["id"]:
		return []
	var t := ter(k)
	match t:
		"plains":
			if gardens:
				return ["food", "wood", "ore", "idea", "gold"]
			return ["food"] if has_adv(p, "Farming") else []
		"forest":
			return ["wood"] if has_adv(p, "Farming") else []
		"mountain":
			if civ_adv(p, "Terracing"):
				return ["ore", "wood", "food"]
			return ["ore"] if has_adv(p, "Mining") else []
		"barren":
			if civ_adv(p, "Flood Plains"):
				return ["food", "wood"]
			return ["food"] if has_adv(p, "Irrigation") else []
		"sea":
			if exp and pirate_blocked(k, p):
				return []
			var o := []
			if has_adv(p, "Fishing"):
				o.append("food")
			if c["b"].has("port") and k == c["port"]:
				o.append("gold")
				o.append("mood")
			elif c["b"].has("port"):
				o.append("gold")
				o.append("mood")
			return o
	return []


## picks: [[casella, risorsa], …]. card: "mass_collection"/"focused_collection" (id carta) o "".
func valid_collect(c: Dictionary, picks: Array, card := "") -> bool:
	var info := collect_options(c)
	var mass: bool = card != "" and D.action_card(card).size() > 0 and D.action_card(card)[1] == "mass_collection"
	var focus: bool = card != "" and D.action_card(card).size() > 0 and D.action_card(card)[1] == "focused_collection"
	var lim: int = info["count"] + (2 if mass else 0)
	if picks.size() == 0 or picks.size() > lim:
		return false
	var allowed := {}
	for s in info["slots"]:
		allowed[s["h"]] = s["opts"]
	var far_allowed := {}
	for s in info["far"]:
		far_allowed[s["h"]] = s["opts"]
	var used := {}
	var seas := 0
	var fars := 0
	for pk in picks:
		var k: String = pk[0]
		var r: String = pk[1]
		var opts2: Array = allowed.get(k, [])
		if opts2.is_empty():
			opts2 = far_allowed.get(k, [])
			if not opts2.is_empty():
				fars += 1
		if not r in opts2:
			return false
		if used.has(k) and not (focus and is_land(k)):
			return false
		used[k] = true
		if is_sea(k):
			seas += 1
	if seas > 1 or fars > info["far_max"]:
		return false
	return true


func do_collect(p: int, cid: int, picks: Array, card := "", metal := false, free := false) -> bool:
	if not cities.has(cid):
		return false
	var c: Dictionary = cities[cid]
	if c["o"] != p or not can_activate(c) or not valid_collect(c, picks, card):
		return false
	if T.get("econlib", false) and T["collects"] > 0:
		return false
	if card != "":
		if not players[p]["hand"].has(card):
			return false
		players[p]["hand"].erase(card)
		discard("action", card, p)
		log_msg("%s gioca %s." % [pname(p), D.card_title(card)])
	activate(c)
	spend_action(free)
	var got := {}
	var far_used := false
	for pk in picks:
		var r: String = pk[1]
		got[r] = got.get(r, 0) + 1
		if hdist(pk[0], c["h"]) == 2:
			far_used = true
	if far_used:
		T["husbandry"] = true
	if metal and has_adv(p, "Metallurgy") and got.get("ore", 0) >= 2:
		got["ore"] -= 1
		got["gold"] = got.get("gold", 0) + 1
	if has_adv(p, "Public Education") and c["b"].has("academy") and not T["pubed"]:
		T["pubed"] = true
		got["idea"] = got.get("idea", 0) + 1
	if exp:
		if civ_adv(p, "Rice Paddies"):
			var extra := 0
			for k in [c["h"]] + neighbors(c["h"]):
				if extra < 2 and ter(k) == "plains" and city_at(k).is_empty() and not land_units_at(k, p).filter(func(u): return u["t"] == "settler").is_empty():
					extra += 1
			if extra > 0:
				got["food"] = got.get("food", 0) + extra
		if civ_adv(p, "Canals") and got.get("food", 0) == 1:
			got["food"] = 2
		if civ_adv(p, "Pottery") and got.get("food", 0) >= 3 and not T.get("pottery", false):
			T["pottery"] = true
			got["culture"] = got.get("culture", 0) + 1
	if got.has("captive"):
		for pk in picks:
			if pk[1] == "captive":
				var bu := armies_at(pk[0], -1)
				if not bu.is_empty():
					units.erase(bu[0]["id"])
					players[p]["captives"] += 1
		got.erase("captive")
		log_msg("%s prende un Prigioniero come tributo." % pname(p))
	var parts := []
	for r in got:
		var g := gain(p, r, got[r])
		if got[r] > 0:
			parts.append("%d %s" % [got[r], D.RES_NAME.get(r, "Cultura")] + ("" if g == got[r] else " (%d persi per il limite)" % (got[r] - g)))
	T["collects"] += 1
	log_msg("%s raccoglie: %s." % [pname(p), ", ".join(parts)])
	await _lighthouse(p, c)
	T["act_collect"] = true
	after_activation(c)
	T.erase("act_collect")
	fx.emit("collect", {"h": c["h"], "got": got})
	changed.emit()
	return true


## Scelta automatica della raccolta (per l'IA e come proposta alla persona).
func auto_collect(c: Dictionary, weights := {}) -> Array:
	var info := collect_options(c)
	var p: int = c["o"]
	var w := {"food": 1.0, "wood": 1.0, "ore": 1.1, "idea": 1.0, "gold": 1.2, "mood": 1.15}
	w.merge(weights, true)
	var cand := []
	for s in info["slots"] + info["far"]:
		for r in s["opts"]:
			var plain: bool = r in D.RES
			var have := res(p, r) if plain else 0
			var room: int = res_limit(p, r) - have if plain else 9
			var v: float = w.get(r, 1.3) * (1.0 if room > 0 else 0.05)
			cand.append({"h": s["h"], "r": r, "v": v, "far": s["far"], "sea": is_sea(s["h"])})
	cand.sort_custom(func(a, b): return a["v"] > b["v"])
	var picks := []
	var used := {}
	var count := {}
	var seas := 0
	var fars := 0
	for x in cand:
		if picks.size() >= info["count"]:
			break
		if used.has(x["h"]):
			continue
		if x["sea"] and seas >= 1:
			continue
		if x["far"] and fars >= info["far_max"]:
			continue
		# non sprecare oltre il limite
		var r: String = x["r"]
		if r in D.RES and res(p, r) + count.get(r, 0) >= res_limit(p, r):
			continue
		used[x["h"]] = true
		count[r] = count.get(r, 0) + 1
		if x["sea"]:
			seas += 1
		if x["far"]:
			fars += 1
		picks.append([x["h"], r])
	if picks.is_empty() and not cand.is_empty():
		picks.append([cand[0]["h"], cand[0]["r"]])
	return picks


# ------------------------------------------------------------------ costruzione

func can_build(p: int, c: Dictionary, b: String, ignore_activation := false) -> String:
	if not b in bld_list():
		return "edificio sconosciuto"
	if c["o"] != p:
		return "non è tua"
	if city_size(c) >= 5:
		return "la città ha già 5 pezzi"
	if c["b"].has(b):
		return "c'è già"
	if not has_adv(p, D.B_REQ[b]):
		return "serve " + D.adv_it(D.B_REQ[b])
	if c["mood"] == 0 and not (T.get("forced", false)):
		return "città arrabbiata"
	if city_size(c) + 1 > cities_of(p).size():
		return "città troppo grande per il numero di città"
	if supply_left(p, b) <= 0:
		return "pezzi esauriti"
	if b == "port" and not is_coastal(c):
		return "non è sulla costa"
	if plague_by >= 0 and not has_adv(p, "Sanitation"):
		return "Peste: niente costruzioni"
	if not ignore_activation and not can_activate(c):
		return "già attivata da arrabbiata"
	return ""


func build_cost(p: int, b: String, c := {}) -> Dictionary:
	var cost := D.BUILD_COST.duplicate()
	if b == "temple" and has_adv(p, "State Religion") and not T.get("statrel", false):
		cost.erase("food")
	if exp and not c.is_empty():
		# Imhotep: Accademia/Osservatorio senza Cibo né Legno; Hammurabi: Fortezza senza Cibo né Legno
		if (b in ["academy", "observatory"] and leader_is(p, "l17") and leader_at(p, c["h"])) or \
				(b == "fortress" and leader_is(p, "l04") and leader_at(p, c["h"])):
			cost.erase("food")
			cost.erase("wood")
	return cost


## Costruisce un edificio. activation: la città si attiva (azione Attiva città).
func do_build(p: int, cid: int, b: String, free_cost := false, activation := true, use_action := true) -> bool:
	if not cities.has(cid):
		return false
	var c: Dictionary = cities[cid]
	if can_build(p, c, b, not activation) != "":
		return false
	var cost := {} if free_cost else build_cost(p, b, c)
	if not can_pay_build(p, c, b, cost) and not cost.is_empty():
		return false
	if b == "temple" and not cost.has("food") and not free_cost:
		T["statrel"] = true
	if not cost.is_empty():
		pay_build(p, cost, c, b)
	if activation:
		activate(c)
	if use_action:
		spend_action(false)
	if b == "port":
		var seas := adjacent_sea(c["h"])
		c["port"] = await choose_hex(p, "Dove metti il Porto?", seas)
	c["b"][b] = p
	log_msg("%s costruisce %s." % [pname(p), D.B_ART.get(b, "un ") + D.B_NAME[b]])
	match b:
		"observatory":
			draw_action(p)
		"obelisk":
			if civ_adv(p, "Stelas"):
				gain(p, "culture", 1)
			if leader_is(p, "l18") and leader_at(p, c["h"]):
				gain(p, "culture", 1)
		"academy":
			gain(p, "idea", 2)
		"temple":
			var i := await choose(p, "Il Tempio ti dà…", ["+1 Umore", "+1 Cultura"], {"force": true})
			gain(p, "mood" if i == 0 else "culture", 1)
			if has_adv(p, "Dogma"):
				var opts2 := []
				for a in D.ADV["Theocracy"]:
					if can_buy_adv(p, a[0]):
						opts2.append(a[0])
				if not opts2.is_empty():
					var j := await choose(p, "Dogma: scegli un avanzamento di Teocrazia gratuito", opts2.map(func(x): return D.adv_it(x)))
					await gain_advance(p, opts2[j], true)
	fx.emit("build", {"h": c["h"], "b": b})
	if activation:
		await _lighthouse(p, c)
		after_activation(c)
	if exp and leader_at(p, c["h"]):
		# Go-Toba, studioso: dopo un'Accademia o un Osservatorio, un avanzamento come azione gratuita
		if lcode(p) == "l28" and b in ["academy", "observatory"]:
			var lst := buyable_advances(p)
			if not lst.is_empty() and await yes_no(p, "Go-Toba: compri subito un avanzamento (azione gratuita)?"):
				var i2 := await choose(p, "Quale avanzamento?", lst.map(func(a): return D.adv_it(a)), {"advances": lst, "force": true})
				pay(p, {"food": adv_food_cost(p, lst[i2])}, ["idea"])
				await gain_advance(p, lst[i2], true)
		# Siyaj K'ak': dopo una costruzione, un'Influenza gratuita dalla sua città
		if lcode(p) == "l32":
			var ops := influence_options(p).filter(func(o): return o["from"] == c["id"] and o["need"] <= res(p, "culture"))
			if not ops.is_empty():
				var labels := ["No"]
				var pick := []
				for o in ops:
					for bb in o["b"]:
						labels.append(infl_target_text(o, bb) + (" (+%d Cultura)" % o["need"] if o["need"] > 0 else ""))
						pick.append([o, bb])
				var j3 := await choose(p, "Siyaj K'ak', afflusso culturale: tenti un'Influenza gratuita?", labels, {"force": true})
				if j3 > 0:
					await do_influence(p, c["id"], pick[j3 - 1][0]["to"], pick[j3 - 1][1], true)
	changed.emit()
	return true


# ------------------------------------------------------------------ reclutamento

func can_recruit_any(c: Dictionary) -> bool:
	return can_activate(c)


## Dove si possono reclutare le unità dell'espansione.
func recruit_block(p: int, c: Dictionary, t: String) -> String:
	match t:
		"cavalry":
			if c["b"].has("market"):
				return ""
			if civ_adv(p, "Mounted Archers") and city_size(c) == 1:
				return ""
			if civ_adv(p, "Horsemanship") and c["b"].has("fortress"):
				return ""
			if civ_adv(p, "Provinces") and hdist(c["h"], players[p]["home"]) >= 3:
				return ""
			return "serve un Mercato"
		"elephant":
			if c["b"].has("market"):
				return ""
			if civ_adv(p, "Indian Elephants") and ter(c["h"]) == "forest":
				return ""
			if civ_adv(p, "Elephants"):
				for x in neighbors(c["h"]):
					if ter(x) == "barren":
						return ""
			if civ_adv(p, "Warbeasts"):
				return ""
			return "serve un Mercato"
		"leader":
			if players[p].get("no_leader", false):
				return "niente più Leader (Anche tu, Bruto?)"
			if players[p].get("leaders_avail", []).is_empty():
				return "nessun Leader disponibile"
			return ""
	return ""


func can_recruit_type(p: int, c: Dictionary, t: String) -> bool:
	return recruit_block(p, c, t) == ""


## Elefanti reclutabili qui solo grazie alle Bestie da Guerra (costo con Oro).
func _warbeasts_only(p: int, c: Dictionary) -> bool:
	if c["b"].has("market") or not civ_adv(p, "Warbeasts"):
		return false
	if civ_adv(p, "Indian Elephants") and ter(c["h"]) == "forest":
		return false
	if civ_adv(p, "Elephants"):
		for x in neighbors(c["h"]):
			if ter(x) == "barren":
				return false
	return true


## Reclutando un Leader: si sceglie una carta fra quelle rimaste (il vecchio Leader viene scartato).
func _choose_leader(p: int) -> void:
	var old := leader_unit(p)
	if not old.is_empty():
		remove_unit(old)
	var av: Array = players[p]["leaders_avail"]
	var labels := []
	for code in av:
		var L: Array = CivData.LEADERS[code]
		labels.append("%s — %s: %s / %s: %s" % [L[0], L[3], L[4], L[5], L[6]])
	var i := 0
	if av.size() > 1:
		i = await choose(p, "Quale Leader recluti?", labels, {"force": true, "leaders": av})
	var code: String = av[i]
	av.erase(code)
	players[p]["leader"] = code
	players[p]["leaders_ever"] += 1
	log_msg("%s sceglie come Leader %s." % [pname(p), CivData.LEADERS[code][0]])


func recruit_cost(p: int, comp: Dictionary, sanit: bool, draft: bool, c := {}) -> Dictionary:
	var cost := {}
	for t in comp:
		var k: int = comp[t]
		if t == "settler" and sanit and k > 0:
			k -= 1
			cost["mood"] = cost.get("mood", 0) + 1
		if t == "elephant" and k > 0 and not c.is_empty() and _warbeasts_only(p, c):
			# Bestie da Guerra: senza Mercato ogni Elefante costa 1 Oro al posto di 1 Cibo
			cost["gold"] = cost.get("gold", 0) + k
			cost["food"] = cost.get("food", 0) - k
		if t == "infantry" and draft and k > 0:
			k -= 1
			cost["mood"] = cost.get("mood", 0) + (2 if has_adv(p, "Civil Liberties") else 1)
		if t == "ship" and draft and k > 0 and comp.get("infantry", 0) == 0 and civ_adv(p, "Mercenaries"):
			k -= 1
			cost["mood"] = cost.get("mood", 0) + (2 if has_adv(p, "Civil Liberties") else 1)
		for r in D.U_COST[t]:
			cost[r] = cost.get(r, 0) + D.U_COST[t][r] * k
	# Spartani: Cultura al posto dell'Umore della Coscrizione; Mercenari: Oro
	if draft and exp and cost.get("mood", 0) > res(p, "mood"):
		var miss: int = cost["mood"] - res(p, "mood")
		var sub := "culture" if civ_adv(p, "Spartans") else ("gold" if civ_adv(p, "Mercenaries") else "")
		if sub != "":
			cost["mood"] -= miss
			cost[sub] = cost.get(sub, 0) + miss
	return cost


func valid_recruit(p: int, c: Dictionary, comp: Dictionary, sanit := false, draft := false) -> String:
	if c["o"] != p:
		return "non è tua"
	if not can_activate(c):
		return "città già attivata"
	var tot := 0
	for t in comp:
		if not t in unit_list():
			return "unità sconosciuta"
		if comp[t] > 0 and not can_recruit_type(p, c, t):
			return "%s: %s" % [D.U_NAME[t], recruit_block(p, c, t)]
		if comp[t] < 0:
			return "numero non valido"
		tot += comp[t]
	if tot == 0:
		return "niente da reclutare"
	if tot > eff_size(c):
		return "al massimo %d unità" % eff_size(c)
	if comp.get("ship", 0) > 0 and not c["b"].has("port"):
		return "le navi servono un Porto"
	for t in comp:
		if comp[t] > 0 and supply_left(p, t) < comp[t] and units_of(p, t).size() < comp[t]:
			return "pezzi esauriti"
	var n_army := 0
	for t in comp:
		if t in D.ARMY:
			n_army += comp[t]
	if comp.get("leader", 0) > 1:
		return "un solo Leader"
	if n_army > 0:
		var here := armies_at(c["h"], p).size()
		if comp.get("leader", 0) > 0 and leader_at(p, c["h"]):
			here -= 1
		if here + n_army > stack_limit(p, c["h"]):
			return "massimo %d unità d'armata per casella" % stack_limit(p, c["h"])
	if sanit and (not has_adv(p, "Sanitation") or comp.get("settler", 0) == 0):
		return "Fognature non disponibile"
	var draft_ship: bool = civ_adv(p, "Mercenaries") and comp.get("ship", 0) > 0
	if draft and (not has_adv(p, "Draft") or (comp.get("infantry", 0) == 0 and not draft_ship)):
		return "Coscrizione non disponibile"
	if not can_pay(p, recruit_cost(p, comp, sanit, draft, c)):
		return "risorse insufficienti"
	return ""


func do_recruit(p: int, cid: int, comp: Dictionary, sanit := false, draft := false) -> bool:
	if not cities.has(cid):
		return false
	var c: Dictionary = cities[cid]
	if valid_recruit(p, c, comp, sanit, draft) != "":
		return false
	var paid := pay(p, recruit_cost(p, comp, sanit, draft, c))
	activate(c)
	spend_action(false)
	var parts := []
	for t in unit_list():
		var k: int = comp.get(t, 0)
		if t == "leader" and k > 0:
			await _choose_leader(p)
		if t == "infantry" and k > 0 and draft and T.get("shogun_req", false) and civ_adv(p, "Shogunate") and not T.get("shogun_d", false):
			# Shogunato: la Coscrizione porta una carta Azione invece di una Fanteria
			T["shogun_d"] = true
			k -= 1
			draw_action(p)
			log_msg("Shogunato: %s pesca una carta Azione con la Coscrizione." % pname(p))
		for i in k:
			if supply_left(p, t) <= 0:
				# pezzo spostato dal tabellone
				var lst := units_of(p, t)
				lst.sort_custom(func(a, b): return carried(a["id"]).size() < carried(b["id"]).size())
				if not lst.is_empty():
					remove_unit(lst[0])
			var where: String = c["port"] if t == "ship" else c["h"]
			new_unit(p, t, where)
		if k > 0:
			parts.append("%d %s" % [k, D.U_PLURAL[t] if k > 1 else D.U_NAME[t]])
	log_msg("%s recluta %s." % [pname(p), ", ".join(parts)])
	if draft:
		T["draft_recruits"] += 1
	if has_adv(p, "Medicine"):
		for r in ["ore", "wood", "food", "gold"]:
			if paid.get(r, 0) > 0:
				gain(p, r, 1)
				break
	if civ_adv(p, "Formal Training") and c["b"].has("academy"):
		gain(p, "idea", 1)
	if draft and leader_is(p, "l20") and leader_at(p, c["h"]):
		gain(p, "culture", 1)
	var army_rec: bool = comp.get("ship", 0) > 0
	for t in D.ARMY:
		if comp.get(t, 0) > 0:
			army_rec = true
	if has_adv(p, "Nationalism") and army_rec:
		var i := await choose(p, "Nazionalismo: ricevi…", ["+1 Umore", "+1 Cultura"], {"force": true})
		gain(p, "mood" if i == 0 else "culture", 1)
	fx.emit("recruit", {"h": c["h"]})
	changed.emit()
	if comp.get("ship", 0) > 0 and c["port"] != "":
		var enemies := []
		for u in ships_at(c["port"]):
			if u["o"] != p:
				enemies.append(u)
		if not enemies.is_empty():
			await naval_battle(p, ships_at(c["port"], p), c["port"], "")
	await _lighthouse(p, c)
	after_activation(c)
	if exp:
		await _after_recruit_exp(p, c, comp)
	await check_now(p, "recruit", {})
	return true


## Dopo il reclutamento: Vercingetorige (schieramento rapido), Espansione (Cina) e Arcieri a Cavallo (Unni).
func _after_recruit_exp(p: int, c: Dictionary, comp: Dictionary) -> void:
	if leader_is(p, "l11") and leader_at(p, c["h"]):
		var news := []
		for u in units_of(p):
			if u["h"] == c["h"] and u["t"] != "ship" and u["t"] != "leader" and u["on"] == -1:
				news.append(u)
		var k_new := 0
		for t in comp:
			if t != "ship" and t != "leader":
				k_new += int(comp[t])
		news = news.slice(maxi(0, news.size() - k_new))
		var dests := []
		for x in neighbors(c["h"]):
			if is_land(x) and not has_enemy(x, p) and armies_at(x, p).size() + news.filter(func(u): return is_army(u)).size() <= stack_limit(p, x):
				dests.append(x)
		if not news.is_empty() and not dests.is_empty():
			var j := await choose(p, "Reclutamento rapido: dove schieri le nuove unità?", ["Restano in città"] + dests.map(func(x): return _hex_label(x)), {"force": true, "hexes": [""] + dests})
			if j > 0:
				for u in news:
					u["h"] = dests[j - 1]
	var move_kind := ""
	if comp.get("settler", 0) > 0 and civ_adv(p, "Sprawling"):
		move_kind = "settlers"
	elif comp.get("cavalry", 0) > 0 and civ_adv(p, "Mounted Archers"):
		move_kind = "cavalry"
	if move_kind != "" and await yes_no(p, "%s: muovi subito %s?" % ["Espansione" if move_kind == "settlers" else "Arcieri a Cavallo",
			"i Coloni nelle città" if move_kind == "settlers" else "la nuova Cavalleria"], "Sì", "No"):
		T["move_only"] = move_kind
		T["move_only_h"] = c["h"]
		await do_move_action(p, true, 3)
		T.erase("move_only")
		T.erase("move_only_h")


func _lighthouse(p: int, c: Dictionary) -> void:
	if not "great_lighthouse" in c["w"] or supply_left(p, "ship") <= 0:
		return
	var seas := []
	for k in hexes:
		if is_sea(k):
			var ok := true
			for u in ships_at(k):
				if u["o"] != p:
					ok = false
			if ok:
				seas.append(k)
	if seas.is_empty():
		return
	if not await yes_no(p, "Grande Faro: metti una Nave gratis?", "Sì", "No"):
		return
	var k := await choose_hex(p, "Grande Faro: in quale Mare?", seas)
	new_unit(p, "ship", k)
	log_msg("%s mette una Nave grazie al Grande Faro." % pname(p))


# ------------------------------------------------------------------ meraviglie

func can_build_wonder(p: int, c: Dictionary, w: String, discount := 0, ignore_act := false) -> String:
	if not players[p]["won"].has(w):
		return "non hai la carta"
	if city_size(c) >= 5:
		return "la città ha già 5 pezzi"
	if not has_adv(p, "Engineering"):
		return "serve Ingegneria"
	var info: Dictionary = D.WONDERS[w]
	var arch: int = int(players[p].get("architect", 0))
	if not has_adv(p, info["req"]) and arch <= 0:
		return "serve " + D.adv_it(info["req"])
	if c["o"] != p or c["mood"] != 2:
		return "serve una tua città Felice"
	if city_size(c) + 1 > cities_of(p).size():
		return "città troppo grande per il numero di città"
	if w == "great_lighthouse" and not c["b"].has("port"):
		return "serve una città con Porto"
	if plague_by >= 0 and not has_adv(p, "Sanitation"):
		return "Peste: niente costruzioni"
	if not ignore_act and not can_activate(c):
		return "città già attivata"
	var cost: Dictionary = wonder_cost(p, c, w)
	cost["culture"] = maxi(0, cost["culture"] - discount)
	if not plan_payment_wonder(p, cost, c):
		return "risorse insufficienti"
	return ""


func plan_payment_wonder(p: int, cost: Dictionary, c := {}) -> bool:
	if exp and (civ_adv(p, "Architecture") or (not c.is_empty() and leader_at(p, c["h"]))):
		return not plan_build(p, cost, c, "wonder").is_empty()
	# la Cultura per le meraviglie non si sostituisce con l'Umore (nemmeno con l'Arena)
	if res(p, "culture") < cost.get("culture", 0):
		return false
	var c2 := cost.duplicate()
	c2.erase("culture")
	return can_pay(p, c2)


func do_wonder(p: int, cid: int, w: String, activation := true, use_action := true) -> bool:
	if not cities.has(cid):
		return false
	var c: Dictionary = cities[cid]
	if can_build_wonder(p, c, w, 0, not activation) != "":
		return false
	var cost: Dictionary = wonder_cost(p, c, w)
	if int(players[p].get("architect", 0)) > 0:
		players[p]["architect"] = 0
		discards["event"].append("e55")
		log_msg("Il Grande Architetto dirige i lavori.")
	if exp and not plan_build(p, cost, c, "wonder").is_empty() and plan_payment(p, cost).is_empty():
		pay_build(p, cost, c, "wonder")
	else:
		lose(p, "culture", cost["culture"])
		cost.erase("culture")
		pay(p, cost)
	if activation:
		activate(c)
	if use_action:
		spend_action(false)
	players[p]["won"].erase(w)
	c["w"].append(w)
	wonder_builder[w] = p
	wonders_this_age[p] = wonders_this_age.get(p, 0) + 1
	log_msg("%s costruisce %s!" % [pname(p), D.WONDERS[w]["it"]])
	fx.emit("wonder", {"h": c["h"], "w": w})
	if w == "great_statue":
		draw_objective(p)
	if activation:
		await _lighthouse(p, c)
		after_activation(c)
	changed.emit()
	await check_now(p, "wonder", {})
	return true


# ------------------------------------------------------------------ felicità

func happy_cost(p: int, steps: Dictionary) -> int:
	var tot := 0
	for cid in steps:
		if cities.has(int(cid)):
			tot += city_size(cities[int(cid)]) * int(steps[cid])
	return tot


## Paga Umore (con Rituali anche risorse, con l'Arena anche Cultura).
func can_pay_mood(p: int, amt: int) -> bool:
	var have := res(p, "mood")
	if arena(p):
		have += res(p, "culture")
	if has_adv(p, "Rituals"):
		for r in D.RES:
			have += res(p, r)
	return have >= amt


func pay_mood(p: int, amt: int) -> void:
	var left := amt - lose(p, "mood", amt)
	if left > 0 and arena(p):
		left -= lose(p, "culture", left)
	if left > 0 and has_adv(p, "Rituals"):
		for r in ["idea", "food", "wood", "ore", "gold"]:
			left -= lose(p, r, left)
			if left <= 0:
				break


func do_happy(p: int, steps: Dictionary, free := false) -> bool:
	var tot := 0
	for cid in steps:
		var c: Dictionary = cities.get(int(cid), {})
		if c.is_empty() or c["o"] != p or int(steps[cid]) <= 0 or c["mood"] + int(steps[cid]) > 2:
			return false
	tot = happy_cost(p, steps)
	if tot <= 0 or not can_pay_mood(p, tot):
		return false
	pay_mood(p, tot)
	spend_action(free)
	for cid in steps:
		change_mood(cities[int(cid)], int(steps[cid]))
	log_msg("%s aumenta la felicità delle sue città (%d Umore)." % [pname(p), tot])
	fx.emit("happy", {})
	changed.emit()
	return true


# ------------------------------------------------------------------ influenza culturale

## Bersagli possibili da una città sorgente: [{target, b, need_range}], range = dimensione.
func influence_sources(p: int) -> Array:
	var out := []
	for c in cities_of(p):
		out.append(c)
	return out


func is_influenced(c: Dictionary) -> bool:
	for b in c["b"]:
		if c["b"][b] != c["o"]:
			return true
	return false


func boost_blocked(p: int, target: Dictionary) -> bool:
	var o: int = target["o"]
	if o < 0 or o == p:
		return false
	if has_adv(o, "Separation of Power") and target["mood"] == 2:
		return true
	if has_adv(o, "Totalitarianism") and not armies_at(target["h"], o).is_empty():
		return true
	if has_adv(o, "Devotion") and target["b"].has("temple"):
		return true
	return false


## Edifici bersagliabili di una città: quelli non del colore p, di cui p ha ancora pezzi.
func influence_buildings(p: int, target: Dictionary) -> Array:
	var out := []
	if target["o"] >= 0 and target["o"] != p and has_adv(target["o"], "Monuments") and not target["w"].is_empty():
		return out
	if target["o"] >= 0 and leader_is(target["o"], "l42") and leader_at(target["o"], target["h"]):
		return out
	for b in target["b"]:
		if target["b"][b] == p or b == "obelisk":
			continue
		if exp and b == "port" and civ_adv(target["b"][b], "City Independence"):
			continue
		if supply_left(p, b) > 0:
			out.append(b)
	return out


## Tentativi possibili: [{from, to, b:[edifici], need, src_h, to_h, label}]. Con l'espansione «to» può
## indicare un'unità (-(id)-1, Zoroastrismo) e «b» contenere "druid" (Influenza dei Druidi) o "unit".
func influence_options(p: int) -> Array:
	var out := []
	if T.get("infl_ok", false):
		return out
	var srcs: Array = influence_sources_exp(p) if exp else []
	if not exp:
		for c in cities_of(p):
			srcs.append({"from": c["id"], "h": c["h"], "range": city_size(c), "self_only": is_influenced(c), "label": "tua città di dim. %d" % city_size(c)})
	for src in srcs:
		var self_only: bool = src["self_only"]
		for id in cities:
			var tg: Dictionary = cities[id]
			if self_only and tg["id"] != src["from"]:
				continue
			var bs := influence_buildings(p, tg)
			if tg["o"] == -1 and civ_adv(p, "Druidic Influence") and not tg.has("druid"):
				bs = ["druid"]
			if bs.is_empty():
				continue
			if tg["o"] == p and tg["id"] != src["from"] and not is_influenced(tg):
				continue
			var d := dist_revealed(src["h"], tg["h"])
			if d > 50:
				continue
			var need := maxi(0, d - int(src["range"]))
			if need > 0 and (self_only or boost_blocked(p, tg)):
				continue
			if need > res(p, "culture"):
				continue
			out.append({"from": src["from"], "to": tg["id"], "b": bs, "need": need, "src_h": src["h"], "to_h": tg["h"], "label": src["label"]})
		# Zoroastrismo: un'unità d'armata nemica (non Leader) su una casella senza città
		if civ_adv(p, "Zoroastrianism") and not self_only:
			for u in units.values():
				if u["o"] == p or u["t"] == "leader" or not is_army(u) or u["on"] != -1 or not city_at(u["h"]).is_empty():
					continue
				var d2 := dist_revealed(src["h"], u["h"])
				if d2 > 50:
					continue
				var need2 := maxi(0, d2 - int(src["range"]))
				if need2 > res(p, "culture"):
					continue
				out.append({"from": src["from"], "to": -int(u["id"]) - 1, "b": ["unit"], "need": need2, "src_h": src["h"], "to_h": u["h"], "label": src["label"]})
	return out


## Descrizione di un bersaglio dell'influenza (per l'interfaccia).
func infl_target_text(o: Dictionary, b: String) -> String:
	if b == "unit":
		var uid: int = -int(o["to"]) - 1
		var u: Dictionary = units.get(uid, {})
		return "%s di %s (Zoroastrismo)" % [D.U_NAME.get(u.get("t", ""), "Unità"), pname(u.get("o", -1))]
	var tg: Dictionary = cities[o["to"]]
	if b == "druid":
		return "Città barbara (Influenza dei Druidi: 1 PV)"
	return "%s nella città di %s" % [D.B_NAME[b], pname(tg["o"])]


func do_influence(p: int, from_id: int, to_id: int, b: String, free := false) -> bool:
	var ok_opt := {}
	for o in influence_options(p):
		if o["from"] == from_id and o["to"] == to_id and b in o["b"]:
			ok_opt = o
	if ok_opt.is_empty():
		return false
	var th: String = ok_opt["to_h"]
	var tg: Dictionary = cities.get(to_id, {})
	var src_c: Dictionary = cities.get(from_id, {}) if from_id >= 0 else {}
	var src_free: bool = src_c.is_empty() or not is_influenced(src_c) or src_c["o"] != p
	spend_action(free)
	if ok_opt["need"] > 0:
		lose(p, "culture", ok_opt["need"])
	var roll := d6()
	var bonus := 1 if has_adv(p, "Conversion") else 0
	var tot := roll + bonus
	last_dice = {"infl": [roll]}
	fx.emit("influence_roll", {"roll": roll, "h": th})
	log_msg("%s tenta di influenzare: %s, tiro %d%s." % [pname(p), infl_target_text(ok_opt, b), roll, " +1" if bonus else ""])
	await wait(0.8)
	# Ashoka: una volta per turno ritira se la sua città ha un Tempio o il bersaglio è un Tempio
	if tot < 5 and lcode(p) == "l26" and leader_at(p, ok_opt["src_h"]) and not T.get("ashoka", false) \
			and (b == "temple" or (not src_c.is_empty() and src_c["b"].has("temple"))):
		if await yes_no(p, "Ashoka: ritiri il dado?"):
			T["ashoka"] = true
			roll = d6()
			tot = roll + bonus
			log_msg("Ashoka ritira: %d." % roll)
	if tot < 5 and src_free and (tg.is_empty() or not boost_blocked(p, tg)):
		var need := 5 - tot
		if res(p, "culture") >= need:
			if await yes_no(p, "Tiro %d: spendi %d Cultura per riuscire?" % [tot, need], "Sì, spendi %d" % need, "No"):
				lose(p, "culture", need)
				tot += need
	if tot >= 5:
		T["infl_ok"] = true
		if has_adv(p, "Conversion"):
			gain(p, "culture", 1)
		if civ_adv(p, "Code of Laws") and players[p]["hand"].size() <= 4:
			draw_action(p)
		if leader_is(p, "l35") and leader_at(p, ok_opt["src_h"]):
			gain(p, "mood", 1)
		match b:
			"druid":
				tg["druid"] = p
				log_msg("Riuscito! I druidi di %s influenzano una città barbara (+1 PV)." % pname(p))
			"unit":
				var u: Dictionary = units[-to_id - 1]
				var prev_o: int = u["o"]
				u["o"] = p
				log_msg("Riuscito! Un'unità di %s passa a %s." % [pname(prev_o), pname(p)])
				if not enemy_units_at(u["h"], p).filter(func(x): return is_army(x)).is_empty():
					await land_battle(p, [u], u["h"], u["h"], false)
			_:
				var prev: int = tg["b"][b]
				tg["b"][b] = p
				log_msg("Riuscito! %s di %s passa sotto l'influenza di %s." % [D.B_NAME[b], pname(prev), pname(p)])
		fx.emit("influence", {"h": th, "ok": true})
	else:
		log_msg("L'influenza non riesce.")
		fx.emit("influence", {"h": th, "ok": false})
	changed.emit()
	return true


# ------------------------------------------------------------------ rotte commerciali

## Abbinamenti fra coloni/navi e città nemiche non arrabbiate entro 2 caselle (massimo 4).
func trade_routes(p: int) -> Dictionary:
	var srcs := []
	for u in units_of(p):
		if u["t"] in ["settler", "ship"]:
			if exp and u["t"] == "ship" and pirate_blocked(u["h"], p):
				continue
			if exp and u["t"] == "settler" and raided(p, u["h"]):
				continue
			srcs.append(u)
		elif u["t"] == "elephant" and civ_adv(p, "Indian Elephants") and u["on"] == -1:
			var ec := city_at(u["h"])
			if not ec.is_empty() and ec["o"] == p and ec["mood"] > 0:
				srcs.append(u)
	var targets := []
	for id in cities:
		var c: Dictionary = cities[id]
		if c["o"] >= 0 and c["o"] != p and c["mood"] > 0:
			targets.append(c)
		elif c["o"] == -1 and c["mood"] > 0 and civ_adv(p, "Tribal Trade"):
			targets.append(c)
	# accoppiamento massimo (piccolo: ricerca con cammini aumentanti)
	var adj := {}
	for u in srcs:
		var lst := []
		var reach := 2
		if u["t"] == "ship" and civ_adv(p, "Cedars & Dyes"):
			reach = 3
		for ti in targets.size():
			var d := dist_revealed(u["h"], targets[ti]["h"], reach)
			if d <= 2 or (d <= reach and is_coastal(targets[ti])):
				lst.append(ti)
		adj[u["id"]] = lst
	var match_t := {}
	var ships := 0
	for u in srcs:
		var seen := {}
		_augment(u["id"], adj, match_t, seen)
	var tot := mini(match_t.size(), 4)
	var pairs := []
	for ti in match_t:
		pairs.append([match_t[ti], targets[ti]["id"]])
	# Re Hiram: la rotta del Colono o della Nave con cui si trova non conta nel limite di 4
	if exp and match_t.size() > 4:
		for ti in match_t:
			var su: int = match_t[ti]
			if units.has(su) and leader_is(p, "l38") and leader_at(p, units[su]["h"]):
				tot = 5
				break
	var markets := {}
	for ti in match_t:
		if units.has(match_t[ti]) and units[match_t[ti]]["t"] == "ship":
			ships += 1
		var tc: Dictionary = targets[ti]
		if exp and tc["o"] >= 0 and tc["b"].get("market", -9) == tc["o"]:
			markets[tc["o"]] = true
	return {"count": tot, "ships": mini(ships, tot), "markets": markets.keys(), "pairs": pairs}


func _augment(uid: int, adj: Dictionary, match_t: Dictionary, seen: Dictionary) -> bool:
	for ti in adj[uid]:
		if seen.has(ti):
			continue
		seen[ti] = true
		if not match_t.has(ti) or _augment(match_t[ti], adj, match_t, seen):
			match_t[ti] = uid
			return true
	return false


# ------------------------------------------------------------------ pagamenti alternativi

## Pagamento di un edificio o di una meraviglia con le sostituzioni delle civiltà e dei Leader.
## Restituisce il piano {risorsa: quantità, "captives": n} oppure {} se non basta.
func plan_build(p: int, cost: Dictionary, c: Dictionary, b: String) -> Dictionary:
	var base := plan_payment(p, cost)
	if not base.is_empty() or not exp:
		return base
	# risorse che mancano dopo aver usato quelle giuste e l'Oro
	var have := {}
	for r in D.RES + ["mood", "culture"]:
		have[r] = res(p, r)
	var plan := {}
	var short := 0
	for r in cost:
		var need: int = cost[r]
		var t := mini(need, have[r])
		if t > 0:
			plan[r] = plan.get(r, 0) + t
			have[r] -= t
		need -= t
		if need > 0 and r != "culture" and r != "mood":
			var g := mini(need, have["gold"])
			if g > 0:
				plan["gold"] = plan.get("gold", 0) + g
				have["gold"] -= g
				need -= g
		if need > 0 and r == "culture" and civ_adv(p, "Architecture"):
			var m := mini(need, have["mood"])
			plan["mood"] = plan.get("mood", 0) + m
			have["mood"] -= m
			need -= m
		if need > 0:
			if r == "culture" or r == "mood":
				return {}
			short += need
	if short == 0:
		return plan
	var here := not c.is_empty() and leader_at(p, c["h"])
	# Pakal: 1 Cultura riduce il costo di 2 risorse
	if here and lcode(p) == "l31" and b in bld_list() and have["culture"] >= 1:
		plan["culture"] = plan.get("culture", 0) + 1
		have["culture"] -= 1
		short = maxi(0, short - 2)
	# Acamapichtli: ogni Prigioniero vale 2 risorse
	if short > 0 and here and lcode(p) == "l01":
		var cap: int = int(players[p].get("captives", 0))
		var k := mini(cap, (short + 1) / 2)
		if k > 0:
			plan["captives"] = k
			short = maxi(0, short - 2 * k)
	# Architettura (Egitto) ed Schiavismo (Roma): Umore come qualsiasi risorsa
	if short > 0 and (civ_adv(p, "Architecture") or (civ_adv(p, "Slave Economy") and b in bld_list())):
		var m2 := mini(short, have["mood"])
		if m2 > 0:
			plan["mood"] = plan.get("mood", 0) + m2
			have["mood"] -= m2
			short -= m2
	# Ziggurat: Idee come qualsiasi risorsa per i Templi
	if short > 0 and b == "temple" and civ_adv(p, "Ziggurats"):
		var i2 := mini(short, have["idea"])
		if i2 > 0:
			plan["idea"] = plan.get("idea", 0) + i2
			short -= i2
	if short > 0:
		return {}
	return plan


func can_pay_build(p: int, c: Dictionary, b: String, cost := {}) -> bool:
	if cost.is_empty():
		cost = build_cost(p, b, c)
	return cost.is_empty() or not plan_build(p, cost, c, b).is_empty()


func pay_build(p: int, cost: Dictionary, c: Dictionary, b: String) -> void:
	var pl := plan_build(p, cost, c, b)
	for r in pl:
		if r == "_":
			continue
		if r == "captives":
			players[p]["captives"] -= int(pl[r])
		else:
			lose(p, r, int(pl[r]))


## Costo di una meraviglia con gli sconti dell'espansione (Grande Architetto, Serse, Qin, Nebuchadnezzar).
func wonder_cost(p: int, c: Dictionary, w: String) -> Dictionary:
	var cost: Dictionary = D.WONDERS[w]["cost"].duplicate()
	if not exp:
		return cost
	cost["culture"] = maxi(0, cost["culture"] - int(players[p].get("architect", 0)))
	var here := not c.is_empty() and leader_at(p, c["h"])
	if here and ((lcode(p) == "l14" and w == "great_wall") or (lcode(p) == "l06" and w == "great_gardens")):
		cost["culture"] = maxi(0, cost["culture"] - 2)
	if here and lcode(p) == "l36":
		var left := 2
		var cut := mini(left, cost["culture"])
		cost["culture"] -= cut
		left -= cut
		while left > 0:
			var big := "ore"
			for r in ["wood", "food"]:
				if cost[r] > cost[big]:
					big = r
			if cost[big] <= 0:
				break
			cost[big] -= 1
			left -= 1
	return cost


# ------------------------------------------------------------------ influenza estesa

## Fonti dell'Influenza: [{"from": id, "h": casella, "range": portata, "self_only": bool, "label"}].
## id >= 0: città; id < 0: Colono (Proselitismo), -(id unità).
func influence_sources_exp(p: int) -> Array:
	var out := []
	for c in cities_of(p):
		var rng_c := city_size(c)
		if leader_is(p, "l16") and leader_at(p, c["h"]):
			rng_c += 1
		if civ_adv(p, "Proselytism"):
			rng_c += land_units_at(c["h"], p).filter(func(u): return u["t"] == "settler").size()
		out.append({"from": c["id"], "h": c["h"], "range": rng_c, "self_only": is_influenced(c), "label": "tua città di dim. %d" % city_size(c)})
	if civ_adv(p, "Hellenization"):
		for id in cities:
			var c2: Dictionary = cities[id]
			if c2["o"] >= 0 and c2["o"] != p and c2["b"].values().has(p):
				out.append({"from": c2["id"], "h": c2["h"], "range": city_size(c2), "self_only": false, "label": "città ellenizzata di %s" % pname(c2["o"])})
	if civ_adv(p, "Proselytism"):
		for u in units_of(p, "settler"):
			if u["on"] == -1 and city_at(u["h"]).is_empty():
				var extra := land_units_at(u["h"], p).filter(func(v): return v["t"] == "settler").size() - 1
				out.append({"from": -int(u["id"]), "h": u["h"], "range": 2 + extra, "self_only": false, "label": "Colono missionario"})
	return out
