class_name CocEngine
extends "res://scripts/core/engine_civ.gd"
## Motore delle regole di Clash of Cultures: Monumental Edition (gioco base).
## Ogni scelta passa da ask(): l'IA risponde subito, per le persone si emette decision_requested
## e si attende provide_decision(); online le scelte passano dal registro delle mosse.

# ------------------------------------------------------------------ partita

func run() -> void:
	log_msg("Comincia la partita: %d civiltà, 6 ere di 3 round." % n)
	log_msg("Primo giocatore: %s." % pname(first))
	changed.emit()
	var last_age := 6 if not opts.get("short", false) else 4
	age = 1
	while age <= last_age and not game_over:
		wonders_this_age.clear()
		for rnd in range(1, 4):
			round_no = rnd
			for i in n:
				var p := (first + i) % n
				await do_turn(p)
				if game_over:
					return
		await status_phase()
		var anyone_without := false
		for p in n:
			if cities_of(p).is_empty():
				anyone_without = true
		if anyone_without:
			log_msg("Un giocatore non ha più città: la partita finisce.")
			break
		age += 1
	await final_scoring()


func do_turn(p: int) -> void:
	cur = p
	turn_count += 1
	new_turn_state(p)
	T["actions"] = 3 - int(assassinated.get(p, 0))
	assassinated.erase(p)
	for key in negotiation.keys():
		if negotiation[key] <= turn_count:
			negotiation.erase(key)
	log_msg("— Turno di %s (era %d, round %d)" % [pname(p), age, round_no])
	fx.emit("turn", {"p": p})
	if T.get("lose_action", false):
		T["actions"] -= 1
	if players[p].get("lose_next", false):
		T["actions"] -= 1
		players[p]["lose_next"] = false
	# Attività bancaria (Persia): con almeno 1 Oro, +1 Oro o +1 Cultura
	if civ_adv(p, "Banking") and res(p, "gold") >= 1:
		var bi := await choose(p, "Attività bancaria: ricevi…", ["+1 Oro", "+1 Cultura"], {"force": true})
		gain(p, "gold" if bi == 0 else "culture", 1)
	# rotte commerciali a inizio turno
	if has_adv(p, "Trade Routes"):
		await _trade_income(p)
	changed.emit()
	var guard := 0
	while not game_over:
		guard += 1
		if guard > 200:
			break
		if cities_of(p).is_empty() and units_of(p).is_empty():
			break
		var m = await ask(p, {"type": "turn", "actions": T["actions"]})
		if not (m is Dictionary):
			break
		if m.get("t", "") == "end":
			break
		if OS.get_environment("COC_STATS") != "":
			print("ACT %s %d" % [m.get("t", "") + ("_" + str(m.get("what", m.get("id", ""))) if m.get("t", "") in ["free", "card"] else ""), age])
		var ok = await apply_move(p, m)
		if not ok:
			if players[p]["ai"] or online != null and p != online.seat:
				# l'IA ha proposto una mossa non valida: chiude il turno per sicurezza
				if T["actions"] <= 0:
					break
			if OS.get_environment("COC_DEBUG") != "":
				print("MOSSA NON VALIDA ", pname(p), " ", m, " azioni ", T["actions"])
			if not players[p]["ai"] or online != null:
				log_msg("(mossa non consentita)")
		T["acted"] = true
		await check_now(p, "any", {})
		changed.emit()
	cur = -1
	changed.emit()


func _trade_income(p: int) -> void:
	var tr := trade_routes(p)
	var k: int = tr["count"]
	if k <= 0:
		return
	if exp:
		await trade_bonus(p, tr)
		k = await trade_alt(p, k)
	var food := mini(k, maxi(0, food_limit(p) - res(p, "food")))
	var gold := 0
	if has_adv(p, "Currency"):
		gold = k - food
	var got_f := gain(p, "food", food)
	gain(p, "gold", gold)
	for q in tr.get("markets", []):
		gain(q, "gold", 1)
		log_msg("Mercato: %s riceve 1 Oro dalle rotte di %s." % [pname(q), pname(p)])
	log_msg("Rotte commerciali: %s riceve %d Cibo%s." % [pname(p), got_f, (" e %d Oro" % gold) if gold > 0 else ""])
	# Moneta: chi lo desidera può prendere Oro al posto del Cibo
	if has_adv(p, "Currency") and got_f > 0:
		var i := await choose(p, "Moneta: vuoi cambiare il Cibo delle rotte in Oro?", ["Tieni il Cibo", "Cambia %d Cibo in Oro" % got_f], {"force": true})
		if i == 1:
			lose(p, "food", got_f)
			gain(p, "gold", got_f)


# ------------------------------------------------------------------ mosse del turno

func main_ok(p: int) -> bool:
	return T["actions"] > 0


func apply_move(p: int, m: Dictionary) -> bool:
	var t: String = m.get("t", "")
	match t:
		"advance":
			if not main_ok(p) or not can_buy_adv(p, m.get("a", "")):
				return false
			# Pace e poesia (India): una volta per turno 1 Umore invece del Cibo
			var pp: bool = m.get("pp", false) and civ_adv(p, "Peace & Poetry") and not T.get("pp", false) and res(p, "mood") >= 1
			if not pp and not can_pay(p, {"food": adv_food_cost(p, m["a"])}, ["idea"]):
				return false
			spend_action(false)
			if pp:
				T["pp"] = true
				lose(p, "mood", 1)
				return await do_advance(p, m["a"], true)
			return await do_advance(p, m["a"])
		"found":
			if not main_ok(p):
				return false
			var u: int = int(m.get("u", -1))
			if not units.has(u):
				return false
			spend_action(false)
			if not await do_found(p, u):
				T["actions"] += 1
				return false
			return true
		"collect":
			if not main_ok(p):
				return false
			var bc := _ballcourt(p, m)
			var okc: bool = await do_collect(p, int(m.get("c", -1)), m.get("picks", []), m.get("card", ""), m.get("metal", false))
			_ballcourt_end(p, bc, okc)
			return okc
		"build":
			if not main_ok(p):
				return false
			return await do_build(p, int(m.get("c", -1)), m.get("b", ""))
		"recruit":
			if not main_ok(p):
				return false
			var bc2 := _ballcourt(p, m)
			T["shogun_req"] = m.get("shogun", false)
			var okr: bool = await do_recruit(p, int(m.get("c", -1)), m.get("comp", {}), m.get("sanit", false), m.get("draft", false))
			T.erase("shogun_req")
			_ballcourt_end(p, bc2, okr)
			return okr
		"wonder":
			if not main_ok(p):
				return false
			return await do_wonder(p, int(m.get("c", -1)), m.get("w", ""))
		"move":
			if not main_ok(p):
				return false
			await do_move_action(p)
			return true
		"happy":
			if not main_ok(p):
				return false
			return await do_happy(p, m.get("steps", {}))
		"influence":
			if not main_ok(p):
				return false
			return await do_influence(p, int(m.get("from", -1)), int(m.get("to", -1)), m.get("b", ""))
		"card":
			return await play_card(p, m)
		"free":
			return await free_action(p, m)
	return false


## Ballcourts (Maya): con «bc» la città conta 1 in più pagando 1 Umore (solo se l'azione riesce).
func _ballcourt(p: int, m: Dictionary) -> bool:
	if not m.get("bc", false) or not civ_adv(p, "Ballcourts") or res(p, "mood") < 1:
		return false
	T["bc_city"] = int(m.get("c", -1))
	return true


func _ballcourt_end(p: int, used: bool, ok: bool) -> void:
	T.erase("bc_city")
	if used and ok:
		lose(p, "mood", 1)


# ------------------------------------------------------------------ azioni gratuite e speciali

## Elenco delle azioni speciali disponibili ora (per l'interfaccia e l'IA).
func free_options(p: int) -> Array:
	var out := []
	var acts: int = T["actions"]
	if has_adv(p, "Voting") and res(p, "mood") >= 1:
		out.append("voting")
	if has_adv(p, "Economic Liberty") and res(p, "mood") >= 1 and T["collects"] == 0:
		out.append("econlib")
	if has_adv(p, "Arts") and not T["arts"] and (res(p, "culture") >= 1 or (civ_adv(p, "Hellenization") and res(p, "mood") >= 2)) and not T["infl_ok"]:
		out.append("arts")
	if has_adv(p, "Drama & Music") and not T["drama"] and (res(p, "mood") > 0 or res(p, "culture") > 0):
		out.append("drama")
	if has_adv(p, "Bartering") and not T["bartering"] and (players[p]["hand"].size() + players[p]["obj"].size()) > 0:
		out.append("bartering")
	if has_adv(p, "Absolute Power") and not T["absolute"] and res(p, "mood") >= 2:
		out.append("absolute")
	if has_adv(p, "Taxation") and not T["taxation"] and acts > 0 and res(p, "mood") >= 1:
		out.append("taxation")
	if has_adv(p, "Civil Liberties") and acts > 0:
		out.append("civil")
	if has_adv(p, "Circus & Sports") and acts > 0 and res(p, "culture") >= 1:
		out.append("circus")
	if has_adv(p, "Forced Labor") and not T["forced"] and res(p, "mood") >= 1:
		out.append("forced")
	if owns_wonder(p, "great_statue") and not T["statue"] and not players[p]["obj"].is_empty():
		out.append("statue")
	if owns_wonder(p, "great_library") and T["library"] == "":
		out.append("library")
	out += exp_specials(p)
	return out


func free_name(w: String) -> String:
	return FREE_NAME.get(w, XNAME.get(w, w))


const FREE_NAME := {"voting": "Voto: Aumenta la felicità (1 Umore)", "econlib": "Libertà economica: raccolta (1 Umore)",
	"arts": "Arti: Influenza la cultura (1 Cultura)", "drama": "Teatro e musica: Umore ↔ Cultura",
	"bartering": "Baratto: scarta una carta per 1 Oro o 1 Cultura", "absolute": "Potere assoluto: +1 azione (2 Umore)",
	"taxation": "Tassazione (azione, 1 Umore)", "civil": "Libertà civili: +3 Umore (azione)",
	"circus": "Circo e giochi (azione)", "forced": "Lavori forzati (1 Umore)",
	"statue": "Grande Statua: scarta un Obiettivo per +1 azione", "library": "Grande Biblioteca: usa un avanzamento"}


