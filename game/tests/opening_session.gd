extends SceneTree
const Session = preload("res://src/presentation/opening_session.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Visuals = preload("res://src/content/visual_library.gd")
const RadioResources = preload("res://src/presentation/opening_radio_resources.gd")
const Radio = preload("res://src/simulation/radio_sequence.gd")
const Preview = preload("res://src/presentation/opening_preview.gd")
const RadioPreview = preload("res://src/presentation/radio_preview.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/bindings/visuals triples")
	for i in range(0,args.size()-2,3):verify_source(args[i],args[i+1],args[i+2])
	print("Opening session checks: %d failures" % failures)
	quit(1 if failures else 0)

func verify_source(content: String, pack: String, texture_pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var visuals := Visuals.new()
	check(library.open(content) and library.select_language("gb"),library.error)
	check(bindings.open(pack,library.manifest),bindings.error)
	check(visuals.open(texture_pack,library.manifest),visuals.error)
	var session := Session.new();root.add_child(session)
	check(session.configure(library,bindings,visuals,0,0.5,1789100000),session.error)
	if session.status!="running":session.free();return
	check(session.snapshot().elapsed_ms==0,"Resource loading advanced opening time")
	check(session.snapshot().world_frame.has("damage_particles")==not bindings.damage_particles.get("owners",{}).is_empty(),"Session damage effects disagree with the imported capability")
	check((session.damage_particles!=null)==not bindings.damage_particles.get("owners",{}).is_empty(),"Session omitted source damage sprite drawing")
	check((session.planets!=null)==not bindings.opening_sky.get("planet_resources",{}).is_empty(),"Session planet presentation disagrees with its capability")
	if session.planets!=null:check(session.planets.models.size()==5 and session.planets.selection.planets.size()==5,"Fresh opening omitted planet drawing")
	check((session.sun!=null)==not bindings.opening_sky.get("sun_flares",{}).is_empty(),"Session sun presentation disagrees with its capability")
	if session.sun!=null:
		check(session.sun.frame.previous_intensity==0,"Fresh native sun did not use explicit zero initialization")
		var retained: Dictionary=session.sun.frame.duplicate(true)
		check(session.present() and session.sun.frame==retained,"Repeated presentation consumed screen flare intensity")
	var travelling: bool=not bindings.opening_staging.get("projectile_visuals",{}).is_empty()
	check((session.projectiles!=null)==travelling,"Session projectile presentation disagrees with its capability")
	if travelling:check(session.projectiles.guns.size()==3,"Precombat session omitted an NPC weapon model")
	var impacts: bool=not bindings.opening_staging.get("projectile_impacts",{}).is_empty()
	check((session.impacts!=null)==impacts,"Session impact presentation disagrees with its capability")
	if impacts:
		check(session.impacts.guns.size()==3,"Precombat session omitted NPC impact models")
		for gun in session.impacts.guns:
			check(gun.slots.size()==4,"Session changed the source NPC impact capacity")
			for slot in gun.slots:check(not slot.visible,"Session rendered an unused impact slot")
	var scenery_start: Dictionary = session.snapshot().scenery
	if not bindings.opening_actors.npc_initialization.get("world_initialization",{}).is_empty():
		check(not scenery_start.world_initialization.is_empty(),"Session omitted complete world initialization")
		check(scenery_start.random_state.state==(203124760899757 if library.manifest.profile.edition=="ios-hd" else 184786094478354),"Session began with the wrong world RNG boundary")
		check(scenery_start.random_state==scenery_start.world_initialization.random_state,"Session did not adopt initialized world RNG")
	else:
		check(scenery_start.world_initialization.is_empty(),"Legacy session fabricated world initialization")
	var targets_start: Dictionary = session.snapshot().target_inventory
	check(targets_start.npc_ids==[0,1,2] and targets_start.scenery_indices==range(scenery_start.objects.size()),"Opening target inventory omitted a source group")
	check(targets_start.third_group_absence=="missing_equipment_type" and targets_start.required_equipment_type==33,"Opening optional-group absence is not source-bound")
	check(scenery_start.center==Vector3.ZERO and scenery_start.station_id==78,"Opening field has wrong center or source station")
	check(scenery_start.objects.size()==session.scenery.objects.size(),"Opening scenery not attached to scene")
	check(scenery_start.bodies.objects.size()==scenery_start.objects.size(),"Opening omitted native scenery bodies")
	for index in scenery_start.objects.size():
		check(scenery_start.bodies.objects[index].position==scenery_start.objects[index].position,"Opening body and model positions disagree")
	for level in 4:
		var selected: Dictionary = scenery_start.detail.duplicate(true)
		for key in selected.selections:selected.selections[key]={"visible":true,"level":level}
		check(session.scenery.apply_detail(selected),session.scenery.error)
		for index in session.scenery.objects.size():
			var object: Node3D = session.scenery.objects[index]
			for surface in object.instances:check(surface.visible==(level==0),"Base scenery surfaces hid their LOD children")
			for alternate in range(1,4):check(object.get_node("Level%d" % alternate).visible==(level==alternate),"Wrong scenery detail mesh visibility")
		var bad := selected.duplicate(true);bad.selections[0].level=4
		check(not session.scenery.apply_detail(bad),"Missing scenery LOD was accepted")
	check(session.present(),session.error)
	if bindings.scenery_effects.is_empty():
		var intact_bodies: RefCounted = session._scenery._bodies.fork_for_frame()
		check(session._scenery._bodies.normal_hit(0,2147483647).destroyed_now,"Could not prepare legacy destruction boundary check")
		var pending_destruction := session.snapshot()
		check(not session.step(100000) and session.snapshot()==pending_destruction,"Legacy unsupported destruction advanced the opening timeline")
		session._scenery._bodies=intact_bodies

	check(scenery_start.objects.size()==(50 if library.manifest.profile.edition=="ios-hd" else 130),"Opening lost edition-local scenery count")

	check(session.radio_resources.line_counts.size()==23,"Missing opening radio timing layout")
	check(session.step(100000),session.error)
	var sun_before: Dictionary={} if session.sun==null else session.sun.frame.duplicate(true)
	var before := session.snapshot()
	check(before.scenery.objects!=scenery_start.objects,"Normal opening presentation did not spin scenery")
	check(session.set_pause("user",true,100000),session.error)
	check(session.set_pause("focus",true,200000),session.error)
	check(session.step(9000000) and session.snapshot()==before,"Pause advanced opening radio or scene")
	if session.sun!=null:check(session.sun.frame==sun_before,"Pause advanced sun intensity")
	check(session.set_pause("user",false,9000000),session.error)
	check(session.step(9500000) and session.snapshot()==before,"User resume overrode focus pause")
	check(session.set_pause("focus",false,9500000),session.error)
	check(session.step(9600000),session.error)
	if session.sun!=null:
		check(session.sun.frame.previous_intensity==sun_before.next_intensity,"New scene step lost preceding sun intensity")
		var retained: Dictionary=session.sun.frame.duplicate(true)
		check(not session.step(-1) and session.sun.frame==retained,"Failed scene step advanced sun intensity")
	check(session.snapshot().elapsed_ms==before.elapsed_ms+100,"Resume caught up paused wall time")
	var phases := {};var visible_events := {};var now := 9600000;var radio_spin := false;var previous_scenery: Array = session.snapshot().scenery.objects
	for frame in 3000:
		now+=100000
		check(session.step(now),session.error)
		var state: Dictionary = session.snapshot()
		if travelling:check(state.world_frame.projectile_visuals.elapsed_ms==state.elapsed_ms,"Session projectiles lost the world clock")
		if impacts:check(state.world_frame.impact_visuals.elapsed_ms==state.elapsed_ms,"Session impacts lost the world clock")
		check(state.scenery.detail.counter_ms==state.scene.ship_detail.counter_ms,"Scenery and ships diverged from the shared LOD refresh clock")
		phases[state.camera.shot.phase]=true
		if state.radio.visible:
			visible_events[state.radio.active_event]=true
			radio_spin=radio_spin or state.scenery.objects!=previous_scenery
		previous_scenery=state.scenery.objects
		if session.status=="encounter_required":break
	check(radio_spin,"Timed radio incorrectly froze asteroid spin")
	check(phases.size()==5,"Opening application scene missed a recovered camera phase")
	check(visible_events.size()==9,"Opening scene did not display all precombat transmissions")
	check(session.status=="encounter_required","Opening failed to stop at the combat boundary")
	var boundary := session.snapshot()
	if boundary.world_frame.is_empty():
		check(boundary.scenery.random_state==scenery_start.random_state,"Legacy scenery spin consumed construction RNG")
	else:
		check(boundary.scenery.random_state!=scenery_start.random_state,"Opening NPC decisions never consumed shared RNG")
		check(boundary.world_frame.random_state==boundary.scenery.random_state and boundary.world_frame.elapsed_ms==boundary.elapsed_ms,"Session frame owners diverged")
		for actor in boundary.combat.actors:
			check(actor.pose==boundary.scene.actors[actor.actor_id].pose and actor.pose==boundary.world_frame.controller.actors[actor.actor_id].flight.pose,"Session lost the live actor pose")
	check(boundary.scenery.world_initialization==scenery_start.world_initialization,"Presentation mutated world initialization records")
	check(boundary.scenery.bodies==scenery_start.bodies,"Precombat presentation altered scenery damage state")
	check(boundary.target_inventory==targets_start and session._targets.validate_owners(boundary.combat,boundary.scenery.bodies),"Precombat motion or activation changed target membership")
	check(boundary.radio.finished.slice(0,9).all(func(value):return value),"Opening stopped before supported radio finished")
	check(boundary.radio.started.slice(9).all(func(value):return not value),"Unsupported combat or later radio was fabricated")
	for actor in boundary.scene.actors:check(actor.current_hull>0,"Opening invented a defeated actor")
	check(session.step(now+900000000) and session.snapshot()==boundary,"Unsupported encounter continued advancing")
	check(not session.set_pause("invented",true,now),"Unknown pause reason accepted")
	session.clear();check(session.get_child_count()==0 and session.snapshot().is_empty() and session.radio_resources==null and session.planets==null and session.sun==null,"Opening clear retained scene or content resources")
	check(not session.configure(library,bindings,null,now) and session.get_child_count()==0,"Missing visuals retained a partial scene")
	session.free()
	# Shared radio preparation remains edition/language-bound, and reconfiguration
	# removes previously prepared text/portraits on failure.
	var resources := RadioResources.new();check(resources.prepare(library,bindings,visuals),resources.error)
	var radio := Radio.new();check(radio.configure(bindings,library,resources.line_counts),radio.error)
	var old_id: String = bindings.base_content_id;bindings.base_content_id="0".repeat(64)
	check(not resources.prepare(library,bindings,visuals) and resources.line_counts.is_empty() and resources.speakers.is_empty(),"Failed radio preparation kept stale content")
	bindings.base_content_id=old_id
	var radio_preview := RadioPreview.new();root.add_child(radio_preview);radio_preview.set_process(false)
	radio_preview.set_context(library,bindings,visuals)
	for language in library.manifest.languages:
		check(library.select_language(language),library.error)
		radio_preview.start()
		check(radio_preview._running,radio_preview.status.text)
		check(radio_preview.radio.snapshot().get("language")==language,"Shared radio preparation retained the preceding language")
		radio_preview.reset()
	radio_preview.free();check(library.select_language("gb"),library.error)
	var preview := Preview.new();root.add_child(preview);preview.set_process(false)
	preview.set_context(library,bindings,visuals);preview.start()
	check(preview.session!=null and preview.session.status=="running",preview.status.text)
	if preview.session!=null:
		check(preview.session.interactive==Session.supports_player_controls(bindings),"Application capability disagrees with interactive configuration")
		preview.hide();check(preview.session.is_paused(),"Hidden opening retained a running clock")
		preview.show();check(not preview.session.is_paused(),"Visible opening kept its hidden pause")
		preview.set_user_paused(true);preview.hide();preview.show()
		check(preview.session.is_paused(),"Tab switch cleared user pause")
		preview.set_user_paused(false)
	preview.reset();check(preview.session==null,"Stop retained opening session")
	preview.free()
	print("Opening session: ",library.manifest.profile.edition," full precombat radio, five phases, pause, boundary and reset verified")

func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
