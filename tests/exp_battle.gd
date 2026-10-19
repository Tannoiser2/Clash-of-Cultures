extends SceneTree
## Prova mirata delle battaglie dell'espansione: Leader, Cavalleria, Elefanti, Eclissi, pirati.
## godot --headless --path . -s res://tests/exp_battle.gd

func _initialize() -> void:
	var kills := 0
	var att_wins := 0
	for g in 40:
		var e = load("res://scripts/core/engine.gd").new()
		e.headless = true
		root.add_child(e)
		e.setup({"seats": [{"color": 0, "ai": true, "name": "A"}, {"color": 1, "ai": true, "name": "B"}], "seed": 500 + g, "opts": {"civ": true}})
		var ha: String = e.players[0]["home"]
		var hb := ""
		for k in e.neighbors(ha):
			if e.is_land(k) and e.city_at(k).is_empty():
				hb = k
				break
		if hb == "":
			e.queue_free()
			continue
		e.new_turn_state(0)
		e.cur = 0
		for p in 2:
			e.players[p]["adv"].append("Tactics")
			e.players[p]["leader"] = e.players[p]["leaders_avail"].pop_front()
		var att := [e.new_unit(0, "infantry", hb), e.new_unit(0, "cavalry", hb), e.new_unit(0, "elephant", hb), e.new_unit(0, "leader", hb)]
		var dh: String = ""
		for k in e.neighbors(hb):
			if e.is_land(k) and e.city_at(k).is_empty() and k != ha:
				dh = k
				break
		if dh == "":
			e.queue_free()
			continue
		e.new_unit(1, "infantry", dh)
		e.new_unit(1, "elephant", dh)
		e.new_unit(1, "leader", dh)
		if g % 3 == 0:
			e.eclipse = true
		for u in att:
			u["h"] = dh
		var r = await e.land_battle(0, att, dh, hb, false)
		if r["win"]:
			att_wins += 1
		kills += e.players[0]["killed_leaders"].size() + e.players[1]["killed_leaders"].size()
		# pirati
		await e.pirates_event(0)
		var sc0: Dictionary = e.score(0)
		e.queue_free()
	print("vittorie attaccante ", att_wins, "/40, leader uccisi ", kills)
	quit()
