extends Node
## Stato della partita e funzioni di servizio (geometria esagonale, risorse, città, unità).
## Il motore vero e proprio è diviso in più file che si estendono a catena:
## engine_state → engine_actions → engine_combat → engine (eventi, status, partita).

signal changed
signal log_added(text: String)
signal decision_requested(req: Dictionary)
signal decision_provided(result)
signal game_ended(results: Array)
signal fx(kind: String, data: Dictionary)

const D = preload("res://scripts/data/coc_data.gd")
const SQ3 := 1.7320508

var rng := RandomNumberGenerator.new()
var ai_delay := 0.0
var headless := false
var ais := {}
var online = null
var abort := false
var opts := {}
var exp := false                # espansione Civiltà

# ---- stato
var n := 0
var players: Array = []
var hexes := {}            # "c,r" -> {c, r, reg, ter ("" se inesplorata), exhausted}
var regions: Array = []    # {hexes:[4 chiavi], tile, revealed, theta, slots:{T,L,R,B -> chiave}, start}
var cities := {}           # id -> {id, o, h, mood, b:{edificio: proprietario}, w:[meraviglie], port, act}
var units := {}            # id -> {id, o, t, h, on}
var next_id := 1
var tile_bag: Array = []
var decks := {"action": [], "objective": [], "event": [], "wonder": []}
var discards := {"action": [], "objective": [], "event": [], "wonder": []}
var table_wonders: Array = []   # meraviglie scoperte sul tavolo (nessuna nel gioco base)
var wonder_builder := {}        # meraviglia -> chi l'ha costruita
var age := 1
var round_no := 1
var first := 0
var cur := -1                   # giocatore di turno
var T := {}                     # stato del turno in corso
var plague_by := -1             # chi ha pescato la Peste (finché non pesca un altro evento)
var assassinated := {}          # giocatore -> azioni in meno nel prossimo turno
var negotiation := {}           # "a,b" -> scadenza (turni)
var wonders_this_age := {}      # giocatore -> numero di meraviglie costruite in questa era
var game_over := false
var results: Array = []
var log_lines: Array = []
var turn_count := 0
var battle := {}                # battaglia in corso (per la UI)
var last_dice := {}
# ---- espansione Civiltà
var eclipse := false            # E41: la prossima battaglia fra giocatori dura un solo round
var trojan := false             # E42: il Cavallo di Troia è sul tavolo
var diplomat := {}              # E57: {"a": possessore, "b": altro giocatore}
var oracle := {}                # E58: giocatore -> obiettivo da pescare alla prossima pesca


# ------------------------------------------------------------------ geometria

static func hk(c: int, r: int) -> String:
	return "%d,%d" % [c, r]


static func hc(k: String) -> Vector2i:
	var p := k.split(",")
	return Vector2i(int(p[0]), int(p[1]))


static func nbr_keys(k: String) -> Array:
	var v := hc(k)
	var c := v.x
	var r := v.y
	var d: Array
	if c % 2 == 0:
		d = [[0, -1], [0, 1], [-1, -1], [1, -1], [-1, 0], [1, 0]]
	else:
		d = [[0, -1], [0, 1], [-1, 0], [1, 0], [-1, 1], [1, 1]]
	var out := []
	for x in d:
		out.append(hk(c + x[0], r + x[1]))
	return out


## Posizione nel piano (x a destra, y in basso) con raggio dell'esagono = 1.
static func hpos(k: String) -> Vector2:
	var v := hc(k)
	return Vector2(1.5 * v.x, SQ3 * (v.y + (0.5 if v.x % 2 != 0 else 0.0)))


static func cube(k: String) -> Vector3i:
	var v := hc(k)
	var x := v.x
	var z := v.y - (v.x - (v.x & 1)) / 2
	return Vector3i(x, -x - z, z)


static func hdist(a: String, b: String) -> int:
	var p := cube(a)
	var q := cube(b)
	return maxi(maxi(absi(p.x - q.x), absi(p.y - q.y)), absi(p.z - q.z))


func neighbors(k: String) -> Array:
	var out := []
	for x in nbr_keys(k):
		if hexes.has(x):
			out.append(x)
	return out


func ter(k: String) -> String:
	return hexes[k]["ter"] if hexes.has(k) else ""


func revealed(k: String) -> bool:
	return hexes.has(k) and hexes[k]["ter"] != ""


func is_land(k: String) -> bool:
	var t := ter(k)
	return t != "" and t != "sea"


func is_sea(k: String) -> bool:
	return ter(k) == "sea"


