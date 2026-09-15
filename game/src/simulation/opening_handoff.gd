extends RefCounted
## Prepare a detached rescue entry from the completed native Opening. This is
## scoped to its supported steering/fire controls: no mining, trade, hiring,
## manual travel or save loading has changed the fresh campaign's other fields.
## Preparing the packet does not advance the old scene or award a mission.
const Definitions=preload("res://src/content/opening_handoff_definitions.gd")
const Loadout=preload("res://src/simulation/opening_loadout.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Reputation=preload("res://src/simulation/faction_reputation.gd")
var error:=""

static func calculate_progress(rules: Dictionary, cursor: Variant, player_kills: Variant, pirate_kills: Variant, other_score: Variant) -> Dictionary:
	if not Definitions.parameters(rules):return {}
	for value in [cursor,player_kills,pirate_kills,other_score]:
		if not Numbers.integer(value,0,2147483647):return {}
	if pirate_kills>player_kills:return {}
	var score: int=other_score+player_kills*int(rules.player_kill_weight)+pirate_kills*int(rules.pirate_kill_weight)+cursor*int(rules.cursor_weight)
	if score>2147483647:return {}
	var rank:=0
	for i in rules.rank_thresholds.size():
		if score>=int(rules.rank_thresholds[i]):rank=i
	return {"campaign_cursor":cursor,"rank":rank,"rank_score":score,"player_kills":player_kills,"pirate_kills":pirate_kills,"other_score":other_score}

func prepare(bindings: RefCounted, catalogues: RefCounted, opening: Dictionary) -> Dictionary:
	error=""
	if bindings==null or catalogues==null or not Definitions.parameters(bindings.opening_handoff):return fail("Mac Opening handoff is unavailable; prepare current bindings")
	var rules: Dictionary=bindings.opening_handoff
	if opening.get("escape",{}).get("boundary")!="arrival_transition_required":return fail("Opening has not reached its rescue transition")
	var radio: Variant=opening.get("radio",{}).get("finished")
	if not radio is Array or radio.size()!=bindings.opening_dialogue.events.size() or not radio.all(func(value):return value is bool and value):return fail("Opening transmissions are incomplete")
	var world: Variant=opening.get("world_frame")
	if not world is Dictionary:return fail("Opening handoff requires its actual world state")
	for key in ["base_content_id","binding_id"]:
		if world.get(key)!=bindings.get(key):return fail("Opening world belongs to another content identity")
	var live: Variant=world.get("player")
	if not live is Dictionary or not Numbers.integer(live.get("vitals",{}).get("hull"),1,2147483647):return fail("A destroyed player cannot enter the rescue")
	var loadout:=Loadout.new()
	if not loadout.configure(bindings,catalogues,bindings.base_content_id):return fail(loadout.error)
	var seed:=loadout.snapshot()
	var cached: Variant=world.get("player_cache")
	if not Cache.matches(cached,seed,int(rules.opening_cursor)):return fail("Opening handoff lacks its retained player cache")
	if live.get("ship_id")!=seed.ship_id or live.get("equipment_ids")!=seed.equipment_ids:return fail("Opening handoff does not support an altered ship or loadout")
	# This opening has no device capable of changing the reputation override.
	for id in seed.equipment_ids:
		if catalogues.tables.items[id].arrays[2][5]==int(rules.reputation_override_equipment_type):return fail("Opening handoff does not support a reputation override device")
	var counters:=completed_counters(bindings,opening.get("combat",{}),world.get("controller",{}).get("death_accounting"))
	if counters.is_empty():return {}
	var player:=Player.new()
	if not player.configure_arrival(bindings,catalogues,cached):return fail(player.error)
	var cursor:=int(rules.arrival_cursor)
	var progress:=calculate_progress(rules,cursor,counters.player_kills,counters.pirate_kills,int(rules.initial_other_score))
	if progress.is_empty():return fail("Opening career exceeds the supported score range")
	var axis:=int(rules.rescue_reputation_axis)
	var uncertainty: int=counters.player_kills*int(rules.pirate_reputation_change_maximum)
	var lower: int=int(rules.initial_reputation[axis])-uncertainty
	var upper: int=int(rules.initial_reputation[axis])+uncertainty
	if int(rules.initial_reputation_override)>=0 or upper>int(rules.rescue_hostile_above):return fail("Rescue disposition is outside the verified Opening bounds")
	var conditions:={"companions_empty":int(rules.initial_companion_count)==0,"location_match":int(rules.initial_location_wrapper_id)==seed.station_id}
	# The source getter is cursor >44. There is no independent free-roam
	# preference in this predicate, and the supported rescue has cursor one.
	if cursor>int(rules.center_cursor_upper_inclusive) or not conditions.companions_empty or conditions.location_match:return fail("Rescue entry falls outside its supported world profile")
	if Reputation.available(bindings):
		var history:=Reputation.new()
		if not history.restore(bindings,opening.combat.get("reputation")):return fail(history.error)
		var hits:=history.snapshot()
		if hits.campaign_cursor!=0 or hits.events.size()!=opening.combat.actors.size():return fail("Opening reputation lacks its three actual lethal hits")
		for event in hits.events:
			if event.nonplayer_kill!=opening.combat.actors[event.actor_id].nonplayer_kill:return fail("Opening reputation disagrees with its lethal attribution")
		progress.reputation=history.apply_to(Reputation.initial(bindings))
		if progress.reputation.is_empty():return fail(history.error)
	return {"base_content_id":seed.base_content_id,"binding_id":seed.binding_id,"campaign_cursor":cursor,
		"previous_cache":cached.duplicate(true),"player_cache":player.cache_snapshot(),"player":player.snapshot(),
		"progress":progress,
		"entry_conditions":conditions,"rescue_disposition":{"actor_hostile":false,"reputation_axis":axis,"minimum":lower,"maximum":upper,"override":int(rules.initial_reputation_override)}}

func completed_counters(bindings: RefCounted, combat: Dictionary, accounting: Variant) -> Dictionary:
	if not accounting is Dictionary or not accounting.get("events") is Array or not accounting.get("counter_deltas") is Dictionary:return fail("Opening death accounting is unavailable")
	for key in ["base_content_id","binding_id"]:
		if accounting.get(key)!=bindings.get(key):return fail("Opening death accounting belongs to another content identity")
	var actors: Variant=combat.get("actors")
	if not actors is Array or actors.size()!=3 or accounting.events.size()!=3:return fail("Opening encounter has not completed its three actor lifecycles")
	var totals:={"hostile_remaining":0,"hostile_deaths":0,"world_player_kills":0,"world_other_kills":0,"player_kills":0,"pirate_kills":0}
	var seen:=[]
	for event in accounting.events:
		if not event is Dictionary or not Numbers.integer(event.get("actor_id"),0,2) or not event.get("nonplayer_kill") is bool:return fail("Invalid Opening death event")
		for key in ["base_content_id","binding_id"]:
			if event.get(key)!=bindings.get(key):return fail("Opening death event belongs to another content identity")
		var id:=int(event.actor_id)
		if id in seen:return fail("Opening death event was duplicated")
		seen.append(id)
		var actor: Variant=actors[id]
		if not actor is Dictionary or actor.get("actor_id")!=id or actor.get("actor_kind")!=8 or actor.get("vitals",{}).get("hull")!=0 or actor.get("nonplayer_kill")!=event.nonplayer_kill:return fail("Opening death event disagrees with its actor")
		var credit:=0 if event.nonplayer_kill else 1
		var delta:={"hostile_remaining":-1,"hostile_deaths":1,"world_player_kills":credit,"world_other_kills":1-credit,"player_kills":credit,"pirate_kills":credit}
		if event.get("counter_deltas")!=delta:return fail("Opening death counters disagree with attribution")
		for key in delta:totals[key]+=delta[key]
	if accounting.counter_deltas!=totals:return fail("Opening accumulated death counters disagree with events")
	return totals

func fail(message: String) -> Dictionary:
	error=message
	return {}
