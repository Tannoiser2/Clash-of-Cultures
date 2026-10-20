extends RefCounted
## Intelligenza artificiale di Clash of Cultures. Euristica a priorità: espansione (coloni e
## fondazioni), raccolta mirata a ciò che serve, avanzamenti con un valore che tiene conto degli
## obiettivi in mano, edifici, difesa dai barbari, campagne militari contro la città nemica più
## conveniente (si parte solo con forze sufficienti), navi per esplorare, portare coloni oltremare e
## cacciare i pirati, risparmio mirato per le meraviglie (Cultura, Umore e risorse), felicità.
## level: 0 facile (più casuale e prudente), 1 normale, 2 difficile.

const D = preload("res://scripts/data/coc_data.gd")

var level := 1
var style := "balanced"

## Personalità dell'IA: ogni stile sposta i pesi delle stesse valutazioni.
## war_age: era da cui attacca i giocatori; war_dist: distanza massima del bersaglio; war_lack: unità
## che recluta apposta per una campagna; war_unit: valore di ciascuna; war_bonus: interesse per le città
## dei giocatori; ratio: forza richiesta per attaccare; march: frazione di forze con cui si avvicina;
## garrison: guarnigione minima per città; fortress/build/adv: bonus a Fortezze, edifici, avanzamenti;
## wonder: quanto tiene alle meraviglie; settler/ship: bonus a coloni e navi; cats: categorie preferite.
const STYLES := {
	"balanced": {"it": "Equilibrato", "war_age": 2, "war_dist": 6, "war_lack": 2, "war_unit": 3.0, "war_bonus": 0.0,
		"ratio": 1.45, "march": 0.7, "garrison": 0, "fortress": 0.0, "build": 0.0, "adv": 0.0, "wonder": 1.0,
		"settler": 0.0, "ship": 0.0, "cats": {}},
	"aggressive": {"it": "Conquistatore", "war_age": 2, "war_dist": 8, "war_lack": 3, "war_unit": 4.0, "war_bonus": 2.5,
		"ratio": 1.25, "march": 0.5, "garrison": 0, "fortress": 0.0, "build": 0.0, "adv": 0.0, "wonder": 0.8,
		"settler": 0.0, "ship": 0.0, "cats": {"Warfare": 1.5, "Autocracy": 1.0}},
	"defensive": {"it": "Difensore", "war_age": 5, "war_dist": 3, "war_lack": 0, "war_unit": 2.0, "war_bonus": -1.0,
		"ratio": 1.9, "march": 1.0, "garrison": 1, "fortress": 3.0, "build": 0.5, "adv": 0.0, "wonder": 1.3,
		"settler": 0.0, "ship": 0.0, "cats": {"Warfare": 0.8, "Spirituality": 1.0, "Theocracy": 1.0}},
	"builder": {"it": "Costruttore", "war_age": 4, "war_dist": 4, "war_lack": 0, "war_unit": 2.0, "war_bonus": -1.0,
		"ratio": 1.7, "march": 1.0, "garrison": 0, "fortress": 0.0, "build": 1.5, "adv": 1.0, "wonder": 1.6,
		"settler": 0.5, "ship": 0.0, "cats": {"Construction": 1.2, "Education": 1.2, "Science": 1.0, "Traditions": 1.0, "Democracy": 1.0}},
	"seafarer": {"it": "Navigatore", "war_age": 3, "war_dist": 6, "war_lack": 1, "war_unit": 3.0, "war_bonus": 0.0,
		"ratio": 1.45, "march": 0.7, "garrison": 0, "fortress": 0.0, "build": 0.0, "adv": 0.3, "wonder": 1.0,
		"settler": 1.5, "ship": 1.5, "cats": {"Maritime": 1.5, "Economy": 1.2}},
}


const STYLE_TEXT := {
	"balanced": "un po' di tutto: si espande, costruisce e attacca quando conviene.",
	"aggressive": "punta sull'esercito: recluta per conquistare, attacca presto e anche con meno margine.",
	"defensive": "guarnigioni in ogni città, Fortezze e meraviglie; attacca solo se è molto più forte.",
	"builder": "edifici, avanzamenti e meraviglie; l'esercito serve quasi solo a difendersi.",
	"seafarer": "porti, navi e coloni oltremare; cerca le categorie Mare ed Economia.",
}


## Parametro dello stile attuale.
func sv(k: String):
	return STYLES.get(style, STYLES["balanced"]).get(k, STYLES["balanced"][k])
var rng := RandomNumberGenerator.new()
var fails := 0
var last_turn := -1
var tried := {}
var war_cache := {}
var war_last := {}

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
	if info["border"] == "c" and eng.has_adv(p, "Engineering") and not eng.players[p]["won"].is_empty():
		v += 1.5
	# categorie preferite dallo stile
	v += float(sv("cats").get(info["cat"], 0.0))
	if style == "aggressive" and a in ["Tactics", "Draft", "Steel Weapons", "Siegecraft", "Husbandry", "Bartering"]:
		v += 1.5
	if style == "defensive" and a in ["Tactics", "Siegecraft", "Myths"]:
		v += 1.5
	if style == "seafarer" and a in ["Fishing", "Navigation", "Cartography", "Warships", "Trade Routes"]:
		v += 1.5 + (1.5 if a == "Trade Routes" else 0.0)
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
	if a in ["Fishing", "Irrigation"]:
		# quante caselle di mare (o aride) attorno alle città diventano raccoglibili
		var want := "sea" if a == "Fishing" else "barren"
		var k := 0
		for c in eng.cities_of(p):
			for x in eng.neighbors(c["h"]):
				if eng.ter(x) == want:
					k += 1
		v += minf(4.0, k * 0.8)
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
	# espansione: l'avanzamento sblocca un avanzamento di civiltà
	if eng.exp:
		var ck: String = eng.players[p].get("civ", "")
		if ck != "":
			for ca in CivData.CIVS[ck]["adv"]:
				if not eng.players[p]["adv"].has(ca[0]) and (ca[2] == a or (ca[2] == "gov" and info["cat"] in D.GOVERNMENTS)):
					v += 2.5
		if a in ["Bartering", "Math", "Arts"]:
			v += 0.8
		if a == "Bartering" and eng.age >= 2:
			v += 1.0
	return v


func _has_ore_source(eng, p: int) -> bool:
	for c in eng.cities_of(p):
		for x in [c["h"]] + eng.neighbors(c["h"]):
			if eng.ter(x) == "mountain":
				return true
	return false


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
		if u["o"] != p and eng.is_army(u) and eng.hdist(u["h"], c["h"]) <= 2:
			k += 1
	# le città barbare vicine generano rinforzi
	for b in eng.cities_of(-1):
		if eng.hdist(b["h"], c["h"]) <= 2:
			k += 1
	return mini(k, 3)


# ------------------------------------------------------------------ guerra

func _unit_power(u: Dictionary) -> float:
	match u["t"]:
		"infantry":
			return 1.0
		"cavalry", "elephant":
			return 1.3
		"leader":
			return 0.7
	return 0.0


func _power(units: Array) -> float:
	var v := 0.0
	for u in units:
		v += _unit_power(u)
	return v