## Distanza contando le caselle senza attraversare regioni inesplorate (BFS).
func dist_revealed(a: String, b: String, maxd := 99) -> int:
	if a == b:
		return 0
	var seen := {a: 0}
	var q := [a]
	while not q.is_empty():
		var x: String = q.pop_front()
		var d: int = seen[x]
		if d >= maxd:
			continue
		for y in neighbors(x):
			if seen.has(y) or not revealed(y):
				continue
			if y == b:
				return d + 1
			seen[y] = d + 1
			q.append(y)
	return 999


## Tutte le caselle esplorate entro maxd (attraversando qualsiasi casella esplorata).
func within(a: String, maxd: int, land_only := false) -> Dictionary:
	var seen := {a: 0}
	var q := [a]
	while not q.is_empty():
		var x: String = q.pop_front()
		var d: int = seen[x]
		if d >= maxd:
			continue
		for y in neighbors(x):
			if seen.has(y) or not revealed(y):
				continue
			if land_only and not is_land(y):
				continue
			seen[y] = d + 1
			q.append(y)
	return seen


# ------------------------------------------------------------------ giocatori e risorse

func pname(p: int) -> String:
	if p == -1:
		return "i Barbari"
	if p == -2:
		return "i Pirati"
	if p < 0 or p >= n:
		return "?"
	return players[p]["name"]


func log_msg(t: String) -> void:
	if OS.get_environment("COC_DEBUG") != "":
		print(t)
	log_lines.append(t)
	log_added.emit(t)


const MAN_GOD := {"Nationalism": "Dogma", "Totalitarianism": "Devotion", "Absolute Power": "Conversion", "Forced Labor": "Fanaticism"}


func has_adv(p: int, a: String) -> bool:
	if p < 0:
		return false
	if players[p]["adv"].has(a):
		return true
	# Uomo Dio (Egitto): ogni avanzamento di Teocrazia dà anche il potere di quello di Autocrazia alla sua sinistra
	if exp and MAN_GOD.has(a) and players[p]["adv"].has("Man God") and players[p]["adv"].has(MAN_GOD[a]):
		return true
	# Grande Biblioteca: un avanzamento dichiarato per il turno
	if cur == p and T.get("library", "") == a:
		return true
	return false


func res(p: int, r: String) -> int:
	if r == "mood":
		return players[p]["mood"]
	if r == "culture":
		return players[p]["culture"]
	return players[p]["res"][r]


func food_limit(p: int) -> int:
	return 7 if has_adv(p, "Storage") else 2


func res_limit(p: int, r: String) -> int:
	if r == "food":
		return food_limit(p)
	if r == "idea" and has_adv(p, "Dogma") and not civ_adv(p, "Ziggurats"):
		return 2
	return 7


func gain(p: int, r: String, amt: int) -> int:
	if p < 0 or amt <= 0:
		return 0
	if r == "mood":
		players[p]["mood"] += amt
		return amt
	if r == "culture":
		players[p]["culture"] += amt
		return amt
	var before: int = players[p]["res"][r]
	players[p]["res"][r] = mini(res_limit(p, r), before + amt)
	return players[p]["res"][r] - before


func lose(p: int, r: String, amt: int) -> int:
	if p < 0:
		return 0
	var have := res(p, r)
	var x := mini(have, amt)
	if r == "mood":
		players[p]["mood"] -= x
	elif r == "culture":
		players[p]["culture"] -= x
	else:
		players[p]["res"][r] -= x
	return x


func arena(p: int) -> bool:
	return owns_wonder(p, "great_arena")


