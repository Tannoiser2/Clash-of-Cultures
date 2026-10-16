extends RefCounted
## Intelligenza artificiale di Clash of Cultures. Euristica a priorità: espansione (coloni e
## fondazioni), raccolta mirata a ciò che serve, avanzamenti con un valore che tiene conto degli
## obiettivi in mano, edifici, difesa dai barbari e attacchi quando conviene, meraviglie, felicità.
## level: 0 facile (più casuale e prudente), 1 normale, 2 difficile.

const D = preload("res://scripts/data/coc_data.gd")

var level := 1
var rng := RandomNumberGenerator.new()
var fails := 0
var last_turn := -1
var tried := {}

const ADV_VALUE := {
	"Storage": 9.0, "Tactics": 7.5, "Myths": 8.0, "Writing": 7.0, "Fishing": 6.0, "Irrigation": 6.0,
	"Husbandry": 5.0, "Bartering": 5.0, "Arts": 5.5, "Philosophy": 7.0, "Public Education": 5.5,
	"Engineering": 5.5, "Roads": 5.0, "Sanitation": 6.0, "Draft": 6.0, "Math": 5.0, "Medicine": 5.0,
	"Circus & Sports": 4.5, "Drama & Music": 5.5, "Rituals": 5.0, "State Religion": 5.5, "Priesthood": 4.5,
	"Navigation": 3.5, "Warships": 3.0, "Cartography": 3.5, "Free Education": 4.5, "Siegecraft": 3.0,
	"Steel Weapons": 4.0, "Taxation": 4.5, "Trade Routes": 4.0, "Currency": 3.5, "Monuments": 4.5,
	"Astronomy": 4.0, "Metallurgy": 4.0, "Voting": 5.0, "Separation of Power": 4.0, "Civil Liberties": 5.5,
	"Economic Liberty": 4.5, "Nationalism": 5.0, "Totalitarianism": 4.0, "Absolute Power": 5.5,
	"Forced Labor": 4.0, "Dogma": 5.0, "Devotion": 4.0, "Conversion": 4.5, "Fanaticism": 4.0,
}


func decide(eng, p: int, req: Dictionary):
	match req.get("type", ""):
		"turn":
			return _turn(eng, p)
		"move":
			return _move(eng, p, req)
		"choice":
			return _choice(eng, p, req)
	return 0


func _jitter() -> float:
	return rng.randf_range(0.0, [3.0, 1.2, 0.4][clampi(level, 0, 2)])


# ------------------------------------------------------------------ valutazioni

func adv_value(eng, p: int, a: String) -> float:
	var v: float = ADV_VALUE.get(a, 3.0)
	var info: Dictionary = D.adv_info(a)
	if info["border"] != "":
		v += 1.0
	# obiettivi in mano che chiedono una categoria completa
	var cat_obj := {"militarized": "Warfare", "culture": "Traditions", "enlightened": "Education", "seafarer": "Maritime",
		"merchant": "Economy", "city_planner": "Construction", "science": "Science"}
	for id in eng.players[p]["obj"]:
		for key in eng.obj_parts(id):
			if cat_obj.get(key, "") == info["cat"]:
				v += 2.5
			if key == "government" and info["cat"] in D.GOVERNMENTS:
				v += 2.0
	# rendere accessibili le categorie già avviate
	var owned := 0
	for x in D.ADV[info["cat"]]:
		if eng.players[p]["adv"].has(x[0]):
			owned += 1
	v += owned * 0.4
	if a == "Tactics" and (_barb_threat(eng, p) > 0 or not eng.cities_of(-1).is_empty()):
		v += 5.0
	if a == "Fishing" and not _any_coastal(eng, p):
		v -= 3.0
	if a == "Irrigation" and not _near_barren(eng, p):
		v -= 2.5
	if a == "Storage" and eng.res(p, "food") >= 2:
		v += 2.0
	if a == "Engineering" and eng.age >= 2:
		v += 2.0
	# prerequisito della meraviglia in mano
	for w in eng.players[p]["won"]:
		if D.WONDERS[w]["req"] == a:
			v += 3.0
	return v


