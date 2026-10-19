extends "res://scripts/core/engine_combat.gd"
## Espansione Civiltà: azioni speciali degli avanzamenti di civiltà e dei Leader, pagamenti alternativi
## (Umore, Idee, Prigionieri), influenza estesa, rotte commerciali delle civiltà e altre regole proprie.

# ---- definite in engine.gd (qui servono solo le firme)
func play_card(_p: int, _m: Dictionary) -> bool:
	return false


func playable_cards(_p: int) -> Array:
	return []


func card_kind(_id: String) -> String:
	return ""


func barbarians_spawn(_p: int, _full: bool) -> void:
	pass


# ------------------------------------------------------------------ scelte comuni

func _choose_city(p: int, title: String, cs: Array) -> Dictionary:
	if cs.is_empty():
		return {}
	var keys := []
	for c in cs:
		keys.append(c["h"])
	var k := await choose_hex(p, title, keys)
	return city_at(k)


func _choose_adv(p: int, title: String, lst: Array) -> String:
	if lst.is_empty():
		return ""
	var i := await choose(p, title, lst.map(func(a): return "%s (%s)" % [D.adv_it(a), D.CAT_NAME[D.adv_info(a)["cat"]]]), {"advances": lst, "force": true})
	return lst[i]


func _choose_player(p: int, title: String, lst: Array) -> int:
	if lst.is_empty():
		return -1
	var i := await choose(p, title, lst.map(func(q): return pname(q)), {"force": true})
	return lst[i]


# ------------------------------------------------------------------ azioni speciali dell'espansione

const XNAME := {
	"x_sacrifice": "Sacrificio Umano: un Prigioniero per 1 Cultura o 1 Umore",
	"x_hegemony": "Egemonia: una Nave fonda una città sulla costa (azione)",
	"x_calendar": "Calendario: guarda il prossimo Evento",
	"x_bands": "Bande Combattenti: Coloni ↔ Fanteria (azione)",
	"x_tallies": "Tribù Alleate: fai comparire i Barbari (azione)",
	"x_nomads": "Nomadi: una città di dimensione 1 si sposta (azione)",
	"x_aqueducts": "Acquedotti: Fognature come azione gratuita",
	"x_l41": "Cesare: aumenta la felicità della sua città",
	"x_l40": "Augusto: carta Azione e Obiettivo (azione, 1 Cultura)",
	"x_ladv": "Leader: avanzamento per 1 Cultura o 1 Umore (azione)",
	"x_l44a": "Erik il Rosso: rivendica la regione (azione, 1 Cultura)",
	"x_l44b": "Erik il Rosso: sbarco dalla Nave",
	"x_l43": "Canuto: Tassazione senza Umore (azione)",
	"x_l19": "Alessandro: gioca una carta «come azione» (1 Cultura)",
	"x_l35": "Dario: costruisci nella sua città (2 Cultura)",
	"x_l34": "Ciro: Cultura o Umore per le regioni (azione)",
	"x_l16": "Cleopatra: 1 Cultura a difesa della sua città",
	"x_lwonder": "Leader: Meraviglia nella sua città (azione gratuita)",
	"x_l30": "Suiko: un pezzo influenzato torna tuo (1 Cultura)",
	"x_l27": "Sri Gupta: avanzamento in una nuova categoria (1 Cultura)",
	"x_l08": "Annone: muovi un gruppo di Navi",
	"x_l09": "Didone: fonda una città (azione gratuita)",
	"x_l03": "Marqzen: sposta un'unità nemica vicina (azione)",
	"x_l01": "Acamapichtli: raccogli dalla sua città (2 Umore)",
	"x_l02": "Ahuitzotl: costruisci sacrificando 2 Prigionieri",
	"x_l04": "Hammurabi: la sua città diventa Felice (azione, 1 Cultura)",
}

const LEADER_ADV_CAT := {"l38": "Construction", "l21": "Education", "l15": "Warfare", "l13": "Agriculture"}


