extends RefCounted
## Original ship setup for accepted early contracts.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Encounters=preload("res://src/content/contract_encounter_definitions.gd")
const ControlRules=preload("res://src/content/combat_training_control_definitions.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const Transit=preload("res://src/content/convoy_transit_definitions.gd")
const VALUES = {"scope":"mido_contract_ship_combat","campaign_cursor":13,"mission_kinds":[4,12],"weapons":{"rank_offset":-2,"rank_multiplier":0.8999999761581421,"rank_level_min":0,"rank_level_max":20,"scaled_level_max":22,"zero_level_damage":3,"damage_offset":2,"game_difficulty_offset":-0.5,"category":0,"capacity":4,"lifetime_ms":3000,"interval_base_ms":600,"interval_cursor_multiplier":-2,"speed":16.0,"rival_speed":28.0,"rival_adds_rank_to_damage":true,"factions":[{"actor_kind":0,"item_id":0,"kind":0,"catalogue_kind":0,"model_resource_id":6754},{"actor_kind":1,"item_id":3,"kind":0,"catalogue_kind":0,"model_resource_id":6760},{"actor_kind":2,"item_id":7,"kind":0,"catalogue_kind":0,"model_resource_id":6764},{"actor_kind":3,"item_id":25,"kind":0,"catalogue_kind":2,"model_resource_id":6802},{"actor_kind":8,"item_id":19,"kind":1,"catalogue_kind":1,"model_resource_id":6795}]},"player_target_id":-1,"initial_target_index":0,"challenge_player_last_for_odd_actor_ids":true,"rival":{"initial_mode":0,"initial_active":true,"initial_targeting_blocked":false,"boost_enabled":false,"motion_speed":2.0,"initial_hostile":false,"updated_hostile":false,"friendly":true},"pirate":{"initial_hostile":false,"updated_hostile":true,"friendly":false,"boost_enabled":true}}
const SPANS = {"ship_combat_weapon_level":[54868,245],"ship_combat_damage":[55500,423],"ship_combat_weapon_factions":[55923,217],"ship_combat_special_guards":[56140,1125],"ship_combat_weapon_constructor":[57315,197],"ship_combat_weapon_table":[58994,44],"ship_combat_targets":[59632,1421],"ship_combat_boost_gate":[621413,474],"ship_combat_hostility":[610958,487],"ship_combat_speed_initialization":[606944,55],"ship_combat_motion_speed":[627033,118],"ship_combat_level_constants":[1575346,12]}

static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data,VALUES)