## Forza difensiva stimata di una casella nemica (unità, Fortezza, rinforzi che il difensore può reclutare).
func _def_power(eng, p: int, k: String) -> float:
	var v := _power(eng.enemy_units_at(k, p).filter(func(x): return eng.is_army(x) and x["on"] == -1))
	var c: Dictionary = eng.city_at(k)
	if not c.is_empty():
		if c["b"].has("fortress"):
			v += 1.5
		if "great_wall" in c["w"]:
			v += 1.0
		if c["o"] >= 0:
			v += 0.6
	return v


## Distanze via terra verso k, su caselle esplorate e senza nemici (k esclusa).
func _land_dist(eng, p: int, k: String, maxd := 7) -> Dictionary:
	var seen := {k: 0}
	var q := [k]
	while not q.is_empty():
		var x: String = q.pop_front()
		var d: int = seen[x]
		if d >= maxd:
			continue
		for y in eng.neighbors(x):
			if seen.has(y):
				continue
			# le caselle inesplorate si attraversano esplorandole (spesso sono terra)
			if eng.revealed(y) and (not eng.is_land(y) or eng.has_enemy(y, p)):
				continue
			seen[y] = d + 1
			q.append(y)
	return seen


## Bersaglio della campagna militare: la città nemica (di un giocatore o barbara) più conveniente da
## conquistare, raggiungibile via terra. {h, need (forza che serve), o, dm (distanze verso h)} o {}.
func _war_target(eng, p: int) -> Dictionary:
	var ck: Array = war_cache.get(p, [])
	if not ck.is_empty() and ck[0] == eng.turn_count:
		return ck[1]
	var best := {}
	if eng.has_adv(p, "Tactics"):
		var my_cities: Array = eng.cities_of(p)
		var my_armies: Array = eng.units_of(p).filter(func(u): return eng.is_army(u) and u["on"] == -1)
		var my_pow := _power(my_armies)
		var top := -1
		var top_s := -1.0
		for q in eng.n:
			if q != p:
				var sc0: float = eng.score(q)["total"]
				if sc0 > top_s:
					top_s = sc0
					top = q
		var conq := 0
		for id in eng.players[p]["obj"]:
			for key in eng.obj_parts(id):
				if key in ["conqueror", "warmonger", "aggressor", "great_battle", "warlord", "king_slayer", "marauder", "great_commander", "draconian"]:
					conq += 1
		var bs := 0.5
		for c in eng.cities.values():
			var o: int = c["o"]
			if o == p:
				continue
			if o >= 0:
				if eng.age < maxi(int(sv("war_age")), 4 if level == 0 else 2):
					continue
				if not eng.can_attack(p, o):
					continue
			var dm := _land_dist(eng, p, c["h"], 9)
			var dist := 99
			for mc in my_cities:
				dist = mini(dist, dm.get(mc["h"], 99))
			for u in my_armies:
				dist = mini(dist, dm.get(u["h"], 99))
			if dist > (int(sv("war_dist")) if o >= 0 else 5):
				continue
			var dp := _def_power(eng, p, c["h"])
			var need := dp * 1.4 + 1.0
			if need > (4.8 if style == "aggressive" else 4.2):
				continue
			var val: float = 4.0 + eng.city_size(c) * 1.5
			if o == -1:
				val += 1.0
			else:
				val += conq * 1.5 + (1.5 if o == top else 0.0) + (1.0 if level >= 2 else 0.0) + float(sv("war_bonus"))
			var sc: float = val - dist * 0.7 - dp * 1.2 - maxf(0.0, need - my_pow) * 0.6
			# si resta sul bersaglio scelto finché ha senso: niente eserciti che vanno avanti e indietro
			if c["h"] == war_last.get(p, ""):
				sc += 2.5
			if sc > bs:
				bs = sc
				best = {"h": c["h"], "need": need, "o": o, "dm": dm}
		# punto di raccolta: la propria città più vicina al bersaglio
		if not best.is_empty():
			var rd := 99
			for mc in my_cities:
				var d3: int = best["dm"].get(mc["h"], 99)
				if d3 < rd:
					rd = d3
					best["rally"] = mc["h"]
			if best.has("rally"):
				best["rm"] = _land_dist(eng, p, best["rally"], 10)
	war_cache[p] = [eng.turn_count, best]
	war_last[p] = best.get("h", "")
	if OS.get_environment("COC_WARDBG") != "" and not best.is_empty():
		print("WAR p%d era%d -> %s (o%d) need %.1f" % [p, eng.age, best["h"], best["o"], best["need"]])
	return best


# ------------------------------------------------------------------ mare

## Miglior posto dove fondare raggiungibile per mare da h: [mare, casella di terra, punteggio] o [].
func _sea_spot(eng, p: int, h: String) -> Array:
	var reach: Dictionary = eng.sea_reach(h, p, eng.has_adv(p, "Navigation"))
	var best := []
	var bs := 2.0
	var seen := {}
	for r in reach:
		for x in eng.neighbors(r):
			if seen.has(x) or not eng.is_land(x):
				continue
			seen[x] = true
			if eng.has_enemy(x, p):
				continue
			var sv: float = spot_value(eng, p, x) - 0.12 * eng.hdist(h, r)
			if sv > bs:
				bs = sv
				best = [r, x, sv]
	return best


## Città nemiche (non arrabbiate) entro 2 caselle da k non ancora servite da altri coloni o navi propri.
func _route_value(eng, p: int, k: String, ids: Array) -> int:
	var n := 0
	for c in eng.cities.values():
		if c["o"] < 0 or c["o"] == p or c["mood"] == 0 or eng.hdist(c["h"], k) > 2:
			continue
		var served := false
		for u in eng.units_of(p):
			if u["t"] in ["settler", "ship"] and not ids.has(u["id"]) and eng.hdist(u["h"], c["h"]) <= 2:
				served = true
				break
		if not served:
			n += 1
	return n


func _sea_spot_from_city(eng, p: int, c: Dictionary) -> Array:
	for x in eng.neighbors(c["h"]):
		if eng.is_sea(x):
			return _sea_spot(eng, p, x)
	return []


