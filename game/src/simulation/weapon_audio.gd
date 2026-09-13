extends RefCounted
## Native sound selection for already resolved, ordered ordinary weapon owners.
const Definitions=preload("res://src/content/weapon_audio_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")

static func player_entries(data: Dictionary, items: Array, ordered_weapons: Array) -> Array:
	if not Definitions.parameters(data) or items.size()!=data.player_event_ids.size() or ordered_weapons.size()>255:return []
	var order := []
	var entries := []
	for weapon in ordered_weapons:
		if not weapon is Dictionary or not Numbers.integer(weapon.get("item_id"),0,items.size()-1):return []
		var id: int=weapon.item_id
		if not items[id] is Dictionary:return []
		var arrays: Variant=items[id].get("arrays")
		if not arrays is Array or arrays.size()!=3 or not (arrays[2] is Array or arrays[2] is PackedInt32Array) or arrays[2].size()<=int(data.price_high_index):return []
		var low: Variant=arrays[2][int(data.price_low_index)]
		var high: Variant=arrays[2][int(data.price_high_index)]
		if not Numbers.integer(low,-2147483648,2147483647) or not Numbers.integer(high,-2147483648,2147483647):return []
		var delta: int=int(high)-int(low)
		if not Numbers.integer(delta,-2147483648,2147483647):return []
		@warning_ignore("integer_division")
		var price: int=int(low)+delta/2
		if not Numbers.integer(price,-2147483648,2147483647):return []
		var factor: Variant=weapon.get("interval_multiplier")
		if not (factor is float or factor is int) or not is_finite(factor):return []
		var raw_pitch: float=maxf(0.0,Vitals.single(1.0-float(factor)))
		# A fresh owner starts at zero; a negative update leaves it there.
		if raw_pitch>1.0:return []
		order.append({"item_id":id,"price":price,"index":order.size()})
		entries.append({"enabled":false,"source_id":int(data.player_event_ids[id]),"pitch_raw":raw_pitch})
	# Equal prices keep creation order. The original sorts a copy of item IDs,
	# then enables original array indices; it does not reorder the firing array.
	order.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.price>b.price or (a.price==b.price and a.index<b.index))
	var seen := {}
	var remaining: int=int(data.player_sound_limit)
	for i in order.size():
		var id: int=order[i].item_id
		if seen.has(id):continue
		seen[id]=true
		if remaining==0:break
		entries[i].enabled=true
		remaining-=1
	return entries

static func npc_entry(data: Dictionary, actor_kind: int) -> Dictionary:
	if not Definitions.parameters(data) or actor_kind<0:return {}
	var id: int=int(data.npc_event_ids[actor_kind]) if actor_kind<data.npc_event_ids.size() else int(data.npc_default_event_id)
	return {"enabled":bool(data.initial_enabled),"source_id":id,"pitch_raw":float(data.npc_pitch)}

static func cue(entry: Dictionary, position: Vector3) -> Dictionary:
	if not entry.get("enabled",false) or int(entry.source_id)<0:return {}
	return {"source_id":int(entry.source_id),"position":position,"pitch_raw":float(entry.pitch_raw)}
