extends "res://scripts/core/engine_state.gd"
## Preparazione della partita e azioni del turno: avanzamenti, fondazione, attivazione delle città
## (raccolta, costruzione, reclutamento, meraviglie), felicità, influenza culturale, esplorazione.

const LAYOUT_FOR := {2: "1", 3: "2", 4: "0"}

# ------------------------------------------------------------------ preparazione

## config: {"seats":[{"color","ai","name","level"}], "seed", "opts":{}}
func setup(config: Dictionary) -> void:
	if config.has("seed"):
		rng.seed = int(config["seed"])
	else:
		rng.randomize()
	opts = config.get("opts", {}).duplicate()
	ai_delay = float(config.get("ai_delay", 0.0))
	players.clear()
	for st in config["seats"]:
		players.append({"color": int(st["color"]), "ai": bool(st["ai"]), "name": str(st["name"]),
			"level": int(st.get("level", 1)), "res": {"food": 2, "wood": 0, "ore": 0, "idea": 0, "gold": 0},
			"mood": 0, "culture": 0, "adv": ["Farming", "Mining"], "tracker": 3, "hand": [], "obj": [],
			"won": [], "done": [], "vp_extra": 0.0, "home": "", "events": [], "gov_cubes": 0})
	n = players.size()
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
		_reveal_region(ri, "start", best)
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
	for e in D.EVENTS:
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
	if m == 0 and T.get("forced", false) and c["o"] == T.get("p", -1):
		m = 1
	if m == 2:
		return s + 1
	if m == 0:
		return 1
	return s


func can_activate(c: Dictionary) -> bool:
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
	if c["act"] > 1:
		change_mood(c, -1)
		log_msg("La città di %s si è attivata di nuovo: l'umore peggiora (%s)." % [pname(c["o"]), D.MOOD_NAME[c["mood"]]])


func spend_action(free: bool) -> void:
	if not free:
		T["actions"] -= 1


# ------------------------------------------------------------------ avanzamenti

func can_buy_adv(p: int, a: String) -> bool:
	var info := D.adv_info(a)
	if info.is_empty() or players[p]["adv"].has(a):
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
	fx.emit("advance", {"p": p, "a": a})
	changed.emit()
	if from_tracker:
		players[p]["tracker"] -= 1
		if players[p]["tracker"] <= 0:
			players[p]["tracker"] = 3
			await resolve_event(p)


func do_advance(p: int, a: String, free_food := false, from_tracker := true) -> bool:
	if not can_buy_adv(p, a):
		return false
	var fc := 0 if free_food else adv_food_cost(p, a)
	if fc == 0 and not free_food and D.adv_info(a)["cat"] == "Science" and has_adv(p, "Priesthood") and not (a in ["Engineering", "Roads", "Navigation", "Cartography"]):
		T["priesthood"] = true
	var paid := {}
	if fc > 0:
		if not can_pay(p, {"food": fc}, ["idea"]):
			return false
		paid = pay(p, {"food": fc}, ["idea"])
	await gain_advance(p, a, from_tracker)
	if has_adv(p, "Free Education") and (paid.get("idea", 0) > 0 or paid.get("gold", 0) > 0) and a != "Free Education" and res(p, "idea") > 0:
		if await yes_no(p, "Istruzione gratuita: cambiare 1 Idea in 1 Umore?", "Sì, cambia", "No"):
			lose(p, "idea", 1)
			gain(p, "mood", 1)
	return true


# ------------------------------------------------------------------ fondazione

func can_found_at(p: int, k: String) -> bool:
	if not is_land(k) or ter(k) == "barren" or hexes[k]["exhausted"]:
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
	log_msg("%s fonda una città (%s)." % [pname(p), D.TER_NAME[ter(k)]])
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
			return ["ore"] if has_adv(p, "Mining") else []
		"barren":
			return ["food"] if has_adv(p, "Irrigation") else []
		"sea":
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
	var parts := []
	for r in got:
		var g := gain(p, r, got[r])
		if got[r] > 0:
			parts.append("%d %s" % [got[r], D.RES_NAME[r]] + ("" if g == got[r] else " (%d persi per il limite)" % (got[r] - g)))
	T["collects"] += 1
	log_msg("%s raccoglie: %s." % [pname(p), ", ".join(parts)])
	await _lighthouse(p, c)
	after_activation(c)
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
			var have := res(p, r) if r != "mood" else 0
			var room: int = res_limit(p, r) - have if r != "mood" else 9
			var v: float = w[r] * (1.0 if room > 0 else 0.05)
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
		if r != "mood" and res(p, r) + count.get(r, 0) >= res_limit(p, r):
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
	if not b in D.BUILDINGS:
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


func build_cost(p: int, b: String) -> Dictionary:
	var cost := D.BUILD_COST.duplicate()
	if b == "temple" and has_adv(p, "State Religion") and not T.get("statrel", false):
		cost.erase("food")
	return cost


