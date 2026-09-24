extends RefCounted
const Layouts=preload("res://src/content/declaration_layouts.gd")
## Verified ordinary gun variants and equipped player entry for combat training.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Training=preload("res://src/content/combat_training_definitions.gd")
const TrainingControl=preload("res://src/content/combat_training_control_definitions.gd")
const Equipment=preload("res://src/content/station_equipment_definitions.gd")
const Player=preload("res://src/content/player_initialization_definitions.gd")
const Hit=preload("res://src/content/ordinary_hit_definitions.gd")
const PlayerHit=preload("res://src/content/player_hit_definitions.gd")
const Bounds=preload("res://src/content/weapon_collision_bounds.gd")
const Audio=preload("res://src/content/weapon_audio_definitions.gd")
const VALUES := {"scope":"combat_training_ordinary_weapons","campaign_cursor":7,"actor_count":4,"rank_min":0,"rank_max":1,"npc_weapons":[{"actor_id":0,"actor_kind":8,"hull_catalogue_id":2,"item_id":19,"category":0,"kind":1,"catalogue_kind":1,"damage":3,"interval_ms":586,"lifetime_ms":3000,"projectile_capacity":4,"speed_units_per_millisecond":16.0,"model_resource_id":6795,"nonplayer_source":true},{"actor_id":1,"actor_kind":8,"hull_catalogue_id":2,"item_id":19,"category":0,"kind":1,"catalogue_kind":1,"damage":3,"interval_ms":586,"lifetime_ms":3000,"projectile_capacity":4,"speed_units_per_millisecond":16.0,"model_resource_id":6795,"nonplayer_source":true},{"actor_id":2,"actor_kind":8,"hull_catalogue_id":2,"item_id":19,"category":0,"kind":1,"catalogue_kind":1,"damage":3,"interval_ms":586,"lifetime_ms":3000,"projectile_capacity":4,"speed_units_per_millisecond":16.0,"model_resource_id":6795,"nonplayer_source":true},{"actor_id":3,"actor_kind":3,"hull_catalogue_id":30,"item_id":25,"category":0,"kind":0,"catalogue_kind":2,"damage":3,"interval_ms":586,"lifetime_ms":3000,"projectile_capacity":4,"speed_units_per_millisecond":16.0,"model_resource_id":6802,"nonplayer_source":true}],"target_memberships":[[-1,3],[-1,3],[-1,3],[-1,0,1,2]],"player_weapon_targets":[0,1,2,3],"player_primary":{"item_id":22,"category":0,"kind":2,"projectile_capacity":25,"dispersion":{"steps":2,"draw_scale":0.01,"center_scale":0.005}},"player_entry":{"ship_id":0,"station_id":78,"system_id":15,"campaign_cursor":7,"cache_reset":-1}}
const SPANS := {"npc_setup":[54772,4266],"weapon_constructor":[-190034,1052],"item_setter":[-188700,356],"nonplayer_setter":[-188326,14],"world_setter":[-187836,10],"spread_setter":[-188344,18],"mount_setter":[-188274,68],"ordinary_launch":[-187798,3176],"ordinary_update":[-180366,710],"contacts":[-183076,2704],"normal_damage":[538936,1846],"player_factory":[-37352,2046],"weapon_factory":[64358,2880],"cache_reset_and_state":[431888,113],"world_entry":[335220,77],"refresh_equipment":[857965,93],"equipment_departure_gate":[437089,263],"player_mount_assignment":[-35754,56],"weapon_dispatch":[67166,12],"npc_dispatch":[58994,36],"spread_scale":[1556914,4],"spread_center":[1572190,4],"npc_speed":[1575350,4]}

const MAC_ALTERNATE := {"npc_setup":[54772,4266],"weapon_constructor":[-190526,1052],"item_setter":[-189192,356],"nonplayer_setter":[-188818,14],"world_setter":[-188328,10],"spread_setter":[-188836,18],"mount_setter":[-188766,68],"ordinary_launch":[-188290,3176],"ordinary_update":[-180858,710],"contacts":[-183568,2704],"normal_damage":[539472,1846],"player_factory":[-37352,2046],"weapon_factory":[64358,2880],"cache_reset_and_state":[432316,113],"world_entry":[334920,77],"refresh_equipment":[858597,93],"equipment_departure_gate":[437523,262],"player_mount_assignment":[-35754,56],"weapon_dispatch":[67166,12],"npc_dispatch":[58994,36],"spread_scale":[1531914,4],"spread_center":[1547254,4],"npc_speed":[1550414,4]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, training: Dictionary, control: Dictionary, equipment: Dictionary, actors: Dictionary, weapons: Dictionary) -> String:
	if not data is Dictionary:return "Missing combat-training weapon declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported combat-training weapon declarations"
	if not Training.parameters(training) or not TrainingControl.parameters(control) or not Equipment.parameters(equipment) or not Player.parameters(actors.get("player_initialization")):return "Combat-training weapons lack verified world, control, equipment or player context"
	for key in ["ordinary_hit_policy","player_hit_policy","collision_bounds","audio"]:
		if not weapons.get(key) is Dictionary or weapons[key].is_empty():return "Combat-training weapons lack shared contact or audio declarations"
	if not Hit.parameters(weapons.ordinary_hit_policy) or not PlayerHit.parameters(weapons.player_hit_policy) or not Bounds.parameters(weapons.collision_bounds) or not Audio.parameters(weapons.audio):return "Invalid combat-training shared weapon context"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Combat-training weapons lack their source anchor"
	var layouts: Array=[SPANS,MAC_ALTERNATE]
	return "" if Layouts.matches(data.provenance,int(origin.offset),source_bytes,layouts) else "Invalid combat training weapon extents"

static func dispersed_primary(weapon: Dictionary) -> bool:
	var rule: Dictionary=VALUES.player_primary
	for key in ["item_id","category","kind","projectile_capacity"]:
		if not weapon.get(key) is int or weapon[key]!=int(rule[key]):return false
	return Equal.equal_value(weapon.get("dispersion"),rule.dispersion)

static func npc_hit(data: Dictionary, weapon: Dictionary) -> bool:
	if not parameters(data) or weapon.get("nonplayer_source")!=true:return false
	for row in data.npc_weapons:
		var matches:=true
		for key in ["item_id","category","kind","damage"]:
			if not weapon.get(key) is int or weapon[key]!=int(row[key]):matches=false
		if matches:return true
	return false
