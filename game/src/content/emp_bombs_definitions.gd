extends RefCounted
## Original player EMP bomb flight, blast and systems recovery.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const VALUES = {"scope":"player_emp_bomb_physics","category":1,"kind":6,"item_ids":[41,42,43],"model_ids":[14684,14684,14684],"capacity":1,"system_damage_property":10,"blast_radius_property":14,"muzzle_offset":[0.0,0.0,400.0],"cooldown_initial_interval":true,"cooldown_strict":true,"ammunition_per_launch":1,"ammunition_per_detonation":0,"manual_detonation":true,"contact_detonation":true,"expiry_detonation":true,"blast_distance_truncated":true,"blast_radius_strict":true,"linear_system_damage":true,"normal_damage":false,"detonated_lifetime":-1,"systems":{"scope":"emp_system_damage_and_recovery","requires_active":true,"requires_damage_permission":true,"requires_positive_hull":true,"requires_positive_integrity":true,"partial_integrity_recovers":false,"recovery_while_disabled":true,"recovery_strict":true,"depletion_resets_recovery":true,"affects_combat_pools":false}}
const SPANS = {"emp_factory_case":[67190,4],"emp_factory":[65815,232],"emp_muzzle_offset":[1574918,4],"emp_models":[1576622,12],"emp_radius_assignment":[-35845,29],"emp_radius_setter":[-188312,12],"emp_initial_clock":[-189587,54],"emp_owner_trigger":[543530,362],"emp_launch_quantity":[-187771,81],"emp_launch_position":[-187669,706],"emp_launch_direction":[-186542,206],"emp_launch_motion":[-186124,147],"emp_launch_consume":[-185977,281],"emp_frame_clock":[-180349,57],"emp_frame_motion":[-180195,539],"emp_collision_kind":[-183037,134],"emp_collision_detonation":[-182388,18],"emp_collision_tail":[-180382,13],"emp_pulse":[-184530,1454],"emp_active_getter":[540924,14],"emp_immune_getter":[535540,28],"emp_system_configuration":[535708,56],"emp_system_damage_gates":[538094,81],"emp_system_subtract":[538465,23],"emp_system_disabled":[538870,40],"emp_system_recovery":[544763,112]}

# Native composition.
static func parameters(data: Variant) -> bool:return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and parameters(bindings.mido_travel.get("emp_bombs"))