func _any_coastal(eng, p: int) -> bool:
	for c in eng.cities_of(p):
		if eng.is_coastal(c):
			return true
	return false


func _near_barren(eng, p: int) -> bool:
	for c in eng.cities_of(p):
		for x in eng.neighbors(c["h"]):
			if eng.ter(x) == "barren":
				return true
	return false


## Barbari (o nemici) entro 2 caselle dalle città.
func _barb_threat(eng, p: int) -> int:
	var k := 0
	for u in eng.units_of(-1):
		if not eng.is_army(u):
			continue
		for c in eng.cities_of(p):
			if eng.hdist(u["h"], c["h"]) <= 2:
				k += 1
				break
	return k


func _city_threat(eng, p: int, c: Dictionary) -> int:
	var k := 0
	for u in eng.units.values():
		if u["o"] != p and eng.is_army(u) and eng.hdist(u["h"], c["h"]) <= 3:
			k += 1
	# le città barbare vicine generano rinforzi
	for b in eng.cities_of(-1):
		if eng.hdist(b["h"], c["h"]) <= 3:
			k += 1
	return k


## Bontà di una casella per fondarci una città.
func spot_value(eng, p: int, k: String) -> float:
	if not eng.can_found_at(p, k):
		return -99.0
	var v := 0.0
	var kinds := {}
	for x in [k] + eng.neighbors(k):
		var t: String = eng.ter(x)
		if t == "":
			v += 0.6
			continue
		if not eng.city_at(x).is_empty() and x != k:
			v -= 2.0
		match t:
			"plains":
				v += 1.2
				kinds["food"] = true
			"forest":
				v += 1.0
				kinds["wood"] = true
			"mountain":
				v += 1.0
				kinds["ore"] = true
			"sea":
				v += 0.7
				kinds["sea"] = true
			"barren":
				v += 0.2
	v += kinds.size() * 0.8
	for u in eng.units_of(-1):
		if eng.hdist(u["h"], k) <= 1:
			v -= 3.0
	for c in eng.cities.values():
		if c["o"] != p and eng.hdist(c["h"], k) <= 2:
			v -= 1.5
	return v


# ------------------------------------------------------------------ turno