func free_action(p: int, m: Dictionary) -> bool:
	var w: String = m.get("what", "")
	if not w in free_options(p):
		return false
	if w.begins_with("x_"):
		return await exp_special(p, w, m)
	match w:
		"voting":
			var steps: Dictionary = m.get("steps", {})
			if happy_cost(p, steps) <= 0 or not can_pay_mood(p, happy_cost(p, steps) + 1):
				return false
			lose(p, "mood", 1)
			var ok_h: bool = await do_happy(p, steps, true)
			if not ok_h:
				gain(p, "mood", 1)
			return ok_h
		"econlib":
			var c: Dictionary = cities.get(int(m.get("c", -1)), {})
			if c.is_empty():
				return false
			if not can_activate(c) or not valid_collect(c, m.get("picks", [])):
				return false
			lose(p, "mood", 1)
			T["econlib"] = true
			var ok_c: bool = await do_collect(p, c["id"], m.get("picks", []), "", m.get("metal", false), true)
			if not ok_c:
				gain(p, "mood", 1)
				T["econlib"] = false
			return ok_c
		"arts":
			T["arts"] = true
			var arts_r := "culture" if res(p, "culture") >= 1 else "mood"
			var arts_k := 1 if arts_r == "culture" else 2
			lose(p, arts_r, arts_k)
			var ok_i: bool = await do_influence(p, int(m.get("from", -1)), int(m.get("to", -1)), m.get("b", ""), true)
			if not ok_i:
				gain(p, arts_r, arts_k)
				T["arts"] = false
			return ok_i
		"drama":
			T["drama"] = true
			if m.get("dir", "m2c") == "m2c" and res(p, "mood") > 0:
				lose(p, "mood", 1)
				gain(p, "culture", 1)
			elif res(p, "culture") > 0:
				lose(p, "culture", 1)
				gain(p, "mood", 1)
			log_msg("%s usa Teatro e musica." % pname(p))
			return true
		"bartering":
			var id: String = m.get("card", "")
			if players[p]["hand"].has(id):
				players[p]["hand"].erase(id)
				discard("action" if id.begins_with("a") else "event", id, p)
			elif players[p]["obj"].has(id):
				players[p]["obj"].erase(id)
				discard("objective", id, p)
			else:
				return false
			T["bartering"] = true
			gain(p, "gold" if m.get("get", "gold") == "gold" else "culture", 1)
			log_msg("%s scarta una carta con il Baratto." % pname(p))
			return true
		"absolute":
			T["absolute"] = true
			lose(p, "mood", 2)
			T["actions"] += 1
			log_msg("%s usa il Potere assoluto: un'azione in più." % pname(p))
			return true
		"taxation":
			var k := cities_of(p).size()
			var get: Dictionary = m.get("get", {})
			var tot := 0
			for r in get:
				if not r in ["food", "ore", "wood", "gold"] or (r == "gold" and not has_adv(p, "Currency")):
					return false
				tot += int(get[r])
			if tot != k:
				return false
			T["taxation"] = true
			spend_action(false)
			lose(p, "mood", 1)
			for r in get:
				gain(p, r, int(get[r]))
			log_msg("%s riscuote le tasse." % pname(p))
			return true
		"civil":
			spend_action(false)
			gain(p, "mood", 3)
			log_msg("%s: Libertà civili, +3 Umore." % pname(p))
			return true
		"circus":
			var c2: Dictionary = cities.get(int(m.get("c", -1)), {})
			var st := int(m.get("steps", 1))
			if c2.is_empty() or c2["o"] != p or st < 1 or st > 2 or c2["mood"] + st > 2 or res(p, "culture") < st:
				return false
			spend_action(false)
			lose(p, "culture", st)
			change_mood(c2, st)
			log_msg("%s organizza giochi nel circo." % pname(p))
			return true
		"forced":
			T["forced"] = true
			lose(p, "mood", 1)
			log_msg("%s impone i Lavori forzati." % pname(p))
			return true
		"statue":
			var oid: String = m.get("card", "")
			if not players[p]["obj"].has(oid):
				return false
			players[p]["obj"].erase(oid)
			discard("objective", oid, p)
			T["statue"] = true
			T["actions"] += 1
			return true
		"library":
			var a: String = m.get("a", "")
			var info := D.adv_info(a)
			if info.is_empty() or info["cat"] in D.GOVERNMENTS or players[p]["adv"].has(a):
				return false
			T["library"] = a
			log_msg("%s consulta la Grande Biblioteca: %s per questo turno." % [pname(p), info["it"]])
			return true
	return false


# ------------------------------------------------------------------ carte Azione

## Carte giocabili adesso (fuori dal combattimento): [{id, kind}].
func playable_cards(p: int) -> Array:
	var out := []
	for id in players[p]["hand"]:
		var k := card_kind(id)
		if k == "":
			continue
		if _card_ok(p, id, k) and _card_useful(p, k):
			out.append(id)
	return out


## Controlli più fini: la carta avrebbe davvero effetto adesso.
func _card_useful(p: int, k: String) -> bool:
	match k:
		"advance":
			return D.all_advances().any(func(a): return can_buy_adv(p, a))
		"idea_synergy":
			return not buyable_advances(p).is_empty()
		"city_growth":
			for c in cities_of(p):
				for b in D.BUILDINGS:
					if can_build(p, c, b) == "":
						return true
			return false
		"inspiration", "tech_exchange":
			for q in _near_players(p):
				for a in players[q]["adv"]:
					if can_buy_adv(p, a):
						return true
			return false
		"teach_us":
			for q in T["captured_from"]:
				for a in players[q]["adv"]:
					if can_buy_adv(p, a):
						return true
			return false
		"tech_synergy":
			if not can_pay(p, {"food": 4}, ["idea"]):
				return false
			for cat in D.CATEGORIES:
				var k2 := 0
				for a in D.ADV[cat]:
					if not players[p]["adv"].has(a[0]):
						k2 += 1
				if k2 >= 2 and (players[p]["adv"].has(D.ADV[cat][0][0]) or can_buy_adv(p, D.ADV[cat][0][0])):
					return true
			return false
		"cultural_awe":
			for c in cities_of(-1):
				if city_size(c) == 1:
					for src in cities_of(p):
						if dist_revealed(src["h"], c["h"]) <= city_size(src) + res(p, "culture"):
							return true
			return false
		"militia":
			return supply_left(p, "infantry") > 0
	return true


func card_kind(id: String) -> String:
	if id.begins_with("a"):
		var a := D.action_card(id)
		return a[1] if not a.is_empty() else ""
	if id.begins_with("e"):
		return D.EVENTS[id][2]
	return ""


func _card_ok(p: int, id: String, k: String) -> bool:
	var cul := res(p, "culture")
	var acts: int = T["actions"]
	if civ_adv(p, "Shogunate") and not T.get("shogun_c", false):
		acts += 1
	match k:
		"advance":
			return cul >= 1
		"leadership", "assassination":
			return cul >= 1
		"militia":
			return cul >= 1 and not cities_of(p).is_empty() and supply_left(p, "infantry") > 0
		"leap_knowledge":
			for c in cities_of(p):
				if c["b"].has("academy"):
					return true
			return false
		"inspiration", "tech_exchange":
			return not _near_players(p).is_empty()
		"negotiations":
			return cul >= 1 and not T.get("acted", false)
		"spies", "explorers", "new_goals", "city_growth":
			return cul >= 1 and acts > 0
		"tech_synergy", "idea_synergy", "mercenaries":
			return acts > 0
		"heroic_general":
			return T["won_army"]
		"good_ideas":
			return T["won_army"] or T["captured"]
		"teach_us":
			return not T["captured_from"].is_empty()
		"cultural_awe":
			return acts > 0 and not T["infl_ok"]
	if k.begins_with("gp_"):
		return acts > 0
	return false


## Giocatori con unità o città entro 2 caselle da unità o città di p.
func _near_players(p: int) -> Array:
	var mine := []
	for c in cities_of(p):
		mine.append(c["h"])
	for u in units_of(p):
		mine.append(u["h"])
	var out := []
	for q in n:
		if q == p:
			continue
		var theirs := []
		for c in cities_of(q):
			theirs.append(c["h"])
		for u in units_of(q):
			theirs.append(u["h"])
		var near := false
		for a in mine:
			for b in theirs:
				if hdist(a, b) <= 2:
					near = true
					break
			if near:
				break
		if near:
			out.append(q)
	return out


func _use_card(p: int, id: String, cost := 0) -> void:
	players[p]["hand"].erase(id)
	if cost > 0:
		lose(p, "culture", cost)
	discard("event" if id.begins_with("e") else "action", id, p)
	T["played"].append(id)
	log_msg("%s gioca «%s»." % [pname(p), D.card_title(id)])
	fx.emit("card", {"p": p, "id": id})


func play_card(p: int, m: Dictionary) -> bool:
	var id: String = m.get("id", "")
	if not players[p]["hand"].has(id):
		return false
	var k := card_kind(id)
	if not _card_ok(p, id, k):
		return false
	var bumped := false
	if civ_adv(p, "Shogunate") and not T.get("shogun_c", false) and (k in ["spies", "explorers", "new_goals", "city_growth", "tech_synergy", "idea_synergy", "mercenaries", "cultural_awe"] or k.begins_with("gp_")):
		T["shogun_c"] = true
		T["free_next"] = true
		if T["actions"] <= 0:
			T["actions"] += 1
			T["free_next"] = false
			bumped = true
		log_msg("Shogunato: la carta non costa un'azione.")
	var acts0: int = T["actions"]
	# Sotterfugio (Giappone): un avversario vicino può annullare la carta scartandone una
	if exp and await _subterfuge(p, id):
		players[p]["hand"].erase(id)
		discard("event" if id.begins_with("e") else "action", id, p)
		T["free_next"] = false
		if bumped:
			T["actions"] -= 1
		changed.emit()
		return true
	var ok_card: bool = await _play_card_effect(p, id, k)
	T["free_next"] = false
	if not ok_card:
		T.erase("shogun_c")
		if bumped and T["actions"] == acts0:
			T["actions"] -= 1
	return ok_card


func _subterfuge(p: int, id: String) -> bool:
	for q in n:
		if q == p or not civ_adv(q, "Subterfuge"):
			continue
		var cards: Array = players[q]["hand"].filter(func(x): return x.begins_with("a"))
		if cards.is_empty():
			continue
		var near := false
		var mine := cities_of(q).map(func(c): return c["h"]) + units_of(q).filter(func(u): return is_army(u)).map(func(u): return u["h"])
		var theirs := cities_of(p).map(func(c): return c["h"]) + units_of(p).map(func(u): return u["h"])
		for a in mine:
			for b in theirs:
				if hdist(a, b) <= 2:
					near = true
		if not near:
			continue
		var labels := ["Lascia giocare"] + cards.map(func(x): return "Scarta «%s»" % D.card_title(x))
		var j := await choose(q, "Sotterfugio: %s gioca «%s». Lo annulli?" % [pname(p), D.card_title(id)], labels, {"force": true})
		if j > 0:
			players[q]["hand"].erase(cards[j - 1])
			discard("action", cards[j - 1], q)
			log_msg("Sotterfugio: %s annulla la carta di %s." % [pname(q), pname(p)])
			return true
	return false


