extends RefCounted
const FlightStages=preload("res://src/content/flight_stages.gd")
const Frames=preload("res://src/simulation/frame_clock.gd")
var _max_ms:=0
## Mac starter destruction component. The flight owner supplies its physical
## motion before each player pass, then applies the returned camera, activity,
## particle and audio events in source order. No cargo or save is owned here.
const Definitions=preload("res://src/content/player_destruction_definitions.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Resources=preload("res://src/content/npc_destruction_resources.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Ordinary=preload("res://src/content/ordinary_flight_definitions.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Explosion=preload("res://src/simulation/type_zero_explosion.gd")
const Training=preload("res://src/content/combat_training_story_definitions.gd")
const Fitting=preload("res://src/content/ordinary_fitting_definitions.gd")
var error:=""
var _rules:={}
var _state:={}
var _presentation_identity: RefCounted
# Immutable departure template shared by frame forks. The launcher remains
# the authority for any later removal of an exhausted ammunition stack.
var _departure_loadout: Dictionary={}

func configure(bindings: RefCounted, resources: RefCounted, construction: RefCounted,catalogues: RefCounted=null) -> bool:
	error=""
	if not bindings is Bindings or not resources is Resources or not construction is Construction or not Definitions.parameters(bindings.player_destruction):return reject("Player destruction requires its verified Mac departure and effect resources")
	var rules: Dictionary=bindings.player_destruction
	var entry: Dictionary=construction.snapshot();var effect: Dictionary=resources.snapshot()
	for key in ["base_content_id","binding_id"]:
		if entry.get(key)!=bindings.get(key) or effect.get(key)!=bindings.get(key):return reject("Player destruction belongs to another content identity")
	var training: bool=entry.get("campaign_cursor")==7
	var local_flight: bool=entry.get("campaign_cursor") in (FlightStages.LOCAL+FlightStages.POST_SAHI)
	var first_mining: bool=entry.get("campaign_cursor")==2
	if first_mining:
		var flight: Dictionary=Ordinary.for_departure(bindings,entry)
		var objective: Dictionary=Ordinary.objective(bindings,2)
		if flight.is_empty() or objective.is_empty() or construction.equipment_owner()!=null:return reject("First-mining destruction requires its accepted starter departure and objective")
		rules=rules.duplicate(true)
		rules.departure_cursor=int(flight.campaign_cursor)
		rules.story_cursors=[int(flight.campaign_cursor),int(objective.cursor_after_acknowledgement)]
	elif training:
		if Training.flight(bindings).is_empty() or construction.equipment_owner()==null:return reject("Training destruction requires its equipped ordinary departure")
		rules=rules.duplicate(true)
		rules.departure_cursor=7;rules.story_cursors=[7,int(bindings.combat_training_story.cursor_after_acknowledgement)]
	elif local_flight:
		if Ordinary.for_departure(bindings,entry).is_empty() or construction.equipment_owner()==null:return reject("Local destruction requires its equipped Mido flight")
		rules=rules.duplicate(true);rules.departure_cursor=int(entry.campaign_cursor);rules.story_cursors=[entry.campaign_cursor,17 if entry.campaign_cursor==16 else entry.campaign_cursor]
		var campaign=load("res://src/content/free_campaign_definitions.gd")
		if campaign.visit_at(bindings.mido_travel,entry.campaign_cursor,entry.location.station_id):
			var visit: Dictionary=campaign.dialogue_rules(bindings,entry.campaign_cursor,entry.departure.mission)
			rules.story_cursors.append(int(visit.next_cursor))
		if Ordinary.Kappa.prepared_entry(bindings,entry):rules.story_cursors.append(22)
	if entry.get("campaign_cursor")!=int(rules.departure_cursor) or entry.get("departure",{}).get("loadout",{}).get("ship_id")!=int(rules.ship_id):return reject("Unsupported player destruction context")
	var clock:=Explosion.create(effect,[],14292)
	if clock.is_empty():return reject("Player destruction lacks its authored explosion clocks")
	for index in 2:
		if clock.models[index].get("model_id")!=int(rules.model_ids[index]) or clock.models[index].get("resource")!=Resources.PATHS[index]:return reject("Player destruction changed its explosion model bindings")
	var initial: Dictionary=entry.get("player",{})
	var expected_equipment: Array=construction.equipment_owner().snapshot().loadout.equipment_ids if training or local_flight else [90,81]
	if initial.get("ship_id")!=int(rules.ship_id) or initial.get("equipment_ids")!=expected_equipment:return reject("Player destruction requires its retained starter loadout")
	# The native tutorial inventory can only contain these source offers and
	# retained drill/scanner. None supplies the escape-pod subtype27.
	if training and not expected_equipment.all(func(id):return id in [0,22,55,81,90]):return reject("Training destruction has an unsupported escape-device context")
	if local_flight:
		if entry.campaign_cursor in (FlightStages.FREE+FlightStages.POST_SAHI) and Fitting.available(bindings) and catalogues!=null:
			if catalogues.content_id!=bindings.base_content_id:return reject("Destruction equipment belongs to another catalogue")
			for id in expected_equipment:
				if not Numbers.integer(id,0,catalogues.tables.items.size()-1) or catalogues.tables.items[id].arrays[2][5]==27:return reject("Escape-device destruction is not yet supported")
		# Either tutorial starter gun may remain mounted beside the exchanged gear.
		elif expected_equipment not in [[22,86,81,55],[0,86,81,55]]:return reject("Local destruction has an unsupported escape-device context")
	_rules=rules.duplicate(true)
	# Imported JSON numbers become floats; native story observations use ints.
	_rules.story_cursors=_rules.story_cursors.map(func(value):return int(value))
	_max_ms=Frames.simulation_limit(bindings,150)
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"actor_id":"player",
		"departure_cursor":int(rules.departure_cursor),"campaign_cursor":int(rules.departure_cursor),
		"phase":"ready","elapsed_ms":0,"player_updates":0,"failure_elapsed_ms":0,"fade_elapsed_ms":0,
		"failed":false,"exit_requested":false,"fragments":[],"effect":clock,
		"physical_pose":entry.player_pose,"statistics_pose":entry.player_pose,"model_rotation":Vector3.ZERO,"rendered_model_basis":Basis.IDENTITY,
		"camera_pose":entry.camera_view.pose,"camera_follow_enabled":true,"particle_emitting":false,"particle_drawing":true,
		"equipment_ids":initial.equipment_ids.duplicate(),"events":{}}
	_departure_loadout=entry.departure.loadout.duplicate(true)
	_presentation_identity=RefCounted.new()
	return true

