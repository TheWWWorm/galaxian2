extends SceneTree
## Component verification with explicit freighter-damage fixtures. This is not
## an earned mission completion or an application playthrough.
const Bindings=preload("res://src/content/resource_bindings.gd")
const Library=preload("res://src/content/library.gd")
const Rules=preload("res://src/content/alioth_attack_definitions.gd")
const ReturnRules=preload("res://src/content/alioth_return_definitions.gd")
const OrdinaryFlight=preload("res://src/content/ordinary_flight_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Attack=preload("res://src/simulation/alioth_attack.gd")
const Radio=preload("res://src/simulation/radio_sequence.gd")
const Resources=preload("res://src/presentation/opening_radio_resources.gd")
const Audio=preload("res://src/content/audio_resources.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
var failures:=0
var checks:=0
var bindings: RefCounted
var library: RefCounted
var counts:=[]
var player_pose:=Transform3D(Basis.IDENTITY,Vector3(10,20,30))
var portal_pose:=Transform3D(Basis.IDENTITY,Vector3(0,0,210000))
var random_state:={}

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected explicit content/binding/visual triples")
	for i in range(0,args.size()-2,3):verify(args[i],args[i+1])
	print("Alioth attack: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(content: String,pack: String) -> void:
	bindings=Bindings.new();library=Library.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not library.select_language("gb"):
		check(false,library.error+bindings.error);return
	var owner:=Attack.new()
	if not Rules.available(bindings):
		check(not owner.configure(bindings) and owner.snapshot().is_empty() and Rules.radio(bindings).is_empty(),"Legacy content enabled an unverified attack")
		return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	for key in Rules.SPANS:
		var changed: Dictionary=bindings.mido_travel.duplicate(true)
		changed.provenance[key].offset+=1
		check(not Travel.validate(changed,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Moved attack proof accepted: "+key)
	for key in Rules.VALUES:
		var changed: Dictionary=bindings.mido_travel.duplicate(true)
		changed.alioth_attack[key]=null
		check(not Travel.parameters(changed),"Changed attack value accepted: "+key)
	var alternate: bool=bindings.early_contracts.briefing_text_base==775
	var mixed: Dictionary=bindings.mido_travel.duplicate(true)
	mixed.alioth_attack=Rules.VALUES.duplicate(true) if alternate else Rules.MAC_VALUES.duplicate(true)
	check(not Travel.parameters(mixed),"Mixed-source Alioth attack events were accepted")
	if bindings.mido_travel.has("alioth_return"):
		mixed=bindings.mido_travel.duplicate(true)
		mixed.alioth_return=ReturnRules.VALUES.duplicate(true) if alternate else ReturnRules.MAC_VALUES.duplicate(true)
		check(not Travel.parameters(mixed),"Mixed-source Alioth return events were accepted")
		var docked:=OrdinaryFlight.station_return(bindings,17)
		check(not docked.is_empty() and OrdinaryFlight.docking_parameters(docked),"Alioth return overlay failed its source-specific validator")
		check(docked.events.map(func(event):return int(event.text_id))==range(1835 if alternate else 1821,1852 if alternate else 1838),"Actual docking selected another source's return dialogue")
		check(docked.events==bindings.mido_travel.alioth_return.events,"Docking changed the source speakers or voice bindings")
		var changed:=docked.duplicate(true)
		changed.events[0].text_id=1821 if alternate else 1835
		check(not OrdinaryFlight.docking_parameters(changed),"Mixed-source docking dialogue was accepted")
	var resources:=Resources.new()
	if not resources.prepare(library,bindings,null,16):check(false,resources.error);return
	counts=resources.line_counts.duplicate()
	check(counts.size()==5 and resources.speakers.has(19) and resources.speakers.has(0) and resources.speakers.has(1),"Original Alioth speakers or text layout are missing")
	var random:=Random.new();random.seed_from(12345);random_state=random.snapshot()
	verify_radio()
	verify_sequence()
	verify_clocked_sequence()
	verify_audio()

func context() -> Dictionary:
	var actors:=[]
	for source in Rules.VALUES.population.actors:
		var row: Dictionary=source.duplicate()
		row.current_hull=100;row.active=true;row.visible=true;row.body_pose=Transform3D(Basis.IDENTITY,Vector3(0,0,170000))
		actors.append(row)
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":16,"actors":actors}

func fresh_radio() -> RefCounted:
	var radio:=Radio.new()
	check(radio.configure(bindings,library,counts,16),radio.error)
	return radio

func finish(radio: RefCounted,event: int,at: int,actors: Dictionary) -> int:
	check(radio.step_alioth_attack(at+2000,actors).is_empty() and not radio.snapshot().visible,"Radio appeared at the strict delay boundary")
	check(radio.step_alioth_attack(at+2001,actors)==[{"kind":"display","event":event,"text_id":1813+event+(14 if bindings.early_contracts.briefing_text_base==775 else 0)}],"Original radio text did not appear")
	var end:=at+2000+1500+2000*int(counts[event])
	check(radio.step_alioth_attack(end,actors).is_empty() and not radio.snapshot().finished[event],"Radio finished at the strict duration boundary")
	check(radio.step_alioth_attack(end+1,actors)==[{"kind":"finished","event":event}],"Original radio line did not finish once")
	check(radio.snapshot().active_event==-1,"Another radio line started in the completion frame")
	return end+1

func verify_radio() -> void:
	var radio:=fresh_radio();var actors:=context();var prior: Dictionary=radio.snapshot()
	check(radio.step(10000,{0:0,1:0,2:0},0).is_empty() and not radio.error.is_empty() and radio.snapshot()==prior,"Generic hulls bypassed the actual attack cast")
	var bad:=context();bad.actors.pop_back()
	check(radio.step_alioth_attack(10000,bad).is_empty() and not radio.error.is_empty() and radio.snapshot()==prior,"An incomplete cast changed radio")
	bad=context();bad.actors[0].actor_kind=9
	check(radio.step_alioth_attack(10000,bad).is_empty() and not radio.error.is_empty() and radio.snapshot()==prior,"Another cast changed radio")
	check(radio.step_alioth_attack(9999,actors).is_empty(),"Void radio began before 10000 ms")
	check(radio.step_alioth_attack(10000,actors)==[{"kind":"started","event":0}],"Void radio missed 10000 ms")
	var now:=finish(radio,0,10000,actors)
	check(radio.step_alioth_attack(now,actors)==[{"kind":"started","event":1}],"Keith's reply lost its dependency")
	now=finish(radio,1,now,actors)
	for id in 3:
		actors.actors[id].active=false;actors.actors[id].visible=false
		check(radio.step_alioth_attack(now,actors).is_empty(),"Freighter inactivity or invisibility counted as destruction")
		actors.actors[id].current_hull=0
		if id<2:check(radio.step_alioth_attack(now,actors).is_empty(),"Escape started while a freighter survived")
	check(radio.step_alioth_attack(now,actors)==[{"kind":"started","event":2}],"Three exhausted freighter hulls did not trigger escape")
	for event in range(2,5):
		if event>2:check(radio.step_alioth_attack(now,actors)==[{"kind":"started","event":event}],"Escape radio order changed")
		now=finish(radio,event,now,actors)
	check(radio.step_alioth_attack(now,actors).is_empty() and radio.snapshot().finished.all(func(v):return v),"Finished radio replayed")
	var early:=fresh_radio()
	check(early.step_alioth_attack(0,actors)==[{"kind":"started","event":2}],"An unverified prerequisite was added to condition9")

func flags() -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":16,
		"started":[false,false,false,false,false],"finished":[false,false,false,false,false]}

func advance(owner: RefCounted,delta: int,radio: Dictionary,actors: Dictionary) -> bool:
	return owner.advance(delta,radio,actors,player_pose,portal_pose,random_state)

func verify_sequence() -> void:
	var owner:=Attack.new();check(owner.configure(bindings),owner.error)
	var radio:=flags();var actors:=context()
	check(advance(owner,100,radio,actors) and owner.snapshot().phase==0 and not owner.snapshot().input_blocked,"Untriggered attack removed player control")
	var prior:=owner.snapshot()
	for invalid in [-1,751 if not bindings.fast_forward.is_empty() else 151,1.5]:check(not owner.advance(invalid,radio,actors,player_pose,portal_pose,random_state) and owner.snapshot()==prior,"Invalid frame changed attack")
	radio.started[0]=true
	check(advance(owner,0,radio,actors),owner.error)
	var first:=owner.snapshot()
	check(first.phase==1 and first.input_blocked and not first.player_update_suspended and not first.hud_visible,"First view changed the source player-update gate")
	check(first.frame.camera_operations==[{"action":"follow_actor","actor_id":0},{"action":"set_eye","position":Vector3(6000,4000,217500)}],"First view lost the actual freighter pose")
	check(first.frame.cancel_player_actions and first.frame.reset_starfield,"First view omitted action cancellation or starfield rebasing")
	check(advance(owner,100,radio,actors) and owner.snapshot().frame.camera_operations[0].delta==Vector3(-100,0,-300),"Freighter camera changed source movement units")
	prior=owner.snapshot();var regressed:=radio.duplicate(true);regressed.started[0]=false
	check(not advance(owner,1,regressed,actors) and owner.snapshot()==prior,"Regressed radio changed the accepted frame")
	radio.finished[0]=true;radio.started[1]=true;radio.finished[1]=true
	var clone: RefCounted=owner.fork_for_frame()
	check(advance(clone,0,radio,actors) and owner.snapshot()==prior,"Prospective camera changed its retained owner")
	owner=clone
	check(owner.snapshot().phase==2 and not owner.snapshot().input_blocked and owner.snapshot().hud_visible,"Keith's reply failed to restore flight")
	while owner.snapshot().elapsed_ms<20000:
		if not advance(owner,mini(100,20000-owner.snapshot().elapsed_ms),radio,actors):check(false,owner.error);return
	check(owner.snapshot().phase==2 and owner.snapshot().frame.portal_operations.is_empty(),"Portal closed before its inclusive 20001 ms gate")
	radio.started[2]=true
	check(advance(owner,1,radio,actors) and owner.snapshot().phase==3,"The portal gate skipped directly to escape")
	check(owner.snapshot().frame.portal_operations==[{"slot":3,"elapsed_ms":59000,"extent":4096}],"Portal closure lost its source clock/extent")
	check(advance(owner,0,radio,actors),owner.error)
	var escape:=owner.snapshot()
	check(escape.phase==4 and escape.input_blocked and escape.player_update_suspended and not escape.hud_visible,"Escape failed to suspend player updates")
	check(escape.frame.portal_operations==[{"slot":3,"elapsed_ms":-3000,"extent":0,"visible":true}],"Escape portal did not reopen")
	check(escape.frame.camera_operations[1].position==Vector3(-9000,-4000,180000),"Escape camera substituted its authored offset")
	verify_escape_positions(escape.frame)
	check(advance(owner,100,radio,actors) and owner.snapshot().frame.actor_overrides.is_empty() and owner.snapshot().frame.camera_operations[0].delta==Vector3(50,0,20),"Escape repeated relocation or changed camera speed")
	radio.finished[2]=true;radio.started[3]=true
	check(advance(owner,0,radio,actors) and owner.snapshot().phase==4,"Void ships retired before Brent finished")
	radio.finished[3]=true
	check(advance(owner,0,radio,actors),owner.error)
	var retired:=owner.snapshot()
	check(retired.phase==5 and retired.frame.retire_actor_ids==[3,4,5,6] and retired.player_update_suspended,"Retirement changed the wrong actors or restored the player early")
	check(not retired.completion_ready and not retired.frame.portal_operations.is_empty(),"Void retirement completed the mission or left the portal open")
	radio.started[4]=true
	check(advance(owner,100,radio,actors) and owner.snapshot().phase==5,"Control returned before the final line finished")
	radio.finished[4]=true
	check(advance(owner,0,radio,actors),owner.error)
	var returned:=owner.snapshot()
	check(returned.phase==6 and not returned.input_blocked and not returned.player_update_suspended and returned.hud_visible,"The final radio failed to restore flight")
	check(returned.completion_ready and returned.frame.completion_became_ready and returned.campaign_cursor==16,"Completion bypassed acknowledgement or failed to signal condition22")
	check(advance(owner,100,radio,actors) and not owner.snapshot().frame.completion_became_ready and owner.snapshot().frame.retire_actor_ids.is_empty(),"Finished attack repeated effects")
	prior=owner.snapshot();var foreign:=actors.duplicate(true);foreign.binding_id="foreign"
	check(not advance(owner,0,radio,foreign) and owner.snapshot()==prior,"Foreign actors changed the retained encounter")

func verify_escape_positions(frame: Dictionary) -> void:
	# Independently calculated with the source 48-bit recurrence and seed12345;
	# two bounded draws per Void ship, y then z. No engine RNG is used.
	var expected:=[Vector3(0,251,194080),Vector3(0,-1759,193828),Vector3(0,55,195084),Vector3(0,-625,195802)]
	check(frame.actor_overrides.size()==4,"Escape lost a Void actor")
	for i in mini(4,frame.actor_overrides.size()):
		var row: Dictionary=frame.actor_overrides[i]
		check(row.actor_id==3+i and row.body_pose.origin==expected[i],"Escape position differs from the independent source RNG vector")
		check(row.route_points==[Vector3(0,0,240000)] and row.route_initial_index==0 and not row.route_loop and row.clear_targets,"Escape failed to replace the route and clear combat targets")
		check(row.body_pose.basis.z.dot((portal_pose.origin-row.body_pose.origin).normalized())>0.99999,"Escaping ship did not face the actual portal")
	check(frame.input_random_state==random_state and frame.random_state.state==35090963149596,"Escape consumed a different shared random sequence")

func verify_clocked_sequence() -> void:
	var radio:=fresh_radio();var owner:=Attack.new();check(owner.configure(bindings),owner.error)
	var stages:=[0];var displayed:=[];var actors:=context();var now:=0
	while now<180000 and owner.snapshot().phase!=6:
		now+=100
		# Explicit combat fixture: only the three freighters lose hull at45s.
		if now>=45000:
			for id in 3:actors.actors[id].current_hull=0
		if not advance(owner,100,radio.snapshot(),actors):check(false,owner.error);return
		if stages.back()!=owner.snapshot().phase:stages.append(owner.snapshot().phase)
		for event in radio.step_alioth_attack(now,actors):
			if event.kind=="display":displayed.append(event.text_id)
		if not radio.error.is_empty():check(false,radio.error);return
	check(stages==[0,1,2,3,4,5,6] and displayed==([1827,1828,1829,1830,1831] if bindings.early_contracts.briefing_text_base==775 else [1813,1814,1815,1816,1817]),"Clocked attack skipped a camera stage or original line")
	check(owner.snapshot().completion_ready and owner.snapshot().campaign_cursor==16,"Clocked attack skipped the retained campaign owner")
	print("Alioth source-layout clock: final radio/camera at %d ms; %s lines"%[now,str(counts)])

func verify_audio() -> void:
	for language in ["gb","de"]:
		check(library.select_language(language),library.error)
		var audio:=Audio.new();check(audio.configure(library,bindings,16),audio.error)
		for id in [546,497,498,499,500]:
			var clip:=audio.prepare(id)
			check(not clip.is_empty() and not clip.has("unsupported") and clip.get("voice",false),"Original attack voice is unavailable: %s/%d %s"%[language,id,audio.error])
	check(library.select_language("gb"),library.error)

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