## Paga un costo {risorsa: quantità}. L'Oro sostituisce le risorse (non Umore/Cultura).
## subst: risorse che possono sostituire il Cibo (Idee per gli avanzamenti).
## Restituisce il pagamento effettivo, oppure {} se non basta (e non paga nulla).
func plan_payment(p: int, cost: Dictionary, food_subst := [], gold_ok := true) -> Dictionary:
	var have := {}
	for r in D.RES:
		have[r] = res(p, r)
	have["mood"] = res(p, "mood")
	have["culture"] = res(p, "culture")
	var pay := {}
	var short := {}
	for r in cost:
		var need: int = cost[r]
		if need <= 0:
			continue
		var take := mini(need, have.get(r, 0))
		if take > 0:
			pay[r] = pay.get(r, 0) + take
			have[r] -= take
		if take < need:
			short[r] = need - take
	# Grande Arena: Umore e Cultura intercambiabili
	for r in short.keys():
		if r in ["mood", "culture"] and arena(p):
			var other := "culture" if r == "mood" else "mood"
			var t2 := mini(short[r], have[other])
			if t2 > 0:
				pay[other] = pay.get(other, 0) + t2
				have[other] -= t2
				short[r] -= t2
				if short[r] == 0:
					short.erase(r)
	if short.has("food"):
		for s in food_subst:
			var t3 := mini(short["food"], have[s])
			if t3 > 0:
				pay[s] = pay.get(s, 0) + t3
				have[s] -= t3
				short["food"] -= t3
			if short["food"] == 0:
				short.erase("food")
				break
	if gold_ok:
		for r in short.keys():
			if r in ["mood", "culture"]:
				continue
			var t4 := mini(short[r], have["gold"])
			if t4 > 0:
				pay["gold"] = pay.get("gold", 0) + t4
				have["gold"] -= t4
				short[r] -= t4
			if short[r] == 0:
				short.erase(r)
	if not short.is_empty():
		return {}
	if pay.is_empty():
		pay["_"] = 0
	return pay


func can_pay(p: int, cost: Dictionary, food_subst := [], gold_ok := true) -> bool:
	return not plan_payment(p, cost, food_subst, gold_ok).is_empty()


func pay(p: int, cost: Dictionary, food_subst := [], gold_ok := true) -> Dictionary:
	var pl := plan_payment(p, cost, food_subst, gold_ok)
	for r in pl:
		if r != "_":
			lose(p, r, pl[r])
	return pl


static func cost_text(c: Dictionary) -> String:
	var parts := []
	for r in ["food", "wood", "ore", "idea", "gold", "mood", "culture"]:
		if c.get(r, 0) > 0:
			parts.append("%d %s" % [c[r], D.RES_NAME[r]])
	return ", ".join(parts) if not parts.is_empty() else "niente"


# ------------------------------------------------------------------ città e unità

func city_at(k: String) -> Dictionary:
	for id in cities:
		if cities[id]["h"] == k:
			return cities[id]
	return {}


func city_size(c: Dictionary) -> int:
	return 1 + c["b"].size() + c["w"].size()


func cities_of(p: int) -> Array:
	var out := []
	for id in cities:
		if cities[id]["o"] == p:
			out.append(cities[id])
	return out


func units_at(k: String) -> Array:
	var out := []
	for id in units:
		if units[id]["h"] == k:
			out.append(units[id])
	return out


func units_of(p: int, t := "") -> Array:
	var out := []
	for id in units:
		var u: Dictionary = units[id]
		if u["o"] == p and (t == "" or u["t"] == t):
			out.append(u)
	return out


static func is_army(u: Dictionary) -> bool:
	return u["t"] in D.ARMY


## Edifici e unità in gioco (con l'espansione anche Mercato, Obelisco, Osservatorio, Cavalleria, Elefante, Leader).
func bld_list() -> Array:
	return D.BUILDINGS + D.EXP_BUILDINGS if exp else D.BUILDINGS


func unit_list() -> Array:
	return D.UNITS + D.EXP_UNITS if exp else D.UNITS


func armies_at(k: String, p := -99) -> Array:
	var out := []
	for u in units_at(k):
		if is_army(u) and u["on"] == -1 and (p == -99 or u["o"] == p):
			out.append(u)
	return out


func land_units_at(k: String, p: int) -> Array:
	var out := []
	for u in units_at(k):
		if u["o"] == p and u["t"] != "ship" and u["on"] == -1:
			out.append(u)
	return out


func ships_at(k: String, p := -99) -> Array:
	var out := []
	for u in units_at(k):
		if u["t"] == "ship" and (p == -99 or u["o"] == p):
			out.append(u)
	return out


func carried(ship_id: int) -> Array:
	var out := []
	for id in units:
		if units[id]["on"] == ship_id:
			out.append(units[id])
	return out


func enemy_units_at(k: String, p: int) -> Array:
	var out := []
	for u in units_at(k):
		if u["o"] != p:
			out.append(u)
	return out


func has_enemy(k: String, p: int) -> bool:
	if not enemy_units_at(k, p).is_empty():
		return true
	var c := city_at(k)
	return not c.is_empty() and c["o"] != p


func supply_left(p: int, piece: String) -> int:
	var lim: int = D.LIMITS[piece] if p >= 0 else D.BARB_LIMIT.get(piece, 99)
	var used := 0
	if piece == "settlement":
		used = cities_of(p).size()
	elif piece in D.BUILDINGS or piece in D.EXP_BUILDINGS:
		for id in cities:
			if cities[id]["b"].get(piece, -9) == p:
				used += 1
	else:
		used = units_of(p, piece).size()
	return lim - used