func _ship_move(eng, p: int, ids: Array) -> Array:
	var h: String = eng.units[ids[0]]["h"]
	var tg: Dictionary = eng.move_targets(p, ids)
	if tg.is_empty():
		return []
	var cargo := []
	for id in ids:
		cargo += eng.carried(int(id))
	# porta i coloni a destinazione
	if cargo.any(func(u): return u["t"] == "settler"):
		var sp := _sea_spot(eng, p, h)
		if not sp.is_empty() and sp[0] != h and tg.has(sp[0]) and not tg[sp[0]].get("battle", false):
			return [6.5, {"units": ids, "to": sp[0], "roads": false}]
		return []
	if not cargo.is_empty():
		return []
	var best := []
	# un colono aspetta in una città costiera senza posti buoni via terra: vai a prenderlo
	for s in eng.units_of(p, "settler"):
		if s["on"] != -1 or eng.city_at(s["h"]).get("o", -9) != p:
			continue
		if _settler_target(eng, p, s["h"])[1] >= 2.0:
			continue
		if h in eng.neighbors(s["h"]):
			return []
		for x in eng.neighbors(s["h"]):
			if tg.has(x) and not tg[x].get("battle", false) and tg[x]["kind"] == "sea":
				if _sea_spot(eng, p, x).is_empty():
					continue
				best = [4.5, {"units": ids, "to": x, "roads": false}]
	if not best.is_empty():
		return best
	# Rotte Commerciali: la nave si piazza vicino alle città nemiche (Cibo a ogni turno)
	if eng.has_adv(p, "Trade Routes"):
		var here_r := _route_value(eng, p, h, ids)
		if here_r > 0:
			return []
		var br := 0
		for k in tg:
			if tg[k]["kind"] != "sea" or tg[k].get("battle", false):
				continue
			var rv := _route_value(eng, p, k, ids)
			if rv > br:
				br = rv
				best = [4.0 + rv * 0.8, {"units": ids, "to": k, "roads": false}]
		if not best.is_empty():
			return best
	for k in tg:
		var info: Dictionary = tg[k]
		var v := 0.0
		if info.get("battle", false):
			var en: int = eng.ships_at(k).filter(func(u): return u["o"] != p).size()
			var mine := ids.size() + (1 if eng.has_adv(p, "Warships") else 0)
			if mine >= en + 1 or (mine >= en and level >= 2):
				v = 5.0 + (1.5 if eng.ships_at(k)[0]["o"] == -2 else 0.0)
		elif info["kind"] == "explore_sea":
			v = 3.2 if eng.age <= 4 else 1.2
		v += _jitter() * 0.3
		if v > 1.5 and (best.is_empty() or v > best[0]):
			best = [v, {"units": ids, "to": k, "roads": false}]
	return best


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
			v -= 4.0
		elif x != k:
			# caselle già sfruttate da un'altra città: meno raccolta per entrambe
			for c2 in eng.cities.values():
				if eng.hdist(c2["h"], x) == 1:
					v -= 0.7
					break
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
	# il Minerale serve per edifici e meraviglie: conta molto se ancora non lo si raccoglie
	if kinds.has("ore") and not _has_ore_source(eng, p):
		v += 1.5
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
			var tg2 := _settler_target(eng, p, u["h"])
			if sv >= 4.5 or (sv >= 1.5 and tg2[1] <= sv + 0.3):
				cands.append([9.0 + sv * 0.3, {"t": "found", "u": u["id"]}])
		# città
		for c in eng.cities_of(p):
			if not eng.can_activate(c):
				continue
			# una seconda attivazione peggiora l'umore: da neutrale ad arrabbiata costa molto
			var extra_act: float = 0.0
			if c["act"] > 0:
				extra_act = 6.0 if c["mood"] == 1 else 3.5
			if c["mood"] == 0 and c["act"] > 0:
				continue
			# raccolta
			var use_bc: bool = eng.civ_adv(p, "Ballcourts") and eng.res(p, "mood") >= 3 and c["mood"] > 0
			if use_bc:
				eng.T["bc_city"] = c["id"]
			var picks: Array = eng.auto_collect(c, _need_weights(eng, p))
			var valid_c: bool = not picks.is_empty() and eng.valid_collect(c, picks)
			eng.T.erase("bc_city")
			if valid_c:
				var gv := 0.0
				var wt := _wonder_target(eng, p)
				for pk in picks:
					var r: String = pk[1]
					if not r in D.RES or eng.res(p, r) < eng.res_limit(p, r):
						gv += 1.0
					if wt != "" and r in ["food", "wood", "ore"] and eng.res(p, r) < D.WONDERS[wt]["cost"][r]:
						gv += 1.6 if _wonder_focus(eng, p) else 0.8
				cands.append([gv * 1.6 - extra_act + _jitter() - (0.6 if use_bc else 0.0), {"t": "collect", "c": c["id"], "picks": picks,
					"metal": eng.has_adv(p, "Metallurgy"), "bc": use_bc}])
			# costruzione
			for b in eng.bld_list():
				if eng.can_build(p, c, b) == "" and eng.can_pay(p, eng.build_cost(p, b, c)):
					var bvv := _building_value(eng, p, c, b) - _saving_penalty(eng, p, eng.build_cost(p, b, c)) + _glut_bonus(eng, p, eng.build_cost(p, b, c))
					if _wonder_focus(eng, p) and _uses_wonder_res(eng, p, eng.build_cost(p, b, c)):
						bvv -= 8.0
					cands.append([bvv - extra_act + _jitter(), {"t": "build", "c": c["id"], "b": b}])
			# meraviglie
			for w in eng.players[p]["won"]:
				if eng.can_build_wonder(p, c, w) == "":
					cands.append([18.0 - extra_act, {"t": "wonder", "c": c["id"], "w": w}])
			# reclutamento
			var rc := _recruit_plan(eng, p, c)
			if not rc.is_empty():
				var rcost: Dictionary = eng.recruit_cost(p, rc[1]["comp"], rc[1]["sanit"], rc[1]["draft"], c)
				var pen := 0.0 if _city_threat(eng, p, c) > 0 else _saving_penalty(eng, p, rcost)
				if _wonder_focus(eng, p) and _city_threat(eng, p, c) == 0 and _uses_wonder_res(eng, p, rcost):
					pen += 8.0
				cands.append([rc[0] - extra_act - pen + _glut_bonus(eng, p, rcost) + _jitter(), rc[1]])
		# avanzamento
		var buy: Array = eng.buyable_advances(p)
		var use_pp: bool = false
		if buy.is_empty() and eng.civ_adv(p, "Peace & Poetry") and not eng.T.get("pp", false) and eng.res(p, "mood") >= 2:
			buy = D.all_advances().filter(func(a): return eng.can_buy_adv(p, a))
			use_pp = true
		if not buy.is_empty():
			var ba := ""
			var bav := -1.0
			for a in buy:
				var v := adv_value(eng, p, a) + _jitter()
				if v > bav:
					bav = v
					ba = a
			# dopo i primi avanzamenti, edifici e meraviglie rendono di più
			var adv_pen := 1.5 if eng.players[p]["adv"].size() >= 9 else 0.0
			var ideas: int = eng.res(p, "idea")
			# le Idee servono solo per gli avanzamenti: se ce ne sono, spenderle non costa nulla
			var spen := 0.0 if use_pp or ideas >= 2 else _saving_penalty(eng, p, {"food": 2})
			var ib := (1.5 + 0.6 * maxi(0, ideas - 3)) if ideas >= 2 else 0.0
			cands.append([3.0 + bav * 0.55 - adv_pen - spen + ib + float(sv("adv")), {"t": "advance", "a": ba, "pp": use_pp}])
		# movimento
		var mv := _best_group_move(eng, p, {})
		if not mv.is_empty() and mv[0] > 2.0:
			# l'azione Muovi sposta fino a 3 gruppi: contano anche il secondo e il terzo
			var mvv: float = mv[0]
			var moved := {}
			var mv2 := mv
			for i in 2:
				for id in mv2[1]["units"]:
					moved[int(id)] = true
				mv2 = _best_group_move(eng, p, moved)
				if mv2.is_empty() or mv2[0] <= 2.0:
					break
				mvv += mv2[0] * 0.3
			cands.append([mvv, {"t": "move"}])
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
	if OS.get_environment("COC_AIDBG") != "":
		cands.sort_custom(func(x, y): return x[0] > y[0])
		var top := []
		for i in mini(5, cands.size()):
			top.append("%s %.1f" % [cands[i][1].get("t", "") + "_" + str(cands[i][1].get("b", cands[i][1].get("w", ""))), cands[i][0]])
		print("AIDBG p%d era%d wt=%s mood%d res%s cul%d happy%d | %s" % [p, eng.age, _wonder_target(eng, p), eng.res(p, "mood"), str(eng.players[p]["res"].values()), eng.res(p, "culture"), eng.cities_of(p).filter(func(c): return c["mood"] == 2).size(), ", ".join(top)])
	var bk := str(best)
	if best.get("t", "") != "end":
		tried[bk] = tried.get(bk, 0) + 1
	return best