func _turn(eng, p: int) -> Dictionary:
	if eng.turn_count != last_turn:
		last_turn = eng.turn_count
		fails = 0
		tried = {}
	else:
		fails += 1
	if fails > 25:
		return {"t": "end"}
	var acts: int = eng.T["actions"]
	var best := {"t": "end"}
	var bv := 0.3 if acts > 0 else 0.0
	var cands := []
	# carte giocabili
	for id in eng.playable_cards(p):
		var cv := _card_value(eng, p, id)
		if cv > 0:
			cands.append([cv, {"t": "card", "id": id}])
	# azioni speciali gratuite
	for w in eng.free_options(p):
		var fm := _free_move(eng, p, w)
		if not fm.is_empty():
			cands.append(fm)
	if acts > 0:
		# fondare
		for u in eng.foundable_settlers(p):
			var sv := spot_value(eng, p, u["h"])
			if sv >= 3.4 or (sv >= 2.5 and eng.cities_of(p).size() < 3):
				cands.append([9.0 + sv * 0.3, {"t": "found", "u": u["id"]}])
		# città
		for c in eng.cities_of(p):
			if not eng.can_activate(c):
				continue
			var extra_act: float = 2.5 if c["act"] > 0 else 0.0
			if c["mood"] == 0 and c["act"] > 0:
				continue
			# raccolta
			var picks: Array = eng.auto_collect(c, _need_weights(eng, p))
			if not picks.is_empty() and eng.valid_collect(c, picks):
				var gv := 0.0
				var wt := _wonder_target(eng, p)
				for pk in picks:
					var r: String = pk[1]
					if r == "mood" or eng.res(p, r) < eng.res_limit(p, r):
						gv += 1.0
					if wt != "" and r in ["food", "wood", "ore"] and eng.res(p, r) < D.WONDERS[wt]["cost"][r]:
						gv += 0.8
				cands.append([gv * 1.6 - extra_act + _jitter(), {"t": "collect", "c": c["id"], "picks": picks,
					"metal": eng.has_adv(p, "Metallurgy")}])
			# costruzione
			for b in D.BUILDINGS:
				if eng.can_build(p, c, b) == "" and eng.can_pay(p, eng.build_cost(p, b)):
					var bvv := _building_value(eng, p, c, b) - _saving_penalty(eng, p, eng.build_cost(p, b))
					cands.append([bvv - extra_act + _jitter(), {"t": "build", "c": c["id"], "b": b}])
			# meraviglie
			for w in eng.players[p]["won"]:
				if eng.can_build_wonder(p, c, w) == "":
					cands.append([12.0 - extra_act, {"t": "wonder", "c": c["id"], "w": w}])
			# reclutamento
			var rc := _recruit_plan(eng, p, c)
			if not rc.is_empty():
				var rcost: Dictionary = eng.recruit_cost(p, rc[1]["comp"], rc[1]["sanit"], rc[1]["draft"])
				var pen := 0.0 if _city_threat(eng, p, c) > 0 else _saving_penalty(eng, p, rcost)
				cands.append([rc[0] - extra_act - pen + _jitter(), rc[1]])
		# avanzamento
		var buy: Array = eng.buyable_advances(p)
		if not buy.is_empty():
			var ba := ""
			var bav := -1.0
			for a in buy:
				var v := adv_value(eng, p, a) + _jitter()
				if v > bav:
					bav = v
					ba = a
			cands.append([3.0 + bav * 0.55 - _saving_penalty(eng, p, {"food": 2}), {"t": "advance", "a": ba}])
		# movimento
		var mv := _best_group_move(eng, p, {})
		if not mv.is_empty() and mv[0] > 2.0:
			cands.append([mv[0], {"t": "move"}])
		# felicità
		var hp := _happy_plan(eng, p)
		if not hp.is_empty():
			cands.append(hp)
		# influenza
		var inf := _influence_plan(eng, p)
		if not inf.is_empty():
			cands.append([inf[0], {"t": "influence", "from": inf[1], "to": inf[2], "b": inf[3]}])
	for cnd in cands:
		var key := str(cnd[1])
		if tried.get(key, 0) >= 2:
			continue
		if cnd[0] > bv:
			bv = cnd[0]
			best = cnd[1]
	var bk := str(best)
	if best.get("t", "") != "end":
		tried[bk] = tried.get(bk, 0) + 1
	return best


func _need_weights(eng, p: int) -> Dictionary:
	var w := {}
	for r in ["food", "wood", "ore", "idea", "gold"]:
		var have: int = eng.res(p, r)
		w[r] = 1.6 - 0.15 * have
	w["food"] += 0.3
	w["mood"] = 1.0 if eng.res(p, "mood") < 3 else 0.6
	# meraviglia in vista: servono le sue risorse
	var wt := _wonder_target(eng, p)
	if wt != "":
		var cost: Dictionary = D.WONDERS[wt]["cost"]
		for r in ["food", "wood", "ore"]:
			if eng.res(p, r) < cost[r]:
				w[r] += 0.8
	return w


## Penalità per una spesa che allontana dalla meraviglia che si sta preparando.
func _saving_penalty(eng, p: int, cost: Dictionary) -> float:
	var wt := _wonder_target(eng, p)
	if wt == "" or eng.age < 2:
		return 0.0
	var need: Dictionary = D.WONDERS[wt]["cost"]
	var pen := 0.0
	for r in ["wood", "ore", "food"]:
		if cost.get(r, 0) > 0 and eng.res(p, r) < need[r]:
			pen += (2.5 if r != "food" else 1.5) * (2.0 if eng.res(p, "culture") >= 3 else 1.0)
	return pen