func _play_card_effect(p: int, id: String, k: String) -> bool:
	match k:
		"advance":
			var lst := []
			for a in D.all_advances():
				if can_buy_adv(p, a):
					lst.append(a)
			if lst.is_empty():
				return false
			_use_card(p, id, 1)
			var a := await _choose_adv(p, "Avanzamento gratuito", lst)
			await gain_advance(p, a, false)
		"leadership":
			_use_card(p, id, 1)
			T["actions"] += 1
		"militia":
			_use_card(p, id, 1)
			var c := await _choose_city(p, "Milizia: in quale città?", cities_of(p))
			new_unit(p, "infantry", c["h"])
		"leap_knowledge":
			_use_card(p, id)
			var k2 := 0
			for c in cities_of(p):
				if c["b"].has("academy"):
					k2 += 1
			gain(p, "idea", k2)
		"inspiration":
			var q := await _choose_player(p, "Ispirazione: da chi copi?", _near_players(p))
			var lst2 := []
			for a in players[q]["adv"]:
				if can_buy_adv(p, a):
					lst2.append(a)
			if lst2.is_empty():
				return false
			_use_card(p, id)
			await gain_advance(p, await _choose_adv(p, "Ispirazione: quale avanzamento?", lst2), false)
		"tech_exchange":
			var q2 := await _choose_player(p, "Scambio tecnologico con…", _near_players(p))
			var mine := []
			for a in players[q2]["adv"]:
				if can_buy_adv(p, a):
					mine.append(a)
			if mine.is_empty():
				return false
			_use_card(p, id)
			await gain_advance(p, await _choose_adv(p, "Quale avanzamento copi?", mine), false)
			var theirs := []
			for a in players[p]["adv"]:
				if can_buy_adv(q2, a):
					theirs.append(a)
			if not theirs.is_empty():
				await gain_advance(q2, await _choose_adv(q2, "Scambio tecnologico: quale avanzamento copi da %s?" % pname(p), theirs), false)
		"assassination":
			var lst3 := []
			for q in n:
				if q != p and not assassinated.has(q):
					lst3.append(q)
			if lst3.is_empty():
				return false
			_use_card(p, id, 1)
			var q3 := await _choose_player(p, "Assassinio: chi colpisci?", lst3)
			assassinated[q3] = 1
		"negotiations":
			_use_card(p, id, 1)
			var lst4 := []
			for q in n:
				if q != p:
					lst4.append(q)
			var q4 := await _choose_player(p, "Trattative con…", lst4)
			negotiation["%d,%d" % [mini(p, q4), maxi(p, q4)]] = turn_count + n
		"spies":
			var lst5 := []
			for q in n:
				if q != p:
					lst5.append(q)
			_use_card(p, id, 1)
			spend_action(false)
			var q5 := await _choose_player(p, "Spie: chi spii?", lst5)
			await _spies(p, q5)
		"explorers":
			_use_card(p, id, 1)
			spend_action(false)
			await _reveal_near_city(p, false)
			if supply_left(p, "settler") > 0 and not cities_of(p).is_empty() and await yes_no(p, "Esploratori: metti un Colono gratis in una tua città?"):
				var c3 := await _choose_city(p, "In quale città?", cities_of(p))
				new_unit(p, "settler", c3["h"])
		"new_goals":
			_use_card(p, id, 1)
			spend_action(false)
			var drawn := []
			for i in 2:
				var o := draw("objective", p)
				if o != "":
					drawn.append(o)
			if not drawn.is_empty() and not players[p]["obj"].is_empty():
				var labels := ["Nessuno scambio"]
				var pairs := [[]]
				for mine_o in players[p]["obj"]:
					for d in drawn:
						labels.append("Dai «%s», prendi «%s»" % [D.card_title(mine_o), D.card_title(d)])
						pairs.append([mine_o, d])
				var j := await choose(p, "Nuovi obiettivi", labels, {"force": true})
				if j > 0:
					players[p]["obj"].erase(pairs[j][0])
					players[p]["obj"].append(pairs[j][1])
					drawn.erase(pairs[j][1])
					drawn.append(pairs[j][0])
			for d in drawn:
				decks["objective"].append(d)
			shuffle(decks["objective"])
		"city_growth":
			var opts2 := []
			var labels2 := []
			for c in cities_of(p):
				for b in D.BUILDINGS:
					if can_build(p, c, b) == "":
						opts2.append([c["id"], b])
						labels2.append("%s a %s" % [D.B_NAME[b], _hex_label(c["h"])])
			if opts2.is_empty():
				return false
			_use_card(p, id, 1)
			var j2 := await choose(p, "Crescita urbana: cosa costruisci?", labels2, {"force": true})
			T["actions"] += 0
			await do_build(p, opts2[j2][0], opts2[j2][1], true, true, true)
		"tech_synergy":
			var cats := []
			for cat in D.CATEGORIES:
				var av := []
				for a in D.ADV[cat]:
					if not players[p]["adv"].has(a[0]):
						av.append(a[0])
				if av.size() >= 2 and can_pay(p, {"food": 4}, ["idea"]):
					var top: String = D.ADV[cat][0][0]
					if players[p]["adv"].has(top) or can_buy_adv(p, top):
						cats.append(cat)
			if cats.is_empty():
				return false
			_use_card(p, id)
			spend_action(false)
			var ci := await choose(p, "Sinergia tecnologica: quale categoria?", cats.map(func(c): return D.CAT_NAME[c]), {"force": true})
			for i in 2:
				var av2 := []
				for a in D.ADV[cats[ci]]:
					if can_buy_adv(p, a[0]):
						av2.append(a[0])
				if av2.is_empty() or not can_pay(p, {"food": 2}, ["idea"]):
					break
				var a2 := await _choose_adv(p, "Sinergia tecnologica: avanzamento %d" % (i + 1), av2)
				pay(p, {"food": adv_food_cost(p, a2)}, ["idea"])
				await gain_advance(p, a2, false)
		"idea_synergy":
			var lst6 := buyable_advances(p)
			if lst6.is_empty():
				return false
			_use_card(p, id)
			spend_action(false)
			var a3 := await _choose_adv(p, "Sinergia di idee: quale avanzamento?", lst6)
			pay(p, {"food": adv_food_cost(p, a3)}, ["idea"])
			await gain_advance(p, a3, false)
			gain(p, "idea", 2)
		"heroic_general":
			_use_card(p, id)
			var cs := cities_of(p).filter(func(c): return c["mood"] < 2)
			if not cs.is_empty():
				var c4 := await _choose_city(p, "Generale eroico: quale città migliora?", cs)
				change_mood(c4, 1)
				cs = cities_of(p).filter(func(c): return c["mood"] < 2)
				if not cs.is_empty() and res(p, "mood") >= 1 and await yes_no(p, "Paghi 1 Umore per un altro passo?"):
					lose(p, "mood", 1)
					var c5 := await _choose_city(p, "Quale città?", cs)
					change_mood(c5, 1)
		"good_ideas":
			_use_card(p, id)
			gain(p, "idea", 2)
		"teach_us":
			var lst7 := []
			for q in T["captured_from"]:
				for a in players[q]["adv"]:
					if can_buy_adv(p, a) and not lst7.has(a):
						lst7.append(a)
			if lst7.is_empty():
				return false
			_use_card(p, id)
			await gain_advance(p, await _choose_adv(p, "Insegnateci! Quale avanzamento copi?", lst7), false)
		"cultural_awe":
			return await _cultural_awe(p, id)
		"mercenaries":
			return await _mercenaries(p, id)
		_:
			if k.begins_with("gp_"):
				return await _great_person(p, id, k)
			return false
	changed.emit()
	return true


func _spies(p: int, q: int) -> void:
	var labels := ["Nessuno scambio"]
	var opts2 := [[]]
	for kind in [["hand", "carta Azione"], ["obj", "Obiettivo"], ["won", "Meraviglia"]]:
		for theirs in players[q][kind[0]]:
			for mine in players[p][kind[0]]:
				labels.append("Prendi «%s», dai «%s»" % [D.card_title(theirs), D.card_title(mine)])
				opts2.append([kind[0], theirs, mine])
	var i := await choose(p, "Spie: le carte di %s" % pname(q), labels, {"force": true, "spy": q})
	if i > 0:
		var o: Array = opts2[i]
		players[q][o[0]].erase(o[1])
		players[p][o[0]].erase(o[2])
		players[q][o[0]].append(o[2])
		players[p][o[0]].append(o[1])
		log_msg("%s scambia una carta con %s." % [pname(p), pname(q)])


func _reveal_near_city(p: int, may_found: bool) -> void:
	var cand := {}
	for c in cities_of(p):
		var ri := region_of(c["h"])
		for k in regions[ri]["hexes"]:
			for y in neighbors(k):
				var r2 := region_of(y)
				if r2 >= 0 and not regions[r2]["revealed"]:
					cand[r2] = y
	if cand.is_empty():
		return
	var keys := []
	for r in cand:
		keys.append(cand[r])
	var k2 := await choose_hex(p, "Quale regione scopri?", keys, keys.map(func(x): return "Regione inesplorata"))
	var ri2 := region_of(k2)
	await explore(p, ri2, "")
	if may_found and supply_left(p, "settlement") > 0 and can_pay(p, {"food": 2}):
		var spots := []
		for k in regions[ri2]["hexes"]:
			if can_found_at(p, k):
				spots.append(k)
		if not spots.is_empty() and await yes_no(p, "Paghi 2 Cibo per fondare una città nella nuova regione?"):
			pay(p, {"food": 2})
			var k3 := await choose_hex(p, "Dove fondi la città?", spots)
			new_city(p, k3, 1)
			log_msg("%s fonda una città nella regione scoperta." % pname(p))


func _cultural_awe(p: int, id: String) -> bool:
	var targets := []
	for cid in cities:
		var c: Dictionary = cities[cid]
		if c["o"] != -1 or city_size(c) != 1:
			continue
		for src in cities_of(p):
			var d := dist_revealed(src["h"], c["h"])
			if d <= city_size(src) + res(p, "culture"):
				targets.append([src, c, maxi(0, d - city_size(src))])
				break
	if targets.is_empty():
		return false
	var keys := targets.map(func(t): return t[1]["h"])
	var k := await choose_hex(p, "Soggezione culturale: quale città barbara?", keys)
	var t: Array = targets[keys.find(k)]
	_use_card(p, id)
	spend_action(false)
	lose(p, "culture", t[2])
	var roll := d6() + (1 if has_adv(p, "Conversion") else 0)
	if roll < 5 and res(p, "culture") >= 5 - roll and await yes_no(p, "Tiro %d: spendi %d Cultura per riuscire?" % [roll, 5 - roll]):
		lose(p, "culture", 5 - roll)
		roll = 5
	var c: Dictionary = t[1]
	if roll >= 5:
		T["infl_ok"] = true
		c["o"] = p
		c["mood"] = 1
		var barbs := units_at(c["h"]).filter(func(u): return u["o"] == -1)
		for u in barbs:
			remove_unit(u)
		if not barbs.is_empty():
			var i := await choose(p, "Un barbaro può unirsi a te come…", ["Colono", "Fanteria", "Nessuno"], {"force": true})
			if i < 2:
				new_unit(p, "settler" if i == 0 else "infantry", c["h"])
		log_msg("La città barbara si sottomette a %s!" % pname(p))
	else:
		log_msg("La città barbara resiste all'influenza.")
	changed.emit()
	return true