func _need_weights(eng, p: int) -> Dictionary:
	var w := {}
	for r in ["food", "wood", "ore", "idea", "gold"]:
		var have: int = eng.res(p, r)
		w[r] = 1.6 - 0.15 * have
		# oltre il limite la risorsa va persa; vicino al limite serve poco
		if have >= eng.res_limit(p, r):
			w[r] = -2.0
		elif have >= 5 and r in ["wood", "ore"]:
			w[r] = 0.5
	w["food"] += 0.3
	# legno e minerale servono per gli edifici
	for r in ["wood", "ore"]:
		if eng.res(p, r) < 2:
			w[r] += 0.5
	w["mood"] = 1.0 if eng.res(p, "mood") < 3 else 0.6
	# meraviglia in vista: servono le sue risorse
	var wt := _wonder_target(eng, p)
	if wt != "":
		var cost: Dictionary = D.WONDERS[wt]["cost"]
		for r in ["food", "wood", "ore"]:
			if eng.res(p, r) < cost[r]:
				w[r] += 0.8
	return w


## Bonus per una spesa che usa risorse ammassate vicino al limite (altrimenti andrebbero sprecate).
func _glut_bonus(eng, p: int, cost: Dictionary) -> float:
	var b := 0.0
	for r in ["food", "wood", "ore", "idea", "gold"]:
		var extra: int = eng.res(p, r) - 4
		if extra > 0 and cost.get(r, 0) > 0:
			b += 0.7 * mini(extra, cost[r])
	return b


## La spesa toglie risorse che mancano ancora alla Meraviglia?
func _uses_wonder_res(eng, p: int, cost: Dictionary) -> bool:
	var wt := _wonder_target(eng, p)
	if wt == "":
		return false
	var need: Dictionary = D.WONDERS[wt]["cost"]
	for r in ["food", "wood", "ore", "gold", "culture"]:
		if cost.get(r, 0) > 0 and eng.res(p, r) - cost[r] < need.get(r, 0) + (0 if r != "gold" else 99):
			return true
	return false


## Una città nemica (di un giocatore o barbara) entro 3 caselle.
func _near_enemy_city(eng, p: int, c: Dictionary) -> bool:
	for c2 in eng.cities.values():
		if c2["o"] != p and eng.hdist(c2["h"], c["h"]) <= 3:
			return true
	return false


## Penalità per una spesa che allontana dalla meraviglia che si sta preparando.
func _saving_penalty(eng, p: int, cost: Dictionary) -> float:
	var wt := _wonder_target(eng, p)
	if wt == "" or eng.age < 2:
		return 0.0
	var need: Dictionary = D.WONDERS[wt]["cost"]
	var pen := 0.0
	for r in ["wood", "ore", "food"]:
		if cost.get(r, 0) > 0 and eng.res(p, r) < need[r]:
			pen += (2.5 if r != "food" else 1.5) * (2.0 if eng.res(p, "culture") >= 3 else 1.0) * (1.5 if eng.age >= 3 else 1.0) \
					* (1.5 if _wonder_focus(eng, p) else 1.0)
	return pen


## Umore da tenere da parte per rendere Felice la città che ospiterà la Meraviglia.
func _wonder_mood_reserve(eng, p: int) -> int:
	if _wonder_target(eng, p) == "" or eng.age < 3:
		return 0
	var cs: Array = eng.cities_of(p)
	var best := 99
	for c in cs:
		if eng.city_size(c) + 1 > cs.size() or eng.city_size(c) >= 5:
			continue
		if c["mood"] == 2:
			return 0
		best = mini(best, eng.city_size(c) * (2 - c["mood"]))
	return 0 if best == 99 else best


## Meraviglia vicina (Cultura quasi pronta): si risparmia su tutto il resto.
func _wonder_focus(eng, p: int) -> bool:
	var w := _wonder_target(eng, p)
	if w == "" or eng.age < 3:
		return false
	return _wonder_missing(eng, p, w) <= roundi((8 if eng.age == 3 else 14) * float(sv("wonder")))


## Si mette da parte la Cultura per una Meraviglia in mano (ne servono 5).
func _saving_culture(eng, p: int) -> bool:
	return not eng.players[p]["won"].is_empty() and eng.age >= 2


## Meraviglia in mano che si può puntare (prerequisiti posseduti o quasi).
func _wonder_target(eng, p: int) -> String:
	if not eng.has_adv(p, "Engineering"):
		return ""
	var best := ""
	var bm := 99
	for w in eng.players[p]["won"]:
		if eng.has_adv(p, D.WONDERS[w]["req"]) or int(eng.players[p].get("architect", 0)) > 0:
			var m := _wonder_missing(eng, p, w)
			if m < bm:
				bm = m
				best = w
	return best


## Risorse che mancano per la Meraviglia (la Cultura conta doppio; l'Oro copre qualsiasi risorsa).
func _wonder_missing(eng, p: int, w: String) -> int:
	var cost: Dictionary = D.WONDERS[w]["cost"]
	var m := 0
	for r in ["food", "wood", "ore"]:
		m += maxi(0, cost[r] - eng.res(p, r))
	m = maxi(0, m - eng.res(p, "gold"))
	m += 2 * maxi(0, cost["culture"] - eng.res(p, "culture"))
	return m