## Costruisce un edificio. activation: la città si attiva (azione Attiva città).
func do_build(p: int, cid: int, b: String, free_cost := false, activation := true, use_action := true) -> bool:
	if not cities.has(cid):
		return false
	var c: Dictionary = cities[cid]
	if can_build(p, c, b, not activation) != "":
		return false
	var cost := {} if free_cost else build_cost(p, b)
	if not can_pay(p, cost):
		return false
	if b == "temple" and not cost.has("food") and not free_cost:
		T["statrel"] = true
	pay(p, cost)
	if activation:
		activate(c)
	if use_action:
		spend_action(false)
	if b == "port":
		var seas := adjacent_sea(c["h"])
		c["port"] = await choose_hex(p, "Dove metti il Porto?", seas)
	c["b"][b] = p
	log_msg("%s costruisce %s." % [pname(p), "un " + D.B_NAME[b] if b != "academy" else "un'Accademia"])
	match b:
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
	changed.emit()
	return true


# ------------------------------------------------------------------ reclutamento

func can_recruit_any(c: Dictionary) -> bool:
	return can_activate(c)


func recruit_cost(p: int, comp: Dictionary, sanit: bool, draft: bool) -> Dictionary:
	var cost := {}
	for t in comp:
		var k: int = comp[t]
		if t == "settler" and sanit and k > 0:
			k -= 1
			cost["mood"] = cost.get("mood", 0) + 1
		if t == "infantry" and draft and k > 0:
			k -= 1
			cost["mood"] = cost.get("mood", 0) + (2 if has_adv(p, "Civil Liberties") else 1)
		for r in D.U_COST[t]:
			cost[r] = cost.get(r, 0) + D.U_COST[t][r] * k
	return cost


func valid_recruit(p: int, c: Dictionary, comp: Dictionary, sanit := false, draft := false) -> String:
	if c["o"] != p:
		return "non è tua"
	if not can_activate(c):
		return "città già attivata"
	var tot := 0
	for t in comp:
		if not t in D.UNITS:
			return "unità sconosciuta"
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
	if comp.get("infantry", 0) > 0:
		var here := armies_at(c["h"], p).size()
		if here + comp["infantry"] > 4:
			return "massimo 4 eserciti per casella"
	if sanit and (not has_adv(p, "Sanitation") or comp.get("settler", 0) == 0):
		return "Igiene non disponibile"
	if draft and (not has_adv(p, "Draft") or comp.get("infantry", 0) == 0):
		return "Leva non disponibile"
	if not can_pay(p, recruit_cost(p, comp, sanit, draft)):
		return "risorse insufficienti"
	return ""


func do_recruit(p: int, cid: int, comp: Dictionary, sanit := false, draft := false) -> bool:
	if not cities.has(cid):
		return false
	var c: Dictionary = cities[cid]
	if valid_recruit(p, c, comp, sanit, draft) != "":
		return false
	var paid := pay(p, recruit_cost(p, comp, sanit, draft))
	activate(c)
	spend_action(false)
	var parts := []
	for t in ["settler", "infantry", "ship"]:
		var k: int = comp.get(t, 0)
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
	if has_adv(p, "Nationalism") and (comp.get("infantry", 0) > 0 or comp.get("ship", 0) > 0):
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
	await check_now(p, "recruit", {})
	return true


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

func can_build_wonder(p: int, c: Dictionary, w: String, discount := 0) -> String:
	if not players[p]["won"].has(w):
		return "non hai la carta"
	if city_size(c) >= 5:
		return "la città ha già 5 pezzi"
	if not has_adv(p, "Engineering"):
		return "serve Ingegneria"
	var info: Dictionary = D.WONDERS[w]
	if not has_adv(p, info["req"]):
		return "serve " + D.adv_it(info["req"])
	if c["o"] != p or c["mood"] != 2:
		return "serve una tua città Felice"
	if city_size(c) + 1 > cities_of(p).size():
		return "città troppo grande per il numero di città"
	if w == "great_lighthouse" and not c["b"].has("port"):
		return "serve una città con Porto"
	if plague_by >= 0 and not has_adv(p, "Sanitation"):
		return "Peste: niente costruzioni"
	if not can_activate(c):
		return "città già attivata"
	var cost: Dictionary = info["cost"].duplicate()
	cost["culture"] = maxi(0, cost["culture"] - discount)
	if not plan_payment_wonder(p, cost):
		return "risorse insufficienti"
	return ""


func plan_payment_wonder(p: int, cost: Dictionary) -> bool:
	# la Cultura per le meraviglie non si sostituisce con l'Umore (nemmeno con l'Arena)
	if res(p, "culture") < cost.get("culture", 0):
		return false
	var c2 := cost.duplicate()
	c2.erase("culture")
	return can_pay(p, c2)