func new_unit(p: int, t: String, k: String, on := -1) -> Dictionary:
	var u := {"id": next_id, "o": p, "t": t, "h": k, "on": on}
	units[next_id] = u
	next_id += 1
	return u


func remove_unit(u: Dictionary, killer := -9) -> void:
	if u["t"] == "ship":
		for c in carried(u["id"]):
			if c["t"] == "leader":
				leader_gone(c["o"], killer)
			units.erase(c["id"])
	if u["t"] == "leader":
		leader_gone(u["o"], killer)
	units.erase(u["id"])


## Il leader è morto o è stato sostituito: la carta va a chi l'ha ucciso in battaglia (2 PV) o nella scatola.
func leader_gone(p: int, killer := -9) -> void:
	if p < 0 or not exp:
		return
	var code: String = players[p].get("leader", "")
	if code == "":
		return
	players[p]["leader"] = ""
	if killer >= 0 and killer != p:
		players[killer]["killed_leaders"].append(code)
		log_msg("%s uccide %s, leader di %s (+2 PV)." % [pname(killer), CivData.LEADERS[code][0], pname(p)])
	else:
		log_msg("%s, leader di %s, lascia la scena." % [CivData.LEADERS[code][0], pname(p)])
	if civ_adv(p, "Embalming"):
		gain(p, "culture", 1)
	# la Cultura di Cleopatra se ne va con lei
	for id in cities:
		if cities[id]["o"] == p:
			cities[id].erase("cleo")



func new_city(p: int, k: String, mood := 1) -> Dictionary:
	var c := {"id": next_id, "o": p, "h": k, "mood": mood, "b": {}, "w": [], "port": "", "act": 0}
	cities[next_id] = c
	next_id += 1
	return c


func owns_wonder(p: int, w: String) -> bool:
	for c in cities_of(p):
		if w in c["w"]:
			return true
	return false


func wonder_city(w: String) -> Dictionary:
	for id in cities:
		if w in cities[id]["w"]:
			return cities[id]
	return {}


func adjacent_sea(k: String) -> Array:
	var out := []
	for x in neighbors(k):
		if is_sea(x):
			out.append(x)
	return out


func is_coastal(c: Dictionary) -> bool:
	return not adjacent_sea(c["h"]).is_empty()


func change_mood(c: Dictionary, steps: int) -> void:
	c["mood"] = clampi(c["mood"] + steps, 0, 2)


## Città dove il giocatore ha almeno un edificio sotto la sua influenza (non sue).
func influenced_count(p: int) -> Dictionary:
	var cs := 0
	var bs := 0
	for id in cities:
		var c: Dictionary = cities[id]
		if c["o"] == p:
			continue
		var any := false
		for b in c["b"]:
			if c["b"][b] == p:
				bs += 1
				any = true
		if any:
			cs += 1
	return {"cities": cs, "buildings": bs}


func gov_of(p: int) -> String:
	for g in D.GOVERNMENTS:
		for a in D.ADV[g]:
			if players[p]["adv"].has(a[0]):
				return g
	return ""


func adv_count(p: int) -> int:
	return players[p]["adv"].size()


## Punti vittoria (con il dettaglio).
func score(p: int) -> Dictionary:
	var pieces := 0
	for id in cities:
		var c: Dictionary = cities[id]
		if c["o"] == p:
			pieces += 1
		for b in c["b"]:
			if c["b"][b] == p:
				pieces += 1
	var adv: float = players[p]["adv"].size() * 0.5
	if exp and civ_adv(p, "City Independence"):
		# Fenicia: gli avanzamenti di governo non valgono punti (i porti valgono 1½ PV, sotto)
		for g in D.GOVERNMENTS:
			for a in D.ADV[g]:
				if players[p]["adv"].has(a[0]):
					adv -= 0.5
	var objs: int = players[p]["done"].size() * 2
	var won := 0.0
	for w in D.WONDERS:
		var wc := wonder_city(w)
		var builder: int = wonder_builder.get(w, -9)
		var val := 5.0 if w == "great_pyramids" else 4.0
		if w == "great_pyramids":
			if builder == p:
				won += val
			continue
		if wc.is_empty():
			continue
		var owner: int = wc["o"]
		if owner == p and builder == p:
			won += val
		elif owner == p:
			won += val / 2.0
		elif builder == p:
			won += val / 2.0
	var ev: float = players[p]["vp_extra"]
	if exp:
		ev += players[p].get("killed_leaders", []).size() * 2.0
		ev += players[p].get("captives", 0) * 0.5
		ev += float(players[p].get("anarchy", 0))
		ev += float(players[p].get("erik", []).size())
		for id in cities:
			if cities[id].get("druid", -9) == p:
				ev += 1.0
		if civ_adv(p, "City Independence"):
			for id in cities:
				if cities[id]["b"].get("port", -9) == p:
					ev += 0.5
		# Canuto il Grande: l'insediamento della sua città vale ½ PV per casella di distanza dalla prima città
		var lu := leader_unit(p)
		if not lu.is_empty() and players[p].get("leader", "") == "l43":
			var lc := city_at(lu["h"])
			if not lc.is_empty() and lc["o"] == p:
				ev += 0.5 * hdist(lc["h"], players[p]["home"])
	return {"pieces": pieces, "adv": adv, "obj": objs, "wonders": won, "events": ev,
		"total": pieces + adv + objs + won + ev}