func start(player: RefCounted, physical_pose: Variant, model_rotation: Variant, camera_pose: Variant, campaign_cursor: Variant, rendered_model_basis: Variant=null, statistics_pose: Variant=null, secondaries: RefCounted=null) -> bool:
	error=""
	if _state.is_empty() or _state.phase!="ready" or not player is Player:return reject("Start player destruction once, after accepted lethal contact")
	var current: Dictionary=player.snapshot()
	for key in ["base_content_id","binding_id"]:
		if current.get(key)!=_state[key]:return reject("Lethal player belongs to another departure")
	if current.get("campaign_cursor")!=_state.departure_cursor or current.get("ship_id")!=int(_rules.ship_id) or not _accepts_equipment(current.get("equipment_ids"),secondaries):return reject("Lethal player changed its supported loadout")
	if not Numbers.integer(current.get("vitals",{}).get("hull"),0,0):return reject("Player destruction requires exhausted hull")
	if not Flight.rigid_pose(physical_pose) or not Flight.rigid_pose(camera_pose) or not model_rotation is Vector3 or not model_rotation.is_finite():return reject("Player destruction requires finite source poses and Euler angles")
	if not campaign_cursor is int or not campaign_cursor in _rules.story_cursors:return reject("Unsupported player destruction story cursor")
	if (rendered_model_basis==null)!=(statistics_pose==null):return reject("Supply the retained visual basis and statistics pose together")
	if rendered_model_basis!=null:
		if not rendered_model_basis is Basis or not Flight.rigid_pose(Transform3D(rendered_model_basis,Vector3.ZERO)) or not Flight.rigid_pose(statistics_pose):return reject("Player destruction requires rigid retained visual and statistics poses")
	else:
		rendered_model_basis=Vectors.local_xyz(model_rotation)
		statistics_pose=physical_pose*Transform3D(rendered_model_basis,Vector3.ZERO)
	var next:=_state.duplicate(true)
	next.phase="tumble";next.physical_pose=physical_pose;next.model_rotation=model_rotation
	# Banking writes a matrix without updating the child's stored Euler angles.
	# Statistics may have sampled an earlier bank, or retained a mining pose.
	next.rendered_model_basis=rendered_model_basis;next.statistics_pose=statistics_pose
	next.camera_pose=camera_pose;next.campaign_cursor=campaign_cursor;next.particle_emitting=true
	next.camera_follow_enabled=false
	var stop_ids: Array[int]=[]
	for identifier in _rules.stop_sound_ids:stop_ids.append(int(identifier))
	next.events={"started":true,"breakup":false,"failed":false,"expired":false,
		"disable_camera_follow":true,"disable_statistics":true,"disable_engine_effects":true,
		"stop_current_engine_sound":true,"stop_current_music":true,"stop_sound_ids":stop_ids,
		"sound_events":[],"audio_events":[],"particle_events":[{"emitting":true}]}
	_state=next
	return true