## Meraviglia in mano che si può puntare (prerequisiti posseduti o quasi).
func _wonder_target(eng, p: int) -> String:
	if not eng.has_adv(p, "Engineering"):
		return ""
	for w in eng.players[p]["won"]:
		if eng.has_adv(p, D.WONDERS[w]["req"]):
			return w
	return ""


func _building_value(eng, p: int, c: Dictionary, b: String) -> float:
	var v := 6.8
	match b:
		"temple":
			v += 1.5
		"academy":
			v += 2.0
		"fortress":
			v += 0.5 + 2.0 * float(_city_threat(eng, p, c) > 0)
		"port":
			v += 0.5
	for id in eng.players[p]["obj"]:
		for key in eng.obj_parts(id):
			if key in ["diverse", "religious", "academic", "fortified", "coastal", "citadel"]:
				v += 1.0
	return v


func _recruit_plan(eng, p: int, c: Dictionary) -> Array:
	var size: int = eng.eff_size(c)
	var settlers: int = eng.units_of(p, "settler").size()
	var ncity: int = eng.cities_of(p).size()
	var threat := _city_threat(eng, p, c)
	var here: int = eng.armies_at(c["h"], p).size()
	var comp := {"settler": 0, "infantry": 0, "ship": 0}
	var v := 0.0
	var budget := size
	# difesa
	if threat > here and eng.supply_left(p, "infantry") > 0:
		var k := mini(budget, mini(threat - here + 1, 4 - here))
		comp["infantry"] = k
		budget -= k
		v += 5.5 * k + (3.0 if here == 0 else 0.0)
	# coloni per espandersi
	if budget > 0 and ncity + settlers < 7 and settlers < 2 and eng.supply_left(p, "settler") > 0:
		comp["settler"] = 2 if (budget >= 2 and ncity < 4 and settlers == 0) else 1
		budget -= comp["settler"]
		v += (7.0 if ncity < 4 else 4.0) + (comp["settler"] - 1) * 2.0
	# un piccolo esercito per i barbari vicini
	if budget > 0 and eng.has_adv(p, "Tactics") and _barb_threat(eng, p) > 0 and here < 3 and comp["infantry"] == 0:
		comp["infantry"] = mini(budget, 2)
		v += 3.0
	if comp["settler"] + comp["infantry"] == 0:
		return []
	var sanit: bool = eng.has_adv(p, "Sanitation") and comp["settler"] > 0 and eng.res(p, "mood") >= 1
	var draft: bool = eng.has_adv(p, "Draft") and comp["infantry"] > 0 and eng.res(p, "mood") >= (2 if eng.has_adv(p, "Civil Liberties") else 1)
	if sanit and draft and eng.res(p, "mood") < 2:
		draft = false
	# riduci finché si può pagare
	while comp["settler"] + comp["infantry"] > 0:
		if eng.valid_recruit(p, c, comp, sanit, draft) == "":
			return [v, {"t": "recruit", "c": c["id"], "comp": comp, "sanit": sanit, "draft": draft}]
		if comp["infantry"] > 0:
			comp["infantry"] -= 1
			v -= 3.0
			if comp["infantry"] == 0:
				draft = false
		elif comp["settler"] > 0:
			comp["settler"] -= 1
			v -= 4.0
			sanit = false
	return []


func _happy_plan(eng, p: int) -> Array:
	var steps := {}
	var cost := 0
	var have: int = eng.res(p, "mood")
	var cs: Array = eng.cities_of(p)
	cs.sort_custom(func(a, b): return eng.city_size(a) > eng.city_size(b))
	for c in cs:
		if c["mood"] < 2:
			var sz: int = eng.city_size(c)
			if cost + sz <= have:
				steps[c["id"]] = 1
				cost += sz
	if steps.is_empty():
		return []
	var v := 1.5 + steps.size() * 1.6
	for c in cs:
		if steps.has(c["id"]) and c["mood"] == 0:
			v += 2.0
	# una città felice serve per costruire la meraviglia
	var wt := _wonder_target(eng, p)
	if wt != "" and not cs.any(func(c): return c["mood"] == 2) and eng.res(p, "culture") >= 4:
		v += 5.0
	return [v, {"t": "happy", "steps": steps}]