# ------------------------------------------------------------------ espansione: civiltà e leader

func civ_adv(p: int, a: String) -> bool:
	return exp and p >= 0 and p < n and players[p]["adv"].has(a)


## Il leader attivo di p è quello indicato (codice "l41"…) ed è sul tabellone.
func leader_is(p: int, code: String) -> bool:
	return exp and p >= 0 and players[p].get("leader", "") == code and not leader_unit(p).is_empty()


func leader_unit(p: int) -> Dictionary:
	for id in units:
		var u: Dictionary = units[id]
		if u["o"] == p and u["t"] == "leader":
			return u
	return {}


## Il leader si trova in questa casella.
func leader_at(p: int, k: String) -> bool:
	var lu := leader_unit(p)
	return not lu.is_empty() and lu["h"] == k


## Pirati: bloccano la raccolta e le rotte nel loro Mare e nei Mari adiacenti.
func pirate_blocked(k: String, p: int) -> bool:
	if not exp or civ_adv(p, "Pirate Allies"):
		return false
	for x in [k] + neighbors(k):
		if not is_sea(x):
			continue
		for u in ships_at(x, -2):
			return true
	return false


func pirates() -> Array:
	return units_of(-2, "ship")


# ------------------------------------------------------------------ leader: dove sono

## La città (tua) in cui si trova il tuo Leader, se non è a bordo di una nave.
func leader_city(p: int) -> Dictionary:
	var lu := leader_unit(p)
	if lu.is_empty() or lu["on"] != -1:
		return {}
	var c := city_at(lu["h"])
	if c.is_empty() or c["o"] != p:
		return {}
	return c


func lcode(p: int) -> String:
	if not exp or p < 0 or leader_unit(p).is_empty():
		return ""
	return players[p].get("leader", "")


## Limite di accatastamento: 4 unità d'armata, 5 con Serse.
func stack_limit(p: int, k: String) -> int:
	if lcode(p) == "l36" and leader_at(p, k):
		return 5
	return 4


# ------------------------------------------------------------------ mazzi

func shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func draw(kind: String, p := -1) -> String:
	# Grande Mausoleo: si può prendere dagli scarti (l'IA e gli umani: automaticamente se migliore no; teniamo il mazzo)
	if decks[kind].is_empty():
		if discards[kind].is_empty():
			return ""
		decks[kind] = discards[kind].duplicate()
		discards[kind].clear()
		shuffle(decks[kind])
		log_msg("Il mazzo %s viene rimescolato." % _deck_name(kind))
	return decks[kind].pop_back()


static func _deck_name(kind: String) -> String:
	return {"action": "delle carte Azione", "objective": "degli Obiettivi", "event": "degli Eventi", "wonder": "delle Meraviglie"}[kind]


func discard(kind: String, id: String, p := -1) -> void:
	if id == "":
		return
	if p >= 0 and owns_wonder(p, "great_mausoleum") and kind in ["action", "event"]:
		discards[kind].push_front(id)
	else:
		discards[kind].append(id)


func draw_action(p: int, k := 1) -> void:
	for i in k:
		var c := draw("action", p)
		if c != "":
			players[p]["hand"].append(c)


func draw_objective(p: int, k := 1) -> void:
	for i in k:
		var c := ""
		if oracle.has(p):
			c = oracle[p]
			oracle.erase(p)
		else:
			c = draw("objective", p)
		if c != "":
			players[p]["obj"].append(c)