func _mercenaries(p: int, id: String) -> bool:
	var mine := []
	for c in cities_of(p):
		mine.append(c["h"])
	for u in units_of(p):
		if is_army(u):
			mine.append(u["h"])
	var groups := {}
	for u in units_of(-1):
		if not is_army(u):
			continue
		for x in mine:
			if hdist(x, u["h"]) <= 2:
				groups[u["h"]] = true
	if groups.is_empty():
		return false
	_use_card(p, id)
	spend_action(false)
	for g in groups.keys():
		if not await yes_no(p, "Mercenari: muovi l'esercito barbaro in %s?" % _hex_label(g)):
			continue
		var grp := armies_at(g, -1)
		var dests := neighbors(g).filter(func(x): return is_land(x) and (has_enemy(x, -1) or armies_at(x, -1).size() + grp.size() <= 4))
		var payopts := []
		for r in ["food", "wood", "ore", "culture"]:
			if res(p, r) > 0:
				payopts.append(r)
		if payopts.is_empty() or dests.is_empty() or grp.is_empty():
			continue
		var ri := await choose(p, "Con che cosa paghi?", payopts.map(func(r): return D.RES_NAME[r]), {"force": true})
		lose(p, payopts[ri], 1)
		var to := await choose_hex(p, "Dove va l'esercito barbaro?", dests)
		var from_city: bool = not city_at(g).is_empty() and city_at(g)["o"] == -1
		if has_enemy(to, -1):
			for u in grp:
				u["h"] = to
			await barbarian_attack(grp, to)
		else:
			for u in grp:
				u["h"] = to
		if from_city and supply_left(-1, "infantry") > 0:
			new_unit(-1, "infantry", g)
	changed.emit()
	return true


func _great_person(p: int, id: String, k: String) -> bool:
	if k == "gp_oracle":
		_use_card(p, id)
		spend_action(false)
		var drawn := []
		for i in n:
			var o := draw("objective", p)
			if o != "":
				drawn.append(o)
		for q in _order_from(p):
			if drawn.is_empty():
				break
			var j := 0
			if drawn.size() > 1:
				j = await choose(p, "Grande oracolo: quale Obiettivo dai a %s?" % ("te stesso" if q == p else pname(q)), drawn.map(func(o): return D.card_title(o)), {"force": true})
			oracle[q] = drawn[j]
			drawn.remove_at(j)
		log_msg("Il Grande oracolo assegna a ciascuno il prossimo Obiettivo.")
		changed.emit()
		return true
	var cat: String = D.GREAT_PERSON_CAT[k]
	_use_card(p, id)
	spend_action(false)
	var lst := []
	for a in D.all_advances():
		var info := D.adv_info(a)
		var ok: bool = (info["cat"] == cat) or (cat == "gov" and info["cat"] in D.GOVERNMENTS)
		if ok and can_buy_adv(p, a):
			lst.append(a)
	if not lst.is_empty() and await yes_no(p, "Avanzamento gratuito (%s)?" % ("governo" if cat == "gov" else D.CAT_NAME[cat])):
		await gain_advance(p, await _choose_adv(p, "Quale avanzamento?", lst), false)
	match k:
		"gp_discoverer":
			await _reveal_near_city(p, true)
		"gp_artist":
			var cs := cities_of(p).filter(func(c): return c["mood"] < 2)
			if not cs.is_empty():
				var c := await _choose_city(p, "Quale città diventa Felice?", cs)
				c["mood"] = 2
		"gp_prophet":
			var cs2 := cities_of(p).filter(func(c): return can_build(p, c, "temple", true) == "" and can_pay(p, build_cost(p, "temple")))
			if not cs2.is_empty() and await yes_no(p, "Costruisci un Tempio?"):
				var c2 := await _choose_city(p, "In quale città?", cs2)
				await do_build(p, c2["id"], "temple", false, false, false)
		"gp_philosopher":
			gain(p, "idea", 2)
		"gp_athlete":
			var opts3 := ["Niente"]
			if res(p, "culture") > 0:
				opts3.append("Cambia tutta la Cultura (%d) in Umore" % res(p, "culture"))
			if res(p, "mood") > 0:
				opts3.append("Cambia tutto l'Umore (%d) in Cultura" % res(p, "mood"))
			var j2 := await choose(p, "Grande atleta: converti?", opts3, {"force": true})
			if j2 > 0:
				var from_c: bool = opts3[j2].begins_with("Cambia tutta la Cultura")
				var amt := res(p, "culture") if from_c else res(p, "mood")
				lose(p, "culture" if from_c else "mood", amt)
				gain(p, "mood" if from_c else "culture", amt)
		"gp_scientist":
			gain(p, "idea", 1)
			draw_action(p)
		"gp_statesman":
			draw_action(p, 2)
		"gp_warlord":
			T["warlord_bonus"] = true
			T["actions"] += 1
			await do_move_action(p)
			T["warlord_bonus"] = false
		"gp_merchant":
			if has_adv(p, "Trade Routes"):
				await _trade_income(p)
		"gp_engineer":
			var opts2 := []
			var labels := []
			for c in cities_of(p):
				for b in D.BUILDINGS:
					if can_build(p, c, b, true) == "" and can_pay(p, build_cost(p, b)):
						opts2.append([c["id"], b])
						labels.append("%s a %s" % [D.B_NAME[b], _hex_label(c["h"])])
			if not opts2.is_empty():
				var j := await choose(p, "Grande ingegnere: cosa costruisci?", ["Niente"] + labels, {"force": true})
				if j > 0:
					await do_build(p, opts2[j - 1][0], opts2[j - 1][1], false, false, false)
	changed.emit()
	return true


# ------------------------------------------------------------------ eventi

func resolve_event(p: int) -> void:
	if plague_by == p:
		plague_by = -1
		log_msg("La Peste è finita.")
	if civ_adv(p, "Star Catalogues"):
		var sc := await choose(p, "Cataloghi stellari: prima dell'evento ricevi…", ["+1 Idea", "+1 Cultura"], {"force": true})
		gain(p, "idea" if sc == 0 else "culture", 1)
	var id := draw("event", p)
	if id == "":
		return
	# Sacrifici umani (Aztechi): un Prigioniero annulla l'evento appena pescato
	if civ_adv(p, "Human Sacrifice") and int(players[p].get("captives", 0)) > 0:
		if await yes_no(p, "Sacrifici umani: sacrifichi un Prigioniero per annullare «%s» e pescarne un altro?" % D.EVENTS[id][0]):
			players[p]["captives"] -= 1
			discard("event", id, p)
			log_msg("%s sacrifica un Prigioniero: l'evento «%s» è annullato." % [pname(p), D.EVENTS[id][0]])
			id = draw("event", p)
			if id == "":
				return
	var e: Array = D.EVENTS[id]
	log_msg("Evento per %s: %s." % [pname(p), e[0]])
	fx.emit("event", {"p": p, "id": id})
	await wait(1.2)
	match e[1]:
		"gold":
			gain(p, "gold", 2)
			log_msg("Miniera d'oro: %s riceve 2 Oro." % pname(p))
		"exhaust":
			await _exhaust(p)
		"barb_spawn":
			await barbarians_spawn(p, true)
		"barb_move":
			await barbarians_move(p)
		"pirates":
			await pirates_event(p)
	if opts.get("no_events", false):
		discard("event", id, p)
		changed.emit()
		return
	var kept := await _event_effect(p, id, e[2])
	if not kept:
		discard("event", id, p)
	changed.emit()


func _exhaust(p: int) -> void:
	var cand := {}
	for c in cities_of(p):
		for x in neighbors(c["h"]):
			if is_land(x) and ter(x) != "barren" and not hexes[x]["exhausted"] and units_at(x).is_empty() and city_at(x).is_empty():
				cand[x] = true
	if cand.is_empty():
		return
	var k := await choose_hex(p, "Terra esausta: dove metti il segnalino?", cand.keys())
	hexes[k]["exhausted"] = true
	log_msg("Una terra di %s si esaurisce." % pname(p))


## Peggiora l'umore di una città per un evento (con Miti si può pagare 1 Umore per evitarlo).
func event_mood(p: int, c: Dictionary, to_angry := false) -> void:
	if c.is_empty() or c["mood"] == 0:
		return
	# Marqzen, signore delle tempeste: annulla il calo d'umore nella sua città
	if lcode(p) == "l03" and leader_at(p, c["h"]) and c["o"] == p:
		log_msg("Marqzen protegge la sua città dall'evento.")
		return
	if has_adv(p, "Myths") and res(p, "mood") >= 1:
		if await yes_no(p, "Miti: paghi 1 Umore per evitare che la città peggiori l'umore?"):
			lose(p, "mood", 1)
			return
	if to_angry:
		c["mood"] = 0
	else:
		change_mood(c, -1)
	fx.emit("mood", {"h": c["h"]})


func _event_city(p: int, title: String, filter := Callable()) -> Dictionary:
	var cs := []
	for c in cities_of(p):
		if c["mood"] > 0 and (not filter.is_valid() or filter.call(c)):
			cs.append(c)
	if cs.is_empty():
		return {}
	return await _choose_city(p, title, cs)


func _order_from(p: int) -> Array:
	var out := []
	for i in n:
		out.append((p + i) % n)
	return out


func _spread3(p: int) -> bool:
	return has_adv(p, "Roads") or has_adv(p, "Navigation") or has_adv(p, "Trade Routes")


func _food_target(p: int, title: String, others := true) -> int:
	var lst := []
	for q in n:
		if q != p or not others:
			lst.append(q)
	var room := lst.filter(func(q): return res(q, "food") < food_limit(q))
	if not room.is_empty():
		lst = room
	return await _choose_player(p, title, lst)


