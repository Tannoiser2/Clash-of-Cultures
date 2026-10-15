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
		if u["o"] != p:
			return true
	return false


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
		if units[int(id)]["t"] == "infantry":
			return true
	return false


func _ship_room(k: String, p: int) -> int:
	var room := 0
	for s in ships_at(k, p):
		room += 2 - carried(s["id"]).size()
	return room


func can_attack(p: int, target: int) -> bool:
	if target < 0:
		return true
	var key := "%d,%d" % [mini(p, target), maxi(p, target)]
	return not negotiation.has(key)


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
		if units[int(id)]["t"] == "infantry":
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
				s["h"] = dest
				set_mv(s["id"], "moved")
			T["ships_moved"] = true
		"explore":
			var ri2 := region_of(to)
			await explore(p, ri2, to)
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
					if carried(s["id"]).size() < 2:
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
		elif u["t"] == "infantry" and u["on"] == -1:
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
		if u["t"] == "infantry" and u["on"] == -1:
			def_army.append(u)
	for u in att:
		set_mv(u["id"], "battled")
		set_mv(u["id"], "stop")
	T["battles"].append(h)
	var city_def: bool = not c.is_empty() and c["o"] == defender
	var fortress: bool = city_def and c["b"].has("fortress")
	var att_army := []
	for u in att:
		if u["t"] == "infantry":
			att_army.append(u)
	# coloni soli: sconfitti senza combattere
	if def_army.is_empty() and not fortress:
		var killed_settlers := 0
		for u in def_units:
			if u["on"] == -1 and u["t"] != "ship":
				remove_unit(u)
				killed_settlers += 1
		if killed_settlers > 0:
			log_msg("%s elimina %d coloni di %s." % [pname(p), killed_settlers, pname(defender)])
			await check_now(p, "battle", {"won": true, "attacker": true, "defender": defender, "killed": 0, "lost": 0,
				"killed_settler": killed_settlers, "vs_army": false})
		if city_def:
			T["last_def"] = 0
			await capture_city(p, c, att, from_ship, false)
		changed.emit()
		return {"win": true, "defender": defender}
	var bt := {"att": att.duplicate(), "def": def_units.duplicate(), "p": p, "q": defender, "h": h, "naval": false,
		"round": 0, "city": city_def, "fortress": fortress, "log": [], "from_ship": from_ship}
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
	while true:
		bt["round"] += 1
		var rnd: int = bt["round"]
		var A := _fighters(bt, "att")
		var Dd := _fighters(bt, "def")
		# carte
		var att_kinds := "A"
		var def_kinds := "A" + ("F" if fortress else "")
		var ca := await _pick_tactic(p, att_kinds, true, false, city_def, bt)
		var cd := ""
		if defender >= 0:
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
		var ra := _roll(dice_a, A.size(), not no_clash_on_att)
		var rd := _roll(dice_d, Dd.size(), not no_clash_on_def)
		var cva: int = ra["cv"]
		var cvd: int = rd["cv"]
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
		hits_a = maxi(0, hits_a - cancel[defender])
		hits_d = maxi(0, hits_d - cancel[p])
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
		if await yes_no(p, "La battaglia continua (%d contro %d). Ti ritiri?" % [A.size(), Dd.size()], "Continua", "Ritirati") == false:
			retreated = true
			for u in _side_units(bt, "att"):
				u["h"] = from
				if from_ship:
					pass
			log_msg("%s si ritira." % pname(p))
			break
	battle = {}
	# coloni del difensore rimasti senza eserciti
	if att_won:
		for u in enemy_units_at(h, p):
			if u["t"] != "ship":
				remove_unit(u)
	if def_won:
		for u in _side_units(bt, "att"):
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
	var info := {"won": att_won, "attacker": true, "defender": defender, "killed": lost_def, "lost": lost_att,
		"start_att": start_att, "start_def": start_def, "vs_army": start_def > 0, "city": city_def,
		"size": city_size(c) if not c.is_empty() else 0, "wonder": not c.is_empty() and not c["w"].is_empty(), "h": h}
	await check_now(p, "battle", info)
	if defender >= 0:
		var info2 := info.duplicate()
		info2["won"] = def_won
		info2["attacker"] = false
		info2["killed"] = lost_att
		info2["lost"] = lost_def
		await check_now(defender, "battle", info2)
	T["last_def"] = start_def
	if att_won and city_def and city_at(h).get("id", -1) == c.get("id", -2):
		await capture_city(p, c, _side_units(bt, "att"), from_ship, true, start_def > 0 or fortress)
	changed.emit()
	return {"win": att_won, "defender": defender}


