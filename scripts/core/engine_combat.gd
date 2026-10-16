extends "res://scripts/core/engine_actions.gd"
## Movimento (terra, navi, imbarco e sbarco, Strade, Navigazione), battaglie di terra e navali,
## conquista delle città, barbari.

# ------------------------------------------------------------------ movimento

func mv_flag(uid: int, f: String) -> bool:
	return T["mv"].get(uid, {}).get(f, false)


func set_mv(uid: int, f: String) -> void:
	if not T["mv"].has(uid):
		T["mv"][uid] = {}
	T["mv"][uid][f] = true


## Mari raggiungibili da una nave (attraverso mari collegati, senza passare navi nemiche).
func sea_reach(h: String, p: int, nav := false) -> Dictionary:
	var seen := {h: true}
	var q := [h]
	var starts_edge := false
	while not q.is_empty():
		var x: String = q.pop_front()
		if x != h and _enemy_ship(x, p):
			continue
		var nb := neighbors(x)
		for y in nb:
			if seen.has(y) or not is_sea(y):
				continue
			seen[y] = true
			q.append(y)
	if nav:
		# Navigazione: dai mari sul bordo si raggiungono gli altri mari sul bordo
		var edge_any := false
		for x in seen:
			if on_edge(x) and not (x != h and _enemy_ship(x, p)):
				edge_any = true
		if edge_any:
			var extra := []
			for k in hexes:
				if is_sea(k) and on_edge(k) and not seen.has(k):
					extra.append(k)
			for e in extra:
				if seen.has(e):
					continue
				seen[e] = "nav"
				var q2 := [e]
				while not q2.is_empty():
					var x2: String = q2.pop_front()
					if _enemy_ship(x2, p):
						continue
					for y2 in neighbors(x2):
						if seen.has(y2) or not is_sea(y2):
							continue
						seen[y2] = "nav"
						q2.append(y2)
	return seen


func _enemy_ship(k: String, p: int) -> bool:
	for u in ships_at(k):
		if u["o"] != p and not (u["o"] == -2 and civ_adv(p, "Pirate Allies")):
			return true
	return false


## Unità di terra trasportabili da una nave (3 con i Drakkar vichinghi).
func ship_cap(p: int) -> int:
	return 3 if civ_adv(p, "Longships") else 2


## Gruppo valido: stesse unità del giocatore nella stessa posizione. Restituisce {kind, h} o {}.
func group_info(p: int, ids: Array) -> Dictionary:
	if ids.is_empty():
		return {}
	var h := ""
	var kind := ""
	for id in ids:
		var uid := int(id)
		if not units.has(uid):
			return {}
		var u: Dictionary = units[uid]
		if u["o"] != p:
			return {}
		if mv_flag(uid, "battled") or mv_flag(uid, "stop") or T.get("mv_this", {}).has(uid):
			return {}
		var k2 := "ship" if u["t"] == "ship" else ("cargo" if u["on"] != -1 else "land")
		if h == "":
			h = u["h"]
			kind = k2
		elif h != u["h"] or kind != k2:
			return {}
	return {"kind": kind, "h": h}


func group_has_army(ids: Array) -> bool:
	for id in ids:
		if is_army(units[int(id)]):
			return true
	return false


func _ship_room(k: String, p: int) -> int:
	var room := 0
	for s in ships_at(k, p):
		room += ship_cap(p) - carried(s["id"]).size()
	return room


func can_attack(p: int, target: int) -> bool:
	if target < 0:
		return true
	var key := "%d,%d" % [mini(p, target), maxi(p, target)]
	if negotiation.has(key):
		return false
	if _diplomat_pact(p, target) and res(p, "culture") < 2:
		return false
	return true


## E57 Grande Diplomatico: fra i due giocatori del patto chi attacca paga 2 Cultura all'altro.
func _diplomat_pact(a: int, b: int) -> bool:
	if diplomat.is_empty() or a < 0 or b < 0:
		return false
	return (diplomat["a"] == a and diplomat["b"] == b) or (diplomat["a"] == b and diplomat["b"] == a)


func _diplomat_pay(p: int, q: int) -> void:
	if not _diplomat_pact(p, q):
		return
	var k := lose(p, "culture", 2)
	gain(q, "culture", k)
	log_msg("Grande Diplomatico: %s paga %d Cultura a %s per attaccare; il patto finisce." % [pname(p), k, pname(q)])
	diplomat = {}
	discards["event"].append("e57")


## Destinazioni possibili per un gruppo: casella -> {kind, battle, roads, explore}
func move_targets(p: int, ids: Array) -> Dictionary:
	var out := {}
	var g := group_info(p, ids)
	if g.is_empty():
		return out
	var h: String = g["h"]
	var army := group_has_army(ids)
	if army and not has_adv(p, "Tactics"):
		return out
	var forest := false
	var plains := false
	for id in ids:
		if mv_flag(int(id), "forest"):
			forest = true
		if mv_flag(int(id), "plains"):
			plains = true
	if g["kind"] == "ship":
		var reach: Dictionary = sea_reach(h, p, has_adv(p, "Navigation"))
		for k in reach:
			if k == h:
				continue
			var battle := _enemy_ship(k, p)
			out[k] = {"kind": "sea", "battle": battle, "nav": reach[k] is String}
		# esplorazione con le navi
		var seen_r := {}
		for k in reach:
			for y in nbr_keys(k):
				if hexes.has(y) and not revealed(y):
					var ri := region_of(y)
					if not seen_r.has(ri):
						seen_r[ri] = true
						out[y] = {"kind": "explore_sea", "battle": false, "from_sea": k}
		return out
	var n_army := 0
	for id in ids:
		if is_army(units[int(id)]):
			n_army += 1
	for x in neighbors(h):
		if not revealed(x):
			if g["kind"] == "land":
				out[x] = {"kind": "explore", "battle": false}
			continue
		if is_sea(x):
			if g["kind"] == "land" and not _enemy_ship(x, p) and _ship_room(x, p) >= ids.size():
				out[x] = {"kind": "embark", "battle": false}
			continue
		var r := _land_dest(p, x, ids, n_army, army, forest, plains)
		if not r.is_empty():
			r["kind"] = "disembark" if g["kind"] == "cargo" else "land"
			out[x] = r
	# Strade: da o verso una propria città, fino a 2 caselle, ignorando il terreno
	if g["kind"] == "land" and has_adv(p, "Roads") and can_pay(p, {"food": 1, "ore": 1}):
		var from_city: bool = not city_at(h).is_empty() and city_at(h)["o"] == p
		for x in neighbors(h):
			if not is_land(x):
				continue
			for y in [x] + neighbors(x):
				if y == h or not is_land(y) or out.has(y) and y != x:
					continue
				var to_city: bool = not city_at(y).is_empty() and city_at(y)["o"] == p
				if not from_city and not to_city:
					continue
				if y != x and has_enemy(x, p):
					continue
				var r2 := _land_dest(p, y, ids, n_army, army, false, false)
				if r2.is_empty():
					continue
				r2["kind"] = "land"
				r2["roads"] = true
				if not out.has(y):
					out[y] = r2
				elif not out[y].has("roads"):
					out[y]["roads_opt"] = true
	return out