func _influence_plan(eng, p: int) -> Array:
	var best := []
	for o in eng.influence_options(p):
		var tg: Dictionary = eng.cities[o["to"]]
		var need: int = o["need"]
		var v := 3.2 - need * 1.0
		if tg["o"] == p:
			v += 1.0
		if eng.has_adv(p, "Conversion"):
			v += 1.0
		if v > 1.5 and (best.is_empty() or v > best[0]):
			best = [v, o["from"], o["to"], o["b"][0]]
	return best


func _card_value(eng, p: int, id: String) -> float:
	var k: String = eng.card_kind(id)
	var acts: int = eng.T["actions"]
	match k:
		"advance":
			return 7.0 if not eng.buyable_advances(p).is_empty() or eng.res(p, "culture") >= 2 else 0.0
		"leadership":
			return 6.0 if acts <= 1 else 0.0
		"militia":
			return 5.0 if _barb_threat(eng, p) > 0 else 1.0
		"leap_knowledge", "good_ideas", "heroic_general", "teach_us":
			return 8.0
		"inspiration", "tech_exchange":
			return 7.5
		"assassination":
			return 2.0 if eng.res(p, "culture") >= 3 else 0.0
		"negotiations":
			return 0.0
		"spies":
			return 0.0
		"explorers":
			return 3.5
		"new_goals":
			return 0.0
		"city_growth":
			return 6.5
		"tech_synergy":
			return 6.0 if eng.can_pay(p, {"food": 4}, ["idea"]) else 0.0
		"idea_synergy":
			return 6.5
		"cultural_awe":
			return 4.0
		"mercenaries":
			return 0.0
	if k.begins_with("gp_"):
		return 7.0
	return 0.0


func _free_move(eng, p: int, w: String) -> Array:
	match w:
		"absolute":
			if eng.res(p, "mood") >= 4 and eng.T["actions"] <= 1:
				return [5.5, {"t": "free", "what": "absolute"}]
		"drama":
			if eng.res(p, "mood") >= 4 or (_wonder_target(eng, p) != "" and eng.res(p, "mood") >= 2 and eng.res(p, "culture") < 5):
				return [2.0, {"t": "free", "what": "drama", "dir": "m2c"}]
		"civil":
			if eng.res(p, "mood") <= 1:
				return [3.5, {"t": "free", "what": "civil"}]
		"taxation":
			var k: int = eng.cities_of(p).size()
			if k >= 3:
				var get := {}
				var order := ["food", "ore", "wood"]
				for i in k:
					var r: String = order[i % 3]
					get[r] = get.get(r, 0) + 1
				return [2.0 + k * 0.8, {"t": "free", "what": "taxation", "get": get}]
		"econlib":
			for c in eng.cities_of(p):
				if c["act"] == 0:
					var picks: Array = eng.auto_collect(c)
					if picks.size() >= 3 and eng.valid_collect(c, picks):
						return [4.0, {"t": "free", "what": "econlib", "c": c["id"], "picks": picks}]
		"arts":
			var inf := _influence_plan(eng, p)
			if not inf.is_empty() and inf[0] > 2.0:
				return [inf[0] + 1.0, {"t": "free", "what": "arts", "from": inf[1], "to": inf[2], "b": inf[3]}]
		"library":
			for a in ["Storage", "Husbandry", "Roads", "Draft", "Sanitation", "Public Education"]:
				if not eng.players[p]["adv"].has(a):
					return [1.0, {"t": "free", "what": "library", "a": a}]
	return []


# ------------------------------------------------------------------ movimento

func _move(eng, p: int, req: Dictionary) -> Dictionary:
	var mv := _best_group_move(eng, p, eng.T.get("mv_this", {}))
	if mv.is_empty() or mv[0] <= 1.0:
		return {"done": true}
	return mv[1]