# Native setup helpers.
static func population(bindings: RefCounted,packet: Dictionary) -> Dictionary:
	if bindings==null or not parameters(bindings.early_contracts.get("ship_combat")) or not Encounters.parameters(bindings.early_contracts.get("encounter_construction")) or not ControlRules.parameters(bindings.combat_training_control):return {}
	var source: Variant=packet.get("contract_encounter")
	var actors: Variant=packet.get("actors")
	if not source is Dictionary or not source.get("context") is Dictionary or not actors is Array:return {}
	var context: Dictionary=source.context
	var rules: Dictionary=bindings.early_contracts.ship_combat
	for key in ["base_content_id","binding_id"]:
		if packet.get(key)!=bindings.get(key) or context.get(key)!=bindings.get(key):return {}
	if not Transit.supports(bindings.mido_travel,packet.get("campaign_cursor")) or context.get("campaign_cursor")!=packet.campaign_cursor or packet.get("station_id")!=context.get("station_id") or context.station_id not in [75,76,77,78,79]:return {}
	if not context.get("rank") is int or context.rank<0 or context.rank>=bindings.opening_handoff.get("rank_thresholds",[]).size():return {}
	if context.get("difficulty") not in [0.5,1.0] or not source.get("mission") is Dictionary or source.mission!=context.get("mission"):return {}
	var mission: Dictionary=source.mission
	if mission.get("kind") not in [4,12] or mission.get("difficulty") not in [1,2] or mission.get("story")!=false or source.get("kind")!=mission.kind or source.get("actor_count")!=actors.size():return {}
	if (mission.kind==12 and actors.size()!=4) or (mission.kind==4 and actors.size() not in [2,3,4]):return {}
	var data:=rules.duplicate(true)
	data.campaign_cursor=context.campaign_cursor
	# Construction already validates the equipped ship's system against these
	# declarations; the retained contract context identifies its station directly.
	data.merge({"station_id":context.station_id,"system_id":int(bindings.early_contracts.encounter_construction.system_id),"rank":context.rank,"difficulty":context.difficulty,
		"mission_kind":mission.kind,"actor_count":actors.size(),"player_ship_id":int(bindings.combat_training_weapons.player_entry.ship_id),
		"actor_kinds":[],"hull_catalogue_ids":[],"target_memberships":[],"player_weapon_targets":[],"npc_weapons":[]})
	for key in ["rank_base","rank_multiplier","cursor_multiplier","difficulty_offset","percentage_scale","engagement_half_extent","proximity_half_extent","target_activation_half_extent","initial_model_draw_enabled","initial_node_draw_requested","initial_engine_draw_enabled","npc_statistics_targeting_blocked","random_selection_chance","random_selection_attempts","nonplayer_selection_checks_range","completed_route_retains_position_once"]:
		data[key]=bindings.combat_training_control[key]
	var hulls: Dictionary=bindings.early_contracts.encounter_construction.hulls
	for id in actors.size():
		var actor: Variant=actors[id]
		var rival: bool=mission.kind==12 and id==0
		if not actor is Dictionary or actor.get("actor_id")!=id or actor.get("subtype")!=0 or actor.get("population_group")!=("rival" if rival else "pirate"):return {}
		var faction: Variant=actor.get("actor_kind")
		if not faction is int or (rival and (faction not in [0,1,2,3] or faction!=context.get("client_faction"))) or (not rival and faction!=8):return {}
		var hull: Variant=actor.get("hull_catalogue_id")
		if not hull is int or hull<0 or hull>=hulls.factions.size() or int(hulls.factions[hull])!=faction or (faction!=1 and hull<=int(hulls.mask_limit) and (int(hulls.excluded_mask)>>hull)&1):return {}
		if rival and (actor.get("friendly")!=true or actor.get("name","").is_empty() or actor.name!=context.get("contact_name") or actor.get("current_hull_override")!=9999999):return {}
		if not rival and (actor.get("mode")!=5 or actor.get("active")!=false or actor.get("targeting_blocked")!=true):return {}
		data.actor_kinds.append(faction);data.hull_catalogue_ids.append(hull);data.player_weapon_targets.append(id)
		var weapon:=shared_weapon(rules.weapons,context.campaign_cursor,context.rank,float(context.difficulty),faction,rival)
		if weapon.is_empty():return {}
		weapon.actor_id=id;weapon.hull_catalogue_id=hull;data.npc_weapons.append(weapon)
	for id in actors.size():
		var targets:=[]
		for other in actors.size():
			if other!=id and data.actor_kinds[id]!=data.actor_kinds[other]:targets.append(other)
		if mission.kind==12 and id%2==1:targets.append(int(rules.player_target_id))
		else:targets.push_front(int(rules.player_target_id))
		data.target_memberships.append(targets)
	return data

static func weapon_for(data: Dictionary,rank: int,difficulty: float,faction: int,rival: bool) -> Dictionary:
	if not parameters(data) or rank<0 or rank>20 or difficulty not in [0.5,1.0] or (rival and faction not in [0,1,2,3]) or (not rival and faction!=8):return {}
	return shared_weapon(data.weapons,int(data.campaign_cursor),rank,difficulty,faction,rival)

static func shared_weapon(rules: Dictionary,cursor: int,rank: int,difficulty: float,faction: int,rival:=false) -> Dictionary:
	if not Equal.equal_value(rules,VALUES.weapons) or cursor not in [13,14,18,19] or rank<0 or rank>20 or difficulty not in [0.5,1.0] or faction not in [0,1,2,3,8]:return {}
	for source in rules.factions:
		if int(source.actor_kind)!=faction:continue
		var row:=scaled_parameters(rules,cursor,rank,difficulty,rival)
		for key in ["actor_kind","item_id","kind","catalogue_kind","model_resource_id"]:row[key]=int(source[key])
		return row
	return {}

static func scaled_parameters(rules: Dictionary,cursor: int,rank: int,difficulty: float,rival:=false) -> Dictionary:
	# Shared factory arithmetic only. The encounter still supplies a verified
	# faction, ship and any authored damage override before creating a gun.
	if not Equal.equal_value(rules,VALUES.weapons) or cursor not in [13,14,16,18,19] or rank<0 or rank>20 or difficulty not in [0.5,1.0]:return {}
	var level:=int(clampf(Vitals.single(float(rank+int(rules.rank_offset))*float(rules.rank_multiplier)),float(rules.rank_level_min),float(rules.rank_level_max)))
	level=mini(int(rules.scaled_level_max),int(Vitals.single(float(level)+Vitals.single(float(level)*Vitals.single(difficulty+float(rules.game_difficulty_offset))))))
	var damage:=int(rules.zero_level_damage) if level==0 else level+int(rules.damage_offset)
	if rival:damage+=rank
	return {"category":int(rules.category),"damage":damage,"projectile_capacity":int(rules.capacity),"lifetime_ms":int(rules.lifetime_ms),
		"interval_ms":int(rules.interval_base_ms)+cursor*int(rules.interval_cursor_multiplier),
		"speed_units_per_millisecond":float(rules.rival_speed if rival else rules.speed),"nonplayer_source":true}