func _land_dest(p: int, x: String, ids: Array, n_army: int, army: bool, forest: bool, plains: bool) -> Dictionary:
	var enemy := has_enemy(x, p)
	if enemy:
		if not army or forest:
			return {}
		var c := city_at(x)
		var owner := -1
		if not c.is_empty():
			owner = c["o"]
		else:
			owner = enemy_units_at(x, p)[0]["o"]
		if not can_attack(p, owner):
			return {}
		if plains and not c.is_empty() and "great_gardens" in c["w"]:
			return {}
		for u in enemy_units_at(x, p):
			if u["o"] != owner:
				return {}
		return {"battle": true, "target": owner}
	if armies_at(x, p).size() + n_army > 4:
		return {}
	return {"battle": false}


## Azione Muovi: fino a 3 gruppi.
func do_move_action(p: int, free := false) -> void:
	spend_action(free)
	T["mv_this"] = {}
	T["ships_moved"] = false
	T["nav_used"] = false
	var left := 3
	while left > 0 and not game_over:
		var r = await ask(p, {"type": "move", "left": left})
		if not (r is Dictionary) or r.get("done", false):
			break
		var ids: Array = r.get("units", [])
		var to: String = str(r.get("to", ""))
		var tg := move_targets(p, ids)
		if not tg.has(to):
			log_msg("Movimento non valido.")
			if players[p]["ai"] or online != null:
				break
			continue
		var roads: bool = tg[to].get("roads", false) or (tg[to].get("roads_opt", false) and r.get("roads", false))
		await move_group(p, ids, to, tg[to], roads)
		left -= 1
		changed.emit()
	T.erase("mv_this")
	if has_adv(p, "Cartography") and T.get("ships_moved", false):
		gain(p, "idea", 1)
		if T.get("nav_used", false):
			gain(p, "culture", 1)
		log_msg("Cartografia: %s riceve 1 Idea%s." % [pname(p), " e 1 Cultura" if T.get("nav_used", false) else ""])


func move_group(p: int, ids: Array, to: String, info: Dictionary, roads := false) -> void:
	var g := group_info(p, ids)
	var from: String = g["h"]
	var grp := []
	for id in ids:
		grp.append(units[int(id)])
		T["mv_this"][int(id)] = true
	if roads:
		pay(p, {"food": 1, "ore": 1})
	match info["kind"]:
		"sea":
			var cargo := []
			for s in grp:
				cargo += carried(s["id"])
				s["h"] = to
				set_mv(s["id"], "moved")
			for c in cargo:
				c["h"] = to
				T["mv_this"][c["id"]] = true
			T["ships_moved"] = true
			if info.get("nav", false):
				T["nav_used"] = true
			log_msg("%s muove %d %s." % [pname(p), grp.size(), "navi" if grp.size() > 1 else "nave"])
			fx.emit("move", {"from": from, "to": to})
			if info.get("battle", false):
				await naval_battle(p, grp, to, from)
		"explore_sea":
			var ri := region_of(to)
			await explore(p, ri, "", info["from_sea"])
			# la nave va in un mare della nuova regione raggiungibile, se c'è
			var reach: Dictionary = sea_reach(info["from_sea"], p, false)
			var dest := ""
			for k in regions[ri]["hexes"]:
				if is_sea(k):
					for y in neighbors(k):
						if reach.has(y) or y == info["from_sea"]:
							dest = k
			if dest == "":
				dest = info["from_sea"]
			for s in grp:
				for c in carried(s["id"]):
					c["h"] = dest
					T["mv_this"][c["id"]] = true
				s["h"] = dest
				set_mv(s["id"], "moved")
			T["ships_moved"] = true
		"explore":
			var ri2 := region_of(to)
			await explore(p, ri2, to)
			if not is_land(to):
				log_msg("La regione scoperta ha il mare in quella casella: le unità restano dove sono.")
				changed.emit()
				return
			for u in grp:
				u["h"] = to
				set_mv(u["id"], "moved")
				_terrain_flags(u, to)
			log_msg("%s entra nella nuova regione." % pname(p))
			if has_enemy(to, p):
				await land_battle(p, grp, to, from, false)
		"embark":
			var ships := ships_at(to, p)
			for u in grp:
				for s in ships:
					if carried(s["id"]).size() < ship_cap(p):
						u["on"] = s["id"]
						u["h"] = to
						break
				set_mv(u["id"], "moved")
			log_msg("%s imbarca %d unità." % [pname(p), grp.size()])
		"land", "disembark":
			for u in grp:
				u["h"] = to
				u["on"] = -1
				set_mv(u["id"], "moved")
				if not roads:
					_terrain_flags(u, to)
			fx.emit("move", {"from": from, "to": to})
			if info.get("battle", false):
				await land_battle(p, grp, to, from, info["kind"] == "disembark")
			else:
				log_msg("%s muove %d %s." % [pname(p), grp.size(), "unità"])
	changed.emit()


func _terrain_flags(u: Dictionary, k: String) -> void:
	match ter(k):
		"mountain":
			if civ_adv(u["o"], "Terracing") and u["t"] in ["settler", "leader"]:
				return
			if leader_is(u["o"], "l07") and leader_at(u["o"], k) and not units_of(u["o"], "elephant").filter(func(e): return e["h"] == k).is_empty():
				return
			set_mv(u["id"], "stop")
		"forest":
			set_mv(u["id"], "forest")
		"plains":
			set_mv(u["id"], "plains")


# ------------------------------------------------------------------ battaglie

func tactic_cards(p: int, kinds: String, attacker: bool, city_def: bool, attacking_city: bool) -> Array:
	var out := []
	if p < 0 or not has_adv(p, "Tactics"):
		return out
	for id in players[p]["hand"]:
		var a := D.action_card(id)
		if a.is_empty():
			continue
		var t: String = a[2]
		var info := D.tactic(t)
		var ok := false
		for ch in kinds:
			if ch in info["units"]:
				ok = true
		if not ok:
			continue
		if t in ["defiant_stand", "prepared_defenses", "tactical_retreat"] and attacker:
			continue
		if t in ["wedge", "flanking"] and not attacker:
			continue
		if t in ["for_the_people", "upgraded_defenses"] and not city_def:
			continue
		if t == "siege" and not attacking_city:
			continue
		if t == "high_ground" and attacking_city and attacker:
			continue
		if kinds == "S" and t in ["scouts", "martyr"]:
			continue
		out.append(id)
	return out


func _pick_tactic(p: int, kinds: String, attacker: bool, city_def: bool, attacking_city: bool, bt: Dictionary) -> String:
	var cards := tactic_cards(p, kinds, attacker, city_def, attacking_city)
	if cards.is_empty():
		return ""
	var labels := ["Nessuna carta"]
	for id in cards:
		var t: String = D.action_card(id)[2]
		labels.append("%s — %s" % [D.tactic(t)["it"], D.tactic(t)["text"]])
	var i := await choose(p, "Battaglia: giochi una tattica?", labels, {"force": true, "battle": true, "cards": [""] + cards})
	if i == 0:
		return ""
	var id: String = cards[i - 1]
	players[p]["hand"].erase(id)
	return id


func _side_units(bt: Dictionary, side: String) -> Array:
	var out := []
	for u in bt[side]:
		if units.has(u["id"]) and units[u["id"]]["h"] == bt["h"]:
			out.append(u)
	return out


func _fighters(bt: Dictionary, side: String) -> Array:
	var out := []
	for u in _side_units(bt, side):
		if bt["naval"]:
			if u["t"] == "ship":
				out.append(u)
		elif is_army(u) and u["on"] == -1:
			out.append(u)
	return out