func _building_value(eng, p: int, c: Dictionary, b: String) -> float:
	# ogni edificio è 1 PV e fa crescere la città (più raccolta e più reclutamento)
	var v := 9.5 + (1.0 if c["mood"] == 2 else 0.0) + (1.0 if eng.age <= 3 else 0.0) + float(sv("build"))
	if b == "fortress":
		v += float(sv("fortress"))
	if b == "port" and style == "seafarer":
		v += 2.0
	match b:
		"temple":
			v += 1.5
		"academy":
			v += 2.0
		"fortress":
			v += 0.5 + 2.0 * float(_city_threat(eng, p, c) > 0)
		"port":
			v += 0.5
			# il primo porto apre il mare: navi per esplorare, trasportare coloni e cacciare i pirati
			if not eng.cities_of(p).any(func(c2): return c2["b"].has("port")) \
					and _ship_demand(eng, p, c, not _sea_spot_from_city(eng, p, c).is_empty()) > 3.0:
				v += 1.0
		"market":
			v += 1.5 + (1.0 if _city_threat(eng, p, c) > 0 else 0.0)
			# espansione: il Mercato permette Cavalleria ed Elefanti
			if eng.exp and not eng.cities_of(p).any(func(c2): return c2["b"].has("market")):
				v += 1.5
		"observatory":
			v += 1.6
		"obelisk":
			v += 1.0
	for id in eng.players[p]["obj"]:
		for key in eng.obj_parts(id):
			if key in ["diverse", "religious", "academic", "fortified", "coastal", "citadel"]:
				v += 1.0
			if (key == "mercantile" and b == "market") or (key == "scientists" and b == "observatory") or (key == "legacy" and b == "obelisk"):
				v += 2.0
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
	if threat > here and here < 3 and eng.supply_left(p, "infantry") > 0:
		var k := mini(budget, mini(threat - here + 1, 4 - here))
		comp["infantry"] = k
		budget -= k
		v += 5.5 * k + (3.0 if here == 0 else 0.0)
	# Difensore: una guarnigione in ogni città (due nelle città di confine), dall'era 2
	var gar: int = int(sv("garrison"))
	if gar > 0 and eng.age >= 2 and eng.has_adv(p, "Tactics") and comp["infantry"] == 0 and budget > 0:
		var want_g: int = gar + (1 if _near_enemy_city(eng, p, c) else 0)
		if here < want_g and eng.supply_left(p, "infantry") > 0:
			comp["infantry"] = mini(budget, want_g - here)
			budget -= comp["infantry"]
			v += 3.5 * comp["infantry"]
	# coloni per espandersi (anche oltremare, se c'è una nave per portarli)
	var land_tgt: float = _settler_target(eng, p, c["h"])[1]
	var sea_ok: bool = land_tgt < 2.0 and eng.is_coastal(c) and not _sea_spot_from_city(eng, p, c).is_empty() \
			and (not eng.units_of(p, "ship").is_empty() or c["b"].has("port"))
	if budget > 0 and ncity + settlers < (9 if style == "seafarer" else 8) and settlers < 2 and eng.supply_left(p, "settler") > 0 \
			and (land_tgt >= 2.0 or sea_ok):
		comp["settler"] = 2 if (budget >= 2 and ncity < 4 and settlers == 0 and land_tgt >= 2.0) else 1
		budget -= comp["settler"]
		v += (7.0 if ncity < 4 else 4.5) + (comp["settler"] - 1) * 2.0 + float(sv("settler"))
	# navi: trasporto dei coloni, pirati, esplorazione, obiettivi navali
	if budget > 0 and c["b"].has("port") and eng.supply_left(p, "ship") > 0:
		var shipv := _ship_demand(eng, p, c, sea_ok or (settlers > 0 and land_tgt < 2.0))
		if shipv > 0.0:
			comp["ship"] = 1
			budget -= 1
			v += shipv
	# un piccolo esercito per i barbari vicini
	if budget > 0 and eng.has_adv(p, "Tactics") and _barb_threat(eng, p) > 0 and here < 3 and comp["infantry"] == 0:
		comp["infantry"] = mini(budget, 2)
		budget -= comp["infantry"]
		v += 3.0
	# campagna militare: rinforzi per l'esercito che punta alla città nemica
	var focus := _wonder_focus(eng, p)
	var wt := {} if focus else _war_target(eng, p)
	if budget > 0 and not wt.is_empty() and eng.supply_left(p, "infantry") > comp["infantry"]:
		var dm: Dictionary = wt["dm"]
		var rally: String = wt.get("rally", "")
		# si recluta di preferenza nel punto di raccolta; il Conquistatore anche nelle altre città vicine
		if (c["h"] == rally or rally == "" or style == "aggressive") and dm.get(c["h"], 99) <= int(sv("war_dist")):
			var near := 0.0
			var rm: Dictionary = wt.get("rm", {})
			for u in eng.units_of(p):
				if eng.is_army(u) and u["on"] == -1 and (rm.get(u["h"], 99) <= 2 or dm.get(u["h"], 99) <= 2):
					near += _unit_power(u)
			var lack: int = ceili(float(wt["need"]) - near)
			# si recluta per la campagna solo se mancano poche unità: le guerre lunghe costano troppo
			if lack > int(sv("war_lack")) or eng.age < (2 if style == "aggressive" else 3):
				lack = 0
			var k2 := mini(budget, mini(lack, 4 - here - comp["infantry"]))
			k2 = mini(k2, eng.supply_left(p, "infantry") - comp["infantry"])
			if k2 > 0:
				comp["infantry"] += k2
				budget -= k2
				v += (float(sv("war_unit")) + (0.5 if level >= 2 else 0.0)) * k2
	# espansione: un Leader appena possibile (le sue abilità valgono molto)
	if eng.exp and budget > 0 and eng.leader_unit(p).is_empty() and eng.can_recruit_type(p, c, "leader") \
			and eng.res(p, "culture") >= 2 and eng.res(p, "mood") >= 2 and here < 4:
		comp["leader"] = 1
		budget -= 1
		v += 6.0
	if comp["settler"] + comp["infantry"] + comp["ship"] + comp.get("leader", 0) == 0:
		return []
	var mres := _wonder_mood_reserve(eng, p) if threat == 0 else 0
	var sanit: bool = eng.has_adv(p, "Sanitation") and comp["settler"] > 0 and eng.res(p, "mood") >= 1 + mres
	var draft: bool = eng.has_adv(p, "Draft") and comp["infantry"] > 0 and eng.res(p, "mood") >= (2 if eng.has_adv(p, "Civil Liberties") else 1) + mres
	if sanit and draft and eng.res(p, "mood") < 2 + mres:
		draft = false
	# riduci finché si può pagare
	while comp["settler"] + comp["infantry"] + comp["ship"] + comp.get("leader", 0) > 0:
		if eng.valid_recruit(p, c, comp, sanit, draft) == "":
			if eng.exp:
				v += _upgrade_army(eng, p, c, comp, sanit, draft)
			return [v, {"t": "recruit", "c": c["id"], "comp": comp, "sanit": sanit, "draft": draft}]
		if comp["infantry"] > 0:
			comp["infantry"] -= 1
			v -= 3.0
			if comp["infantry"] == 0:
				draft = false
		elif comp["ship"] > 0:
			comp["ship"] = 0
			v -= 3.0
		elif comp["settler"] > 0:
			comp["settler"] -= 1
			v -= 4.0
			sanit = false
		elif comp.get("leader", 0) > 0:
			comp["leader"] = 0
			v -= 6.0
	return []


## Quanto serve una nave reclutata in questa città (0 = non serve).
func _ship_demand(eng, p: int, c: Dictionary, transport: bool) -> float:
	var ships: int = eng.units_of(p, "ship").size()
	var v := 0.0
	if transport and ships == 0:
		v += 5.5
	# pirati vicino alle proprie città
	var pir := 0
	for u in eng.units_of(-2):
		for c2 in eng.cities_of(p):
			if eng.hdist(u["h"], c2["h"]) <= 3:
				pir += 1
				break
	if pir > 0 and ships < pir + 1:
		v += 3.5
	# obiettivi che chiedono navi o battaglie navali
	var naval := 0
	for id in eng.players[p]["obj"]:
		for key in eng.obj_parts(id):
			if key in ["great_navy", "blockade", "sea_lanes", "cleanse_seas", "amphibious"]:
				naval += 1
	if naval > 0 and ships < 2 + naval:
		v += 3.0
	# Rotte Commerciali: navi vicino alle città costiere nemiche
	if eng.has_adv(p, "Trade Routes") and ships < 2:
		for c2 in eng.cities.values():
			if c2["o"] >= 0 and c2["o"] != p and eng.is_coastal(c2) and eng.hdist(c2["h"], c["h"]) <= 5:
				v += 3.0
				break
		# esplorare il mare all'inizio
	if eng.age <= 3 and ships == 0 and _unexplored_by_sea(eng, p, c):
		v += 2.5
	# legno in eccesso: una nave costa 2 Legno
	if eng.res(p, "wood") >= 5 and ships < 2:
		v += 1.5
	v += float(sv("ship")) if v > 0.0 or style == "seafarer" else 0.0
	if ships >= (4 if style == "seafarer" else 3):
		v -= 3.0
	return v