func _accepts_equipment(equipment_ids: Variant,secondaries: RefCounted=null) -> bool:
	if equipment_ids==_state.equipment_ids:return true
	if not is_instance_of(secondaries,load("res://src/simulation/secondary_weapons.gd")):return false
	var retained: Dictionary=secondaries.reconcile_loadout(_departure_loadout)
	return not retained.is_empty() and equipment_ids==retained.equipment_ids

func player_updates_enabled() -> bool:
	return not _state.is_empty() and _state.phase!="ready" and not _state.exit_requested and _state.fade_elapsed_ms<int(_rules.fade_ms)

func advance(milliseconds: Variant, physical_pose: Variant, random_state: Variant, paused:=false, statistics_pose: Variant=null, player_tail:=true) -> Dictionary:
	error=""
	if _state.is_empty() or _state.phase=="ready" or not Numbers.integer(milliseconds,0,_max_ms) or not Flight.rigid_pose(physical_pose):return fail("Player destruction requires a started scene, finite physical pose and bounded frame")
	if statistics_pose!=null and not Flight.rigid_pose(statistics_pose):return fail("Player destruction requires a rigid statistics sample from flight")
	var random:=Random.new()
	if not random.restore(random_state):return fail(random.error)
	if paused or _state.exit_requested:return {"state":snapshot(),"random_state":random.snapshot(),"events":{}}
	var next:=_state.duplicate(true)
	var events:={"started":false,"breakup":false,"failed":false,"expired":false,"sound_events":[],"audio_events":[],"particle_events":[]}
	var was_failed: bool=next.failed
	if was_failed:
		if next.failure_elapsed_ms>2147483647-milliseconds or next.fade_elapsed_ms>2147483647-milliseconds:return fail("Player destruction clock exceeds supported range")
		next.failure_elapsed_ms+=milliseconds
	if player_updates_enabled() and player_tail:
		# Manual motion samples the preceding visual matrix. Guided motion may
		# overwrite that sample; mining may retain it. The flight owner supplies
		# those modes' statistics before this tail rebuilds the visual matrix.
		next.physical_pose=physical_pose
		next.statistics_pose=statistics_pose if statistics_pose!=null else physical_pose*Transform3D(next.rendered_model_basis,Vector3.ZERO)
		next.model_rotation=Vectors.added(next.model_rotation,Vector3.ONE*float(_rules.spin_per_update))
		next.rendered_model_basis=Vectors.local_xyz(next.model_rotation)
		next.player_updates+=1
		var old_ms: int=next.elapsed_ms
		if old_ms<int(_rules.breakup_ms) and old_ms+milliseconds>=int(_rules.breakup_ms):
			Explosion.trigger(next.effect,physical_pose.origin)
			events.breakup=true
			var sound:=int(_rules.breakup_sound_base)+random.next_int(int(_rules.breakup_sound_bound))
			events.sound_events.append(sound);events.audio_events.append({"source_id":sound,"position":physical_pose.origin})
			next.particle_emitting=false;next.particle_drawing=false
			events.particle_events.append({"emitting":false,"drawing":false,"impact_requested":true})
		elif old_ms>int(_rules.effect_update_after_ms):
			events.expired=Explosion.advance(next.effect,milliseconds)
		next.elapsed_ms+=milliseconds
	elif physical_pose!=next.physical_pose or (statistics_pose!=null and statistics_pose!=next.statistics_pose):
		return fail("A skipped player tail must retain physical and statistics poses")
	# The later mission poll repeats the emitter-enable call until failure is
	# set. On the breakup frame this follows the earlier disable/draw operations.
	if not was_failed:
		next.particle_emitting=true;events.particle_events.append({"emitting":true})
		if next.elapsed_ms>int(_rules.failure_after_ms):
			next.failed=true;next.failure_elapsed_ms=0;next.fade_elapsed_ms=0;events.failed=true
			events.sound_events.append(int(_rules.failure_sound))
			events.audio_events.append({"source_id":int(_rules.failure_sound),"position":null})
	elif next.failure_elapsed_ms>int(_rules.failure_delay_ms):
		next.fade_elapsed_ms+=milliseconds
	if not next.model_rotation.is_finite() or not Flight.rigid_pose(next.statistics_pose) or not Flight.rigid_pose(Transform3D(next.rendered_model_basis,Vector3.ZERO)):return fail("Player destruction exceeded source coordinate precision")
	next.phase="explosion" if next.elapsed_ms>=int(_rules.breakup_ms) else "tumble"
	if next.failed:
		next.phase="game_over_delay" if next.failure_elapsed_ms<=int(_rules.failure_delay_ms) else "game_over_fade"
		if next.fade_elapsed_ms>=int(_rules.fade_ms):next.phase="game_over"
	next.events=events
	_state=next
	return {"state":snapshot(),"random_state":random.snapshot(),"events":events.duplicate(true)}

