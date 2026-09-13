extends RefCounted
## Prepares a detached supported mining world. Activation, entry-camera time,
## acknowledged briefing, manual flight and mining have separate native owners.
const MiningFlight=preload("res://src/content/full_hold_flight_definitions.gd")
const Handoff=preload("res://src/content/opening_handoff_definitions.gd")
const Location=preload("res://src/simulation/arrival_location.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const Scenery=preload("res://src/simulation/opening_scenery.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Rig=preload("res://src/simulation/camera_rig.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
var error:=""
var _state:={}
var _scenery: RefCounted
var _camera: RefCounted
var _player: RefCounted

func prepare(bindings: RefCounted, catalogues: RefCounted, packet: Dictionary, environment_seconds: Variant, unix_seconds: Variant, large_display:=true, body_resources: RefCounted=null, effect_resources: RefCounted=null) -> bool:
	error=""
	if bindings==null or catalogues==null or not Handoff.parameters(bindings.opening_handoff):return reject("This pack has no supported mining-flight construction")
	var data:=MiningFlight.flight(bindings,packet.get("campaign_cursor"))
	if data.is_empty():return reject("This departure has no supported mining-flight construction")
	var location:=Location.new()
	var context:=location.resolve_departure(bindings,catalogues,packet.get("player_cache"))
	if context.is_empty():return reject(location.error)
	var player:=Player.new()
	if not player.configure_departure(bindings,catalogues,int(data.campaign_cursor)):return reject(player.error)
	if not _valid_packet(bindings,packet,context,player):return false
	var random:=Random.new()
	if not Numbers.integer(environment_seconds,0,2147483647):return reject("First flight requires explicit environment Unix seconds")
	random.seed_from(environment_seconds)
	var input_random:=random.snapshot()
	if bindings.resolve(int(data.environment_object_resource_id),"mesh").is_empty():return reject(bindings.error)
	# The ordinary early-campaign environment reseeds from Unix seconds, then
	# places the wormhole before selecting yaw. Field construction reseeds again.
	var environment_position:=Vector3.ZERO
	for axis in 3:environment_position[axis]=int(data.environment_object_position_offsets[axis])+random.next_int(int(data.environment_object_position_bounds[axis]))
	var before_yaw:=random.snapshot()
	var units:=int(data.yaw_units)*(1 if random.next_int(2)==0 else -1)
	var yaw:=f32(f32(units*float(data.angle_fraction))*float(data.angle_tau))
	var pose:=Transform3D(Basis(Vector3.UP,yaw),Vector3(data.player_position[0],data.player_position[1],data.player_position[2]))
	var yaw_random:=random.snapshot()
	var conditions:={"companions_empty":true,"location_match":false,"special_placement":false}
	var scenery:=Scenery.new()
	if not scenery.configure_departure(bindings,catalogues,packet.player_cache,conditions,unix_seconds,large_display,body_resources,effect_resources):return reject(scenery.error)
	if not scenery.complete_world_initialization(bindings,catalogues):return reject(scenery.error)
	var field: Dictionary=scenery.snapshot()
	if not random.restore(field.random_state):return reject(random.error)
	var camera_input:=random.snapshot()
	var offset:=Vector3.ZERO
	for axis in 2:offset[axis]=int(data.camera_axis_base)+random.next_int(int(data.camera_axis_bound))
	offset.z=float(data.camera_z)
	for axis in 2:
		if random.next_int(2)==0:offset[axis]=-offset[axis]
	var identity:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	var scene:=identity.duplicate();scene.player_pose=pose
	var shot:=identity.duplicate();shot.merge({"target":"player","mode":"follow"})
	var initial:=shot.duplicate();initial.merge({"mode":"fixed_eye","eye":pose*offset,"inherit_target_up":true},true)
	var camera:=Rig.new()
	if not camera.configure(bindings) or not camera.update(0,shot,scene,initial):return reject(camera.error)
	var state:=identity.duplicate()
	state.merge({"campaign_cursor":int(data.campaign_cursor),"world_type":int(data.world_type),"location":context,
		"entry_conditions":conditions,"departure":packet.duplicate(true),"player_pose":pose,"player_yaw_units":units,
		"camera_shot":shot,"camera_offset":offset,"input_random_state":input_random,"before_yaw_random_state":before_yaw,"yaw_random_state":yaw_random,
		"environment_seconds":environment_seconds,"environment_object":{"resource_id":int(data.environment_object_resource_id),"position":environment_position},
		"camera_input_random_state":camera_input,"random_state":random.snapshot(),"unix_seconds":unix_seconds,
		"entry_released":false,"entry_elapsed_ms":0,"briefing_started":false,"activated":false})
	# Commit only after every prospective owner accepts the complete entry.
	_state=state;_scenery=scenery;_camera=camera;_player=player
	return true

func _valid_packet(bindings: RefCounted, packet: Dictionary, context: Dictionary, player: RefCounted) -> bool:
	var data: Dictionary=bindings.full_hold_departure if packet.get("campaign_cursor")==4 else bindings.station_departure
	if packet.size()!=16:return reject("First flight requires a complete departure packet")
	for key in ["base_content_id","binding_id"]:
		if packet.get(key)!=bindings.get(key):return reject("First-flight packet belongs to another content identity")
	for key in ["campaign_cursor","source_state","world_type","audio_selector","confirmation_required","confirmation_text_id"]:
		var expected: Variant=int(data[key]) if data[key] is float else data[key]
		if typeof(packet.get(key))!=typeof(expected) or packet[key]!=expected:return reject("First-flight departure field changed: "+key)
	var seed:=context.duplicate(true)
	for key in ["campaign_cursor","world_type","sky_index","sky_parameters","current_planet_texture_id"]:seed.erase(key)
	var actual: Dictionary=player.snapshot()
	var reset:=Cache.departure_cache(bindings.opening_actors.player_initialization.flight_cache,data,seed,actual.max_hull,actual.capacities,true)
	if packet.get("loadout")!=seed or packet.get("player")!=actual or packet.get("player_cache")!=player.cache_snapshot() or packet.get("reset_cache")!=reset:return reject("First flight disagrees with the fresh replacement ship")
	if packet.get("cargo_used")!=int(data.initial_cargo_used) or packet.get("source_ship_configuration")!=int(bindings.station_entry.source_ship_configuration):return reject("First flight changed replacement cargo or ship configuration")
	var progress: Variant=packet.get("progress")
	if not progress is Dictionary or not Numbers.integer(progress.get("player_kills"),0,3):return reject("First flight requires supported earned Opening progress")
	var rules: Dictionary=bindings.opening_handoff
	var kills:=int(progress.player_kills)
	var score:=kills*(int(rules.player_kill_weight)+int(rules.pirate_kill_weight))+int(data.campaign_cursor)*int(rules.cursor_weight)
	var rank:=0
	for i in rules.rank_thresholds.size():
		if score>=int(rules.rank_thresholds[i]):rank=i
	if progress!={"campaign_cursor":int(data.campaign_cursor),"rank":rank,"rank_score":score,"player_kills":kills,"pirate_kills":kills,"other_score":int(rules.initial_other_score)}:return reject("First flight changed earned campaign progress")
	var mission: Dictionary=bindings.station_entry.mission
	var mission_kind:=int(data.mission_kind) if int(data.campaign_cursor)==4 else int(mission.next_kind)
	var mission_parameter:=int(data.mission_parameter) if int(data.campaign_cursor)==4 else int(mission.next_parameter)
	if packet.get("mission")!={"kind":mission_kind,"station_id":seed.station_id,"reward":0,"bonus":0,"source_parameter":mission_parameter}:return reject("Mining flight changed the mining mission or granted a reward")
	return true

func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_state.duplicate(true)
	result.scenery=_scenery.snapshot();result.camera_view=_camera.snapshot();result.player=_player.snapshot()
	return result

func scenery_owner() -> RefCounted:return null if _scenery==null else _scenery.fork_for_frame()
func camera_owner() -> RefCounted:return null if _camera==null else _camera.fork_for_frame()
func player_owner() -> RefCounted:return null if _player==null else _player.fork_for_frame()
func clear() -> void:error="";_state={};_scenery=null;_camera=null;_player=null
static func f32(value: float) -> float:return PackedFloat32Array([value])[0]
func reject(message: String) -> bool:error=message;return false
