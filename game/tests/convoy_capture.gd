extends SceneTree
## Component fixtures exercise original radio/capture rules, not an earned
## campaign playthrough. The controller cannot publish a career or station.
const Bindings=preload("res://src/content/resource_bindings.gd")
const Library=preload("res://src/content/library.gd")
const Rules=preload("res://src/content/convoy_capture_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Capture=preload("res://src/simulation/convoy_capture.gd")
const Radio=preload("res://src/simulation/radio_sequence.gd")
const Resources=preload("res://src/presentation/opening_radio_resources.gd")
const Audio=preload("res://src/content/audio_resources.gd")
var failures:=0
var checks:=0
var bindings: RefCounted
var library: RefCounted
var counts:=[]
var player_pose:=Transform3D(Basis.IDENTITY,Vector3(40000,0,120000))
var freighter_pose:=Transform3D(Basis.IDENTITY,Vector3(31000,7000,37000))

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected explicit content/binding/visual triples")
	for i in range(0,args.size()-2,3):verify(args[i],args[i+1])
	print("Convoy capture: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(content: String,pack: String) -> void:
	bindings=Bindings.new();library=Library.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not library.select_language("gb"):
		check(false,library.error+bindings.error);return
	var capture:=Capture.new()
	if not Rules.available(bindings):
		check(not capture.configure(bindings) and capture.snapshot().is_empty() and Rules.radio(bindings).is_empty(),"Legacy content enabled an unverified capture")
		return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	for key in Rules.SPANS:
		var changed: Dictionary=bindings.mido_travel.duplicate(true)
		changed.provenance[key].offset+=1
		check(not Travel.validate(changed,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Moved capture proof accepted: "+key)
	for key in Rules.VALUES:
		var changed: Dictionary=bindings.mido_travel.duplicate(true)
		changed.convoy_capture[key]=null
		check(not Travel.parameters(changed),"Changed capture value accepted: "+key)
	var mixed: Dictionary=bindings.mido_travel.duplicate(true)
	mixed.convoy_capture=Rules.VALUES.duplicate(true) if bindings.early_contracts.briefing_text_base==775 else Rules.MAC_VALUES.duplicate(true)
	check(not Travel.parameters(mixed),"Another source's convoy events were accepted")
	var resources:=Resources.new()
	if not resources.prepare(library,bindings,null,14):check(false,resources.error);return
	counts=resources.line_counts.duplicate()
	check(counts.size()==5 and resources.speakers.has(18) and resources.speakers.has(0) and resources.speakers.has(17),"Original convoy speakers or text layout are missing")
	verify_radio()
	verify_sequence()
	verify_clocked_sequence()
	verify_audio()

func target_context(rows: Array=[]) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":14,"player_targets":rows.duplicate(true)}

func fresh_radio() -> RefCounted:
	var radio:=Radio.new()
	check(radio.configure(bindings,library,counts,14),radio.error)
	return radio

func finish(radio: RefCounted,event: int,at: int,targets: Dictionary) -> int:
	var visible_at:=at+2000
	check(radio.step_convoy(visible_at,targets).is_empty() and not radio.snapshot().visible,"Radio became visible at the strict delay boundary")
	check(radio.step_convoy(visible_at+1,targets)==[{"kind":"display","event":event,"text_id":1795+event+(14 if bindings.early_contracts.briefing_text_base==775 else 0)}],"Original radio text did not appear")
	var end:=visible_at+1500+2000*int(counts[event])
	check(radio.step_convoy(end,targets).is_empty() and not radio.snapshot().finished[event],"Radio finished at the inclusive duration boundary")
	check(radio.step_convoy(end+1,targets)==[{"kind":"finished","event":event}],"Original radio line did not finish once")
	check(radio.snapshot().active_event==-1,"Another line started in the completion frame")
	return end+1

func verify_radio() -> void:
	var radio:=fresh_radio();var targets:=target_context()
	var empty: Dictionary=radio.snapshot()
	check(radio.step(10000,{},0).is_empty() and not radio.error.is_empty() and radio.snapshot()==empty,"Generic hull map bypassed the convoy target list")
	check(radio.step_convoy(9999,targets).is_empty(),"EMP warning began before 10000 ms")
	check(radio.step_convoy(10000,targets)==[{"kind":"started","event":0}],"EMP warning did not start at 10000 ms")
	var now:=finish(radio,0,10000,targets)
	for rows in [[],[{"scenery":true,"current_hull":0}],[{"scenery":false,"current_hull":1,"active":false}]]:
		check(radio.step_convoy(now,target_context(rows)).is_empty(),"A missing, scenery or live target triggered capture")
	var prior: Dictionary=radio.snapshot()
	for bad in [{"scenery":false},{"scenery":false,"current_hull":0.5},{"current_hull":0}]:
		check(radio.step_convoy(now,target_context([bad])).is_empty() and not radio.error.is_empty() and radio.snapshot()==prior,"Malformed target changed radio")
	var foreign:=target_context();foreign.binding_id="f".repeat(64)
	check(radio.step_convoy(now,foreign).is_empty() and not radio.error.is_empty() and radio.snapshot()==prior,"Foreign target list changed radio")
	targets=target_context([{"scenery":false,"current_hull":0,"active":false,"friendly":true}])
	check(radio.step_convoy(now,targets)==[{"kind":"started","event":1}],"Source hull trigger incorrectly required hostility, activity or a kill counter")
	var clone: RefCounted=radio.fork_for_frame()
	var original: Dictionary=radio.snapshot()
	clone.step_convoy(now+1,targets)
	check(radio.snapshot()==original,"Prospective radio changed its retained owner")
	for event in range(1,5):
		if event>1:check(radio.step_convoy(now,targets)==[{"kind":"started","event":event}],"Dependent radio order changed")
		now=finish(radio,event,now,targets)
	check(radio.step_convoy(now,targets).is_empty() and radio.snapshot().finished.all(func(v):return v),"Final capture radio repeated")
	# Condition20 is independent of elapsed condition5. Preserve source selection
	# order even for an unusually early destroyed-target fixture.
	var early:=fresh_radio()
	check(early.step_convoy(0,targets)==[{"kind":"started","event":1}],"An unverified prerequisite was added to the hull trigger")

func flags() -> Dictionary:
	var result:=target_context();result.erase("player_targets")
	result.started=[false,false,false,false,false];result.finished=result.started.duplicate()
	return result

func verify_sequence() -> void:
	var owner:=Capture.new();check(owner.configure(bindings),owner.error)
	var radio:=flags()
	check(owner.advance(100,radio,player_pose,freighter_pose),owner.error)
	check(owner.snapshot().phase==Capture.Stage.INTERCEPTION and not owner.snapshot().input_blocked,"The untriggered encounter disabled the player")
	var prior:=owner.snapshot()
	for invalid in [751 if not bindings.fast_forward.is_empty() else 151,-1,1.5]:check(not owner.advance(invalid,radio,player_pose,freighter_pose) and owner.snapshot()==prior,"Invalid frame changed capture")
	radio.started[1]=true
	check(owner.advance(0,radio,player_pose,freighter_pose),owner.error)
	var pulse:=owner.snapshot()
	check(pulse.phase==Capture.Stage.PULSE and not pulse.input_blocked and pulse.frame.retire_actor_ids==[0],"EMP start skipped its first-pulse stage")
	check(pulse.frame.emp_target=={"actor_id":0,"position":player_pose.origin} and pulse.frame.audio==[{"action":"start","source_id":15}],"First EMP cue changed its source target, position or sound")
	check(owner.advance(100,radio,player_pose,freighter_pose) and owner.snapshot().frame.audio.is_empty(),"EMP start repeated while the radio was active")
	prior=owner.snapshot()
	var regressed:=radio.duplicate(true);regressed.started[1]=false
	check(not owner.advance(1,regressed,player_pose,freighter_pose) and owner.snapshot()==prior,"Regressed radio changed the pending capture")
	var foreign:=radio.duplicate(true);foreign.campaign_cursor=13
	check(not owner.advance(1,foreign,player_pose,freighter_pose) and owner.snapshot()==prior,"Another campaign cursor controlled capture")
	radio.finished[1]=true
	var detached: RefCounted=owner.fork_for_frame()
	check(detached.advance(0,radio,player_pose,freighter_pose) and owner.snapshot()==prior,"A prospective EMP changed the accepted frame")
	owner=detached
	var disabled:=owner.snapshot()
	check(disabled.phase==Capture.Stage.DISABLED and disabled.input_blocked and disabled.ship_visible,"Radio completion failed to disable the ship")
	check(disabled.frame.disable_player and disabled.frame.retire_actor_kind==8 and disabled.frame.blackout==Rules.VALUES.blackout,"EMP did not request the source player and pirate retirement")
	check(disabled.frame.camera_operations[1].delta==Vector3(1000,700,1000) and disabled.frame.audio[0].action=="start_spatial","Disabled view or spatial EMP cue changed")
	check(owner.advance(100,radio,player_pose,freighter_pose),owner.error)
	var drift:=owner.snapshot()
	check(drift.frame.model_rotation_delta.is_equal_approx(Vector3(0,0.01,0)) and drift.frame.camera_operations[0].delta==Vector3(0,0,100),"Disabled drift lost its source units")
	check(drift.frame.disable_player and drift.frame.reset_follow_offsets and drift.frame.audio.is_empty() and drift.frame.retire_actor_kind==-1,"Disabled drift lost follow offsets or replayed the EMP")
	radio.started[2]=true;radio.finished[2]=true;radio.started[3]=true
	check(owner.advance(100,radio,player_pose,freighter_pose) and owner.snapshot().ship_visible,"Capture view began before the surrender line finished")
	radio.finished[3]=true
	check(owner.advance(100,radio,player_pose,freighter_pose),owner.error)
	var captured:=owner.snapshot()
	check(captured.phase==Capture.Stage.CAPTURE_VIEW and not captured.ship_visible and captured.input_blocked,"Capture view restored player control")
	check(captured.frame.capture_actor_id==6 and captured.frame.stop_nozzle_emitters and captured.frame.camera_operations[1].position==freighter_pose.origin and captured.frame.camera_operations[2].delta==Vector3(-10000,-200,5000),"Capture view lost the live freighter or original offset")
	radio.started[4]=true
	check(owner.advance(100,radio,player_pose,freighter_pose) and owner.snapshot().phase==Capture.Stage.CAPTURE_VIEW,"Transfer began before the narrator finished")
	radio.finished[4]=true
	check(owner.advance(100,radio,player_pose,freighter_pose),owner.error)
	check(owner.snapshot().phase==Capture.Stage.TRANSFER_WAIT and owner.snapshot().transfer_elapsed_ms==0,"Narrator completion consumed the next wait phase")
	for i in 39:check(owner.advance(100,radio,player_pose,freighter_pose),owner.error)
	check(owner.advance(99,radio,player_pose,freighter_pose) and owner.snapshot().arrival.is_empty(),"Alioth transfer occurred before 4000 ms")
	check(owner.advance(1,radio,player_pose,freighter_pose),owner.error)
	var arrived:=owner.snapshot()
	check(arrived.phase==Capture.Stage.ARRIVAL_REQUIRED and arrived.arrival==Rules.VALUES.arrival and arrived.frame.arrival==arrived.arrival,"Capture failed to request exactly cursor15/station98 with no reward")
	check(arrived.campaign_cursor==14,"Choreography directly advanced the career")
	check(not owner.advance(0,radio,player_pose,freighter_pose) and owner.snapshot()==arrived,"Terminal capture requested arrival twice")
	arrived.arrival.station_id=0
	check(owner.snapshot().arrival.station_id==98,"Snapshot mutation changed arrival")

func verify_audio() -> void:
	for language in ["gb","de"]:
		check(library.select_language(language),library.error)
		var audio:=Audio.new();check(audio.configure(library,bindings,14),audio.error)
		for id in range(492,497):
			var clip:=audio.prepare(id)
			check(not clip.is_empty() and not clip.has("unsupported") and clip.get("voice",false),"Original convoy voice is unavailable: %s/%d %s"%[language,id,audio.error])
		var emp:=audio.prepare(15)
		check(not emp.is_empty() and not emp.has("unsupported"),"Original EMP cue is unavailable: "+audio.error)
	check(library.select_language("gb"),library.error)

func verify_clocked_sequence() -> void:
	# Exercise both native owners together, with source font-derived timing.
	# The only combat fixture is a target hull reaching zero at 20 seconds.
	var radio:=fresh_radio();var capture:=Capture.new()
	check(capture.configure(bindings),capture.error)
	var stages:=[Capture.Stage.INTERCEPTION]
	var sounds:=[];var displayed:=[];var entered_wait:=-1;var now:=0
	while now<180000 and capture.snapshot().phase!=Capture.Stage.ARRIVAL_REQUIRED:
		now+=100
		var targets:=target_context([{"scenery":false,"current_hull":0 if now>=20000 else 20}])
		if not capture.advance(100,radio.snapshot(),player_pose,freighter_pose):check(false,capture.error);return
		var state: Dictionary=capture.snapshot()
		if stages.back()!=state.phase:
			stages.append(state.phase)
			if state.phase==Capture.Stage.TRANSFER_WAIT:entered_wait=now
		for cue in state.frame.audio:sounds.append(cue.action)
		for event in radio.step_convoy(now,targets):
			if event.kind=="display":displayed.append(event.text_id)
		if not radio.error.is_empty():check(false,radio.error);return
	check(stages==[0,1,2,3,4,5],"Clocked radio skipped or repeated a capture stage")
	check(displayed==([1809,1810,1811,1812,1813] if bindings.early_contracts.briefing_text_base==775 else [1795,1796,1797,1798,1799]) and sounds==["start","start_spatial"],"Clocked capture lost original radio or repeated EMP sounds")
	check(entered_wait>=0 and now-entered_wait==4000 and capture.snapshot().arrival.station_id==98,"Clocked narrator/transfer boundary changed")
	print("Convoy source-layout clock: arrival request at %d ms; %s lines"%[now,str(counts)])

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