## Battaglia di terra. Restituisce {"win": vince l'attaccante, "defender": chi difendeva}.
func land_battle(p: int, att: Array, h: String, from: String, from_ship: bool) -> Dictionary:
	var c := city_at(h)
	var defender := -1
	if not c.is_empty() and c["o"] != p:
		defender = c["o"]
	else:
		for u in enemy_units_at(h, p):
			defender = u["o"]
	var def_units := enemy_units_at(h, p)
	var def_army := []
	for u in def_units:
		if is_army(u) and u["on"] == -1:
			def_army.append(u)
	for u in att:
		set_mv(u["id"], "battled")
		set_mv(u["id"], "stop")
	T["battles"].append(h)
	var city_def: bool = not c.is_empty() and c["o"] == defender
	var fortress: bool = city_def and c["b"].has("fortress")
	var att_army := []
	for u in att:
		if is_army(u):
			att_army.append(u)
	_diplomat_pay(p, defender)
	# coloni soli: sconfitti senza combattere
	if def_army.is_empty() and not fortress:
		var killed_settlers := 0
		for u in def_units:
			if u["on"] == -1 and u["t"] != "ship":
				remove_unit(u, p)
				killed_settlers += 1
		T["battle_wins"] += 1
		if killed_settlers > 0:
			log_msg("%s elimina %d coloni di %s." % [pname(p), killed_settlers, pname(defender)])
		await check_now(p, "battle", {"won": true, "attacker": true, "defender": defender, "killed": 0, "lost": 0,
			"killed_settler": killed_settlers, "vs_army": false, "start_att": att_army.size(), "start_def": 0,
			"mine": att_army.size(), "theirs": 0, "opp": defender, "city": city_def,
			"size": city_size(c) if not c.is_empty() else 0, "wonder": not c.is_empty() and not c["w"].is_empty(), "h": h})
		if city_def:
			T["last_def"] = 0
			await capture_city(p, c, att, from_ship, false)
		changed.emit()
		return {"win": true, "defender": defender}
	var bt := {"att": att.duplicate(), "def": def_units.duplicate(), "p": p, "q": defender, "h": h, "naval": false,
		"round": 0, "city": city_def, "fortress": fortress, "log": [], "from_ship": from_ship, "kills": {}, "lk": {}}
	battle = bt
	fx.emit("battle_start", {"h": h, "p": p, "q": defender})
	log_msg("Battaglia: %s attacca %s%s." % [pname(p), pname(defender), " in città" if city_def else ""])
	# Grande Muraglia contro i barbari che attaccano (gestito nelle mosse barbare)
	# decisioni prima della battaglia
	var siege_die := false
	var siege_hit := false
	if fortress and has_adv(p, "Siegecraft"):
		if can_pay(p, {"wood": 2}) and await yes_no(p, "Arte d'assedio: paghi 2 Legno per annullare il dado in più della Fortezza?"):
			pay(p, {"wood": 2})
			siege_die = true
		if can_pay(p, {"ore": 2}) and await yes_no(p, "Arte d'assedio: paghi 2 Minerale per annullare il colpo annullato dalla Fortezza?"):
			pay(p, {"ore": 2})
			siege_hit = true
	var steel := {p: 0, defender: 0}
	for side in [p, defender]:
		if side < 0 or not has_adv(side, "Steel Weapons"):
			continue
		var other: int = defender if side == p else p
		var both: bool = other >= 0 and has_adv(other, "Steel Weapons")
		var free: bool = has_adv(side, "Metallurgy") and not both
		if free:
			steel[side] = 2
		elif can_pay(side, {"ore": 1}) and await yes_no(side, "Armi d'acciaio: paghi 1 Minerale per +%d in ogni round?" % (1 if both else 2)):
			pay(side, {"ore": 1})
			steel[side] = 1 if both else 2
	var fan := {}
	if city_def or (not c.is_empty() and c["b"].has("temple")):
		for side in [p, defender]:
			if side >= 0 and has_adv(side, "Fanaticism") and not c.is_empty() and c["b"].has("temple"):
				fan[side] = true
	var arena_used := {}
	var killed := {p: 0, defender: 0}
	var att_won := false
	var def_won := false
	var start_att := att_army.size()
	var start_def := def_army.size()
	var retreated := false
	var warlord: bool = T.get("warlord_bonus", false) and p == T.get("p", -1)
	if warlord:
		T["warlord_bonus"] = false
	# espansione: decisioni prima della battaglia (Akbar, Go-Toba, Cavallo di Troia, Eclissi)
	var trojan_used := false
	var one_round := false
	if exp:
		await _pre_battle_exp(bt, p, att_army)
		if defender >= 0:
			await _pre_battle_exp(bt, defender, def_army)
		if trojan and city_def and defender >= 0 and (not def_army.is_empty() or fortress) and can_pay(p, {"culture": 1, "wood": 1}):
			if await yes_no(p, "Cavallo di Troia: paghi 1 Cultura e 1 Legno perché il difensore non giochi carte nel 1° round?"):
				pay(p, {"culture": 1, "wood": 1})
				trojan = false
				trojan_used = true
				players[p]["vp_extra"] += 1.0
				log_msg("%s usa il Cavallo di Troia (+1 PV)." % pname(p))
		if eclipse and defender >= 0 and not def_army.is_empty():
			eclipse = false
			one_round = true
			log_msg("Eclissi solare: la battaglia dura un solo round.")
	while true:
		bt["round"] += 1
		var rnd: int = bt["round"]
		var A := _fighters(bt, "att")
		var Dd := _fighters(bt, "def")
		# carte
		var att_kinds := "A"
		var def_kinds: String = ("A" if not _fighters(bt, "def").is_empty() else "") + ("F" if fortress else "")
		var ca := ""
		if not (civ_adv(defender, "Spartans") and Dd.size() < A.size()):
			ca = await _pick_tactic(p, att_kinds, true, false, city_def, bt)
		var cd := ""
		var def_no_cards: bool = (trojan_used and rnd == 1) or (rnd == 1 and leader_is(p, "l23") and city_def and _leader_in(A, p))
		if defender >= 0 and not def_no_cards:
			cd = await _pick_tactic(defender, def_kinds, false, city_def, false, bt)
		var eff := {p: ca, defender: cd}
		for side in eff:
			if eff[side] != "":
				log_msg("%s gioca la tattica %s." % [pname(side), D.tactic(D.action_card(eff[side])[2])["it"]])
		var tac := {p: "", defender: ""}
		for side in eff:
			if eff[side] != "":
				tac[side] = D.action_card(eff[side])[2]
		# esploratori avanzati: annulla e prende la carta nemica
		for side in [p, defender]:
			var other: int = defender if side == p else p
			if tac[side] == "scouts" and eff[other] != "":
				log_msg("Esploratori avanzati: %s annulla la carta di %s e la prende." % [pname(side), pname(other)])
				players[side]["hand"].append(eff[other])
				eff[other] = ""
				tac[other] = ""
		# martirio
		for side in [p, defender]:
			var other: int = defender if side == p else p
			if tac[side] == "martyr":
				var mine := _fighters(bt, "att" if side == p else "def")
				var theirs := _fighters(bt, "def" if side == p else "att")
				if not mine.is_empty():
					remove_unit(mine[0])
				if not theirs.is_empty():
					remove_unit(theirs[0])
					killed[side] += 1
				if eff[other] != "":
					discard("action", eff[other], other)
					eff[other] = ""
					tac[other] = ""
				log_msg("Martirio: ciascuno perde un'unità.")
		var cancel := {p: 0, defender: 0}
		for side in [p, defender]:
			var other: int = defender if side == p else p
			var side_key := "att" if side == p else "def"
			var oth_key := "def" if side == p else "att"
			if tac[side] == "archers":
				var r := d6()
				if r >= 5:
					var th := _fighters(bt, oth_key)
					if not th.is_empty():
						remove_unit(th[0])
						killed[side] += 1
						log_msg("Arcieri: %s elimina subito un esercito." % pname(side))
			if tac[side] == "peltasts":
				var ok := false
				for i in _fighters(bt, side_key).size():
					if d6() >= 5:
						ok = true
				if ok:
					cancel[side] += 1
		# ritirata tattica del difensore
		if tac[defender] == "tactical_retreat" and defender >= 0:
			var dests := []
			for x in neighbors(h):
				if is_land(x) and not has_enemy(x, defender):
					dests.append(x)
			if not dests.is_empty():
				var dx := await choose_hex(defender, "Ritirata tattica: dove ti ritiri?", dests)
				for u in _side_units(bt, "def"):
					if u["t"] != "ship":
						u["h"] = dx
						u["on"] = -1
				log_msg("%s si ritira tatticamente: la battaglia è vinta da %s." % [pname(defender), pname(p)])
				_discard_tactics(eff)
				att_won = true
				break
		A = _fighters(bt, "att")
		Dd = _fighters(bt, "def")
		# tiri
		var dice_a := A.size()
		var dice_d := Dd.size()
		if rnd == 1 and fortress and not siege_die:
			dice_d += 1
		if tac[p] == "flanking":
			dice_a += 1
		if tac[defender] == "prepared_defenses":
			dice_d += 1
		if tac[defender] == "for_the_people" and city_def:
			dice_d += 1
		var no_clash_on_def: bool = tac[p] in ["high_ground", "siege"]
		var no_clash_on_att: bool = tac[defender] == "high_ground"
		if tac[p] == "siege" and defender >= 0 and can_pay(defender, {"food": 2}):
			if await yes_no(defender, "Assedio: paghi 2 Cibo per poter attivare le abilità di scontro?"):
				pay(defender, {"food": 2})
				no_clash_on_def = false
		var ra := _roll(A, dice_a - A.size(), not no_clash_on_att)
		var rd := _roll(Dd, dice_d - Dd.size(), not no_clash_on_def, _cav_bonus(defender, Dd, rnd, fortress))
		var cva: int = ra["cv"]
		var cvd: int = rd["cv"]
		if exp:
			cva += _exp_cv(bt, p, defender, A, Dd, rnd, true, ca != "")
			cvd += _exp_cv(bt, defender, p, Dd, A, rnd, false, cd != "")
			if fortress and leader_is(defender, "l29") and hdist(leader_unit(defender)["h"], h) <= 2:
				cvd += 2
		cva += steel[p] + (2 if tac[p] == "high_morale" else 0) + (1 if tac[p] == "tactical_surprise" else 0)
		cvd += steel.get(defender, 0) + (2 if tac[defender] == "high_morale" else 0) + (1 if tac[defender] == "tactical_surprise" else 0)
		if tac[p] == "wedge":
			cva += Dd.size()
		if tac[p] == "siege" and city_def:
			cva += 1
		if tac[defender] == "defiant_stand":
			cva -= A.size()
		if rnd == 1:
			if fan.has(p):
				cva += 2
			if fan.has(defender):
				cvd += 2
			if city_def and c["mood"] == 2 and defender >= 0 and owns_wonder(defender, "great_wall"):
				cva -= 2
		if warlord:
			cva += 2
		# Grande Arena: +1 dopo il tiro
		for side in [p, defender]:
			if side >= 0 and arena(side) and not arena_used.has(side) and (res(side, "mood") + res(side, "culture")) > 0:
				var mine_cv: int = cva if side == p else cvd
				var oth_cv: int = cvd if side == p else cva
				if (mine_cv + 1) / 5 > mine_cv / 5:
					if await yes_no(side, "Grande Arena: paghi 1 Umore o Cultura per +1 (valore %d)?" % mine_cv):
						if res(side, "mood") > 0:
							lose(side, "mood", 1)
						else:
							lose(side, "culture", 1)
						arena_used[side] = true
						if side == p:
							cva += 1
						else:
							cvd += 1
		cva = maxi(0, cva)
		cvd = maxi(0, cvd)
		var hits_a := cva / 5
		var hits_d := cvd / 5
		# annullamenti
		if rnd == 1 and fortress and not siege_hit:
			cancel[defender] += 1
		if tac[defender] == "upgraded_defenses" and city_def:
			cancel[defender] += 1
		if rnd == 1 and from_ship and has_adv(p, "Warships"):
			cancel[p] += 1
		cancel[p] += ra["cancel"]
		cancel[defender] += rd["cancel"]
		hits_a = maxi(0, hits_a - cancel[defender])
		hits_d = maxi(0, hits_d - cancel[p])
		if exp:
			hits_d = maxi(0, hits_d - await _exp_cancel(bt, p, A, rnd, true, hits_d))
			if defender >= 0:
				hits_a = maxi(0, hits_a - await _exp_cancel(bt, defender, Dd, rnd, false, hits_a))
		last_dice = {"att": ra["dice"], "def": rd["dice"], "cva": cva, "cvd": cvd}
		fx.emit("dice", {"att": ra["dice"], "def": rd["dice"], "cva": cva, "cvd": cvd, "p": p, "q": defender, "h": h})
		log_msg("Round %d: %s %d (%d colpi), %s %d (%d colpi)." % [rnd, pname(p), cva, hits_a, pname(defender), cvd, hits_d])
		await wait(1.1)
		# vittime
		var ka := _casualties(bt, "def", hits_a)
		var kd := _casualties(bt, "att", hits_d)
		killed[p] += ka
		killed[defender] += kd
		for side in [p, defender]:
			var other_key := "def" if side == p else "att"
			var mine_k: int = ka if side == p else kd
			var their_k: int = kd if side == p else ka
			if tac[side] == "routing" and mine_k >= their_k and d6() >= 5:
				var extra := _casualties(bt, other_key, 1)
				killed[side] += extra
				if extra > 0:
					log_msg("Rotta: %s elimina un'altra unità." % pname(side))
			if tac[side] == "tactical_surprise" and mine_k >= 1 and side >= 0:
				draw_action(side)
		_discard_tactics(eff)
		changed.emit()
		A = _fighters(bt, "att")
		Dd = _fighters(bt, "def")
		if A.is_empty() and Dd.is_empty():
			break
		if A.is_empty():
			def_won = true
			break
		if Dd.is_empty():
			att_won = true
			break
		var must_retreat := false
		if one_round:
			must_retreat = true
			players[defender]["vp_extra"] += 1.0
			log_msg("Eclissi solare: %s deve ritirarsi, %s tiene la carta (+1 PV)." % [pname(p), pname(defender)])
		if must_retreat or await yes_no(p, "La battaglia continua (%d contro %d). Ti ritiri?" % [A.size(), Dd.size()], "Continua", "Ritirati") == false:
			retreated = true
			for u in _side_units(bt, "att"):
				u["h"] = from
				if from_ship:
					var placed := false
					for sh in ships_at(from, p):
						if carried(sh["id"]).size() < ship_cap(p):
							u["on"] = sh["id"]
							placed = true
							break
					if not placed:
						remove_unit(u)
			log_msg("%s si ritira." % pname(p))
			break
	battle = {}
	if one_round and att_won:
		players[p]["vp_extra"] += 1.0
		log_msg("Eclissi solare: %s vince in un round e tiene la carta (+1 PV)." % pname(p))
	# coloni del difensore rimasti senza eserciti
	if att_won:
		for u in enemy_units_at(h, p):
			if u["t"] != "ship":
				remove_unit(u, p)
	if def_won:
		for u in _side_units(bt, "att"):
			remove_unit(u, defender)
	if not att_won and not def_won and not retreated:
		# nessuno resta: con l'ultimo esercito se ne vanno anche i coloni
		for u in units_at(h):
			if u["t"] != "ship":
				remove_unit(u)
	var lost_att: int = killed[defender]
	var lost_def: int = killed[p]
	if def_won and fan.has(p) or att_won and fan.has(defender):
		var loser: int = p if def_won else defender
		var cs := cities_of(loser)
		if not cs.is_empty() and supply_left(loser, "infantry") > 0:
			new_unit(loser, "infantry", cs[0]["h"])
			log_msg("Fanatismo: %s riceve una Fanteria." % pname(loser))
	if att_won:
		log_msg("%s vince la battaglia." % pname(p))
		if defender == -1 and start_def > 0:
			gain(p, "gold", 1)
		if start_def > 0:
			T["won_army"] = true
		T["battle_wins"] += 1
	elif def_won:
		log_msg("%s respinge l'attacco." % pname(defender))
		if p == -1 and defender >= 0:
			gain(defender, "gold", 1)
	fx.emit("battle_end", {"h": h, "att_won": att_won})
	if exp:
		await _after_battle_exp(bt, p, defender, att_won, def_won, killed, att_army, def_army)
	var info := {"won": att_won, "attacker": true, "defender": defender, "killed": lost_def, "lost": lost_att,
		"start_att": start_att, "start_def": start_def, "mine": start_att, "theirs": start_def, "opp": defender, "vs_army": start_def > 0, "city": city_def,
		"size": city_size(c) if not c.is_empty() else 0, "wonder": not c.is_empty() and not c["w"].is_empty(), "h": h,
		"leader_in": _leader_in(att_army, p), "killed_leader": bt["lk"].has(p), "beasts_alive": _beasts_alive(bt, "att")}
	await check_now(p, "battle", info)
	if defender >= 0:
		var info2 := info.duplicate()
		info2["won"] = def_won
		info2["attacker"] = false
		info2["killed"] = lost_att
		info2["lost"] = lost_def
		info2["mine"] = start_def
		info2["theirs"] = start_att
		info2["opp"] = p
		info2["leader_in"] = _leader_in(def_army, defender)
		info2["killed_leader"] = bt["lk"].has(defender)
		info2["beasts_alive"] = _beasts_alive(bt, "def")
		await check_now(defender, "battle", info2)
	T["last_def"] = start_def
	if att_won and city_def and city_at(h).get("id", -1) == c.get("id", -2):
		await capture_city(p, c, _side_units(bt, "att"), from_ship, true, start_def > 0 or fortress)
	changed.emit()
	return {"win": att_won, "defender": defender}