func _unexplored_by_sea(eng, p: int, c: Dictionary) -> bool:
	for x in eng.neighbors(c["h"]):
		if eng.is_sea(x):
			for k in eng.sea_reach(x, p):
				for y in eng.nbr_keys(k):
					if eng.hexes.has(y) and not eng.revealed(y):
						return true
			return false
	return false


## Espansione: trasforma la fanteria del reclutamento in un Leader, Cavalleria o Elefanti se possibile.
## Si sceglie l'unità che usa la risorsa più abbondante (Elefante: Cibo, Cavalleria: Legno).
func _upgrade_army(eng, p: int, c: Dictionary, comp: Dictionary, sanit: bool, draft: bool) -> float:
	var bonus := 0.0
	if comp["infantry"] == 0:
		return 0.0
	var has_leader: bool = not eng.leader_unit(p).is_empty()
	if not has_leader and eng.can_recruit_type(p, c, "leader") and comp["infantry"] >= 1:
		var c2: Dictionary = comp.duplicate()
		c2["infantry"] -= 1
		c2["leader"] = 1
		if (not draft or c2["infantry"] > 0) and eng.valid_recruit(p, c, c2, sanit, draft) == "":
			comp.merge(c2, true)
			bonus += 1.5
	for i in 4:
		if comp.get("infantry", 0) <= (1 if draft else 0):
			break
		var order := ["elephant", "cavalry"] if eng.res(p, "food") + eng.res(p, "gold") >= mini(3, eng.res(p, "wood")) else ["cavalry", "elephant"]
		var done := false
		for t in order:
			if not eng.can_recruit_type(p, c, t) or eng.supply_left(p, t) <= comp.get(t, 0):
				continue
			var c3: Dictionary = comp.duplicate()
			c3["infantry"] -= 1
			c3[t] = c3.get(t, 0) + 1
			if eng.valid_recruit(p, c, c3, sanit, draft) == "":
				comp.merge(c3, true)
				bonus += 0.9
				done = true
				break
		if not done:
			break
	return bonus


func _happy_plan(eng, p: int) -> Array:
	var steps := {}
	var cost := 0
	var have: int = eng.res(p, "mood")
	var cs: Array = eng.cities_of(p)
	# meraviglia in vista: rendi Felice la città più economica che può ospitarla
	var wt0 := _wonder_target(eng, p)
	if wt0 != "" and not cs.any(func(c): return c["mood"] == 2 and eng.city_size(c) + 1 <= cs.size()):
		var bestc := {}
		var bcost := 99
		for c in cs:
			if eng.city_size(c) + 1 <= cs.size() and c["mood"] < 2:
				var cc: int = eng.city_size(c) * (2 - c["mood"])
				if cc < bcost:
					bcost = cc
					bestc = c
		if not bestc.is_empty() and eng.can_pay_mood(p, bcost):
			var need_r: Dictionary = D.WONDERS[wt0]["cost"]
			var missing := 0
			for r in ["ore", "wood", "food"]:
				missing += maxi(0, need_r[r] - eng.res(p, r))
			var v0 := 9.0 if missing <= 4 else (7.0 if _wonder_focus(eng, p) else 5.0)
			return [v0, {"t": "happy", "steps": {bestc["id"]: 2 - bestc["mood"]}}]
	cs.sort_custom(func(a, b): return eng.city_size(a) > eng.city_size(b))
	have -= _wonder_mood_reserve(eng, p)
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
	if wt != "" and not cs.any(func(c): return c["mood"] == 2) and eng.res(p, "culture") >= 3:
		var ok_c := false
		for c in cs:
			if steps.has(c["id"]) and c["mood"] == 1 and eng.city_size(c) + 1 <= cs.size():
				ok_c = true
		if ok_c:
			v += 7.0
	return [v, {"t": "happy", "steps": steps}]


func _influence_plan(eng, p: int, reserve := 0) -> Array:
	var best := []
	var saving := _wonder_target(eng, p) != ""
	for o in eng.influence_options(p):
		var need: int = o["need"]
		if saving and need > 0:
			continue
		if need > 0 and need + reserve > eng.res(p, "culture"):
			continue
		var v := 3.2 - need * 1.0
		var b0: String = o["b"][0]
		if b0 == "unit":
			v += 0.5
		elif b0 == "druid":
			v += 0.8
		elif eng.cities[o["to"]]["o"] == p:
			v += 1.0
		if eng.has_adv(p, "Conversion"):
			v += 1.0
		if v > 1.5 and (best.is_empty() or v > best[0]):
			best = [v, o["from"], o["to"], o["b"][0]]
	return best


func _card_value(eng, p: int, id: String) -> float:
	var k: String = eng.card_kind(id)
	var v := _card_value0(eng, p, id, k)
	# le carte che costano Cultura rallentano la Meraviglia
	if v > 0.0 and int(D.ACTION_TOPS.get(k, {}).get("cost", 0)) > 0 and _wonder_focus(eng, p) and eng.res(p, "culture") <= 5:
		v -= 3.0
	return v


func _card_value0(eng, p: int, id: String, k: String) -> float:
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
	if w.begins_with("x_"):
		var xv := _exp_special_value(eng, p, w)
		return [xv, {"t": "free", "what": w}] if xv > 0.0 else []
	match w:
		"absolute":
			if eng.res(p, "mood") >= 4 and eng.T["actions"] <= 1:
				return [5.5, {"t": "free", "what": "absolute"}]
		"drama":
			var wtd := _wonder_target(eng, p)
			if wtd != "" and eng.res(p, "culture") >= 6 and eng.res(p, "mood") < 3:
				return [2.0, {"t": "free", "what": "drama", "dir": "c2m"}]
			if eng.res(p, "mood") >= 4 or (wtd != "" and eng.res(p, "mood") >= 2 and eng.res(p, "culture") < 5):
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
			if _saving_culture(eng, p) and eng.res(p, "culture") < 7:
				return []
			var inf := _influence_plan(eng, p, 1 if eng.res(p, "culture") >= 1 else 0)
			if not inf.is_empty() and inf[0] > 2.0:
				return [inf[0] + 1.0, {"t": "free", "what": "arts", "from": inf[1], "to": inf[2], "b": inf[3]}]
		"library":
			for a in ["Storage", "Husbandry", "Roads", "Draft", "Sanitation", "Public Education"]:
				if not eng.players[p]["adv"].has(a):
					return [1.0, {"t": "free", "what": "library", "a": a}]
	return []


