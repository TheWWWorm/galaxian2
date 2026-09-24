extends RefCounted
## Fresh ordinary flight after cinematic release. Pose stays in the scene;
## retained angular response is sampled after its camera pass for the next frame.
const Definitions = preload("res://src/content/opening_player_flight_definitions.gd")
const Pilot = preload("res://src/simulation/pilot_motion.gd")
const Vehicle = preload("res://src/simulation/vehicle_response.gd")
const Loadout = preload("res://src/simulation/opening_loadout.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
var error := ""
var _identity := {}
var _rules := {}
var _pilot: RefCounted
var _effective_throttle := 0.0

func configure(bindings: RefCounted, catalogues: RefCounted, sensitivity: float) -> bool:
	_identity={};_rules={};_pilot=null;_effective_throttle=0.0;error=""
	if bindings==null or catalogues==null: return reject("Player flight requires its content and equipment")
	var rules: Dictionary=bindings.opening_staging.get("player_flight",{})
	var repair: Dictionary=bindings.opening_actors.get("player_initialization",{}).get("repair",{})
	if not Definitions.parameters(rules) or repair.is_empty(): return reject("This profile lacks fresh ordinary player flight")
	var loadout := Loadout.new();var vehicle := Vehicle.new()
	if not loadout.configure(bindings,catalogues,bindings.base_content_id): return reject(loadout.error)
	if not vehicle.configure(bindings,catalogues,bindings.base_content_id): return reject(vehicle.error)
	var seed: Dictionary=loadout.snapshot()
	var resolved: Dictionary=vehicle.resolve(seed.ship_id,repair.initial_upgrades,seed.equipment_ids)
	if resolved.is_empty(): return reject(vehicle.error)
	var pilot := Pilot.new()
	if not pilot.configure(bindings,bindings.base_content_id,resolved.response_factor,sensitivity): return reject(pilot.error)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_rules=rules.duplicate(true);_pilot=pilot;_effective_throttle=float(_rules.initial_throttle)
	_pilot.angular_units=Vector2(rules.initial_pitch_units,rules.initial_yaw_units)
	return true

func motion(scene: Dictionary, phase: Variant, delta_ms: Variant, strafe_command:=0.0, brake:=false) -> Dictionary:
	error=""
	if _identity.is_empty(): return fail("Configure player flight before advancing")
	for key in _identity:
		if scene.get(key)!=_identity[key]: return fail("Player flight belongs to another scene")
	if not Numbers.integer(phase,int(_rules.ordinary_phase),int(_rules.ordinary_phase)) or not Numbers.integer(delta_ms,0,150):
		return fail("Player flight requires the supported ordinary encounter frame")
	var prior: Variant=scene.get("player_pose")
	if not prior is Transform3D: return fail("Player flight requires a retained pose")
	var effective_throttle := 0.0 if brake else float(_rules.initial_throttle)
	var pose: Transform3D=_pilot.advance_prepared(prior,effective_throttle,float(delta_ms)/1000.0,strafe_command)
	if not _pilot.error.is_empty(): return fail(_pilot.error)
	_effective_throttle=effective_throttle
	var result := _identity.duplicate()
	result.prior_pose=prior;result.pose=pose
	return result

func sample_commands(commands: Vector2, delta_ms: Variant) -> bool:
	error=""
	if _pilot==null or not Numbers.integer(delta_ms,0,150): return reject("Invalid player input frame")
	if not _pilot.sample_commands(commands,float(delta_ms)/1000.0):return reject(_pilot.error)
	return true

func boundary_event() -> int:
	return int(_rules.get("postcombat_after_event_finished",-1))

func snapshot() -> Dictionary:
	if _identity.is_empty(): return {}
	var result := _identity.duplicate()
	result.angular_units=_pilot.angular_units;result.throttle=_effective_throttle
	result.lateral_units_per_millisecond=_pilot.lateral_units_per_millisecond
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._identity=_identity.duplicate();copy._rules=_rules
	copy._pilot=_pilot.fork_for_frame();copy._effective_throttle=_effective_throttle
	return copy

func reject(message: String) -> bool:
	error=message;return false

func fail(message: String) -> Dictionary:
	reject(message);return {}