# ------------------------------------------------------------------ espansione: capi e civiltà in battaglia

func _pre_battle_exp(bt: Dictionary, side: int, army: Array) -> void:
	if side < 0 or not _leader_in(army, side):
		return
	var code: String = players[side]["leader"]
	if code in ["l25", "l28"] and can_pay(side, {"ore": 1}):
		var nm: String = CivData.LEADERS[code][0]
		var txt := "+1 per ogni Elefante" if code == "l25" else "+2"
		if await yes_no(side, "%s: paghi 1 Minerale per %s in ogni round?" % [nm, txt]):
			pay(side, {"ore": 1})
			bt["paid_%d" % side] = true


func _regions_with_city(p: int) -> int:
	var seen := {}
	var home_r := region_of(players[p]["home"])
	for c in cities_of(p):
		var r := region_of(c["h"])
		if r != home_r:
			seen[r] = true
	return seen.size()


func _warfare_count(p: int) -> int:
	var k := 0
	for a in D.ADV["Warfare"]:
		if players[p]["adv"].has(a[0]):
			k += 1
	return k


## Bonus al combattimento dei capi e degli avanzamenti di civiltà per il lato `me` in questo round.
func _exp_cv(bt: Dictionary, me: int, foe: int, mine: Array, theirs: Array, rnd: int, attacker: bool, card_played: bool) -> int:
	if not exp or me < 0:
		return 0
	var b := 0
	var h: String = bt["h"]
	var c := city_at(h)
	if bt["naval"]:
		var lu := leader_unit(me)
		var on_ship: bool = not lu.is_empty() and lu["h"] == h and lu["on"] != -1
		if on_ship and (leader_is(me, "l21") or leader_is(me, "l08")):
			b += 2
		if on_ship and leader_is(me, "l18") and foe == -2:
			b += 2
		if civ_adv(me, "Biremes") and (rnd == 1 or foe < 0 or not has_adv(foe, "Warships")):
			b += 2
		return b
	if civ_adv(me, "Tribal Warfare") and foe >= 0:
		var k := 0
		for id in cities:
			if cities[id]["o"] == -1 and hdist(cities[id]["h"], h) <= 2:
				k += 1
		b += mini(4, k)
	if not _leader_in(mine, me):
		return b
	match players[me]["leader"]:
		"l40":
			var own := false
			for x in regions[region_of(h)]["hexes"]:
				if not city_at(x).is_empty() and city_at(x)["o"] == me:
					own = true
			if not own:
				b += 2
		"l42":
			if foe == -1:
				b += 2
		"l25":
			if bt.get("paid_%d" % me, false):
				b += mine.filter(func(u): return u["t"] == "elephant").size()
		"l28":
			if bt.get("paid_%d" % me, false):
				b += 2
		"l45":
			if attacker and bt.get("from_ship", false):
				b += 2
		"l20":
			b += 2 * maxi(0, theirs.size() - mine.size())
		"l19":
			b += _regions_with_city(me)
		"l18":
			if attacker and not c.is_empty() and is_coastal(c):
				b += 2
		"l37":
			for oc in cities_of(me):
				if oc["b"].has("temple") and hdist(oc["h"], h) <= 2:
					b += 2
					break
		"l33":
			for oc in cities_of(me):
				if hdist(oc["h"], h) <= 2:
					b += 2
					break
		"l32":
			if rnd == 1 and attacker and not c.is_empty():
				b += city_size(c)
		"l30":
			if not attacker:
				b += 2
		"l10":
			if foe >= 0 and _warfare_count(foe) > _warfare_count(me):
				b += 2
		"l11":
			for u in units_of(me, "settler"):
				if hdist(u["h"], h) <= 2:
					b += 1
		"l13":
			if mine.size() >= theirs.size():
				b += 2
		"l27":
			if not card_played:
				b += 2
		"l06":
			if attacker and not c.is_empty() and c["b"].has("temple"):
				b += 2
		"l09":
			if not attacker and not c.is_empty() and c["o"] == me:
				b += 2
		"l05":
			if foe >= 0 and cities_of(foe).size() >= cities_of(me).size():
				b += 2
	return b