func do_wonder(p: int, cid: int, w: String) -> bool:
	if not cities.has(cid):
		return false
	var c: Dictionary = cities[cid]
	if can_build_wonder(p, c, w) != "":
		return false
	var cost: Dictionary = D.WONDERS[w]["cost"].duplicate()
	lose(p, "culture", cost["culture"])
	cost.erase("culture")
	pay(p, cost)
	activate(c)
	spend_action(false)
	players[p]["won"].erase(w)
	c["w"].append(w)
	wonder_builder[w] = p
	wonders_this_age[p] = wonders_this_age.get(p, 0) + 1
	log_msg("%s costruisce %s!" % [pname(p), D.WONDERS[w]["it"]])
	fx.emit("wonder", {"h": c["h"], "w": w})
	if w == "great_statue":
		draw_objective(p)
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


## Paga Umore (con Riti anche risorse, con l'Arena anche Cultura).
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
	for b in target["b"]:
		if target["b"][b] == p:
			continue
		if supply_left(p, b) > 0:
			out.append(b)
	return out


## Tentativi possibili: [{from, to, b:[edifici], range_need}].
func influence_options(p: int) -> Array:
	var out := []
	if T.get("infl_ok", false):
		return out
	for src in cities_of(p):
		var self_only := is_influenced(src)
		for id in cities:
			var tg: Dictionary = cities[id]
			if self_only and tg["id"] != src["id"]:
				continue
			var bs := influence_buildings(p, tg)
			if bs.is_empty():
				continue
			if tg["o"] == p and tg["id"] != src["id"] and not is_influenced(tg):
				continue
			var d := dist_revealed(src["h"], tg["h"])
			if d > 50:
				continue
			var need := maxi(0, d - city_size(src))
			if need > 0 and (self_only or boost_blocked(p, tg)):
				continue
			if need > res(p, "culture"):
				continue
			out.append({"from": src["id"], "to": tg["id"], "b": bs, "need": need})
	return out


func do_influence(p: int, from_id: int, to_id: int, b: String, free := false) -> bool:
	var ok_opt := {}
	for o in influence_options(p):
		if o["from"] == from_id and o["to"] == to_id and b in o["b"]:
			ok_opt = o
	if ok_opt.is_empty():
		return false
	var tg: Dictionary = cities[to_id]
	spend_action(free)
	if ok_opt["need"] > 0:
		lose(p, "culture", ok_opt["need"])
	var roll := d6()
	var bonus := 1 if has_adv(p, "Conversion") else 0
	var tot := roll + bonus
	last_dice = {"infl": [roll]}
	fx.emit("influence_roll", {"roll": roll, "h": tg["h"]})
	log_msg("%s tenta di influenzare %s: tiro %d%s." % [pname(p), "la città di " + pname(tg["o"]), roll, " +1" if bonus else ""])
	await wait(0.8)
	if tot < 5 and not cities[from_id].is_empty() and not is_influenced(cities[from_id]) and not boost_blocked(p, tg):
		var need := 5 - tot
		if res(p, "culture") >= need:
			if await yes_no(p, "Tiro %d: spendi %d Cultura per riuscire?" % [tot, need], "Sì, spendi %d" % need, "No"):
				lose(p, "culture", need)
				tot += need
	if tot >= 5:
		var prev: int = tg["b"][b]
		tg["b"][b] = p
		T["infl_ok"] = true
		if has_adv(p, "Conversion"):
			gain(p, "culture", 1)
		log_msg("Riuscito! %s di %s passa sotto l'influenza di %s." % [D.B_NAME[b], pname(prev), pname(p)])
		fx.emit("influence", {"h": tg["h"], "ok": true})
	else:
		log_msg("L'influenza non riesce.")
		fx.emit("influence", {"h": tg["h"], "ok": false})
	changed.emit()
	return true


# ------------------------------------------------------------------ rotte commerciali

## Abbinamenti fra coloni/navi e città nemiche non arrabbiate entro 2 caselle (massimo 4).
func trade_routes(p: int) -> Dictionary:
	var srcs := []
	for u in units_of(p):
		if u["t"] in ["settler", "ship"]:
			srcs.append(u)
	var targets := []
	for id in cities:
		var c: Dictionary = cities[id]
		if c["o"] >= 0 and c["o"] != p and c["mood"] > 0:
			targets.append(c)
	# accoppiamento massimo (piccolo: ricerca con cammini aumentanti)
	var adj := {}
	for u in srcs:
		var lst := []
		for ti in targets.size():
			if dist_revealed(u["h"], targets[ti]["h"], 2) <= 2:
				lst.append(ti)
		adj[u["id"]] = lst
	var match_t := {}
	var ships := 0
	for u in srcs:
		var seen := {}
		_augment(u["id"], adj, match_t, seen)
	var tot := mini(match_t.size(), 4)
	for ti in match_t:
		if units.has(match_t[ti]) and units[match_t[ti]]["t"] == "ship":
			ships += 1
	return {"count": tot, "ships": mini(ships, tot)}


func _augment(uid: int, adj: Dictionary, match_t: Dictionary, seen: Dictionary) -> bool:
	for ti in adj[uid]:
		if seen.has(ti):
			continue
		seen[ti] = true
		if not match_t.has(ti) or _augment(match_t[ti], adj, match_t, seen):
			match_t[ti] = uid
			return true
	return false