func exp_specials(p: int) -> Array:
	var out := []
	if not exp or p < 0:
		return out
	var acts: int = T["actions"]
	var pl: Dictionary = players[p]
	var cul := res(p, "culture")
	if civ_adv(p, "Human Sacrifice") and int(pl.get("captives", 0)) > 0:
		out.append("x_sacrifice")
	if civ_adv(p, "Hegemony") and acts > 0 and not _hegemony_spots(p).is_empty():
		out.append("x_hegemony")
	if civ_adv(p, "Calendar") and not T.get("x_calendar", false) and not decks["event"].is_empty():
		out.append("x_calendar")
	if civ_adv(p, "Fighting Bands") and acts > 0 and not T.get("x_bands", false) and not _bands_options(p).is_empty():
		out.append("x_bands")
	if civ_adv(p, "Tribal Allies") and acts > 0 and not T.get("x_tallies", false):
		out.append("x_tallies")
	if civ_adv(p, "Nomads") and acts > 0 and not _nomad_options(p).is_empty():
		out.append("x_nomads")
	if civ_adv(p, "Aqueducts") and can_buy_adv(p, "Sanitation"):
		out.append("x_aqueducts")
	var code := lcode(p)
	if code == "":
		return out
	var lc := leader_city(p)
	var lu := leader_unit(p)
	match code:
		"l41":
			if not lc.is_empty() and lc["mood"] < 2 and can_activate(lc) and can_pay_mood(p, city_size(lc)):
				out.append("x_l41")
		"l40":
			if acts > 0 and not lc.is_empty() and cul >= 1 and can_activate(lc):
				out.append("x_l40")
		"l38", "l21", "l15", "l13":
			if acts > 0 and not lc.is_empty() and lc["mood"] == 2 and cul + res(p, "mood") >= 1 and not _leader_adv_list(p).is_empty():
				out.append("x_ladv")
		"l44":
			if lu["on"] != -1:
				var ri := region_of(lu["h"])
				if acts > 0 and cul >= 1 and not pl.get("erik", []).has(ri):
					out.append("x_l44a")
				if not _l44_dests(p).is_empty():
					out.append("x_l44b")
		"l43":
			if acts > 0 and not lc.is_empty() and lc["mood"] == 2 and has_adv(p, "Taxation") and can_activate(lc):
				out.append("x_l43")
		"l19":
			if not lc.is_empty() and cul >= 1 and can_activate(lc) and not _action_cards(p).is_empty():
				out.append("x_l19")
		"l35":
			if not T.get("x_l35", false) and cul >= 2 and not lc.is_empty() and not _builds_in(p, lc, 2).is_empty():
				out.append("x_l35")
		"l34":
			if acts > 0 and not lc.is_empty() and can_activate(lc):
				out.append("x_l34")
		"l16":
			if not T.get("x_l16", false) and cul >= 1 and not lc.is_empty():
				out.append("x_l16")
		"l14", "l06":
			if not lc.is_empty() and not _wonders_in(p, lc).is_empty():
				out.append("x_lwonder")
		"l30":
			if not lc.is_empty() and cul >= 1 and (acts > 0 or has_adv(p, "State Religion")) and not _suiko_pieces(p, lc).is_empty():
				out.append("x_l30")
		"l27":
			if not lc.is_empty() and cul >= 1 and can_activate(lc) and not _new_cat_advances(p).is_empty():
				out.append("x_l27")
		"l08":
			if not T.get("x_l08", false) and lu["on"] != -1 and not mv_flag(lu["on"], "moved") and not mv_flag(lu["on"], "battled"):
				out.append("x_l08")
		"l09":
			for u in land_units_at(lu["h"], p):
				if u["t"] == "settler" and can_found_at(p, u["h"]):
					out.append("x_l09")
					break
		"l03":
			if acts > 0 and not T.get("x_l03", false) and not _terror_options(p).is_empty():
				out.append("x_l03")
		"l01":
			if not T.get("x_l01", false) and res(p, "mood") >= 2 and not lc.is_empty() and city_size(lc) <= 3 and can_activate(lc):
				out.append("x_l01")
		"l02":
			if not T.get("x_l02", false) and int(pl.get("captives", 0)) >= 2 and not lc.is_empty() and not _builds_in(p, lc, 0).is_empty():
				out.append("x_l02")
		"l04":
			if acts > 0 and not lc.is_empty() and lc["mood"] < 2 and cul >= 1:
				out.append("x_l04")
	return out