## Colpi annullati da capi e avanzamenti di civiltà (alcuni a pagamento, una volta per battaglia).
func _exp_cancel(bt: Dictionary, me: int, mine: Array, rnd: int, attacker: bool, incoming: int) -> int:
	if not exp or me < 0 or incoming <= 0:
		return 0
	var k := 0
	var h: String = bt["h"]
	var c := city_at(h)
	if rnd == 1 and civ_adv(me, "Fireworks") and can_pay(me, {"ore": 1, "wood": 1}):
		if await yes_no(me, "Fuochi d'artificio: paghi 1 Minerale e 1 Legno per annullare un colpo?"):
			pay(me, {"ore": 1, "wood": 1})
			k += 1
	if not _leader_in(mine, me) or k >= incoming:
		return k
	var nm: String = CivData.LEADERS[players[me]["leader"]][0]
	match players[me]["leader"]:
		"l02":
			var near := false
			for oc in cities_of(me):
				if hdist(oc["h"], h) <= 2:
					near = true
			if not near:
				k += 1
		"l31":
			if rnd == 1 and not attacker and not c.is_empty() and c["b"].get("obelisk", -9) == me:
				k += 1
		"l39":
			if not attacker and not c.is_empty() and c["o"] == me and not bt.has("once_%d" % me) and res(me, "culture") >= 1:
				if await yes_no(me, "%s: paghi 1 Cultura per annullare un colpo?" % nm):
					lose(me, "culture", 1)
					bt["once_%d" % me] = true
					k += 1
		"l14":
			if not bt.has("once_%d" % me) and res(me, "culture") >= 2:
				if await yes_no(me, "%s: paghi 2 Cultura per annullare un colpo?" % nm):
					lose(me, "culture", 2)
					bt["once_%d" % me] = true
					k += 1
	return k