## Effetto della carta evento. Restituisce true se la carta resta fuori dagli scarti.
func _event_effect(p: int, id: String, key: String) -> bool:
	match key:
		"plague":
			for q in _order_from(p):
				if has_adv(q, "Sanitation") or cities_of(q).size() < 2:
					continue
				for i in (2 if _spread3(q) else 1):
					await event_mood(q, await _event_city(q, "Peste: quale città peggiora l'umore?"))
			plague_by = p
			log_msg("Peste: chi non ha Igiene non può costruire finché %s non pesca un altro evento." % pname(p))
		"epidemic":
			for q in _order_from(p):
				if has_adv(q, "Sanitation") or units_of(q).size() < 2:
					continue
				for i in (2 if _spread3(q) else 1):
					await _lose_unit(q, "Epidemia: quale unità perdi?")
		"famine1", "famine2":
			if not has_adv(p, "Irrigation") and not civ_adv(p, "Aqueducts"):
				var need := 1 if key == "famine1" else 2
				var had := res(p, "food")
				lose(p, "food", need)
				if had < need:
					await event_mood(p, await _event_city(p, "Carestia: quale città diventa Arrabbiata?"), true)
		"fine_all":
			for q in n:
				gain(q, "food", 1)
		"fine_you":
			gain(p, "food", 1)
		"fine_other":
			gain(p, "food", 1)
			if n > 1:
				gain(await _food_target(p, "Chi riceve 1 Cibo?"), "food", 1)
		"good_you":
			gain(p, "food", 2)
		"good_all":
			for q in n:
				gain(q, "food", 2)
		"good_other":
			gain(p, "food", 2)
			if n > 1:
				gain(await _food_target(p, "Chi riceve 2 Cibo?"), "food", 2)
		"splendid_all":
			for q in n:
				gain(q, "food", 3)
		"splendid_you":
			gain(p, "food", 3)
		"splendid_other":
			gain(p, "food", 3)
			for i in 3:
				if n > 1:
					gain(await _food_target(p, "Splendido anno: a chi dai 1 Cibo (%d di 3)?" % (i + 1)), "food", 1)
		"boom":
			if supply_left(p, "settler") > 0 and not cities_of(p).is_empty():
				var c := await _choose_city(p, "Boom demografico: dove metti il Colono?", cities_of(p))
				new_unit(p, "settler", c["h"])
			var lst := []
			for q in n:
				if q != p and supply_left(q, "settler") > 0 and not cities_of(q).is_empty():
					lst.append(q)
			if not lst.is_empty():
				var q2 := await _choose_player(p, "Chi riceve anche un Colono?", lst)
				var c2 := await _choose_city(q2, "Boom demografico: dove metti il Colono?", cities_of(q2))
				new_unit(q2, "settler", c2["h"])
		"migration":
			var lst2 := []
			for q in n:
				if q != p and not cities_of(q).is_empty():
					lst2.append(q)
			var withs := lst2.filter(func(q): return supply_left(q, "settler") > 0)
			if not withs.is_empty():
				lst2 = withs
			if not lst2.is_empty():
				var q3 := await _choose_player(p, "Migrazione: chi riceve un Colono?", lst2)
				if supply_left(q3, "settler") > 0:
					var c3 := await _choose_city(q3, "Migrazione: dove metti il Colono?", cities_of(q3))
					new_unit(q3, "settler", c3["h"])
			await event_mood(p, await _event_city(p, "Migrazione: quale tua città peggiora l'umore?"))
		"local_flood":
			await event_mood(p, await _event_city(p, "Alluvione: quale città costiera?", func(c): return is_coastal(c)))
		"major_flood":
			for q in _order_from(p):
				await event_mood(q, await _event_city(q, "Grande alluvione: quale città costiera?", func(c): return is_coastal(c)))
		"civil_war":
			var cs := []
			for c in cities_of(p):
				if c["mood"] < 2 and not armies_at(c["h"], p).is_empty():
					cs.append(c)
			if not cs.is_empty():
				var c4 := await _choose_city(p, "Guerra civile: quale città?", cs)
				remove_unit(armies_at(c4["h"], p)[0])
				await event_mood(p, c4)
			else:
				await event_mood(p, await _event_city(p, "Guerra civile: quale città peggiora l'umore?"))
		"revolution":
			var g := gov_of(p)
			var army := units_of(p, "infantry")
			var skip_action := false
			var skip_gov := g == ""
			if not army.is_empty() and await yes_no(p, "Rivoluzione: elimini una Fanteria per non perdere un'azione?"):
				remove_unit(army[0])
				skip_action = true
			army = units_of(p, "infantry")
			if not skip_gov and not army.is_empty() and await yes_no(p, "Rivoluzione: elimini una Fanteria per non cambiare governo?"):
				remove_unit(army[0])
				skip_gov = true
			if not skip_action:
				if cur == p and T["actions"] > 0:
					T["actions"] -= 1
				else:
					players[p]["lose_next"] = true
				log_msg("Rivoluzione: %s perde un'azione." % pname(p))
			if not skip_gov:
				await change_government(p, false)
		"volcano":
			if cities_of(p).size() >= 4:
				var c5 := await _choose_city(p, "Vulcano: quale città viene distrutta?", cities_of(p))
				_destroy_city_pieces(c5, 99, true)
				log_msg("Un vulcano distrugge una città di %s." % pname(p))
				players[p]["events"].append(id)
				return true
		"earthquake":
			if cities_of(p).size() >= 3:
				await _earthquake(p)
				players[p]["events"].append(id)
				return true
		"major_earthquake":
			var any := false
			for q in _order_from(p):
				if cities_of(q).size() >= 3:
					await _earthquake(q)
					any = true
			if any:
				players[p]["events"].append(id)
				return true
		_:
			if key.begins_with("gp_"):
				return await _great_person_keep(p, id)
			return await _exp_event(p, id, key)
	return false


# ------------------------------------------------------------------ eventi dell'espansione

func _exp_event(p: int, id: String, key: String) -> bool:
	match key:
		"uprising":
			var tot := res(p, "culture") + res(p, "mood")
			if tot <= 0:
				return false
			var labels := []
			for i in mini(4, tot):
				labels.append("%d segnalin%s (+%s PV)" % [i + 1, "o" if i == 0 else "i", str((i + 1) * 0.5)])
			var k := await choose(p, "Insurrezione: quanti segnalini di Cultura/Umore perdi?", labels, {"force": true}) + 1
			var first_mood := true
			if res(p, "mood") > 0 and res(p, "culture") > 0:
				first_mood = await choose(p, "Insurrezione: cosa perdi per primo?", ["Umore", "Cultura"], {"force": true}) == 0
			var a := "mood" if first_mood else "culture"
			var b := "culture" if first_mood else "mood"
			var left := k - lose(p, a, k)
			lose(p, b, left)
			players[p]["vp_extra"] += 0.5 * k
			log_msg("Insurrezione: %s perde %d segnalini (+%s PV)." % [pname(p), k, str(0.5 * k)])
			players[p]["events"].append(id)
			return true
		"envoys":
			gain(p, "idea", 1)
			gain(p, "culture", 1)
			if n > 1:
				var others := range(n).filter(func(q): return q != p)
				var q := await _choose_player(p, "Incontro di ambasciatori: chi riceve 1 Cultura?", others)
				gain(q, "culture", 1)
			var w := draw("wonder", p)
			if w != "":
				table_wonders.append(w)
				log_msg("Sul tavolo compare la Meraviglia %s: chi deve pescarne una la prende." % D.WONDERS[w]["it"])
		"eclipse":
			eclipse = true
			log_msg("Eclissi solare: la prossima battaglia fra giocatori durerà un solo round.")
			return true
		"trojan":
			trojan = true
			log_msg("Il Cavallo di Troia è sul tavolo.")
			return true
		"brute":
			var lu := leader_unit(p)
			if not lu.is_empty():
				remove_unit(lu)
			if players[p]["no_leader"] or players[p]["leaders_avail"].is_empty():
				return false
			var i := await choose(p, "Tu quoque, Brute? Cosa scegli?", ["Un nuovo Capo, gratis in una tua città", "Tieni la carta (2 PV): niente più Capi"], {"force": true})
			if i == 0 and not cities_of(p).is_empty():
				await _choose_leader(p)
				var c := await _choose_city(p, "Dove arriva il nuovo Capo?", cities_of(p))
				new_unit(p, "leader", c["h"])
			else:
				players[p]["no_leader"] = true
				players[p]["vp_extra"] += 2.0
				players[p]["events"].append(id)
				return true
		"anarchy":
			var k2 := 0
			for g in D.GOVERNMENTS:
				for a2 in D.ADV[g]:
					if players[p]["adv"].has(a2[0]):
						players[p]["adv"].erase(a2[0])
						k2 += 1
			if k2 > 0:
				players[p]["anarchy"] = int(players[p].get("anarchy", 0)) + k2
				log_msg("Anarchia: %s perde %d avanzamenti di governo (1 PV ciascuno su questa carta)." % [pname(p), k2])
				players[p]["events"].append(id)
				return true
		"academics":
			for q in n:
				var k3 := cities_of(q).filter(func(c): return c["b"].has("academy") or c["b"].has("observatory")).size()
				if q == p:
					k3 = maxi(2, k3)
				gain(q, "idea", k3)
		"brisk_trade":
			for q in n:
				var k4 := mini(3, cities_of(q).filter(func(c): return c["b"].has("port") or c["b"].has("market")).size())
				if q == p:
					k4 = maxi(1, k4)
				gain(q, "gold", k4)
		"stability":
			for q in _order_from(p):
				var k5 := mini(3, cities_of(q).filter(func(c): return c["b"].has("temple") or c["b"].has("obelisk")).size())
				if q == p:
					k5 = maxi(1, k5)
				for i2 in k5:
					var j := await choose(q, "Era di stabilità: ricevi… (%d di %d)" % [i2 + 1, k5], ["+1 Umore", "+1 Cultura"], {"force": true})
					gain(q, "mood" if j == 0 else "culture", 1)
		"reformation":
			var victim := -1
			for q in _order_from(p):
				if not cities_of(q).filter(func(c): return c["b"].get("temple", -9) == q).is_empty():
					victim = q
					break
			if victim < 0 or n < 2:
				return false
			var others2 := range(n).filter(func(q): return q != victim)
			var who := await _choose_player(victim, "Riforma: chi metterà sotto la sua influenza un tuo Tempio?", others2)
			var temples := cities_of(victim).filter(func(c): return c["b"].get("temple", -9) == victim)
			var tc := await _choose_city(who, "Riforma: quale Tempio passa sotto la tua influenza?", temples)
			tc["b"]["temple"] = who
			log_msg("Riforma: un Tempio di %s passa sotto l'influenza di %s." % [pname(victim), pname(who)])
		"pandemic":
			for q in _order_from(p):
				if has_adv(q, "Sanitation"):
					continue
				for i3 in cities_of(q).size() / 2:
					await _pandemic_loss(q)
		"black_death":
			for q in _order_from(p):
				var us := units_of(q)
				if us.size() < 4:
					continue
				var k6 := us.size() / 4 + (1 if _spread3(q) else 0)
				for i4 in k6:
					await _lose_unit(q, "Peste nera: quale unità perdi (1 PV)?")
				players[q]["vp_extra"] += float(k6)
				log_msg("Peste nera: %s perde %d unità (+%d PV)." % [pname(q), k6, k6])
		"pests":
			for q in _order_from(p):
				if has_adv(q, "Irrigation") or civ_adv(q, "Aqueducts") or not has_adv(q, "Storage"):
					continue
				if res(q, "food") > 0:
					lose(q, "food", 1)
				else:
					await event_mood(q, await _event_city(q, "Parassiti: quale città diventa Arrabbiata?"), true)
		"drought":
			if has_adv(p, "Irrigation") or civ_adv(p, "Aqueducts"):
				return false
			var barren := {}
			var hit_c := []
			for c in cities_of(p):
				for x in [c["h"]] + neighbors(c["h"]):
					if ter(x) == "barren":
						barren[x] = true
						if not hit_c.has(c):
							hit_c.append(c)
			var need := mini(3, barren.size())
			if need == 0:
				return false
			var had := res(p, "food")
			lose(p, "food", need)
			log_msg("Siccità: %s perde %d Cibo." % [pname(p), mini(had, need)])
			if had < need:
				var cs := hit_c.filter(func(c): return c["mood"] > 0)
				if not cs.is_empty():
					await event_mood(p, await _choose_city(p, "Siccità: quale città diventa Arrabbiata?", cs), true)
		"wildfire":
			var fc := cities_of(p).filter(func(c): return ter(c["h"]) == "forest")
			if fc.is_empty():
				lose(p, "wood", 1)
				return false
			var start := await _choose_city(p, "Incendio: quale tua città in Foresta brucia?", fc)
			var seen := {start["h"]: true}
			var qq := [start["h"]]
			while not qq.is_empty():
				var x2: String = qq.pop_front()
				for y in neighbors(x2):
					if not seen.has(y) and ter(y) == "forest":
						seen[y] = true
						qq.append(y)
			for k7 in seen:
				var c7 := city_at(k7)
				if not c7.is_empty() and c7["o"] >= 0:
					await event_mood(c7["o"], c7)
			log_msg("Un incendio divampa nelle foreste.")
		"prosperous":
			var counts := []
			for q in n:
				counts.append(cities_of(q).size())
			var mx: int = counts.max()
			var mn: int = counts.min()
			for q in n:
				if mx == mn:
					gain(q, "food", 1)
				elif counts[q] == mn:
					gain(q, "food", mx - mn)
	return false