## Miglior movimento di un gruppo: [valore, {units, to, roads}].
func _best_group_move(eng, p: int, moved: Dictionary) -> Array:
	var best := []
	var groups := {}
	for u in eng.units_of(p):
		if moved.has(u["id"]):
			continue
		var key: String = "%s|%s|%d" % [u["h"], "ship" if u["t"] == "ship" else ("cargo" if u["on"] != -1 else "land"), 0]
		if u["t"] == "settler" and u["on"] == -1:
			key += "|s%d" % u["id"]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(u["id"])
	for key in groups:
		var ids: Array = groups[key]
		if eng.group_info(p, ids).is_empty():
			continue
		var u0: Dictionary = eng.units[ids[0]]
		if u0["t"] == "settler":
			var r := _settler_move(eng, p, ids)
			if not r.is_empty() and (best.is_empty() or r[0] > best[0]):
				best = r
		elif u0["t"] == "infantry":
			var r2 := _army_move(eng, p, ids)
			if not r2.is_empty() and (best.is_empty() or r2[0] > best[0]):
				best = r2
	return best


func _settler_move(eng, p: int, ids: Array) -> Array:
	var u: Dictionary = eng.units[ids[0]]
	var here := spot_value(eng, p, u["h"]) if u["on"] == -1 else -99.0
	if here >= 3.4:
		return []
	var tg: Dictionary = eng.move_targets(p, ids)
	var best := []
	for k in tg:
		var info: Dictionary = tg[k]
		if info.get("battle", false):
			continue
		var v := 0.0
		if info["kind"] == "explore":
			v = 4.0
		elif info["kind"] in ["land", "disembark"]:
			var sv := spot_value(eng, p, k)
			# guarda anche un passo più in là
			var look := sv
			for y in eng.neighbors(k):
				look = maxf(look, spot_value(eng, p, y) - 0.8)
				if not eng.revealed(y):
					look = maxf(look, 3.5)
			v = look - maxf(here, 0.0) * 0.5
			if info.get("roads", false):
				v -= 1.0
		else:
			continue
		v += _jitter()
		if v > 1.2 and (best.is_empty() or v > best[0]):
			best = [2.0 + v, {"units": ids, "to": k, "roads": false}]
	return best


func _army_move(eng, p: int, ids: Array) -> Array:
	if not eng.has_adv(p, "Tactics"):
		return []
	var u: Dictionary = eng.units[ids[0]]
	var here_city: Dictionary = eng.city_at(u["h"])
	var guarding: bool = not here_city.is_empty() and here_city["o"] == p and _city_threat(eng, p, here_city) > 0
	var tg: Dictionary = eng.move_targets(p, ids)
	var best := []
	var mine := ids.size()
	for k in tg:
		var info: Dictionary = tg[k]
		var v := 0.0
		if info.get("battle", false):
			var target: int = info.get("target", -1)
			var defs: int = eng.enemy_units_at(k, p).filter(func(x): return eng.is_army(x)).size()
			var c: Dictionary = eng.city_at(k)
			if not c.is_empty() and c["b"].has("fortress"):
				defs += 1
			var ratio := float(mine) / maxf(1.0, float(defs))
			if target == -1:
				if ratio >= 1.5 or defs == 0:
					v = 6.0 + (3.0 if not c.is_empty() else 0.0)
			elif level >= 1 and (ratio >= 2.0 or defs == 0) and not c.is_empty():
				v = 5.0 + eng.city_size(c)
			if guarding and mine <= _city_threat(eng, p, here_city):
				v -= 4.0
		elif info["kind"] == "explore":
			v = 2.5 if eng.age <= 3 else 1.0
		elif info["kind"] == "land":
			# avvicinarsi a un bersaglio barbaro
			for b in eng.units_of(-1):
				if eng.is_army(b) or true:
					var d_now: int = eng.hdist(u["h"], b["h"])
					var d_new: int = eng.hdist(k, b["h"])
					if d_new < d_now and d_now <= 4:
						v = maxf(v, 1.6)
			var cc: Dictionary = eng.city_at(k)
			if not cc.is_empty() and cc["o"] == p and _city_threat(eng, p, cc) > eng.armies_at(k, p).size():
				v = maxf(v, 3.5)
			if guarding:
				v -= 3.0
			if info.get("roads", false):
				v -= 1.0
		v += _jitter() * 0.5
		if v > 1.2 and (best.is_empty() or v > best[0]):
			best = [v, {"units": ids, "to": k, "roads": false}]
	return best