func request_exit() -> Dictionary:
	error=""
	if _state.get("phase")!="game_over" or _state.exit_requested:return fail("Game-over exit requires a new acknowledgement after the fade")
	_state.exit_requested=true
	return {"base_content_id":_state.base_content_id,"binding_id":_state.binding_id,
		"source_state":int(_rules.continue_source_state),"campaign_cursor":_state.campaign_cursor}

func sample_camera(pose: Variant, follow_enabled: Variant) -> bool:
	error=""
	if _state.is_empty() or _state.phase=="ready" or _state.exit_requested or not Flight.rigid_pose(pose) or not follow_enabled is bool:return reject("Death camera sampling requires its active flight's proper view")
	# Death disables follow once. A later mining release can re-enable it;
	# camera updates occur after the player tail and continue after fade end.
	_state.camera_pose=pose;_state.camera_follow_enabled=follow_enabled
	return true

func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_state.duplicate(true)
	result.body_visible=result.phase=="ready" or result.elapsed_ms<int(_rules.breakup_ms)
	result.body_pose=result.physical_pose*Transform3D(result.rendered_model_basis,Vector3.ZERO)
	result.hud_visible=result.phase=="ready"
	result.statistics_active=result.phase=="ready"
	result.player_updates_enabled=player_updates_enabled()
	result.game_over_visible=result.failed and result.failure_elapsed_ms>int(_rules.failure_delay_ms)
	result.continue_enabled=result.phase=="game_over" and not result.exit_requested
	result.game_over_alpha_byte=mini(255,int(Vitals.single(Vitals.single(float(result.fade_elapsed_ms)/float(_rules.fade_ms))*255.0)))
	return result

func presentation_identity() -> RefCounted:return _presentation_identity

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._rules=_rules.duplicate(true);copy._state=_state.duplicate(true);copy._presentation_identity=_presentation_identity
	copy._departure_loadout=_departure_loadout
	copy._max_ms=_max_ms;return copy

func clear() -> void:_max_ms=0;error="";_rules={};_state={};_presentation_identity=null;_departure_loadout={}
func reject(message: String) -> bool:error=message;return false
func fail(message: String) -> Dictionary:reject(message);return {}