## Pandemia: a scelta 1 Umore, Cultura, risorsa, carta Azione, carta Obiettivo o unità.
func _pandemic_loss(q: int) -> void:
	var labels := []
	var kinds := []
	if res(q, "mood") > 0:
		labels.append("1 Umore")
		kinds.append("mood")
	if res(q, "culture") > 0:
		labels.append("1 Cultura")
		kinds.append("culture")
	for r in D.RES:
		if res(q, r) > 0:
			labels.append("1 " + D.RES_NAME[r])
			kinds.append(r)
	if not players[q]["hand"].is_empty():
		labels.append("1 carta Azione")
		kinds.append("hand")
	if not players[q]["obj"].is_empty():
		labels.append("1 carta Obiettivo")
		kinds.append("obj")
	if not units_of(q).is_empty():
		labels.append("1 unità")
		kinds.append("unit")
	if kinds.is_empty():
		return
	var i := await choose(q, "Pandemia: cosa perdi?", labels, {"force": true})
	match kinds[i]:
		"hand":
			discard("action", players[q]["hand"].pop_back(), q)
		"obj":
			discard("objective", players[q]["obj"].pop_back(), q)
		"unit":
			await _lose_unit(q, "Pandemia: quale unità perdi?")
		_:
			lose(q, kinds[i], 1)


# ------------------------------------------------------------------ pirati

func pirates_event(p: int) -> void:
	if civ_adv(p, "Pirate Allies") and pirates().size() >= 4:
		return
	# servono 2 navi pirata: se mancano si tolgono dal tabellone
	while supply_left(-2, "ship") < 2 and not pirates().is_empty():
		units.erase(pirates()[0]["id"])
	var free := []
	for k in hexes:
		if is_sea(k) and ships_at(k).filter(func(u): return u["o"] != -2).is_empty():
			free.append(k)
	if free.is_empty():
		return
	var near := []
	for c in cities_of(p):
		for x in neighbors(c["h"]):
			if free.has(x) and not near.has(x):
				near.append(x)
	var k1 := await choose_hex(p, "Pirati: dove compare la prima nave pirata%s?" % (" (vicino a una tua città)" if not near.is_empty() else ""), near if not near.is_empty() else free)
	new_unit(-2, "ship", k1)
	var k2 := await choose_hex(p, "Pirati: dove compare la seconda nave pirata?", free)
	new_unit(-2, "ship", k2)
	log_msg("Compaiono i Pirati!")
	fx.emit("barbarians", {"h": k1})
	changed.emit()
	# razzia: chi ha una città accanto a una nave pirata perde 1 risorsa, Umore o Cultura
	for q in _order_from(p):
		if civ_adv(q, "Pirate Allies"):
			continue
		var hit := cities_of(q).filter(func(c): return neighbors(c["h"]).any(func(x): return not ships_at(x, -2).is_empty()))
		if hit.is_empty():
			continue
		var labels := []
		var kinds := []
		for r in D.RES + ["mood", "culture"]:
			if res(q, r) > 0:
				labels.append("1 " + D.RES_NAME.get(r, "Cultura"))
				kinds.append(r)
		if kinds.is_empty():
			await event_mood(q, await _choose_city(q, "Razzia dei pirati: quale città peggiora l'umore?", hit.filter(func(c): return c["mood"] > 0)))
		else:
			var i := await choose(q, "Razzia dei pirati: cosa perdi?", labels, {"force": true})
			lose(q, kinds[i], 1)
		log_msg("I Pirati razziano le coste di %s." % pname(q))


## Barbari: un rinforzo in una loro città (con l'espansione può essere Cavalleria o Elefante).
func _barb_reinforce(p: int, k: String) -> void:
	var t := "infantry"
	if exp and not armies_at(k, -1).filter(func(u): return u["t"] == "infantry").is_empty():
		var types := ["infantry"]
		for x in ["cavalry", "elephant"]:
			if supply_left(-1, x) > 0:
				types.append(x)
		if types.size() > 1:
			t = types[await choose(p, "Barbari: quale unità arriva?", types.map(func(x): return D.U_NAME[x]), {"force": true})]
	if supply_left(-1, t) > 0:
		new_unit(-1, t, k)


func _lose_unit(q: int, title: String) -> void:
	var us := units_of(q)
	if us.is_empty():
		return
	var labels := []
	for u in us:
		labels.append("%s in %s" % [D.U_NAME[u["t"]], _hex_label(u["h"])])
	var i := await choose(q, title, labels, {"hexes": us.map(func(u): return u["h"]), "force": true})
	if lcode(q) == "l03" and leader_at(q, us[i]["h"]) and us[i]["t"] != "leader" and city_at(us[i]["h"]).get("o", -9) == q:
		log_msg("Marqzen salva l'unità nella sua città.")
		return
	remove_unit(us[i])


## Toglie fino a k pezzi da una città (2 PV a chi possiede ogni pezzo, le meraviglie valgono il solito).
func _destroy_city_pieces(c: Dictionary, k: int, kill_units := false) -> int:
	var removed := 0
	for b in c["b"].keys():
		if removed >= k:
			break
		var o: int = c["b"][b]
		if o >= 0:
			players[o]["vp_extra"] += 2
		c["b"].erase(b)
		removed += 1
	while removed < k and not c["w"].is_empty():
		var w: String = c["w"].pop_back()
		var o2: int = c["o"]
		if o2 >= 0:
			players[o2]["vp_extra"] += 5.0 if w == "great_pyramids" else 4.0
		wonder_builder.erase(w)
		removed += 1
	if removed < k:
		if c["o"] >= 0:
			players[c["o"]]["vp_extra"] += 2
		if kill_units:
			for u in units_at(c["h"]):
				remove_unit(u)
		cities.erase(c["id"])
		removed += 1
	return removed


func _earthquake(q: int) -> void:
	var k := await choose(q, "Terremoto: quanti pezzi di città togli?", ["1", "2", "3"], {"force": true}) + 1
	var left := k
	var hit := {}
	while left > 0 and not cities_of(q).is_empty():
		var c := await _choose_city(q, "Terremoto: da quale città togli un pezzo (%d rimasti)?" % left, cities_of(q))
		_destroy_city_pieces(c, 1)
		left -= 1
		hit[c["id"]] = true
	for cid in hit:
		if cities.has(cid):
			await event_mood(q, cities[cid])
	log_msg("Terremoto: %s perde %d pezzi di città (2 PV ciascuno)." % [pname(q), k])


## Grandi personaggi: chi li pesca può tenerli pagando 1 Cultura, altrimenti passano a sinistra (2 Cultura).
func _great_person_keep(p: int, id: String) -> bool:
	for i in n:
		var q := (p + i) % n
		var cost := 1 if i == 0 else 2
		if res(q, "culture") < cost:
			continue
		if await yes_no(q, "%s: lo tieni come carta Azione pagando %d Cultura?" % [D.EVENTS[id][0], cost], "Sì, lo tengo", "No"):
			lose(q, "culture", cost)
			log_msg("%s accoglie %s." % [pname(q), D.EVENTS[id][0]])
			match D.EVENTS[id][2]:
				"gp_architect":
					players[q]["architect"] = 3
					log_msg("Grande architetto: 3 Cultura per la prossima Meraviglia di %s." % pname(q))
				"gp_diplomat":
					var others := range(n).filter(func(x): return x != q)
					if others.is_empty():
						discards["event"].append(id)
					else:
						var b := await _choose_player(q, "Grande diplomatico: con chi stringi il patto?", others)
						diplomat = {"a": q, "b": b}
						log_msg("Grande diplomatico: chi fra %s e %s attacca l'altro dovrà pagargli 2 Cultura." % [pname(q), pname(b)])
				_:
					players[q]["hand"].append(id)
			return true
	return false


# ------------------------------------------------------------------ barbari

func _barb_spawn_spots(p: int) -> Array:
	var mine := cities_of(p).map(func(c): return c["h"])
	var others := []
	for id in cities:
		if cities[id]["o"] >= 0 and cities[id]["o"] != p:
			others.append(cities[id]["h"])
	var cand2 := []
	var cand1 := []
	for k in hexes:
		if not is_land(k) or ter(k) == "barren" or hexes[k]["exhausted"]:
			continue
		if not units_at(k).is_empty() or not city_at(k).is_empty():
			continue
		var ok_o := true
		for o in others:
			if dist_revealed(k, o, 2) < 2:
				ok_o = false
		if not ok_o:
			continue
		var ds := mine.map(func(m): return dist_revealed(k, m, 3))
		if ds.is_empty():
			continue
		var mn: int = ds.min()
		if mn == 2:
			cand2.append(k)
		elif mn == 1:
			cand1.append(k)
	return cand2 if not cand2.is_empty() else cand1