func _hegemony_spots(p: int) -> Array:
	var out := []
	if supply_left(p, "settlement") <= 0:
		return out
	for s in units_of(p, "ship"):
		for x in neighbors(s["h"]):
			if is_land(x) and not out.has(x) and city_at(x).is_empty() and not has_enemy(x, p) and not hexes[x]["exhausted"] \
					and (ter(x) != "barren" or civ_adv(p, "Flood Plains")):
				out.append(x)
	return out


func _bands_options(p: int) -> Array:
	var out := []
	for u in units_of(p):
		if u["on"] != -1:
			continue
		if u["t"] == "settler" and supply_left(p, "infantry") > 0 and armies_at(u["h"], p).size() < stack_limit(p, u["h"]):
			out.append(u)
		elif u["t"] == "infantry" and supply_left(p, "settler") > 0:
			out.append(u)
	return out


func _nomad_options(p: int) -> Array:
	var out := []
	for c in cities_of(p):
		if city_size(c) != 1 or c["mood"] == 0 or not can_activate(c):
			continue
		for x in neighbors(c["h"]):
			if is_land(x) and city_at(x).is_empty() and not has_enemy(x, p):
				out.append([c, x])
	return out


func _leader_adv_list(p: int) -> Array:
	var cat: String = LEADER_ADV_CAT.get(lcode(p), "")
	var out := []
	if cat == "":
		return out
	for a in D.ADV[cat]:
		if can_buy_adv(p, a[0]):
			out.append(a[0])
	return out


func _l44_dests(p: int) -> Array:
	var lu := leader_unit(p)
	var out := []
	if lu.is_empty() or lu["on"] == -1:
		return out
	var n_army := 0
	for u in units_at(lu["h"]):
		if u["o"] == p and u["on"] != -1 and is_army(u):
			n_army += 1
	for x in neighbors(lu["h"]):
		if is_land(x) and not has_enemy(x, p) and armies_at(x, p).size() + n_army <= stack_limit(p, x):
			out.append(x)
	return out


func _action_cards(p: int) -> Array:
	var out := []
	var save: int = T["actions"]
	T["actions"] = maxi(save, 1)
	for id in playable_cards(p):
		var k := card_kind(id)
		if k in ["spies", "explorers", "new_goals", "city_growth", "tech_synergy", "idea_synergy", "mercenaries", "cultural_awe"] \
				or k.begins_with("gp_"):
			out.append(id)
	T["actions"] = save
	return out


## Edifici (e meraviglie) costruibili nella città del Leader, senza attivarla. extra_cul: Cultura già impegnata.
func _builds_in(p: int, c: Dictionary, extra_cul: int) -> Array:
	var out := []
	for b in bld_list():
		if can_build(p, c, b, true) == "":
			var save := res(p, "culture")
			players[p]["culture"] = maxi(0, save - extra_cul)
			if can_pay_build(p, c, b):
				out.append(b)
			players[p]["culture"] = save
	for w in _wonders_in(p, c, true):
		out.append(w)
	return out


func _wonders_in(p: int, c: Dictionary, ignore_act := true) -> Array:
	var out := []
	for w in players[p]["won"]:
		if can_build_wonder(p, c, w, 0, ignore_act) == "":
			out.append(w)
	return out


func _suiko_pieces(p: int, c: Dictionary) -> Array:
	var out := []
	for b in c["b"]:
		if c["b"][b] != p and b != "obelisk" and supply_left(p, b) > 0:
			out.append(b)
	return out


func _new_cat_advances(p: int) -> Array:
	var out := []
	for cat in D.CATEGORIES:
		var any := false
		for a in D.ADV[cat]:
			if players[p]["adv"].has(a[0]):
				any = true
		if any:
			continue
		for a in D.ADV[cat]:
			if can_buy_adv(p, a[0]) and can_pay(p, {"food": adv_food_cost(p, a[0])}, ["idea"]):
				out.append(a[0])
	return out