# ------------------------------------------------------------------ scelte

func _choice(eng, p: int, req: Dictionary) -> int:
	var opts: Array = req.get("options", [])
	var title: String = req.get("title", "")
	if opts.is_empty():
		return 0
	if req.has("advances"):
		var lst: Array = req["advances"]
		var bi := 0
		var bv := -99.0
		for i in lst.size():
			var v := adv_value(eng, p, lst[i]) + _jitter()
			if v > bv:
				bv = v
				bi = i
		return bi
	if req.get("battle", false):
		# gioca la tattica migliore disponibile
		var cards: Array = req.get("cards", [])
		var pref := ["high_morale", "archers", "scouts", "prepared_defenses", "flanking", "wedge", "tactical_surprise",
			"defiant_stand", "for_the_people", "upgraded_defenses", "peltasts", "siege", "high_ground", "routing", "martyr"]
		var bi2 := 0
		var bs := 999
		for i in range(1, cards.size()):
			var t: String = D.action_card(cards[i])[2]
			var r := pref.find(t)
			if r >= 0 and r < bs:
				bs = r
				bi2 = i
		if level == 0 and rng.randf() < 0.5:
			return 0
		return bi2
	if req.get("explore", false):
		return rng.randi() % opts.size()
	if title.find("Ti ritiri") >= 0:
		var bt: Dictionary = eng.battle
		if bt.is_empty():
			return 0
		var a: int = eng._fighters(bt, "att").size()
		var d: int = eng._fighters(bt, "def").size()
		return 1 if a < d else 0
	if title.find("Tempio ti dà") >= 0 or title.find("Nazionalismo") >= 0:
		if _wonder_target(eng, p) != "" and eng.res(p, "culture") < 5:
			return 1
		return 1 if eng.res(p, "culture") < eng.res(p, "mood") + 1 else 0
	if title.begins_with("Miti"):
		return 0 if eng.res(p, "mood") >= 2 else 1
	if title.begins_with("Arte d'assedio") or title.begins_with("Armi d'acciaio") or title.begins_with("Grande Arena") \
			or title.begins_with("Assedio") or title.begins_with("Istruzione gratuita") or title.begins_with("Grande Faro"):
		return 0
	if title.find("lo tieni") >= 0:
		return 0 if eng.res(p, "culture") >= 2 else 1
	if title.begins_with("Rivoluzione"):
		return 0 if eng.units_of(p, "infantry").size() >= 3 else 1
	if title.begins_with("Moneta"):
		return 0
	if title.find("Ti ritiri") >= 0:
		return 0
	if title.find("Cambio di governo") >= 0:
		return 0
	if title.find("radi al suolo") >= 0:
		return 0
	if title.find("primo giocatore") >= 0:
		return opts.find(eng.pname(p)) if opts.has(eng.pname(p)) else 0
	if title.find("Completi") >= 0:
		return 0
	if title.find("Terremoto: quanti") >= 0:
		return 0
	if req.has("hexes"):
		var hx: Array = req["hexes"]
		if title.begins_with("Barbari"):
			# lontano dalle proprie città
			var bi3 := 0
			var bd := -1
			for i in hx.size():
				var d2 := 99
				for c in eng.cities_of(p):
					d2 = mini(d2, eng.hdist(hx[i], c["h"]))
				if d2 > bd:
					bd = d2
					bi3 = i
			return bi3
		if title.find("Porto") >= 0:
			return 0
	if title.find("Paghi") >= 0 or title.find("paghi") >= 0:
		return 1
	if title.find("Ispirazione") >= 0 or title.find("copi") >= 0:
		return rng.randi() % opts.size()
	return 0 if level > 0 else rng.randi() % opts.size()