func _discard_tactics(eff: Dictionary) -> void:
	for side in eff:
		if eff[side] != "":
			discard("action", eff[side], side)
			eff[side] = ""


func _roll(ndice: int, n_inf: int, clash: bool) -> Dictionary:
	var dice := []
	var cv := 0
	var inf_used := 0
	for i in ndice:
		var v := d6()
		dice.append(v)
		cv += v
		if clash and v >= 5 and inf_used < n_inf:
			inf_used += 1
			cv += 1
	return {"dice": dice, "cv": cv}


func _casualties(bt: Dictionary, side: String, hits: int) -> int:
	var k := 0
	for i in hits:
		var f := _fighters(bt, side)
		if f.is_empty():
			break
		remove_unit(f[0])
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
			var cap := ships_at(bt["h"], o).size() * 2
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
		"round": 0, "city": false, "fortress": false}
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
		var ra := _roll(da, 0, false)
		var rd := _roll(dd, 0, false)
		var cva: int = ra["cv"] + (2 if tac[p] == "high_morale" else 0) + (1 if tac[p] == "tactical_surprise" else 0)
		var cvd: int = rd["cv"] + (2 if tac[defender] == "high_morale" else 0) + (1 if tac[defender] == "tactical_surprise" else 0)
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
	var info := {"won": att_won, "attacker": true, "defender": defender, "killed": killed[p], "lost": killed[defender],
		"start_att": start_att, "start_def": start_def, "vs_army": false, "naval": true, "killed_ship": killed[p], "h": h}
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
	c["o"] = p
	for b in c["b"].keys():
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
		"naval": false, "round": 0, "city": not c.is_empty(), "fortress": fortress}
	battle = bt
	log_msg("I Barbari attaccano %s!" % pname(q))
	var won := false
	var killed_b := 0
	while true:
		bt["round"] += 1
		var cd := await _pick_tactic(q, "A" + ("F" if fortress else ""), false, not c.is_empty(), false, bt)
		var tq: String = D.action_card(cd)[2] if cd != "" else ""
		var A := _fighters(bt, "att")
		var Dd := _fighters(bt, "def")
		var dd := Dd.size() + (1 if bt["round"] == 1 and fortress else 0) + (1 if tq in ["prepared_defenses", "for_the_people"] else 0)
		var ra := _roll(A.size(), A.size(), tq != "high_ground")
		var rd := _roll(dd, Dd.size(), true)
		var cva: int = ra["cv"] - (A.size() if tq == "defiant_stand" else 0)
		var cvd: int = rd["cv"] + (2 if tq == "high_morale" else 0) + (1 if tq == "tactical_surprise" else 0)
		if bt["round"] == 1 and has_adv(q, "Fanaticism") and not c.is_empty() and c["b"].has("temple"):
			cvd += 2
		var ha := maxi(0, cva) / 5
		var hd := maxi(0, cvd) / 5
		if bt["round"] == 1 and fortress:
			ha = maxi(0, ha - 1)
		if tq == "upgraded_defenses":
			ha = maxi(0, ha - 1)
		fx.emit("dice", {"att": ra["dice"], "def": rd["dice"], "cva": cva, "cvd": cvd, "p": -1, "q": q, "h": h})
		log_msg("Round %d: Barbari %d, %s %d." % [bt["round"], cva, pname(q), cvd])
		await wait(1.0)
		killed_b += _casualties(bt, "att", hd)
		_casualties(bt, "def", ha)
		if cd != "":
			discard("action", cd, q)
		A = _fighters(bt, "att")
		Dd = _fighters(bt, "def")
		if A.is_empty():
			won = true
			break
		if Dd.is_empty():
			break
	battle = {}
	if won:
		gain(q, "gold", 1)
		log_msg("%s respinge i Barbari (+1 Oro)." % pname(q))
		await check_now(q, "battle", {"won": true, "attacker": false, "defender": -1, "killed": killed_b, "lost": 0,
			"start_att": 0, "start_def": barb.size(), "vs_army": true, "h": h})
	else:
		for u in units_at(h):
			if u["o"] == q and u["t"] != "ship":
				remove_unit(u)
		if not c.is_empty():
			await barbarian_capture(c)
	changed.emit()