func draw_wonder(p: int) -> void:
	var c := ""
	# Qin Shi Huang e Nebuchadnezzar II: devono prendere la loro Meraviglia, ovunque sia
	var want: String = {"l14": "great_wall", "l06": "great_gardens"}.get(lcode(p), "")
	if want != "" and not players[p]["won"].has(want) and wonder_city(want).is_empty():
		if decks["wonder"].has(want):
			decks["wonder"].erase(want)
			shuffle(decks["wonder"])
			c = want
		elif discards["wonder"].has(want):
			discards["wonder"].erase(want)
			c = want
		else:
			for q in n:
				if q != p and players[q]["won"].has(want):
					players[q]["won"].erase(want)
					c = want
					var rep_c := draw("wonder", q)
					if rep_c != "":
						players[q]["won"].append(rep_c)
					break
	if c != "":
		pass
	elif not table_wonders.is_empty():
		# E40: la Meraviglia scoperta sul tavolo
		c = table_wonders.pop_front()
	else:
		c = draw("wonder", p)
	if c != "":
		players[p]["won"].append(c)
		log_msg("%s pesca una carta Meraviglia." % pname(p))


# ------------------------------------------------------------------ decisioni

func any_local_human() -> bool:
	if online != null:
		return true
	for p in players:
		if not p["ai"]:
			return true
	return false


func ask(p: int, req: Dictionary):
	req["seat"] = p
	if abort:
		return ais[p].decide(self, p, req)
	if online != null:
		return await online.decide(self, p, req)
	if players[p]["ai"]:
		if ai_delay > 0.0 and not headless and is_inside_tree():
			await get_tree().create_timer(ai_delay).timeout
		return ais[p].decide(self, p, req)
	decision_requested.emit(req)
	var r = await decision_provided
	return r


func provide_decision(r) -> void:
	decision_provided.emit(r)


## Scelta fra opzioni testuali. hexes (facoltativo) associa una casella a ogni opzione.
func choose(p: int, title: String, options: Array, extra := {}) -> int:
	if options.size() <= 1 and not extra.get("force", false):
		return 0
	var req := {"type": "choice", "title": title, "options": options}
	req.merge(extra)
	var r = await ask(p, req)
	var i := int(r) if (r is int or r is float) else 0
	return clampi(i, 0, options.size() - 1)


## Scelta di una casella fra quelle possibili (si illuminano sulla mappa).
func choose_hex(p: int, title: String, keys: Array, labels := []) -> String:
	if keys.is_empty():
		return ""
	if keys.size() == 1:
		return keys[0]
	var opts2 := []
	for i in keys.size():
		opts2.append(labels[i] if i < labels.size() else _hex_label(keys[i]))
	var i := await choose(p, title, opts2, {"hexes": keys})
	return keys[i]


func _hex_label(k: String) -> String:
	var c := city_at(k)
	if not c.is_empty():
		return "Città di %s (%s)" % [pname(c["o"]), D.TER_NAME[ter(k)]]
	return "%s [%s]" % [D.TER_NAME[ter(k)], k]


func yes_no(p: int, title: String, yes := "Sì", no := "No") -> bool:
	return await choose(p, title, [yes, no], {"force": true}) == 0


func wait(sec: float) -> void:
	if headless or abort or not is_inside_tree():
		return
	if online != null and online.catchup:
		return
	if ai_delay <= 0.0 and not any_local_human():
		return
	await get_tree().create_timer(sec).timeout


# ---- metodi definiti nei file successivi della catena (qui solo segnaposto)
func resolve_event(_p: int) -> void:
	pass


func check_now(_p: int, _what: String, _data: Dictionary) -> void:
	pass


func sea_reach(_h: String, _p: int, _nav := false) -> Dictionary:
	return {}


func land_battle(_p: int, _att: Array, _h: String, _from: String, _from_ship: bool) -> Dictionary:
	return {}


func do_move_action(_p: int, _free := false, _max_groups := 3) -> void:
	pass


func naval_battle(_p: int, _ships: Array, _h: String, _from: String) -> Dictionary:
	return {}


func d6() -> int:
	# il dado a 12 facce ha i numeri da 1 a 6 due volte: per i tiri semplici basta il valore
	return rng.randi_range(1, 6)


## Tiro di un dado da combattimento: [valore, icona] (I fanteria, C cavalleria, E elefante, L leader).
func roll_die() -> Array:
	return D.DIE[rng.randi() % 12]