func _after_battle_exp(bt: Dictionary, p: int, q: int, att_won: bool, def_won: bool, killed: Dictionary, att_army: Array, def_army: Array) -> void:
	var winner := p if att_won else (q if def_won else -9)
	for side in [p, q]:
		if side < 0:
			continue
		if civ_adv(side, "Embalming") and res(side, "culture") <= 4:
			gain(side, "culture", 1)
		var other: int = q if side == p else p
		# unità d'armata perse da `side` = uccise dall'avversario
		var lost_army: int = bt["kills"].get(other, 0) + (1 if bt["lk"].has(other) else 0)
		if civ_adv(side, "Runestones") and lost_army >= 2:
			players[side]["vp_extra"] += 1.0
			log_msg("Pietre runiche: %s erige un Obelisco commemorativo (+1 PV)." % pname(side))
	if winner >= 0:
		if civ_adv(winner, "Slave Economy"):
			gain(winner, "gold", 1)
			gain(winner, "mood", 1)
		if civ_adv(winner, "Captives"):
			var take: int = mini(bt["kills"].get(winner, 0), 4 - int(players[winner]["captives"]))
			if take > 0:
				players[winner]["captives"] += take
				log_msg("%s prende %d Prigionieri." % [pname(winner), take])
		var army: Array = att_army if winner == p else def_army
		var foe_army: Array = def_army if winner == p else att_army
		if leader_is(winner, "l15") and _leader_in(army, winner) and bt["round"] == 1 and not foe_army.is_empty():
			gain(winner, "culture", 1)
			gain(winner, "mood", 1)
			log_msg("Guerra lampo: %s riceve 1 Cultura e 1 Umore." % pname(winner))


func _discard_tactics(eff: Dictionary) -> void:
	for side in eff:
		if eff[side] != "":
			discard("action", eff[side], side)
			eff[side] = ""


## Tiro di combattimento con il dado a 12 facce: ogni unità d'armata tira un dado, più gli eventuali dadi extra.
## Abilità di scontro (una per unità, una per icona): Fanteria +1, Cavalleria +2, Elefante (il valore
## non conta ma annulla 1 colpo), Capo (ritira finché non esce un'altra icona).
## Restituisce {"dice": [[valore, icona, attivata, ritirato]…], "cv", "cancel"}.
func _roll(fighters: Array, extra := 0, clash := true, cav_first := 2) -> Dictionary:
	var cnt := {"I": 0, "C": 0, "E": 0, "L": 0}
	var code := {"infantry": "I", "cavalry": "C", "elephant": "E", "leader": "L"}
	for u in fighters:
		if code.has(u["t"]):
			cnt[code[u["t"]]] += 1
	var dice := []
	for i in maxi(0, fighters.size() + extra):
		var d: Array = roll_die()
		dice.append([d[0], d[1], false, false])
	if clash and cnt["L"] > 0:
		for d in dice:
			if d[1] == "L":
				var nd: Array = roll_die()
				while nd[1] == "L":
					nd = roll_die()
				d[0] = nd[0]
				d[1] = nd[1]
				d[3] = true
				break
	var used := {"I": 0, "C": 0, "E": 0}
	var cv := 0
	var cancel := 0
	for d in dice:
		var v: int = d[0]
		var ic: String = d[1]
		if clash and used.has(ic) and used[ic] < cnt[ic]:
			used[ic] += 1
			d[2] = true
			match ic:
				"I":
					v += 1
				"C":
					v += cav_first if used["C"] == 1 else 2
				"E":
					v = 0
					cancel += 1
		cv += v
	return {"dice": dice, "cv": cv, "cancel": cancel}


## Equitazione (Giappone): nel 1° round difendendo una Fortezza una Cavalleria vale +3.
func _cav_bonus(q: int, Dd: Array, rnd: int, fortress: bool) -> int:
	if rnd == 1 and fortress and civ_adv(q, "Horsemanship"):
		return 3
	return 2


func _leader_in(lst: Array, p: int) -> bool:
	for u in lst:
		if u["t"] == "leader" and u["o"] == p:
			return true
	return false


func _beasts_alive(bt: Dictionary, side: String) -> bool:
	for u in _side_units(bt, side):
		if u["t"] in ["cavalry", "elephant"]:
			return true
	return false


const CASUALTY_ORDER := {"infantry": 0, "elephant": 1, "cavalry": 2, "ship": 0, "leader": 3}


func _casualties(bt: Dictionary, side: String, hits: int) -> int:
	var k := 0
	var killer: int = bt["q"] if side == "att" else bt["p"]
	for i in hits:
		var f := _fighters(bt, side)
		if f.is_empty():
			break
		f.sort_custom(func(a, b): return CASUALTY_ORDER.get(a["t"], 0) < CASUALTY_ORDER.get(b["t"], 0))
		var u: Dictionary = f[0]
		if bt.has("kills"):
			if u["t"] == "leader":
				bt["lk"][killer] = true
			elif is_army(u):
				bt["kills"][killer] = bt["kills"].get(killer, 0) + 1
		remove_unit(u, killer)
		k += 1
	if bt["naval"]:
		# controllo del carico
		for s in ships_at(bt["h"]):
			pass
		var by_owner := {}
		for u in units_at(bt["h"]):
			if u["t"] != "ship":
				by_owner[u["o"]] = by_owner.get(u["o"], []) + [u]
		for o in by_owner:
			var cap := ships_at(bt["h"], o).size() * ship_cap(o)
			var lst: Array = by_owner[o]
			while lst.size() > cap:
				remove_unit(lst.pop_back())
	return k