## Valore delle azioni speciali dell'espansione (0 = non conviene).
func _exp_special_value(eng, p: int, w: String) -> float:
	var wt := _wonder_target(eng, p)
	var lc: Dictionary = eng.leader_city(p)
	match w:
		"x_sacrifice":
			return 3.0 if wt != "" and eng.res(p, "culture") < 5 else 0.0
		"x_hegemony":
			var bv := -9.0
			for k in eng._hegemony_spots(p):
				bv = maxf(bv, spot_value(eng, p, k))
			return 7.0 + bv * 0.3 if bv >= 3.0 else 0.0
		"x_calendar":
			return 0.5
		"x_bands":
			return 3.0 if _barb_threat(eng, p) > 0 and eng.units_of(p, "settler").size() >= 2 else 0.0
		"x_aqueducts":
			return 6.0
		"x_l41":
			return 3.0 + (2.0 if lc.get("mood", 1) == 0 else 0.0)
		"x_l40":
			return 4.0
		"x_ladv":
			return 7.5
		"x_l44a":
			return 5.0
		"x_l43":
			return 2.0 + eng.cities_of(p).size() * 0.8
		"x_l35":
			return 6.0 if wt == "" or eng.res(p, "culture") > 7 else 0.0
		"x_l34":
			return 3.0
		"x_lwonder":
			return 16.0
		"x_l30":
			return 4.0
		"x_l27":
			return 5.0
		"x_l09":
			var lu: Dictionary = eng.leader_unit(p)
			return 9.0 if spot_value(eng, p, lu["h"]) >= 3.0 else 0.0
		"x_l01":
			return 3.0
		"x_l02":
			return 6.0
		"x_l04":
			return 3.5 if wt != "" else 1.0
		"x_l16":
			return 1.5 if not lc.is_empty() and _city_threat(eng, p, lc) > 0 else 0.0
	return 0.0


# ------------------------------------------------------------------ movimento

func _move(eng, p: int, req: Dictionary) -> Dictionary:
	var mv := _best_group_move(eng, p, eng.T.get("mv_this", {}))
	if OS.get_environment("COC_AIDBG") != "" and not mv.is_empty():
		var u0: Dictionary = eng.units[mv[1]["units"][0]]
		print("AIMOVE p%d %s da %s a %s v%.1f" % [p, u0["t"], u0["h"], mv[1]["to"], mv[0]])
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
		elif eng.is_army(u0):
			var r2 := _army_move(eng, p, ids)
			if not r2.is_empty() and (best.is_empty() or r2[0] > best[0]):
				best = r2
		elif u0["t"] == "ship":
			var r3 := _ship_move(eng, p, ids)
			if not r3.is_empty() and (best.is_empty() or r3[0] > best[0]):
				best = r3
	return best


## Miglior posto dove fondare raggiungibile via terra entro 5 passi: [casella, punteggio] (punteggio già
## scontato della distanza). Le caselle inesplorate di confine valgono come una scommessa media.
func _settler_target(eng, p: int, from: String) -> Array:
	var best := ["", -99.0]
	var seen := {from: 0}
	var q := [from]
	while not q.is_empty():
		var x: String = q.pop_front()
		var d: int = seen[x]
		var sc := spot_value(eng, p, x) - 0.55 * d
		if sc > best[1]:
			best = [x, sc]
		if d >= 5:
			continue
		for y in eng.neighbors(x):
			if seen.has(y):
				continue
			if not eng.revealed(y):
				seen[y] = d + 1
				var se := 2.6 - 0.55 * (d + 1) if eng.age <= 3 else 1.0
				if se > best[1]:
					best = [y, se]
				continue
			if not eng.is_land(y) or eng.has_enemy(y, p):
				continue
			seen[y] = d + 1
			q.append(y)
	return best


func _settler_move(eng, p: int, ids: Array) -> Array:
	var u: Dictionary = eng.units[ids[0]]
	if u["on"] != -1:
		# a bordo: sbarca dove si può fondare bene
		var tgd: Dictionary = eng.move_targets(p, ids)
		var bd := []
		for k in tgd:
			if tgd[k]["kind"] != "disembark" or tgd[k].get("battle", false):
				continue
			var sv0 := spot_value(eng, p, k)
			if sv0 >= 1.5 and (bd.is_empty() or sv0 > bd[0]):
				bd = [sv0, {"units": ids, "to": k, "roads": false}]
		if not bd.is_empty():
			bd[0] = 7.0
		return bd
	var here := spot_value(eng, p, u["h"])
	var tgt := _settler_target(eng, p, u["h"])
	if tgt[1] < 2.0 and here < 1.5:
		# niente di buono via terra: sali su una nave vicina se oltremare c'è un posto migliore
		var tge: Dictionary = eng.move_targets(p, ids)
		for k in tge:
			if tge[k]["kind"] == "embark":
				var sp := _sea_spot(eng, p, k)
				if not sp.is_empty() and sp[2] > tgt[1] + 0.5:
					return [4.5, {"units": ids, "to": k, "roads": false}]
	if tgt[0] == "" or tgt[0] == u["h"] or tgt[1] <= here + 0.3:
		return []
	var tg: Dictionary = eng.move_targets(p, ids)
	var best := []
	for k in tg:
		var info: Dictionary = tg[k]
		if info.get("battle", false) or not info["kind"] in ["land", "explore"]:
			continue
		if info.get("roads", false):
			continue
		var dd: int = eng.hdist(k, tgt[0])
		var v := 6.0 - dd * 0.8 + _jitter() * 0.2
		if best.is_empty() or v > best[0]:
			best = [v, {"units": ids, "to": k, "roads": false}]
	if best.is_empty() or eng.hdist(best[1]["to"], tgt[0]) >= eng.hdist(u["h"], tgt[0]):
		return []
	best[0] = 3.5 + clampf(tgt[1] - here, 0.0, 2.5)
	return best