func barbarians_spawn(p: int, full: bool) -> void:
	var spots := _barb_spawn_spots(p)
	if not spots.is_empty() and supply_left(-1, "settlement") > 0:
		var k := await choose_hex(p, "Barbari: dove compare il loro insediamento?", spots)
		new_city(-1, k, 1)
		new_unit(-1, "infantry", k)
		log_msg("Compare un insediamento barbaro vicino a %s!" % pname(p))
		fx.emit("barbarians", {"h": k})
	if not full:
		return
	var bc := []
	for c in cities_of(-1):
		if armies_at(c["h"]).size() < 4:
			bc.append(c["h"])
	if not bc.is_empty() and supply_left(-1, "infantry") > 0:
		var k2 := await choose_hex(p, "Barbari: in quale loro città arriva un rinforzo?", bc)
		await _barb_reinforce(p, k2)
	changed.emit()


func barbarians_move(p: int) -> void:
	var mine := cities_of(p).map(func(c): return c["h"])
	if mine.is_empty():
		return
	var groups := {}
	for u in units_of(-1):
		if not is_army(u):
			continue
		for m in mine:
			if _land_dist(u["h"], m, 2) <= 2:
				groups[u["h"]] = groups.get(u["h"], []) + [u["id"]]
				break
	if groups.is_empty():
		await barbarians_spawn(p, false)
		return
	if exp:
		# Silla: i Barbari entro 2 caselle da lui muovono solo con il suo consenso
		for q in n:
			if lcode(q) != "l42":
				continue
			var sh: String = leader_unit(q)["h"]
			for g0 in groups.keys():
				if hdist(g0, sh) <= 2 and (q == p or not await yes_no(q, "Silla: lasci muovere i Barbari vicini a lui verso %s?" % pname(p))):
					groups.erase(g0)
		# Alleati tribali (Celti): 1 Cibo per fermare i Barbari
		if civ_adv(p, "Tribal Allies") and res(p, "food") >= 1 and not groups.is_empty():
			if await yes_no(p, "Alleati tribali: paghi 1 Cibo perché i Barbari non si muovano?"):
				lose(p, "food", 1)
				groups.clear()
		# Tribù unne: 1 Oro o 1 Cultura per mandare i Barbari verso le città degli altri
		if civ_adv(p, "Hunnic Tribes") and (res(p, "gold") >= 1 or res(p, "culture") >= 1) and not groups.is_empty():
			var others := []
			for id in cities:
				if cities[id]["o"] >= 0 and cities[id]["o"] != p:
					others.append(cities[id]["h"])
			if not others.is_empty() and await yes_no(p, "Tribù unne: paghi 1 Oro o 1 Cultura per dirigere i Barbari verso gli avversari?"):
				lose(p, "gold" if res(p, "gold") >= 1 else "culture", 1)
				mine = others
		if groups.is_empty():
			log_msg("I Barbari restano fermi.")
			return
	log_msg("I Barbari si muovono verso %s!" % pname(p))
	for g in groups.keys():
		var grp := []
		for uid in groups[g]:
			if units.has(uid) and units[uid]["h"] == g:
				grp.append(units[uid])
		if grp.is_empty():
			continue
		# passo verso la città più vicina (distanza su terra)
		var best := ""
		var bd := 99
		for x in neighbors(g):
			if not is_land(x):
				continue
			var own := armies_at(x, -1).size()
			if own + grp.size() > 4 and city_at(x).is_empty():
				continue
			for m in mine:
				var d := _land_dist(x, m, 4)
				if d < bd:
					bd = d
					best = x
		if best == "":
			continue
		var target := best
		if has_enemy(target, -1):
			for u in grp:
				u["h"] = target
			fx.emit("move", {"from": g, "to": target})
			await barbarian_attack(grp, target)
		else:
			for u in grp:
				u["h"] = target
			fx.emit("move", {"from": g, "to": target})
	for c in cities_of(-1):
		for m in mine:
			if _land_dist(c["h"], m, 2) <= 2 and armies_at(c["h"]).size() < 4 and supply_left(-1, "infantry") > 0:
				await _barb_reinforce(p, c["h"])
				break
	changed.emit()


func _land_dist(a: String, b: String, maxd: int) -> int:
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
			if seen.has(y) or not is_land(y):
				continue
			if y == b:
				return d + 1
			seen[y] = d + 1
			q.append(y)
	return 99


# ------------------------------------------------------------------ obiettivi

func obj_parts(id: String) -> Array:
	var o := D.objective_card(id)
	return [o[1], o[2]]


func _done_names(p: int) -> Array:
	return players[p]["done"].map(func(d): return d["obj"])


func complete_objective(p: int, id: String, key: String) -> void:
	players[p]["obj"].erase(id)
	players[p]["done"].append({"card": id, "obj": key, "age": age})
	log_msg("%s completa l'obiettivo «%s» (+2 PV)." % [pname(p), D.OBJ[key][0]])
	fx.emit("objective", {"p": p, "key": key})
	changed.emit()


func check_now(p: int, what: String, data: Dictionary) -> void:
	if p < 0:
		return
	var used_names := {}
	for id in players[p]["obj"].duplicate():
		for key in obj_parts(id):
			if D.OBJ[key][1] != "now" or used_names.has(key):
				continue
			if _now_ok(p, key, what, data):
				used_names[key] = true
				complete_objective(p, id, key)
				break


func _now_ok(p: int, key: String, what: String, d: Dictionary) -> bool:
	match key:
		"draconian":
			return cities_of(p).filter(func(c): return c["mood"] == 0).size() >= 4
		"draft":
			return T.get("p", -1) == p and T.get("draft_recruits", 0) >= 2
		"new_founder":
			return what == "found" and hdist(d["h"], players[p]["home"]) >= 5
		"warmonger":
			return T.get("p", -1) == p and T.get("battles", []).size() >= 2 and _distinct(T["battles"]) >= 2 and T.get("battle_wins", 0) >= 1
	if what == "battle":
		var won: bool = d.get("won", false)
		var naval: bool = d.get("naval", false)
		var q: int = d.get("defender", -1)
		match key:
			"daring":
				if not won or naval or not d.get("vs_army", false):
					return false
				var opp: int = d.get("opp", -1)
				if opp >= 0 and _cat_count(opp, "Warfare") > _cat_count(p, "Warfare"):
					return true
				return d.get("theirs", 0) > d.get("mine", 0)
			"defiance":
				return not d.get("attacker", true) and d.get("killed", 0) >= 2
			"legend":
				return d.get("attacker", false) and d.get("start_att", 0) >= 3 and (d.get("size", 0) >= 5 or d.get("wonder", false))
			"great_battle":
				return won and not naval and d.get("start_att", 0) + d.get("start_def", 0) >= 6
			"aggressor":
				return d.get("attacker", false) and q >= 0 and d.get("killed", 0) >= 2
			"warlord":
				return d.get("killed", 0) >= 3 and not naval
			"against_odds":
				return won and d.get("opp", -1) >= 0 and d.get("mine", 0) < d.get("theirs", 0)
			"marauder":
				return q >= 0 and has_adv(q, "Trade Routes") and (d.get("killed_settler", 0) > 0 or d.get("killed_ship", 0) > 0)
			"great_commander":
				return won and not naval and d.get("leader_in", false) and d.get("mine", 0) <= d.get("theirs", 0)
			"king_slayer":
				return won and d.get("killed_leader", false) and d.get("killed", 0) >= 2
			"stampede":
				return won and not naval and d.get("attacker", false) and d.get("vs_army", false) and d.get("beasts_alive", false)
			"cleanse_seas":
				return won and naval and d.get("pirates", false) and T.get("pirate_wins", 0) >= 2
	if what == "capture":
		match key:
			"assimilator":
				return d.get("barb", false) and d.get("defenders", 0) >= 2
			"amphibious":
				return not d.get("barb", false) and d.get("from_ship", false)
			"conqueror":
				return not d.get("barb", false) and d.get("defended", false)
	return false


static func _distinct(a: Array) -> int:
	var s := {}
	for x in a:
		s[x] = true
	return s.size()


func _cat_count(p: int, cat: String) -> int:
	var k := 0
	for a in D.ADV[cat]:
		if players[p]["adv"].has(a[0]):
			k += 1
	return k


func _count_cities_with(p: int, b: String) -> int:
	return cities_of(p).filter(func(c): return c["b"].has(b)).size()


func _more_than_all(p: int, f: Callable) -> bool:
	var mine: float = f.call(p)
	if mine <= 0:
		return false
	for q in n:
		if q != p and f.call(q) >= mine:
			return false
	return true


