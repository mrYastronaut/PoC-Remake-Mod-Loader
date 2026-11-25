extends SceneTree
## Premios al ganar: las cartas de mods entran en el sorteo (ModCards "reward_weight" y "limit").
## godot --headless --path game --script res://tests/mod_rewards_test.gd -- --storage=<dir vacio> --data=<dir vacio>

var failures: Array = []


func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		printerr("FALLO: ", what)


func _init() -> void:
	_run.call_deferred()


func _card(id: int, index: int, mod := "", extra := {}) -> Dictionary:
	var c := {"internal_id": id, "index": index, "pack": 1}
	if mod != "":
		c["mod"] = mod
	c.merge(extra)
	return c


func _run() -> void:
	await process_frame
	var card_db: Node = root.get_node("CardDB")
	var save: Node = root.get_node("SaveData")
	var result_script: GDScript = load("res://scenes/duel/duel_result.gd")
	var r: Node = result_script.new()
	r.game = "yugi"

	var cards: Array[Dictionary] = []
	for i in range(1, 201):
		cards.append(_card(i, i))
	cards.append(_card(1919, 201, "gods", {"limit": 1, "reward_weight": 40}))
	card_db.cards = cards
	save.data["collection"] = {}

	# --- el sorteo: sin pesos todo igual que antes; con peso, mas probabilidad ---
	var pool: Array = card_db.obtainable_in("yugi")
	var draw: Array = r._reward_pool(pool)
	check(draw.size() == 200 + 40, "base 1 vez cada una + 40 entradas de la carta del mod (%d)" % draw.size())
	var plain: Array = []
	for c in pool:
		if not c.has("mod"):
			plain.append(c)
	check(r._reward_pool(plain) == plain, "sin cartas de mods el sorteo es el original")

	var hits := 0
	var trials := 4000
	for _i in trials:
		if r._choose_cards(1)[0]["id"] == 1919:
			hits += 1
	var rate := float(hits) / trials
	check(rate > 0.10 and rate < 0.24, "frecuencia de la carta con peso 40 sobre 240: ~16 %% (%.3f)" % rate)

	# --- unica y ya la tienes: no vuelve a salir ---
	save.data["collection"] = {"1919": 1}
	check(r._reward_pool(pool).size() == 200, "carta unica ya poseida: fuera del sorteo")
	var again := false
	for _i in 1500:
		again = again or r._choose_cards(1)[0]["id"] == 1919
	check(not again, "no se sortea una carta unica que ya se tiene")

	# --- con limit distinto de 1 sigue pudiendo salir ---
	var cards2: Array[Dictionary] = []
	for i in range(1, 201):
		cards2.append(_card(i, i))
	cards2.append(_card(1919, 201, "gods", {"limit": 3, "reward_weight": 5}))
	card_db.cards = cards2
	check(r._reward_pool(card_db.obtainable_in("yugi")).size() == 205, "limit 3 poseida: sigue en el sorteo con su peso")

	# --- el premio de un combate trae cartas distintas ---
	save.data["collection"] = {}
	card_db.cards = cards
	var many: Array = r._choose_cards(3)
	var ids := {}
	for c in many:
		ids[c["id"]] = true
	check(many.size() == 3 and ids.size() == 3, "3 cartas distintas en un combate")

	# --- cards.json: reward_weight ---
	var base := {"key": "s", "names": {"eng": "S"}, "descriptions": {"eng": "d"}, "category": "monster", "atk": 0, "defense": 0, "level": 10, "attribute": "divine", "type_id": 24, "monster_kind": "effect", "image": null}
	var good := ModCards.parse_card(base.merged({"reward_weight": 40}), ["yugi"])
	check(good["ok"] and good["card"].get("reward_weight") == 40, "parse_card acepta reward_weight (%s)" % str(good["errors"]))
	for bad in [0, 1001, 2.5, "3"]:
		check(not ModCards.parse_card(base.merged({"reward_weight": bad}), ["yugi"])["ok"], "parse_card rechaza reward_weight %s" % str(bad))
	check(not ModCards.parse_card(base, ["yugi"])["card"].has("reward_weight"), "sin reward_weight no se anade")

	r.free()
	if failures.is_empty():
		print("mod_rewards_test: OK")
		quit(0)
	else:
		printerr("mod_rewards_test: %d fallos" % failures.size())
		quit(1)
