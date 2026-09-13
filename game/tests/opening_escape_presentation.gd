extends SceneTree
const Session=preload("res://src/presentation/opening_session.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Fade=preload("res://src/simulation/opening_escape_fade.gd")
var failures:=0
var captures:=""

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty() and args[0].begins_with("--captures="):
		captures=args[0].trim_prefix("--captures=");args.remove_at(0)
	check(not args.is_empty() and args.size()%3==0,"Expected content/binding/visual triples")
	for i in range(0,args.size()-2,3):await verify(args[i],args[i+1],args[i+2])
	print("Opening escape presentation checks: %d failures"%failures)
	quit(1 if failures else 0)

func verify(content: String, pack: String, textures: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(content) or not library.select_language("gb") or not bindings.open(pack,library.manifest) or not visuals.open(textures,library.manifest):check(false,library.error+bindings.error+visuals.error);return
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,640);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var session:=Session.new();viewport.add_child(session)
	if not session.configure(library,bindings,visuals,0,0.5,1789100000,true,true,true):
		check(bindings.opening_staging.get("escape_camera",{}).is_empty(),session.error)
		check(session.get_child_count()==0,"Rejected escape retained presentation nodes")
		viewport.free();return
	check(session.escape_sequence and session.hyperdrive!=null and session.fade_overlay!=null,"Session omitted escape presentation")
	check(session.hyperdrive.model.instances.size()==21,"Hyperdrive surface count changed")
	check(session.hyperdrive.model.visible and not session.snapshot().escape.effect.playing,"Stopped initial hyperdrive was not drawable")
	check(not session.fade_overlay.visible and session.snapshot().fade.alpha_byte==0,"Fresh opening began with a fade")
	check((session.planets!=null)==not bindings.opening_sky.get("planet_resources",{}).is_empty(),"Escape omitted its available planet capability")
	var now:=0
	var voice_seen:={}
	for tick in 1500:
		now+=100000
		if not session.step(now):check(false,session.error);viewport.free();return
		verify_radio_audio(session,bindings,voice_seen)
		if session.snapshot().camera.shot.phase==4:break
	check(session.can_control(),"Opening did not release interactive flight")
	var launches:=0
	for tick in 100:
		var alive:=false
		for actor in session.snapshot().combat.actors:
			if actor.vitals.hull<=0:continue
			alive=true
			var gun: RefCounted=session._world_frame._primaries._guns[0].projectiles
			gun._elapsed_ms=int(gun.snapshot().weapon.interval_ms)+1
			check(gun.fire(actor.pose.origin,Vector3.BACK,true).get("fired",false),gun.error);launches+=1
		if not alive:break
		now+=100000
		if not session.step(now):check(false,session.error);viewport.free();return
		verify_radio_audio(session,bindings,voice_seen)
	var checks:={};var fade_request_time:=-1;var before_relocation:={}
	var audio_events:={}
	var death_audio:={}
	if session.audio!=null:
		for cue in session.audio.snapshot().history:
			if cue.has("actor_id"):death_audio[str(cue.actor_id)+":"+str(cue.source_id)]=true
	var particle_checks:={"npc_births":false,"player_births":false,"restore":false,"reset":false}
	var preceding_particles: Dictionary=session.snapshot().world_frame.get("damage_particles",{})
	for tick in 5000:
		now+=100000
		if not session.step(now):check(false,session.error);viewport.free();return
		verify_radio_audio(session,bindings,voice_seen)
		var state: Dictionary=session.snapshot();var escape: Dictionary=state.escape
		if not preceding_particles.is_empty():
			verify_particle_frame(state,preceding_particles,particle_checks)
			preceding_particles=state.world_frame.damage_particles
		if session.audio!=null:
			var sound: Dictionary=session.audio.snapshot()
			check(sound.revision==session._audio_revision and sound.elapsed_ms==state.elapsed_ms,"Audio missed the committed frame")
			if not bindings.opening_actors.npc_initialization.get("destruction_audio",{}).is_empty():
				for event in state.world_frame.actor_events:
					for cue in event.get("destruction",{}).get("audio_events",[]):
						check(sound.history.any(func(row):return row.revision==sound.revision and row.get("actor_id")==event.actor_id and row.source_id==cue.source_id and row.position==cue.position),"A death sound was not committed at its original frame and position")
						death_audio[str(event.actor_id)+":"+str(cue.source_id)]=true
			for cue in escape.frame.audio:
				if cue.action in ["start","start_spatial","replace_music","set_player_engine"]:audio_events[int(cue.source_id)]=true
				check(not sound.history.is_empty() and sound.history[-1].revision==sound.revision,"Audio cue was not committed with its scene")
		var phase:=int(escape.phase)
		if session.damage_particles!=null:
			check(session.damage_particles.frame.elapsed_ms==state.elapsed_ms,"Damage sprite presentation missed a committed world frame")
			if phase==12 and escape.phase_elapsed_ms>=1500 and not checks.has("damage_player"):
				checks.damage_player=true;await capture(viewport,library,"damage-player")
			if phase==4 and not checks.has("damage_npc"):
				var count:=0
				for index in [1,2,3]:count+=int(session.damage_particles.frame.counts[index])
				if count>=3:checks.damage_npc=true;await capture(viewport,library,"damage-npc")
		if session.planets!=null:
			var current: Dictionary=session.planets.selection.planets[int(session.planets.selection.selected_index)-1]
			check(current.texture_id==int(bindings.opening_staging.escape.jump_planet_texture_id if phase>=10 else bindings.opening_sky.planet_resources.opening_texture_id),"Escape planet texture changed at the wrong phase")
		check(session.geometry.player.visible==escape.ship_visible,"Source player visibility diverged")
		var expected: Transform3D=state.scene.player_pose*Transform3D(rotation(escape.model_rotation),Vector3.ZERO)
		check(session.geometry.player.transform.is_equal_approx(expected),"Visual tumble was not composed below the logical player pose")
		check(session.hyperdrive.model.visible,"Stopped hyperdrive discarded its retained surfaces")
		if phase>4:check(not session.can_control() and session.status!="mission_transition_required","Escape hit the old boundary or released controls")
		if not escape.frame.fade_request.is_empty():
			fade_request_time=now
			verify_fade_edges(session._fade)
			check(state.fade.active and state.fade.elapsed_ms==0 and state.fade.alpha_byte==0,"Fade request consumed an earlier frame delta")
		if phase in [5,6,7,8,9,10,11,12,13,14,15,16] and not checks.has(phase):
			checks[phase]=true
			if phase==5:
				var foreign: RefCounted=session._timeline.escape_owner()
				foreign._escape._identity=RefCounted.new()
				check(session.hyperdrive.prepare_frame(foreign).is_empty(),"Renderer accepted another opening owner")
			if phase==7:await capture(viewport,library,"departure-start")
			if phase==9:
				check(escape.effect.playing and escape.effect.time_ms==50 and escape.effect.sample_time_ms==3000,"Reset discarded the stopped hyperdrive sample")
				before_relocation=state.scenery
				# The next frame swaps sky and planet before presenting scenery.
				# Reject that later owner and require the departure view back.
				var audio_before: Dictionary={} if session.audio==null else session.audio.snapshot()
				var retained:=render_state(session)
				var model: Node3D=session.scenery.objects[0]
				var id: int=model.get_meta("source_resource_id")
				model.set_meta("source_resource_id",-1)
				check(not session.step(now+100000),"Invalid scenery accepted the relocation frame")
				check(session.snapshot()==state and render_state(session)==retained,"Failed relocation retained arrival planet, sky or pose")
				if session.audio!=null:check(session.audio.snapshot().history==audio_before.history and session.audio.snapshot().revision==audio_before.revision,"Failed relocation started arrival music")
				model.set_meta("source_resource_id",id)
				check(session.present(),session.error)
			if phase==10:
				check(state.scenery.get("escape_relocated",false),"Session did not retire the preceding scenery")
				check(state.scenery.objects==before_relocation.objects and state.scenery.remaining_count==before_relocation.remaining_count and state.scenery.destroyed_count==before_relocation.destroyed_count,"Relocation moved scenery or awarded destruction")
				for body in state.scenery.bodies.objects:check(not body.active,"Relocation retained an active scenery collider")
				for object in session.scenery.objects:check(not object.visible,"Relocation retained visible intact scenery")
				check(session.sky.selection.layers[1].mesh_id==17809 and session.sky.selection.layers[1].texture_id==10074,"Session retained the preceding sky")
			if phase==12:await capture(viewport,library,"arrival-drift")
		if phase==7 and escape.phase_elapsed_ms>=1500 and not checks.has("departure"):
			checks.departure=true;await capture(viewport,library,"departure-effect")
		if phase==7 and not escape.ship_visible and not checks.has("hidden"):
			checks.hidden=true;await capture(viewport,library,"departure-hidden")
		if phase==11 and escape.phase_elapsed_ms>=1500 and not checks.has("arrival"):
			checks.arrival=true;await capture(viewport,library,"arrival-effect")
		if phase==16 and state.fade.elapsed_ms==2500 and not checks.has("fade"):
			checks.fade=true
			check(state.fade.alpha_byte==127,"Half fade did not truncate source alpha")
			await capture(viewport,library,"half-fade")
			var saved:=session.snapshot()
			check(session.set_pause("user",true,now),session.error)
			check(session.step(now+9000000) and session.snapshot()==saved,"Pause advanced escape or fade")
			if session.audio!=null:check(session.audio.snapshot().paused,"Escape pause did not reach audio")
			check(session.set_pause("user",false,now),session.error)
			var pivot: Vector3=session.hyperdrive._sampler._pivots[-1]
			session.hyperdrive._sampler._pivots[-1]=Vector3(INF,0,0)
			var retained:=render_state(session)
			check(not session.step(now+100000),"Invalid final animation surface was presented")
			check(session.snapshot()==saved and render_state(session)==retained,"Failed frame committed world, fade or model state")
			session.hyperdrive._sampler._pivots[-1]=pivot
			check(session.present(),session.error)
		if phase==16 and state.fade.elapsed_ms==5000:
			check(state.fade.active and state.fade.alpha_byte==255 and escape.boundary.is_empty(),"Fade completed at equality")
			await capture(viewport,library,"fade-equality")
		if session.status=="arrival_transition_required":
			if session.audio!=null:
				for id in [141,143,156,157,158,159,160,161]:check(audio_events.has(id),"Escape never reached audio cue %d"%id)
				var sound: Dictionary=session.audio.snapshot()
				var engine_key: Variant="player_engine" if state.world_frame.has("player_engine") else 156
				check(sound.unsupported.is_empty() and sound.active.has(engine_key),"An escape sound remained unsupported")
				var layered: Dictionary=sound.active[engine_key].layers
				check(layered.history.any(func(row):return row.action=="start" and row.key=="1:0") and layered.sequence.elapsed_ms>4000,"The arrival engine never advanced through its source layers")
				check(sound.music_id==141 and sound.paused,"Arrival boundary did not retain paused jump music")
				if not bindings.opening_dialogue.get("voice",{}).is_empty():check(voice_seen.size()==23 and sound.voice_displayed.all(func(v):return v),"Full escape omitted an original spoken transmission")
				if not bindings.opening_actors.npc_initialization.get("destruction_audio",{}).is_empty():
					for actor in 3:
						check(death_audio.has(str(actor)+":20") and (death_audio.has(str(actor)+":18") or death_audio.has(str(actor)+":19")),"Opening omitted an actor's death or breakup audio")
			if not preceding_particles.is_empty():
				for key in particle_checks:check(particle_checks[key],"Opening never exercised particle event: "+key)
			check(fade_request_time>=0 and now-fade_request_time==5100000,"Arrival transition crossed the wrong fade boundary")
			check(not state.fade.active and state.fade.elapsed_ms==0 and state.fade.black_plate and state.fade.alpha_byte==255,"Arrival lost its persistent black plate")
			for finished in state.radio.finished:check(finished,"Session skipped an original transmission")
			check(state.world_frame.controller.death_accounting.counter_deltas.player_kills==3,"Escape changed earned kill accounting")
			check(session.step(now+9000000) and session.snapshot()==state,"Unsupported arrival continued advancing")
			break
	check(session.status=="arrival_transition_required" and checks.size()>=16,"Escape presentation did not cover every phase")
	var owner: RefCounted=session._timeline.escape_owner()
	var fade:=Fade.new()
	check(not fade.configure(owner),"Fade reset after the escape began")
	print(library.manifest.profile.edition,": ",launches," controlled full-hull contacts; original hyperdrive, tumble, hide/restore, all radio, fade, audio and rollback verified")
	session.clear();check(session.hyperdrive==null and session.fade_overlay==null and session.get_child_count()==0,"Clear retained escape nodes")
	viewport.free()

func verify_radio_audio(session: Node3D, bindings: RefCounted, seen: Dictionary) -> void:
	if bindings.opening_dialogue.get("voice",{}).is_empty():return
	var state: Dictionary=session.snapshot()
	var sound: Dictionary=session.audio.snapshot()
	for change in state.radio_changes:
		if change.kind!="display":continue
		var event:=int(change.event)
		var spoken: Array=sound.history.filter(func(op):return op.revision==sound.revision and op.get("radio_event")==event)
		check(not seen.has(event) and spoken.size()==1 and spoken[0].source_id==bindings.opening_dialogue.voice.event_ids[event] and spoken[0].text_id==change.text_id,"Spoken radio differs from its source display frame")
		seen[event]=true

func verify_fade_edges(owner: RefCounted) -> void:
	var fade: RefCounted=owner.fork_for_frame();var initial: Dictionary=fade.snapshot()
	for delta in [-1,151,0.5,NAN]:
		check(not fade.advance(delta) and fade.snapshot()==initial,"Invalid fade time mutated the owner")
	for tick in 50:check(fade.advance(100),fade.error)
	check(fade.snapshot().active and fade.snapshot().alpha_byte==255,"Fade was not active at 5000 ms")
	check(fade.advance(0) and fade.snapshot().active,"Zero frame completed an opaque fade")
	check(fade.advance(1) and not fade.snapshot().active and fade.snapshot().elapsed_ms==0,"Fade did not stop at 5001 ms")
	check(owner.snapshot()==initial,"Detached fade changed the session owner")

func verify_particle_frame(state: Dictionary,previous: Dictionary,seen: Dictionary) -> void:
	var particles: Dictionary=state.world_frame.damage_particles
	var cue: Dictionary=state.escape.frame
	check(particles.elapsed_ms==state.elapsed_ms,"Particle and world clocks diverged")
	check(particles.manager_ms==0,"Hundred-millisecond world frames retained particle manager time")
	for id in 3:
		var key:="npc%d" % id
		var owner: Dictionary=particles.owners[key]
		check(owner.smoke.baseline==previous.owners[key].root_pose.origin,"Smoke sampled current NPC movement before its source pass")
		check(owner.fire.baseline==previous.owners[key].root_pose.origin,"Fire and smoke sampled different NPC frames")
		if particles.births[key][0]>0:seen.npc_births=true
		for event in state.world_frame.actor_events:
			if event.actor_id==id and event.get("destruction",{}).get("breakup",false):
				check(not owner.smoke.enabled and not owner.fire.enabled,"World breakup omitted trail shutdown")
	var player: Dictionary=particles.owners.player
	if cue.get("ship_restore",false):
		seen.restore=true
		check(player.smoke.enabled and player.fire.enabled,"Restore cue omitted player damage effects")
		check(particles.births.player==[0,0],"Controller cue emitted before the next early world pass")
	if particles.births.player[0]>0:
		seen.player_births=true
		check(seen.restore,"Player health alone enabled authored damage effects")
	if not cue.get("world_change",{}).is_empty():
		seen.reset=true
		check(particles.resets==previous.resets+1,"Relocation omitted particle manager reset")
		for owner in particles.owners.values():
			for kind in ["smoke","fire"]:
				check(owner[kind].dirty,"Relocation kept a preceding particle velocity baseline")
				for slot in owner[kind].slots:check(slot.appearance.age_ms==-1,"Relocation left a preceding particle alive")
	else:check(particles.resets==previous.resets,"Ordinary update reset damage effects")

func render_state(session: Node3D) -> Dictionary:
	var surfaces:=[]
	for i in session.hyperdrive.model.instances.size():
		surfaces.append({"pose":session.hyperdrive.model.instances[i].transform,"tint":session.hyperdrive.model.materials[i].get_shader_parameter("effect_tint")})
	var planets:=[]
	if session.planets!=null:
		for model in session.planets.models:
			planets.append({"pose":model.transform,"texture":model.materials[0].get_shader_parameter("diffuse_texture"),"id":model.get_meta("source_texture_id")})
	var particles:={}
	if session.damage_particles!=null:
		particles={"pose":session.damage_particles.global_transform,"counts":session.damage_particles.frame.counts.duplicate(),"meshes":[]}
		for item in session.damage_particles.items:
			particles.meshes.append([] if item.node.mesh==null else item.node.mesh.surface_get_arrays(0))
	return {"particles":particles,"sun":{} if session.sun==null else session.sun.frame.duplicate(true),"surfaces":surfaces,"player":session.geometry.player.transform,"visible":session.geometry.player.visible,"fade_color":session.fade_overlay.color,"fade_visible":session.fade_overlay.visible,"planets":planets,"planet_selection":{} if session.planets==null else session.planets.selection.duplicate(true),"sky":session.sky.selection.duplicate(true)}

# Independent closed-form fixed Euler matrix, with source row/column convention.
func rotation(value: Vector3) -> Basis:
	var cx:=cos(value.x);var cy:=cos(value.y);var cz:=cos(value.z)
	var sx:=sin(value.x);var sy:=sin(value.y);var sz:=sin(value.z)
	return Basis(Vector3(cy*cz,-cy*sz,sy),Vector3(cx*sz+sx*sy*cz,cx*cz-sx*sy*sz,-sx*cy),Vector3(sx*sz-cx*sy*cz,sx*cz+cx*sy*sz,cx*cy))

func capture(viewport: SubViewport, library: RefCounted, label: String) -> void:
	if captures.is_empty():return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path:=captures.path_join(library.manifest.profile.edition+"-"+label+".png")
	var picture:=viewport.get_texture().get_image()
	check(picture.save_png(path)==OK,"Could not save GPU capture")
	if label=="fade-equality":
		for y in range(0,picture.get_height(),17):
			for x in range(0,picture.get_width(),17):
				var pixel:=picture.get_pixel(x,y)
				check(pixel.r==0 and pixel.g==0 and pixel.b==0,"Opaque fade failed to cover the game viewport")


func check(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)