func _terror_options(p: int) -> Array:
	var lu := leader_unit(p)
	var out := []
	if lu.is_empty() or lu["on"] != -1:
		return out
	for x in neighbors(lu["h"]):
		for u in units_at(x):
			if u["o"] != p and u["t"] != "ship" and u["on"] == -1 and u["t"] != "leader":
				for y in neighbors(x):
					if is_land(y) and y != lu["h"] and city_at(y).is_empty() and units_at(y).filter(func(v): return v["o"] != u["o"]).is_empty():
						out.append([u, y])
	return out


## Esegue un'azione speciale dell'espansione. Restituisce false se non si è fatto nulla.
func exp_special(p: int, w: String, m: Dictionary) -> bool:
	var lc := leader_city(p)
	var lu := leader_unit(p)
	match w:
		"x_sacrifice":
			var i := await choose(p, "Sacrificio Umano: un Prigioniero diventa…", ["1 Cultura", "1 Umore", "Annulla"], {"force": true})
			if i == 2:
				return false
			players[p]["captives"] -= 1
			gain(p, "culture" if i == 0 else "mood", 1)
			log_msg("%s sacrifica un Prigioniero." % pname(p))
		"x_hegemony":
			var spots := _hegemony_spots(p)
			var k := await choose_hex(p, "Egemonia: dove fondi la città?", spots)
			var ship := {}
			for s in units_of(p, "ship"):
				if k in neighbors(s["h"]):
					ship = s
					break
			if ship.is_empty():
				return false
			spend_action(false)
			for u in carried(ship["id"]):
				u["on"] = -1
				u["h"] = k
				set_mv(u["id"], "stop")
			units.erase(ship["id"])
			new_city(p, k, 1)
			log_msg("%s fonda una città con l'Egemonia (%s)." % [pname(p), D.TER_NAME[ter(k)]])
			fx.emit("found", {"h": k})
			await check_now(p, "found", {"h": k})
		"x_calendar":
			T["x_calendar"] = true
			var top: String = decks["event"].back()
			var opts := ["Lascialo dov'è"]
			if res(p, "culture") >= 1:
				opts.append("Paga 1 Cultura e mettilo in fondo al mazzo")
			var j := await choose(p, "Calendario: il prossimo Evento è «%s». %s" % [D.EVENTS[top][0], D.event_text(top)], opts, {"force": true, "cards": ["", ""]})
			if j == 1:
				lose(p, "culture", 1)
				decks["event"].pop_back()
				decks["event"].push_front(top)
				log_msg("%s consulta il Calendario e rimanda un evento." % pname(p))
		"x_bands":
			spend_action(false)
			T["x_bands"] = true
			for guard in 12:
				var lst := _bands_options(p)
				if lst.is_empty():
					break
				var labels := ["Fine"]
				for u in lst:
					labels.append("%s in %s → %s" % [D.U_NAME[u["t"]], _hex_label(u["h"]), "Fanteria" if u["t"] == "settler" else "Colono"])
				var jj := await choose(p, "Bande Combattenti: chi trasformi?", labels, {"force": true, "hexes": [""] + lst.map(func(u): return u["h"])})
				if jj == 0:
					break
				var uu: Dictionary = lst[jj - 1]
				uu["t"] = "infantry" if uu["t"] == "settler" else "settler"
			log_msg("%s riorganizza le sue bande armate." % pname(p))
		"x_tallies":
			spend_action(false)
			T["x_tallies"] = true
			log_msg("%s chiama i suoi alleati tribali." % pname(p))
			await barbarians_spawn(p, true)
		"x_nomads":
			var lst2 := _nomad_options(p)
			var labels2 := []
			for o in lst2:
				labels2.append("%s → %s (%s)" % [_hex_label(o[0]["h"]), _hex_label(o[1]), D.TER_NAME[ter(o[1])]])
			var n2 := await choose(p, "Nomadi: quale città si sposta e dove?", labels2 + ["Annulla"], {"force": true, "hexes": lst2.map(func(o): return o[1]) + [""]})
			if n2 >= lst2.size():
				return false
			var c2: Dictionary = lst2[n2][0]
			var dest: String = lst2[n2][1]
			spend_action(false)
			activate(c2)
			var old: String = c2["h"]
			var bring := land_units_at(old, p)
			if not bring.is_empty() and not await yes_no(p, "Nomadi: le unità nella città la seguono?", "Sì", "No"):
				bring = []
			c2["h"] = dest
			c2["port"] = ""
			c2["b"].erase("port")
			for u in bring:
				u["h"] = dest
			var tr: String = D.TER_RES.get(ter(dest), "")
			if tr != "":
				gain(p, tr, 1)
			log_msg("%s sposta una città nomade." % pname(p))
			after_activation(c2)
		"x_aqueducts":
			await gain_advance(p, "Sanitation", true)
		"x_l41":
			var steps := 1
			if lc["mood"] == 0 and can_pay_mood(p, city_size(lc) * 2):
				steps = 2 if await choose(p, "Cesare: di quanto aumenti la felicità?", ["Di un passo", "Fino a Felice"], {"force": true}) == 1 else 1
			activate(lc)
			pay_mood(p, city_size(lc) * steps)
			change_mood(lc, steps)
			log_msg("Cesare rallegra la sua città.")
			after_activation(lc)
		"x_l40":
			spend_action(false)
			activate(lc)
			lose(p, "culture", 1)
			draw_action(p)
			draw_objective(p)
			for kind in [["hand", "action", "carta Azione"], ["obj", "objective", "carta Obiettivo"]]:
				var lstc: Array = players[p][kind[0]]
				if lstc.is_empty():
					continue
				var jc := await choose(p, "Augusto: quale %s scarti?" % kind[2], lstc.map(func(x): return D.card_title(x)), {"force": true, "cards": lstc.duplicate()})
				var cid: String = lstc[jc]
				lstc.erase(cid)
				discard(kind[1], cid, p)
			after_activation(lc)
		"x_ladv":
			var lst3 := _leader_adv_list(p)
			var a := await _choose_adv(p, "%s: quale avanzamento?" % CivData.LEADERS[lcode(p)][0], lst3)
			spend_action(false)
			if res(p, "culture") >= 1 and (res(p, "mood") < 1 or await choose(p, "Paghi con…", ["1 Cultura", "1 Umore"], {"force": true}) == 0):
				lose(p, "culture", 1)
			else:
				lose(p, "mood", 1)
			await gain_advance(p, a, true)
		"x_l44a":
			spend_action(false)
			lose(p, "culture", 1)
			var ri := region_of(lu["h"])
			if not players[p].has("erik"):
				players[p]["erik"] = []
			players[p]["erik"].append(ri)
			log_msg("Erik il Rosso rivendica una regione per %s (+1 PV)." % pname(p))
		"x_l44b":
			var dests := _l44_dests(p)
			var d2 := await choose_hex(p, "Erik il Rosso: dove sbarcano?", dests)
			var from: String = lu["h"]
			for u in units_at(from):
				if u["o"] == p and u["on"] != -1:
					u["on"] = -1
					u["h"] = d2
					set_mv(u["id"], "moved")
			log_msg("Erik il Rosso sbarca.")
		"x_l43":
			spend_action(false)
			activate(lc)
			var k3 := cities_of(p).size()
			var kinds := ["food", "ore", "wood"] + (["gold"] if has_adv(p, "Currency") else [])
			for i3 in k3:
				var r3 := await choose(p, "Danegeld: tassa %d di %d" % [i3 + 1, k3], kinds.map(func(x): return D.RES_NAME[x]), {"force": true})
				gain(p, kinds[r3], 1)
			log_msg("Canuto il Grande riscuote il Danegeld.")
			after_activation(lc)
		"x_l19":
			var cards := _action_cards(p)
			var jj2 := await choose(p, "Alessandro: quale carta giochi?", cards.map(func(x): return D.card_title(x)) + ["Annulla"], {"force": true, "cards": cards + [""]})
			if jj2 >= cards.size():
				return false
			lose(p, "culture", 1)
			activate(lc)
			T["free_next"] = true
			if T["actions"] <= 0:
				T["actions"] += 1
				T["free_next"] = false
				T["refund_after"] = true
			await play_card(p, {"t": "card", "id": cards[jj2]})
			T["free_next"] = false
			T.erase("refund_after")
			after_activation(lc)
		"x_l35", "x_l02":
			var opts4 := _builds_in(p, lc, 2 if w == "x_l35" else 0)
			var lab4 := opts4.map(func(x): return D.B_NAME[x] if D.B_NAME.has(x) else D.WONDERS[x]["it"])
			var j4 := await choose(p, "Cosa costruisci nella città del Leader?", lab4 + ["Annulla"], {"force": true})
			if j4 >= opts4.size():
				return false
			if w == "x_l35":
				T["x_l35"] = true
				lose(p, "culture", 2)
			else:
				T["x_l02"] = true
				players[p]["captives"] -= 2
			var what: String = opts4[j4]
			if D.WONDERS.has(what):
				await do_wonder(p, lc["id"], what, false, false)
			else:
				await do_build(p, lc["id"], what, false, false, false)
		"x_l34":
			spend_action(false)
			activate(lc)
			var regs := {}
			for c in cities_of(p):
				regs[region_of(c["h"])] = true
			var k4 := mini(regs.size(), city_size(lc))
			var j5 := await choose(p, "Ciro il Grande: %d segnalini, cosa prendi?" % k4, ["Cultura", "Umore"], {"force": true})
			gain(p, "culture" if j5 == 0 else "mood", k4)
			after_activation(lc)
		"x_l16":
			T["x_l16"] = true
			lose(p, "culture", 1)
			lc["cleo"] = int(lc.get("cleo", 0)) + 1
			log_msg("Cleopatra protegge la sua città (%d Cultura)." % lc["cleo"])
		"x_lwonder":
			var ws := _wonders_in(p, lc)
			var j6 := await choose(p, "Quale Meraviglia costruisci nella città del Leader?", ws.map(func(x): return D.WONDERS[x]["it"]) + ["Annulla"], {"force": true})
			if j6 >= ws.size():
				return false
			await do_wonder(p, lc["id"], ws[j6], false, false)
		"x_l30":
			var pcs := _suiko_pieces(p, lc)
			var j7 := await choose(p, "Suiko: quale pezzo torna del tuo colore?", pcs.map(func(x): return D.B_NAME[x]) + ["Annulla"], {"force": true})
			if j7 >= pcs.size():
				return false
			if not has_adv(p, "State Religion"):
				spend_action(false)
			lose(p, "culture", 1)
			lc["b"][pcs[j7]] = p
			log_msg("L'imperatrice Suiko riporta il %s sotto %s." % [D.B_NAME[pcs[j7]], pname(p)])
		"x_l27":
			var lst8 := _new_cat_advances(p)
			var a8 := await _choose_adv(p, "Età dell'oro: avanzamento in una nuova categoria", lst8)
			activate(lc)
			lose(p, "culture", 1)
			pay(p, {"food": adv_food_cost(p, a8)}, ["idea"])
			await gain_advance(p, a8, true)
			after_activation(lc)
		"x_l08":
			T["x_l08"] = true
			T["move_only"] = "ships"
			await do_move_action(p, true, 1)
			T.erase("move_only")
		"x_l09":
			for u in land_units_at(lu["h"], p):
				if u["t"] == "settler" and can_found_at(p, u["h"]):
					log_msg("La regina Didone fonda una città.")
					return await do_found(p, u["id"])
			return false
		"x_l03":
			var ops := _terror_options(p)
			var lab9 := ops.map(func(o): return "%s di %s → %s" % [D.U_NAME[o[0]["t"]], pname(o[0]["o"]), _hex_label(o[1])])
			var j9 := await choose(p, "Diffondere il terrore: quale unità spaventi?", lab9 + ["Annulla"], {"force": true, "hexes": ops.map(func(o): return o[1]) + [""]})
			if j9 >= ops.size():
				return false
			spend_action(false)
			T["x_l03"] = true
			ops[j9][0]["h"] = ops[j9][1]
			log_msg("Marqzen mette in fuga un'unità di %s." % pname(ops[j9][0]["o"]))
		"x_l01":
			var picks: Array = m.get("picks", [])
			if picks.is_empty():
				picks = auto_collect(lc)
			if not valid_collect(lc, picks):
				return false
			T["x_l01"] = true
			lose(p, "mood", 2)
			var okc: bool = await do_collect(p, lc["id"], picks, "", false, true)
			if not okc:
				gain(p, "mood", 2)
				T["x_l01"] = false
			return okc
		"x_l04":
			spend_action(false)
			lose(p, "culture", 1)
			lc["mood"] = 2
			log_msg("Hammurabi rende Felice la sua città.")
		_:
			return false
	changed.emit()
	return true