func naval_battle(p: int, att_ships: Array, h: String, from: String) -> Dictionary:
	var defender := -1
	for u in ships_at(h):
		if u["o"] != p:
			defender = u["o"]
	if defender == -1 and ships_at(h).size() == att_ships.size():
		return {}
	for u in att_ships:
		set_mv(u["id"], "battled")
		set_mv(u["id"], "stop")
	var bt := {"att": att_ships.duplicate(), "def": ships_at(h, defender), "p": p, "q": defender, "h": h, "naval": true,
		"round": 0, "city": false, "fortress": false, "kills": {}, "lk": {}}
	_diplomat_pay(p, defender)
	battle = bt
	log_msg("Battaglia navale: %s contro %s." % [pname(p), pname(defender)])
	var killed := {p: 0, defender: 0}
	var att_won := false
	var start_att := att_ships.size()
	var start_def: int = bt["def"].size()
	while true:
		bt["round"] += 1
		var ca := await _pick_tactic(p, "S", true, false, false, bt)
		var cd := await _pick_tactic(defender, "S", false, false, false, bt) if defender >= 0 else ""
		var eff := {p: ca, defender: cd}
		var tac := {p: D.action_card(ca)[2] if ca != "" else "", defender: D.action_card(cd)[2] if cd != "" else ""}
		var A := _fighters(bt, "att")
		var Dd := _fighters(bt, "def")
		var da := A.size() + (1 if tac[p] == "flanking" else 0)
		var dd := Dd.size() + (1 if tac[defender] == "prepared_defenses" else 0)
		var ra := _roll(A, da - A.size(), false)
		var rd := _roll(Dd, dd - Dd.size(), false)
		var cva: int = ra["cv"] + (2 if tac[p] == "high_morale" else 0) + (1 if tac[p] == "tactical_surprise" else 0)
		var cvd: int = rd["cv"] + (2 if tac[defender] == "high_morale" else 0) + (1 if tac[defender] == "tactical_surprise" else 0)
		if exp:
			cva += _exp_cv(bt, p, defender, A, Dd, bt["round"], true, ca != "")
			cvd += _exp_cv(bt, defender, p, Dd, A, bt["round"], false, cd != "")
		if tac[defender] == "defiant_stand":
			cva -= A.size()
		var ha := maxi(0, cva) / 5
		var hd := maxi(0, cvd) / 5
		if bt["round"] == 1:
			if has_adv(p, "Warships"):
				hd = maxi(0, hd - 1)
			if defender >= 0 and has_adv(defender, "Warships"):
				ha = maxi(0, ha - 1)
		fx.emit("dice", {"att": ra["dice"], "def": rd["dice"], "cva": cva, "cvd": cvd, "p": p, "q": defender, "h": h})
		log_msg("Round navale %d: %s %d, %s %d." % [bt["round"], pname(p), cva, pname(defender), cvd])
		await wait(1.0)
		killed[p] += _casualties(bt, "def", ha)
		killed[defender] += _casualties(bt, "att", hd)
		_discard_tactics(eff)
		A = _fighters(bt, "att")
		Dd = _fighters(bt, "def")
		if A.is_empty() or Dd.is_empty():
			att_won = Dd.is_empty() and not A.is_empty()
			break
		if from != "" and not await yes_no(p, "La battaglia navale continua. Ti ritiri?", "Continua", "Ritirati"):
			for u in _side_units(bt, "att"):
				for cc in carried(u["id"]):
					cc["h"] = from
				u["h"] = from
			break
	battle = {}
	if att_won:
		log_msg("%s vince la battaglia navale." % pname(p))
		T["battle_wins"] = T.get("battle_wins", 0) + 1
		if defender == -2:
			T["pirate_wins"] = T.get("pirate_wins", 0) + 1
	if defender == -2 and killed[p] > 0:
		# per ogni nave pirata affondata: 1 Oro e 1 Umore o Cultura, comunque vada
		for i in killed[p]:
			gain(p, "gold", 1)
			var j := await choose(p, "Nave pirata affondata: ricevi…", ["+1 Umore", "+1 Cultura"], {"force": true})
			gain(p, "mood" if j == 0 else "culture", 1)
		log_msg("%s affonda %d navi pirata." % [pname(p), killed[p]])
	if exp:
		await _after_battle_exp(bt, p, defender, att_won, not att_won and _fighters(bt, "att").is_empty() and not _fighters(bt, "def").is_empty(), killed, [], [])
	var info := {"won": att_won, "attacker": true, "defender": defender, "killed": killed[p], "lost": killed[defender],
		"start_att": start_att, "start_def": start_def, "vs_army": false, "naval": true, "killed_ship": killed[p], "h": h,
		"pirates": defender == -2, "killed_leader": bt["lk"].has(p), "leader_in": false}
	await check_now(p, "battle", info)
	changed.emit()
	return {"win": att_won}


# ------------------------------------------------------------------ conquista

func capture_city(p: int, c: Dictionary, att: Array, from_ship: bool, fought: bool, defended := false) -> void:
	var q: int = c["o"]
	var size := city_size(c)
	var gold := size + 1 if c["mood"] == 2 else (1 if c["mood"] == 0 else size)
	if q == -1:
		c["o"] = p
		if supply_left(p, "settlement") < 0:
			pass
		gain(p, "gold", 1)
		c["mood"] = 0
		log_msg("%s conquista una città barbara (+1 Oro)." % pname(p))
		if exp:
			await _capture_exp(p, c, -1, att, size, false)
		await check_now(p, "capture", {"barb": true, "defenders": int(T.get("last_def", 0))})
		T["captured"] = true
		changed.emit()
		return
	# pezzi del vecchio proprietario
	var comp := 0
	if supply_left(p, "settlement") <= 0:
		# niente insediamento disponibile: la città sparisce
		comp = size
		for w in c["w"]:
			pass
		cities.erase(c["id"])
		gain(p, "gold", comp)
		log_msg("%s rade al suolo la città di %s (+%d Oro)." % [pname(p), pname(q), comp])
		T["captured"] = true
		return
	var was_happyish: bool = c["mood"] > 0
	var was_influenced: bool = false
	for b0 in c["b"]:
		if c["b"][b0] == p:
			was_influenced = true
	c["o"] = p
	for b in c["b"].keys():
		if b == "obelisk":
			continue    # l'Obelisco resta del suo colore
		if c["b"][b] == q:
			if supply_left(p, b) > 0:
				c["b"][b] = p
			else:
				c["b"].erase(b)
				comp += 1
	gain(p, "gold", gold + comp)
	c["mood"] = 0
	log_msg("%s conquista la città di %s (+%d Oro)." % [pname(p), pname(q), gold + comp])
	fx.emit("capture", {"h": c["h"], "p": p})
	T["captured"] = true
	T["captured_from"].append(q)
	if exp:
		if leader_is(p, "l45") and _leader_in(att, p) and was_happyish:
			gain(p, "gold", 2)
			log_msg("Ragnar Lodbrok saccheggia la città (+2 Oro).")
		if leader_is(p, "l37") and _leader_in(att, p) and was_influenced:
			c["mood"] = 2
		await _capture_exp(p, c, q, att, size, was_influenced)
	# il vecchio proprietario riceve un colono
	var cs := cities_of(q)
	if not cs.is_empty() and supply_left(q, "settler") > 0:
		var keys := []
		for x in cs:
			keys.append(x["h"])
		var k := await choose_hex(q, "Hai perso una città: dove metti il Colono?", keys)
		new_unit(q, "settler", k)
	await check_now(p, "capture", {"barb": false, "defended": defended, "from_ship": from_ship, "q": q})
	changed.emit()