func status_ok(p: int, key: String, done_now: Array) -> bool:
	match key:
		"focused":
			return _more_than_all(p, func(q): return D.CATEGORIES.filter(func(c): return _cat_count(q, c) == 4).size())
		"diverse":
			var types := {}
			for c in cities_of(p):
				for b in c["b"]:
					if c["b"][b] == p:
						types[b] = true
			return types.size() >= 4
		"militarized":
			return _cat_count(p, "Warfare") == 4
		"culture":
			return _cat_count(p, "Traditions") == 4
		"enlightened":
			return _cat_count(p, "Education") == 4
		"seafarer":
			return _cat_count(p, "Maritime") == 4
		"merchant":
			return _cat_count(p, "Economy") == 4
		"city_planner":
			return _cat_count(p, "Construction") == 4
		"science":
			return _cat_count(p, "Science") == 4
		"consulates":
			return influenced_count(p)["cities"] >= 2
		"colony":
			if players[p]["done"].any(func(d): return d["obj"] == "new_founder" and d["age"] == age):
				return false
			return cities_of(p).any(func(c): return hdist(c["h"], players[p]["home"]) >= 5)
		"threat":
			for q in n:
				if q == p:
					continue
				for c in cities_of(q):
					var k := 0
					for x in neighbors(c["h"]):
						if is_land(x):
							k += armies_at(x, p).size()
					if k >= 4:
						return true
			return false
		"wonderful":
			if wonders_this_age.size() == 1 and wonders_this_age.has(p):
				return true
			var builders := {}
			for w in wonder_builder:
				builders[wonder_builder[w]] = true
			return builders.size() == 1 and builders.has(p)
		"outposts":
			var mine := cities_of(p).map(func(c): return c["h"])
			var spots := {}
			for u in units_of(p).filter(func(x): return is_army(x)):
				if u["on"] != -1 or not is_land(u["h"]):
					continue
				var bad := mine.has(u["h"])
				for x in neighbors(u["h"]):
					if mine.has(x):
						bad = true
				if not bad:
					spots[u["h"]] = true
			return spots.size() >= 3
		"blockade":
			for id in cities:
				var c: Dictionary = cities[id]
				if c["o"] >= 0 and c["o"] != p and c["port"] != "" and ships_at(c["port"], p).size() >= 2:
					return true
			return false
		"government":
			if _done_names(p).has("government") or done_now.has("government"):
				return false
			for g in D.GOVERNMENTS:
				if _cat_count(p, g) == 4:
					return true
			return false
		"religious":
			return _more_than_all(p, func(q): return _count_cities_with(q, "temple"))
		"fortified":
			return _more_than_all(p, func(q): return _count_cities_with(q, "fortress"))
		"academic":
			return _more_than_all(p, func(q): return _count_cities_with(q, "academy"))
		"coastal":
			return _more_than_all(p, func(q): return _count_cities_with(q, "port"))
		"ore", "wood", "food", "ideas", "rich":
			var r: String = {"ore": "ore", "wood": "wood", "food": "food", "ideas": "idea", "rich": "gold"}[key]
			return res(p, r) >= 5
		"great_army":
			var mine2 := _army_count(p)
			for q in n:
				if q != p and _army_count(q) + 4 > mine2:
					return false
			return true
		"balanced":
			return D.CATEGORIES.filter(func(c): return _cat_count(p, c) >= 1).size() >= 9
		"influence":
			return _more_than_all(p, func(q): return influenced_count(q)["buildings"])
		"advanced":
			return adv_count(p) >= 6 and _more_than_all(p, func(q): return adv_count(q))
		"standing_army":
			if done_now.has("military_might"):
				return false
			return cities_of(p).filter(func(c): return not armies_at(c["h"], p).is_empty()).size() >= 4
		"military_might":
			if done_now.has("standing_army"):
				return false
			return _army_count(p) + units_of(p, "ship").size() >= 12
		"dominion":
			var k2 := 0
			for c in cities_of(p):
				var lonely := true
				for x in neighbors(c["h"]):
					if not city_at(x).is_empty():
						lonely = false
				if lonely:
					k2 += 1
			return k2 >= 4
		"citadel":
			return cities_of(p).any(func(c): return city_size(c) >= 5)
		"trader":
			if done_now.has("sea_lanes"):
				return false
			return trade_routes(p)["count"] >= 3
		"sea_lanes":
			if done_now.has("trader"):
				return false
			return trade_routes(p)["ships"] >= 2
		"civilization":
			return cities_of(p).size() >= 6
		"well_stocked":
			return res(p, "food") >= 3 and res(p, "ore") >= 3 and res(p, "wood") >= 3
		"great_navy":
			var s := units_of(p, "ship").size()
			if s >= 4:
				return true
			for q in n:
				if q != p and units_of(q, "ship").size() + 2 > s:
					return false
			return s > 0
		"happy":
			return cities_of(p).filter(func(c): return c["mood"] == 2).size() >= 4
		# espansione Civiltà
		"scientists":
			return _more_than_all(p, func(q): return _count_cities_with(q, "observatory"))
		"mercantile":
			return _more_than_all(p, func(q): return _count_cities_with(q, "market"))
		"legacy":
			return _more_than_all(p, func(q): return _obelisks_of(q))
		"equestrian":
			return _armies_with(p, "cavalry") >= 3
		"ivory_tide":
			return _armies_with(p, "elephant") >= 3
		"tactical_diversity":
			for t in ["ship", "infantry", "cavalry", "elephant", "leader", "settler"]:
				if units_of(p, t).is_empty():
					return false
			return true
		"great_migration":
			var ss := units_of(p, "settler")
			var mine3 := cities_of(p).map(func(c): return c["h"])
			var ok_s := []
			for u in ss:
				var far := true
				for m in mine3:
					if hdist(u["h"], m) < 2:
						far = false
				if far:
					ok_s.append(u["h"])
			# almeno 3 coloni a 2 o più caselle l'uno dall'altro
			for i in ok_s.size():
				for j in range(i + 1, ok_s.size()):
					for k in range(j + 1, ok_s.size()):
						if hdist(ok_s[i], ok_s[j]) >= 2 and hdist(ok_s[i], ok_s[k]) >= 2 and hdist(ok_s[j], ok_s[k]) >= 2:
							return true
			return false
		"civ_of_ages":
			var ck: String = players[p].get("civ", "")
			if ck == "":
				return false
			for ca in CivData.CIVS[ck]["adv"]:
				if not players[p]["adv"].has(ca[0]):
					return false
			return int(players[p].get("leaders_ever", 0)) >= 2
	return false


func _army_count(p: int) -> int:
	return units_of(p).filter(func(u): return is_army(u)).size()


func _obelisks_of(p: int) -> int:
	var k := 0
	for id in cities:
		if cities[id]["b"].get("obelisk", -9) == p:
			k += 1
	return k


## Numero di caselle diverse in cui p ha un'armata con almeno un'unità di quel tipo.
func _armies_with(p: int, t: String) -> int:
	var spots := {}
	for u in units_of(p, t):
		spots[u["h"]] = true
	return spots.size()


func _status_objectives(p: int) -> void:
	var done_now := []
	for id in players[p]["obj"].duplicate():
		var parts := obj_parts(id)
		var ok := []
		for key in parts:
			if D.OBJ[key][1] == "status" and not done_now.has(key) and status_ok(p, key, done_now):
				ok.append(key)
		if ok.is_empty():
			continue
		var key: String = ok[0]
		if ok.size() > 1:
			var i := await choose(p, "Quale obiettivo completi con questa carta?", ok.map(func(k): return D.OBJ[k][0]), {"force": true})
			key = ok[i]
		var costs := {"ore": "ore", "wood": "wood", "food": "food", "ideas": "idea", "rich": "gold"}
		if costs.has(key):
			if not await yes_no(p, "Completi «%s» pagando 2 %s?" % [D.OBJ[key][0], D.RES_NAME[costs[key]]], "Sì", "No"):
				continue
			lose(p, costs[key], 2)
		done_now.append(key)
		complete_objective(p, id, key)


# ------------------------------------------------------------------ fase di status

func status_phase() -> void:
	log_msg("— Fase di status dell'era %d" % age)
	fx.emit("status", {"age": age})
	for i in n:
		await _status_objectives((first + i) % n)
	for i in n:
		var p := (first + i) % n
		var lst := []
		for a in D.all_advances():
			if can_buy_adv(p, a):
				lst.append(a)
		if not lst.is_empty():
			var a := await _choose_adv(p, "Fase di status: scegli l'avanzamento gratuito", lst)
			await gain_advance(p, a, true)
			if opts.get("short", false):
				lst = D.all_advances().filter(func(x): return can_buy_adv(p, x))
				if not lst.is_empty():
					await gain_advance(p, await _choose_adv(p, "Secondo avanzamento gratuito", lst), false)
	for i in n:
		var p := (first + i) % n
		draw_action(p)
		draw_objective(p)
	for i in n:
		var p := (first + i) % n
		var small := cities_of(p).filter(func(c): return city_size(c) == 1)
		if not small.is_empty() and cities_of(p).size() > 1:
			var labels := ["Nessuna"]
			for c in small:
				labels.append(_hex_label(c["h"]))
			var j := await choose(p, "Fase di status: radi al suolo una città di dimensione 1 (+1 Oro)?", labels,
				{"force": true, "hexes": [""] + small.map(func(c): return c["h"])})
			if j > 0:
				var c2: Dictionary = small[j - 1]
				for u in units_at(c2["h"]):
					pass
				cities.erase(c2["id"])
				gain(p, "gold", 1)
				log_msg("%s rade al suolo una sua città." % pname(p))
	for i in n:
		var p := (first + i) % n
		if gov_of(p) != "" and res(p, "culture") >= 1 and res(p, "mood") >= 1:
			await change_government(p, true)
	# primo giocatore
	var decider := -1
	for q in n:
		if owns_wonder(q, "great_lighthouse"):
			decider = q
	if decider < 0:
		var best := -1
		for i in n:
			var q := (first + i) % n
			var v := res(q, "mood") + res(q, "culture")
			if v > best:
				best = v
				decider = q
	var lst2 := []
	for q in n:
		lst2.append(q)
	first = await _choose_player(decider, "Fase di status: chi sarà il primo giocatore?", lst2)
	log_msg("%s sceglie %s come primo giocatore." % [pname(decider), pname(first)])
	changed.emit()


func change_government(p: int, paid: bool) -> void:
	var g := gov_of(p)
	if g == "":
		return
	var cands := []
	for g2 in D.GOVERNMENTS:
		if g2 != g and players[p]["adv"].has(D.GOV_REQ[g2]):
			cands.append(g2)
	if cands.is_empty():
		return
	var labels := ["Mantieni %s" % D.CAT_NAME[g]] if paid else []
	for g2 in cands:
		labels.append("Passa a %s" % D.CAT_NAME[g2])
	var i := await choose(p, "Cambio di governo" + (" (1 Cultura e 1 Umore)" if paid else ""), labels, {"force": true})
	if paid:
		if i == 0:
			return
		i -= 1
		lose(p, "culture", 1)
		lose(p, "mood", 1)
	var ng: String = cands[i]
	var k := _cat_count(p, g)
	for a in D.ADV[g]:
		players[p]["adv"].erase(a[0])
	var new_list := [D.ADV[ng][0][0]]
	var rest := []
	for a in D.ADV[ng].slice(1):
		rest.append(a[0])
	while new_list.size() < k and not rest.is_empty():
		var j := await choose(p, "Scegli un avanzamento di %s" % D.CAT_NAME[ng], rest.map(func(x): return D.adv_it(x)), {"force": true})
		new_list.append(rest[j])
		rest.remove_at(j)
	for a in new_list:
		players[p]["adv"].append(a)
	log_msg("%s passa a %s." % [pname(p), D.CAT_NAME[ng]])


# ------------------------------------------------------------------ fine partita

func final_scoring() -> void:
	game_over = true
	results.clear()
	for p in n:
		var s := score(p)
		results.append({"p": p, "score": s, "total": s["total"]})
	var pyr: int = wonder_builder.get("great_pyramids", -9)
	results.sort_custom(func(a, b):
		if a["total"] != b["total"]:
			return a["total"] > b["total"]
		if a["p"] == pyr:
			return true
		if b["p"] == pyr:
			return false
		if a["score"]["pieces"] != b["score"]["pieces"]:
			return a["score"]["pieces"] > b["score"]["pieces"]
		if a["score"]["adv"] != b["score"]["adv"]:
			return a["score"]["adv"] > b["score"]["adv"]
		return a["score"]["obj"] > b["score"]["obj"])
	log_msg("— Fine della partita!")
	for r in results:
		log_msg("%s: %.1f punti." % [pname(r["p"]), r["total"]])
	changed.emit()
	game_ended.emit(results)


## Impronta della partita (per verificare che due dispositivi online abbiano giocato la stessa).
func fingerprint() -> String:
	var parts := []
	for p in n:
		parts.append("%s:%s:%d:%d" % [players[p]["name"], str(players[p]["res"]), players[p]["adv"].size(), cities_of(p).size()])
	parts.append(str(age))
	return ",".join(parts).md5_text()