func _army_move(eng, p: int, ids: Array) -> Array:
	if not eng.has_adv(p, "Tactics"):
		return []
	var u: Dictionary = eng.units[ids[0]]
	var here_city: Dictionary = eng.city_at(u["h"])
	var threat: int = _city_threat(eng, p, here_city) if not here_city.is_empty() and here_city["o"] == p else 0
	# il Conquistatore lascia guarnigioni più leggere (la Fortezza aiuta), il Difensore più pesanti
	if style == "aggressive" and threat > 0:
		threat = maxi(1, threat - (2 if here_city["b"].has("fortress") else 1))
	elif style == "defensive" and threat > 0:
		threat += 1
	var guarding: bool = threat > 0
	var wt := _war_target(eng, p)
	# in una propria città minacciata resta una guarnigione: si muove solo il resto
	if guarding and ids.size() > threat:
		var keep := []
		var go := []
		var sorted := ids.duplicate()
		sorted.sort_custom(func(x, y): return (1 if eng.units[int(x)]["t"] == "infantry" else 0) > (1 if eng.units[int(y)]["t"] == "infantry" else 0))
		for id in sorted:
			if keep.size() < threat:
				keep.append(id)
			else:
				go.append(id)
		ids = go
		guarding = false
	var tg: Dictionary = eng.move_targets(p, ids)
	var best := []
	var units: Array = ids.map(func(i): return eng.units[int(i)])
	var mine := ids.size()
	var my_pow := _power(units)
	var dm: Dictionary = wt.get("dm", {})
	var d_now: int = dm.get(u["h"], 99)
	for k in tg:
		var info: Dictionary = tg[k]
		var v := 0.0
		if info.get("battle", false):
			var target: int = info.get("target", -1)
			var c: Dictionary = eng.city_at(k)
			var dp := _def_power(eng, p, k)
			var defs: int = eng.enemy_units_at(k, p).filter(func(x): return eng.is_army(x)).size()
			var undefended: bool = defs == 0 and (c.is_empty() or not c["b"].has("fortress"))
			if target == -1:
				if my_pow >= dp * 1.3 + 0.2 or undefended:
					v = 6.0 + (4.0 if not c.is_empty() else 0.0)
			elif target == -2:
				if my_pow >= dp * 1.3 + 0.2:
					v = 5.0
			else:
				var ratio: float = 2.0 if level == 0 else float(sv("ratio")) - (0.15 if level >= 2 else 0.0)
				if undefended and not c.is_empty():
					v = 10.0 + eng.city_size(c) * 1.5
				elif my_pow >= dp * ratio + 0.3:
					v = 8.0 + (eng.city_size(c) * 1.5 if not c.is_empty() else 1.0)
				if level == 0 and eng.age < 4:
					v = 0.0
			if guarding and mine <= threat:
				v -= 4.0
		elif info["kind"] == "explore":
			v = 2.2 if eng.age <= 2 else 0.5
			# scoprire le caselle attorno alle proprie città allarga la raccolta
			for c3 in eng.cities_of(p):
				if eng.hdist(c3["h"], k) <= 2:
					v = maxf(v, 4.5)
			if not wt.is_empty() and not guarding and dm.get(k, 99) < d_now and my_pow >= float(wt["need"]):
				v = maxf(v, 3.0)
		elif info["kind"] in ["land", "disembark"]:
			# campagna: gli eserciti si radunano nella città più vicina al bersaglio, poi marciano
			if not wt.is_empty() and not guarding:
				var d_new: int = dm.get(k, 99)
				var rally: String = wt.get("rally", "")
				var rm: Dictionary = wt.get("rm", {})
				var join := _power(eng.armies_at(k, p))
				if rally == "" or u["h"] == rally or d_now <= dm.get(rally, 99):
					if d_new < d_now and d_now <= 9:
						if my_pow + join >= float(wt["need"]):
							v = maxf(v, 5.0 + (0.4 if join > 0.0 else 0.0))
						elif d_new >= 2 and my_pow + join >= float(wt["need"]) * float(sv("march")):
							v = maxf(v, 3.2)
				elif rm.get(k, 99) < rm.get(u["h"], 99):
					v = maxf(v, 3.4 + (0.4 if k == rally else 0.0))
			# avvicinarsi a una città barbara debole
			for b in eng.cities_of(-1):
				var d0: int = eng.hdist(u["h"], b["h"])
				var d1: int = eng.hdist(k, b["h"])
				var bdefs: int = eng.armies_at(b["h"], -1).size()
				if d1 < d0 and d0 <= 3 and mine >= bdefs + 1 and not guarding:
					v = maxf(v, 2.6)
			var cc: Dictionary = eng.city_at(k)
			if not cc.is_empty() and cc["o"] == p and _city_threat(eng, p, cc) > eng.armies_at(k, p).size():
				v = maxf(v, 3.8)
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
	if title.find("Tempio ti dà") >= 0 or title.find("Nazionalismo") >= 0 or title.find("ricevi") >= 0:
		if _saving_culture(eng, p) and eng.res(p, "culture") < 5:
			return 1
		if _wonder_mood_reserve(eng, p) > eng.res(p, "mood"):
			return 0
		return 1 if eng.res(p, "culture") < eng.res(p, "mood") + 1 else 0
	if title.begins_with("Miti"):
		return 0 if eng.res(p, "mood") >= 2 else 1
	if title.begins_with("Assedio") or title.begins_with("Armi d'Acciaio") or title.begins_with("Grande Arena") \
			or title.begins_with("L'Assedio") or title.begins_with("Istruzione Gratuita") or title.begins_with("Grande Faro"):
		return 0
	if title.find("lo tieni") >= 0:
		if title.begins_with("Grande Architetto"):
			return 0
		# i Grandi personaggi danno avanzamenti gratis: si tengono, salvo che la Meraviglia sia vicina
		if _wonder_focus(eng, p) and eng.res(p, "culture") <= 5:
			return 1
		return 0 if eng.res(p, "culture") >= 2 else 1
	if title.begins_with("Rivoluzione"):
		return 0 if eng.units_of(p, "infantry").size() >= 3 else 1
	if title.begins_with("Valuta"):
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
	if req.has("hexes") and title.begins_with("Pirati"):
		var hx2: Array = req["hexes"]
		var bi4 := 0
		var bd4 := -1
		for i in hx2.size():
			var d4 := 99
			for c in eng.cities_of(p):
				d4 = mini(d4, eng.hdist(hx2[i], c["h"]))
			if d4 > bd4:
				bd4 = d4
				bi4 = i
		return bi4
	if title.find("annullare un colpo") >= 0 or title.find("in ogni round") >= 0 or title.begins_with("Cavallo di Troia"):
		return 0
	if title.begins_with("Province"):
		return 0 if eng.res(p, "culture") >= 3 else 1
	if title.begins_with("Proconsole"):
		return 0
	if title.find("cosa perdi") >= 0:
		# perde ciò di cui ha di più
		var bi5 := 0
		var bv5 := -1
		var keys := {"Umore": "mood", "Cultura": "culture", "Cibo": "food", "Legno": "wood", "Minerale": "ore", "Idee": "idea", "Oro": "gold"}
		for i in opts.size():
			var o: String = str(opts[i]).substr(2)
			if keys.has(o) and eng.res(p, keys[o]) > bv5:
				bv5 = eng.res(p, keys[o])
				bi5 = i
		return bi5
	if title.begins_with("Boudicca") or title.begins_with("Ashoka") or title.begins_with("Tribù Alleate") or title.begins_with("Tribù Unniche"):
		return 0
	if title.begins_with("Regina Didone"):
		var bt2: Dictionary = eng.battle
		if bt2.is_empty():
			return 1
		return 0 if eng._fighters(bt2, "att").size() > eng._fighters(bt2, "def").size() else 1
	if title.begins_with("Immortali"):
		return mini(opts.size() - 1, 2 if eng.res(p, "culture") >= 4 else 1)
	if title.begins_with("Rotta commerciale"):
		if eng.res(p, "food") >= eng.food_limit(p) and opts.size() > 1:
			return 1
		return 0
	if title.begins_with("Bande Combattenti"):
		for i in opts.size():
			if str(opts[i]).ends_with("→ Fanteria"):
				return i
		return 0
	if title.find("Paghi") >= 0 or title.find("paghi") >= 0:
		return 1
	if title.find("Ispirazione") >= 0 or title.find("copi") >= 0:
		return rng.randi() % opts.size()
	return 0 if level > 0 else rng.randi() % opts.size()
