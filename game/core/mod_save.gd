class_name ModSave
extends RefCounted
## Las cartas de mods viven por encima de las CARD_SLOTS casillas del bloque nativo de system.dat.
## SaveData._ensure_startup_deck proyecta la coleccion a ese bloque, valida el mazo con el motor
## original y vuelve a escribir la coleccion desde el bloque: todo lo que no cabe se perderia.
## Estas funciones apartan los datos de mods antes de la proyeccion para devolverlos despues.

const ZONES := ["main", "side", "fusion"]


## internal_id de cada carta de mods -> true.
static func ids_of(mod_cards: Array) -> Dictionary:
	var out := {}
	for card: Dictionary in mod_cards:
		out[int(card["internal_id"])] = true
	return out


## Divide un diccionario {"<id>": valor} en {"mod": ..., "rest": ...}.
static func split_counts(counts: Dictionary, mod_ids: Dictionary) -> Dictionary:
	var mod := {}
	var rest := {}
	for key in counts:
		if mod_ids.has(int(key)):
			mod[key] = counts[key]
		else:
			rest[key] = counts[key]
	return {"mod": mod, "rest": rest}


## Quita del mazo las cartas de mods. Devuelve {"deck", "removed": {zona: [...]}, "count"}.
static func strip_deck(deck: Dictionary, mod_ids: Dictionary) -> Dictionary:
	var kept := deck.duplicate(true)
	var removed := {}
	var count := 0
	for zone in ZONES:
		var keep := []
		var gone := []
		for card in deck.get(zone, []):
			if mod_ids.has(int(card)):
				gone.append(card)
			else:
				keep.append(card)
		if deck.has(zone):
			kept[zone] = keep
		removed[zone] = gone
		count += gone.size()
	return {"deck": kept, "removed": removed, "count": count}


## Devuelve al final de cada zona las cartas de mods apartadas.
static func restore_deck(deck: Dictionary, removed: Dictionary) -> Dictionary:
	var out := deck.duplicate(true)
	for zone in ZONES:
		var gone: Array = removed.get(zone, [])
		if gone.is_empty():
			continue
		var cards: Array = out.get(zone, [])
		cards.append_array(gone)
		out[zone] = cards
	return out