## Effetti dell'espansione dopo una conquista.
func _capture_exp(p: int, c: Dictionary, q: int, att: Array, size: int, _infl: bool) -> void:
	var led := _leader_in(att, p)
	if civ_adv(p, "Stelas"):
		gain(p, "culture", 1)
	if civ_adv(p, "Provinces") and c["mood"] == 0:
		c["mood"] = 1
		if res(p, "culture") >= 1 and await yes_no(p, "Province: paghi 1 Cultura per rendere Felice la città conquistata?"):
			lose(p, "culture", 1)
			c["mood"] = 2
	if not led:
		return
	match players[p]["leader"]:
		"l24":
			var near := false
			for id in cities:
				var oc: Dictionary = cities[id]
				if oc["o"] != p and oc["id"] != c["id"] and hdist(oc["h"], c["h"]) <= 2:
					near = true
			if near:
				gain(p, "gold", 2)
			if q == -1:
				c["mood"] = 2
		"l26":
			gain(p, "culture", 2 if c["b"].has("temple") else 1)
		"l41":
			if res(p, "gold") >= 1 and supply_left(p, "infantry") > 0 and armies_at(c["h"], p).size() < 4:
				if await yes_no(p, "Proconsole: paghi 1 Oro per una Fanteria nella città conquistata?"):
					lose(p, "gold", 1)
					new_unit(p, "infantry", c["h"])


## I barbari conquistano una città.
func barbarian_capture(c: Dictionary) -> void:
	var q: int = c["o"]
	c["o"] = -1
	c["mood"] = 0
	log_msg("I Barbari conquistano la città di %s!" % pname(q))
	var cs := cities_of(q)
	if not cs.is_empty() and supply_left(q, "settler") > 0:
		var keys := []
		for x in cs:
			keys.append(x["h"])
		var k := await choose_hex(q, "Hai perso una città: dove metti il Colono?", keys)
		new_unit(q, "settler", k)
	changed.emit()


## Un esercito barbaro attacca una casella (città o unità del giocatore q).
func barbarian_attack(barb: Array, h: String) -> void:
	var c := city_at(h)
	var q := -1
	if not c.is_empty():
		q = c["o"]
	else:
		for u in units_at(h):
			if u["o"] >= 0:
				q = u["o"]
	if q < 0:
		return
	if not c.is_empty() and owns_wonder(q, "great_wall"):
		for u in barb:
			remove_unit(u)
		gain(q, "gold", 1)
		log_msg("La Grande Muraglia di %s respinge i Barbari (+1 Oro)." % pname(q))
		return
	var defs := armies_at(h, q)
	var fortress: bool = not c.is_empty() and c["b"].has("fortress")
	if defs.is_empty() and not fortress:
		for u in units_at(h):
			if u["o"] == q and u["t"] != "ship":
				remove_unit(u)
		if not c.is_empty():
			await barbarian_capture(c)
		else:
			log_msg("I Barbari eliminano i coloni di %s." % pname(q))
		return
	var bt := {"att": barb.duplicate(), "def": units_at(h).filter(func(u): return u["o"] == q), "p": -1, "q": q, "h": h,
		"naval": false, "round": 0, "city": not c.is_empty(), "fortress": fortress, "kills": {}, "lk": {}}
	if exp:
		await _pre_battle_exp(bt, q, defs)
	battle = bt
	log_msg("I Barbari attaccano %s!" % pname(q))
	var won := false
	var tie := false
	var killed_b := 0
	var n_def := defs.size()
	while true:
		bt["round"] += 1
		var dk: String = ("A" if not _fighters(bt, "def").is_empty() else "") + ("F" if fortress else "")
		var cd := await _pick_tactic(q, dk, false, not c.is_empty(), false, bt)
		var tq: String = D.action_card(cd)[2] if cd != "" else ""
		var A := _fighters(bt, "att")
		var Dd := _fighters(bt, "def")
		var dd := Dd.size() + (1 if bt["round"] == 1 and fortress else 0) + (1 if tq in ["prepared_defenses", "for_the_people"] else 0)
		var ra := _roll(A, 0, tq != "high_ground")
		var rd := _roll(Dd, dd - Dd.size(), true, _cav_bonus(q, Dd, bt["round"], fortress))
		var cva: int = ra["cv"] - (A.size() if tq == "defiant_stand" else 0)
		var cvd: int = rd["cv"] + (2 if tq == "high_morale" else 0) + (1 if tq == "tactical_surprise" else 0)
		if exp:
			cvd += _exp_cv(bt, q, -1, Dd, A, bt["round"], false, cd != "")
		if bt["round"] == 1 and has_adv(q, "Fanaticism") and not c.is_empty() and c["b"].has("temple"):
			cvd += 2
		var ha := maxi(0, maxi(0, cva) / 5 - rd["cancel"])
		var hd := maxi(0, maxi(0, cvd) / 5 - ra["cancel"])
		if bt["round"] == 1 and fortress:
			ha = maxi(0, ha - 1)
		if tq == "upgraded_defenses":
			ha = maxi(0, ha - 1)
		if exp:
			ha = maxi(0, ha - await _exp_cancel(bt, q, Dd, bt["round"], false, ha))
		fx.emit("dice", {"att": ra["dice"], "def": rd["dice"], "cva": cva, "cvd": cvd, "p": -1, "q": q, "h": h})
		log_msg("Round %d: Barbari %d, %s %d." % [bt["round"], cva, pname(q), cvd])
		await wait(1.0)
		killed_b += _casualties(bt, "att", hd)
		_casualties(bt, "def", ha)
		if cd != "":
			discard("action", cd, q)
		A = _fighters(bt, "att")
		Dd = _fighters(bt, "def")
		if A.is_empty() and Dd.is_empty():
			tie = true
			break
		if A.is_empty():
			won = true
			break
		if Dd.is_empty():
			break
	battle = {}
	if exp:
		await _after_battle_exp(bt, -1, q, not won and not tie, won, {}, barb, defs)
	if tie:
		log_msg("Nessuno sopravvive allo scontro con i Barbari.")
		for u in units_at(h):
			if u["o"] == q and u["t"] != "ship":
				remove_unit(u)
		changed.emit()
		return
	if won:
		gain(q, "gold", 1)
		log_msg("%s respinge i Barbari (+1 Oro)." % pname(q))
		await check_now(q, "battle", {"won": true, "attacker": false, "defender": -1, "killed": killed_b, "lost": 0,
			"start_att": barb.size(), "start_def": n_def, "mine": n_def, "theirs": barb.size(), "opp": -1, "vs_army": true, "h": h})
	else:
		for u in units_at(h):
			if u["o"] == q and u["t"] != "ship":
				remove_unit(u)
		if not c.is_empty():
			await barbarian_capture(c)
	changed.emit()
