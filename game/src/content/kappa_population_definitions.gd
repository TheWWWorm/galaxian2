extends RefCounted
## The authored rescue cast uses the ordinary fighter factory. These definitions
## validate detached construction; the campaign session owns earned departures.
const Rescue=preload("res://src/content/kappa_rescue_definitions.gd")
const Fighters=preload("res://src/content/kappa_fighters_definitions.gd")
const Ambient=preload("res://src/content/ambient_combat_definitions.gd")
const ControlRules=preload("res://src/content/combat_training_control_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Weapons=preload("res://src/content/contract_ship_combat_definitions.gd")
const Life=preload("res://src/content/contract_ship_lifecycle_definitions.gd")

static func available(bindings: RefCounted) -> bool:
	return Rescue.available(bindings) and Fighters.available(bindings) and Travel.parameters(bindings.mido_travel) and Ambient.parameters(bindings.ambient_combat) and ControlRules.parameters(bindings.combat_training_control)

static func context_valid(bindings: RefCounted,context: Dictionary) -> bool:
	if not available(bindings):return false
	for key in ["base_content_id","binding_id"]:
		if context.get(key)!=bindings.get(key):return false
	for key in ["campaign_cursor","station_id","system_id","mission_kind"]:
		if not context.get(key) is int or context[key]!=int(bindings.mido_travel.kappa_rescue[key]):return false
	return context.get("mission_story")==true and context.get("mission_completed")==false and Numbers.integer(context.get("rank"),0,20) and context.get("difficulty") in [0.5,1.0]

static func population(bindings: RefCounted,packet: Dictionary) -> Dictionary:
	if not packet.get("kappa_context") is Dictionary or not context_valid(bindings,packet.kappa_context):return {}
	var context: Dictionary=packet.kappa_context
	for key in ["base_content_id","binding_id","campaign_cursor","station_id"]:
		if packet.get(key)!=context[key]:return {}
	var source: Dictionary=bindings.mido_travel.kappa_rescue.population
	var actors: Variant=packet.get("actors")
	if not actors is Array or actors.size()!=int(source.actor_count):return {}
	for id in actors.size():
		var row: Variant=actors[id];var expected: Dictionary=source.actors[id]
		if not row is Dictionary:return {}
		for key in ["actor_id","actor_kind","subtype","hull_catalogue_id"]:
			if not row.get(key) is int or row[key]!=int(expected[key]):return {}
		if row.get("population_group")!="fighter" or not Flight.rigid_pose(row.get("body_pose")) or row.body_pose!=row.get("statistics_pose"):return {}
		if row.get("script_hostile")!=expected.initial_hostile or row.get("permanent_friendly")!=bindings.mido_travel.kappa_fighters.initial_permanent_friendly:return {}
		if row.get("mode")!=int(source.initial_actor_mode) or row.get("active")!=source.initial_active:return {}
		if not row.get("route") is Dictionary or not row.route.get("loop",false) or row.route.get("waypoints")!=[vec(source.waypoints[int(expected.waypoint_index)])]:return {}
		if id==int(source.target_actor_id) and (row.get("name_text_id")!=int(source.target_name_text_id) or row.body_pose.origin!=vec(source.waypoints[1])+vec(source.target_position_offset)):return {}
	var data: Dictionary=bindings.combat_training_control.duplicate(true)
	data.merge(context,true)
	data.actor_count=actors.size()
	data.initial_actor_mode=int(source.initial_actor_mode);data.initial_active=bool(source.initial_active)
	data.actor_kinds=actors.map(func(actor):return actor.actor_kind)
	data.hull_catalogue_ids=actors.map(func(actor):return actor.hull_catalogue_id)
	data.player_ship_id=int(bindings.combat_training_weapons.player_entry.ship_id)
	data.initial_actor_targeting_blocked=bool(bindings.mido_travel.traffic_control.initial_actor_targeting_blocked)
	return data

static func combat(bindings: RefCounted,packet: Dictionary) -> Dictionary:
	var data:=population(bindings,packet)
	if data.is_empty() or not Weapons.parameters(bindings.early_contracts.get("ship_combat")):return {}
	var rules: Dictionary=bindings.early_contracts.ship_combat.weapons
	data.npc_weapons=[]
	data.player_weapon_targets=bindings.mido_travel.kappa_fighters.player_weapon_targets.map(func(id):return int(id))
	data.target_memberships=bindings.mido_travel.kappa_fighters.npc_target_memberships.map(func(ids):return ids.map(func(id):return int(id)))
	for actor in packet.actors:
		var weapon:=Weapons.scaled_parameters(rules,int(data.campaign_cursor),int(data.rank),float(data.difficulty))
		if weapon.is_empty():return {}
		for key in ["item_id","kind","catalogue_kind","model_resource_id"]:weapon[key]=int(rules.factions[0][key])
		for key in ["actor_id","actor_kind","hull_catalogue_id"]:weapon[key]=actor[key]
		data.npc_weapons.append(weapon)
	return data

static func guidance(bindings: RefCounted,packet: Dictionary) -> Dictionary:
	var data:=combat(bindings,packet)
	if data.is_empty() or not Life.available(bindings):return {}
	data.kappa_rescue=true
	data.selection_skipped_modes=bindings.early_contracts.ship_lifecycle.selection_skipped_modes.map(func(mode):return int(mode))
	return data

static func vec(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])
