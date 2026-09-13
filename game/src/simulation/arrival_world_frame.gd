extends RefCounted
## Owns the supported rescue cinematic: restored player, authored actor, field,
## scene clock, radio and fades. The next station remains an explicit boundary.
const Definitions=preload("res://src/content/arrival_session_definitions.gd")
const HandoffDefinitions=preload("res://src/content/opening_handoff_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Scenery=preload("res://src/simulation/opening_scenery.gd")
const Staging=preload("res://src/simulation/arrival_choreography.gd")
const Motion=preload("res://src/simulation/arrival_actor_motion.gd")
const Radio=preload("res://src/simulation/radio_sequence.gd")
const Fade=preload("res://src/simulation/black_fade.gd")
const View=preload("res://src/simulation/camera_view.gd")
const Detail=preload("res://src/presentation/ship_detail_group.gd")
var error:=""
var _entry:={}
var _player: RefCounted
var _scenery: RefCounted
var _staging: RefCounted
var _motion: RefCounted
var _radio: RefCounted
var _detail: RefCounted
var _fade:={}
var _view:={"pose":Transform3D.IDENTITY}
var _reference:=Vector3.ZERO
var _changes:=[]
var _dispatch:={}
var _rules:={}

func configure(bindings: RefCounted, catalogues: RefCounted, library: RefCounted, packet: Dictionary, line_counts: Array, unix_seconds: int, large_display:=true, body_resources: RefCounted=null) -> bool:
	clear()
	if bindings==null or not Definitions.parameters(bindings.arrival_session):return reject("This pack has no supported Mac rescue session")
	var player:=restore_packet(bindings,catalogues,packet)
	if player==null:return false
	var scenery:=Scenery.new();var staging:=Staging.new();var motion:=Motion.new();var radio:=Radio.new();var detail:=Detail.new()
	if not scenery.configure_arrival(bindings,catalogues,packet.player_cache,packet.entry_conditions,unix_seconds,large_display,body_resources) or not scenery.complete_world_initialization(bindings,catalogues):return reject(scenery.error)
	if not staging.configure(bindings,library):return reject(staging.error)
	if not motion.configure(bindings,catalogues,packet.player_cache,scenery.arrival_motion_construction()):return reject(motion.error)
	if not radio.configure(bindings,library,line_counts,1):return reject(radio.error)
	var actor: Dictionary=motion.snapshot()
	if not detail.configure(bindings,{"player":int(packet.player.ship_id),0:int(actor.hull_catalogue_id)}) or not detail.refresh({"player":Vector3.ZERO,0:actor.body_pose.origin},Vector3.ZERO,1.0):return reject(detail.error)
	var fade:={}
	if not Fade.start(fade,staging.snapshot().frame.fade_request):return reject("Invalid rescue entry fade")
	_entry=packet.duplicate(true);_player=player;_scenery=scenery;_staging=staging;_motion=motion;_radio=radio;_detail=detail;_fade=fade
	_rules=bindings.arrival_session.duplicate(true)
	return true

func restore_packet(bindings: RefCounted,catalogues: RefCounted,packet: Dictionary) -> RefCounted:
	if not HandoffDefinitions.parameters(bindings.opening_handoff):reject("Rescue requires the supported Opening handoff");return null
	for key in ["base_content_id","binding_id"]:
		if packet.get(key)!=bindings.get(key):reject("Rescue packet belongs to another content identity");return null
	if packet.get("campaign_cursor")!=1:reject("Rescue packet has the wrong campaign cursor");return null
	var player:=Player.new()
	if not player.configure_arrival(bindings,catalogues,packet.get("previous_cache",{})):reject(player.error);return null
	if packet.get("player")!=player.snapshot() or packet.get("player_cache")!=player.cache_snapshot() or player.snapshot().vitals.hull<=0:reject("Rescue packet disagrees with its restored player");return null
	var progress: Variant=packet.get("progress")
	if not progress is Dictionary or not Numbers.integer(progress.get("player_kills"),0,3):reject("Rescue requires supported Opening progress");return null
	var rules: Dictionary=bindings.opening_handoff
	var kills:=int(progress.player_kills)
	var score:=kills*int(rules.player_kill_weight)+kills*int(rules.pirate_kill_weight)+int(rules.cursor_weight)
	var rank:=0
	for i in rules.rank_thresholds.size():
		if score>=int(rules.rank_thresholds[i]):rank=i
	var expected:={"campaign_cursor":1,"rank":rank,"rank_score":score,"player_kills":kills,"pirate_kills":kills,"other_score":0}
	var uncertainty:=kills*int(rules.pirate_reputation_change_maximum)
	var axis:=int(rules.rescue_reputation_axis)
	var disposition:={"actor_hostile":false,"reputation_axis":axis,"minimum":int(rules.initial_reputation[axis])-uncertainty,"maximum":int(rules.initial_reputation[axis])+uncertainty,"override":int(rules.initial_reputation_override)}
	if progress!=expected or packet.get("rescue_disposition")!=disposition or packet.get("entry_conditions")!={"companions_empty":true,"location_match":false}:reject("Rescue packet disagrees with its supported Opening decisions");return null
	return player

func evaluate(delta_ms: Variant) -> RefCounted:
	error=""
	if _staging==null or not Numbers.integer(delta_ms,0,150):reject("Rescue requires ordinary frame milliseconds");return null
	if not _staging.snapshot().boundary.is_empty():reject("Rescue has reached its station boundary");return null
	var next: RefCounted=fork_for_frame()
	var actor: Dictionary=_motion.snapshot()
	if not Fade.advance(next._fade,delta_ms):reject("Invalid rescue fade clock");return null
	# Source controller time starts at zero in every new flight. It is distinct
	# from the retained campaign play-time clock and advances before these cues.
	if not next._staging.advance(delta_ms,_radio.snapshot(),actor.statistics_pose.origin,actor.body_pose,next._fade.active):reject(next._staging.error);return null
	var cues: Dictionary=next._staging.snapshot()
	if not cues.frame.fade_request.is_empty() and not Fade.start(next._fade,cues.frame.fade_request):reject("Invalid rescue exit fade");return null
	if not cues.boundary.is_empty():next._fade.black_plate=true
	if not next._detail.update(delta_ms,{"player":Vector3.ZERO,0:actor.body_pose.origin},_reference,1.0,false):reject(next._detail.error);return null
	if int(delta_ms)>0:
		next._view=View.fixed_eye(cues.eye,Transform3D.IDENTITY,false)
		if next._view.has("error"):reject(next._view.error);return null
		next._reference=cues.eye
	# The freshly constructed NPC list contains only the living player, at zero.
	# Player statistics remain at the source origin while its model tumbles.
	var statistics: Transform3D=cues.frame.actor_pose_override*actor.model_local_pose
	var dispatch:={"base_content_id":_entry.base_content_id,"binding_id":_entry.binding_id,"campaign_cursor":1,"generation":cues.generation,
		"mode_at_dispatch":int(cues.frame.actor_script_mode),"actor_hostile":bool(_entry.rescue_disposition.actor_hostile),
		"route_has_targets":not _rules.actor_target_ids.is_empty(),"target_present":_player.snapshot().vitals.hull>0,
		"target_excluded":bool(_rules.player_target_excluded),"target_relative_position":-statistics.origin,"model_local_pose":actor.model_local_pose}
	if not next._motion.advance(cues,dispatch):reject(next._motion.error);return null
	next._dispatch=dispatch
	if not next._scenery.update(delta_ms,_reference):reject(next._scenery.error);return null
	# Presentation updates radio after the controller. A just-finished final
	# transmission is therefore observed by the following controller frame.
	next._changes=next._radio.step(int(cues.elapsed_ms),{},0)
	if not next._radio.error.is_empty():reject(next._radio.error);return null
	return next

func snapshot() -> Dictionary:
	if _staging==null:return {}
	var cues: Dictionary=_staging.snapshot()
	var fade:=_fade.duplicate(true);fade.alpha_byte=Fade.alpha(_fade)
	return {"base_content_id":_entry.base_content_id,"binding_id":_entry.binding_id,"campaign_cursor":1,
		"elapsed_ms":cues.elapsed_ms,"generation":cues.generation,"boundary":cues.boundary,
		"staging":cues,"actor":_motion.snapshot(),"camera":{"view":_view.duplicate(true)},
		"radio":_radio.snapshot(),"radio_changes":_changes.duplicate(true),"fade":fade,
		"ship_detail":_detail.snapshot(),"detail_reference":_reference,"scenery":_scenery.snapshot(),
		"world_frame":{"base_content_id":_entry.base_content_id,"binding_id":_entry.binding_id,"campaign_cursor":1,
			"elapsed_ms":cues.elapsed_ms,"player":_player.snapshot(),"player_cache":_player.cache_snapshot(),
			"player_body":Transform3D.IDENTITY,"player_update_enabled":false,"target_ids":_rules.actor_target_ids.duplicate(),
			"dispatch":_dispatch.duplicate(true),"progress":_entry.progress.duplicate(true)}}

func prepare_station() -> Dictionary:
	error=""
	var state:=snapshot()
	if state.is_empty() or state.boundary!="station_transition_required" or state.radio.finished!=[true,true,true] or state.fade.active or state.fade.alpha_byte!=255:
		reject("Finish the rescue and its fade before preparing station entry")
		return {}
	return {"base_content_id":_entry.base_content_id,"binding_id":_entry.binding_id,"campaign_cursor":1,"source_state":5,
		"rescue_entry":_entry.duplicate(true),"rescue_finished":{"boundary":state.boundary,"finished":state.radio.finished.duplicate(),"fade_active":state.fade.active,"fade_alpha_byte":state.fade.alpha_byte}}

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._entry=_entry;copy._player=_player;copy._rules=_rules
	copy._scenery=_scenery.fork_for_frame();copy._staging=_staging.fork_for_frame();copy._motion=_motion.fork_for_frame()
	copy._radio=_radio.fork_for_frame();copy._detail=_detail.fork_for_frame()
	copy._fade=_fade.duplicate(true);copy._view=_view.duplicate(true);copy._reference=_reference
	copy._changes=_changes.duplicate(true);copy._dispatch=_dispatch.duplicate(true)
	return copy

func clear() -> void:
	error="";_entry={};_player=null;_scenery=null;_staging=null;_motion=null;_radio=null;_detail=null
	_fade={};_view={"pose":Transform3D.IDENTITY};_reference=Vector3.ZERO;_changes=[];_dispatch={};_rules={}
func reject(message: String) -> bool:error=message;return false