# ------------------------------------------------------------------ rotte commerciali delle civiltà

## Rendita delle rotte con le regole delle civiltà: restituisce {"count", "alt": [scelte], …}.
func trade_bonus(p: int, tr: Dictionary) -> void:
	var pairs: Array = tr.get("pairs", [])
	if pairs.is_empty():
		return
	# Pigmalione: +1 Oro o Cultura per la rotta del Colono o della Nave con cui si trova
	if lcode(p) == "l39":
		for pr in pairs:
			if units.has(pr[0]) and leader_at(p, units[pr[0]]["h"]) and units[pr[0]]["t"] in ["settler", "ship"]:
				var j := await choose(p, "Pigmalione, mercante del Mediterraneo: ricevi…", ["+1 Oro", "+1 Cultura"], {"force": true})
				gain(p, "gold" if j == 0 else "culture", 1)
				break
	# Saccheggiatori (Vichinghi): le navi abbinate a città adiacenti fanno perdere 1 risorsa al proprietario
	if civ_adv(p, "Marauders"):
		var hit := {}
		for pr in pairs:
			if not units.has(pr[0]) or not cities.has(pr[1]):
				continue
			var u: Dictionary = units[pr[0]]
			var c: Dictionary = cities[pr[1]]
			if u["t"] == "ship" and hdist(u["h"], c["h"]) == 1 and c["o"] >= 0 and not hit.has(c["o"]):
				hit[c["o"]] = true
				var q: int = c["o"]
				var have := D.RES.filter(func(r): return res(q, r) > 0)
				if have.is_empty():
					continue
				var jq := await choose(q, "Saccheggiatori vichinghi: quale risorsa perdi?", have.map(func(r): return D.RES_NAME[r]), {"force": true})
				lose(q, have[jq], 1)
				log_msg("I predoni di %s saccheggiano %s." % [pname(p), pname(q)])


## Alfabeto e Prosperità: alcune rotte danno Cultura, Idee o Umore invece del Cibo. Restituisce quante rotte
## restano per il Cibo.
func trade_alt(p: int, k: int) -> int:
	if not (civ_adv(p, "Alphabet") or civ_adv(p, "Prosperity")):
		return k
	var alpha := 0
	var left := k
	for i in k:
		var opts := ["Cibo (o Oro)"]
		var kinds := ["food"]
		if civ_adv(p, "Alphabet") and alpha < 2:
			opts += ["1 Cultura (Alfabeto)", "2 Idee (Alfabeto)"]
			kinds += ["culture", "idea"]
		if civ_adv(p, "Prosperity"):
			opts.append("1 Umore (Prosperità)")
			kinds.append("mood")
		var j := await choose(p, "Rotta commerciale %d di %d: cosa porta?" % [i + 1, k], opts, {"force": true})
		match kinds[j]:
			"culture":
				gain(p, "culture", 1)
				alpha += 1
				left -= 1
			"idea":
				gain(p, "idea", 2)
				alpha += 1
				left -= 1
			"mood":
				gain(p, "mood", 1)
				left -= 1
	return left
