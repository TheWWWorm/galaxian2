extends "res://tests/tractor_recovery.gd"
## Detached equipment and wreck vectors using original imported beam models.
const Geometry=preload("res://src/presentation/tractor_geometry.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const AudioResources=preload("res://src/content/audio_resources.gd")
const Audio=preload("res://src/presentation/opening_audio.gd")

func _initialize() -> void:call_deferred("run_geometry")
func run_geometry() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() not in [3,4]:check(false,"Expected identified content, bindings and visuals")
	else:await verify_geometry(args)
	print("Original tractor geometry: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_geometry(args: PackedStringArray) -> void:
	var library:=Library.new();rules=Bindings.new();cat=Catalogues.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not rules.open(args[1],library.manifest) or not cat.open(library) or not visuals.open(args[2],library.manifest):check(false,library.error+rules.error+cat.error+visuals.error);return
	if not Definitions.available(rules):
		var unsupported:=Geometry.new();check(not unsupported.build(Recovery.new(),library,visuals,rules),"An older pack enabled unconfigured tractor presentation");unsupported.free();return
	var audio:=AudioResources.new()
	if not audio.configure(library,rules):check(false,audio.error);return
	for id in [0,4]:
		var clip: Dictionary=audio.prepare(id)
		check(not clip.is_empty() and not clip.has("unsupported"),"Original tractor audio unavailable: "+str(clip.get("unsupported",audio.error)))
		check(clip.get("looping")==bool(id==0),"Tractor loop/pickup playback disagrees with the original event")
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();viewport.add_child(camera);camera.current=true;camera.near=1;camera.far=100000
	var presenter:=Audio.new();root.add_child(presenter)
	presenter._tractor_sounds=[0,4]
	for id in [68,69,70]:
		var device:=Recovery.new()
		if not device.configure(rules,cat,loadout([id,81]),library):check(false,device.error);break
		var geometry:=Geometry.new();viewport.add_child(geometry)
		if not geometry.build(device,library,visuals,rules):check(false,geometry.error);geometry.free();break
		var prepared: Dictionary=geometry.prepare_world(device)
		if prepared.is_empty():check(false,geometry.error);geometry.free();break
		geometry.commit_world(prepared)
		check(not geometry.beam.visible,"An idle tractor beam appeared")
		var row: Dictionary=device.snapshot().beam.playback
		check(row.model_id==14232+id-68 and row.start_ms==33 and row.end_ms==1033 and row.time_ms==33 and row.render_type==2,"Original standard tractor model/timing changed")
		var ship:=actor();var cargo:=hold()
		if not device.queue_acquired_wreck(ship) or not device.advance(0,player(),ship,cargo):check(false,device.error);geometry.free();break
		check(device.snapshot().beam.playback.time_ms==33 and device.snapshot().frame.phase=="started","Starting a tractor advanced its animation")
		var before: Dictionary=device.snapshot()
		var next: RefCounted=device.fork_for_frame()
		if not next.advance(100,player(),ship,cargo):check(false,next.error);geometry.free();break
		prepared=geometry.prepare_world(next)
		if prepared.is_empty():check(false,geometry.error);geometry.free();break
		check(not geometry.beam.visible and device.snapshot()==before,"Preparing a beam drew early or mutated its parent recovery")
		geometry.commit_world(prepared);device=next
		var state: Dictionary=device.snapshot()
		check(geometry.beam.visible and state.beam.scale==Vector3(.5,.5,1300) and state.beam.playback.time_ms==133,"Beam did not use the source pre-pull distance and animation clock")
		check(presenter.prepare_tractor(state.frame).operations==[{"action":"start","source_id":0}],"First pull lost the original loop start")
		var poses: Array=geometry.beam.instances.map(func(instance):return instance.transform)
		for frame in 3:await process_frame
		check(device.snapshot()==state and geometry.beam.instances.map(func(instance):return instance.transform)==poses,"Drawing advanced paused recovery or animation")
		var again:=geometry.prepare_world(device)
		check(not again.is_empty() and again.surfaces==prepared.surfaces,"Presenting the same accepted beam changed its animation")
		var wrong:=Recovery.new()
		check(wrong.configure(rules,cat,loadout([id,81]),library) and geometry.prepare_world(wrong).is_empty(),"Beam geometry accepted another equipped history")
		wrong=device.fork_for_frame();wrong._state.beam.scale=Vector3(NAN,1,1)
		check(geometry.prepare_world(wrong).is_empty() and geometry.beam.visible and geometry.beam.instances.map(func(instance):return instance.transform)==poses,"Invalid beam preparation damaged the current scene")
		camera.look_at_from_position(Vector3(1200,800,1900),Vector3(0,0,650))
		if DisplayServer.get_name()!="headless":
			for frame in 3:await process_frame
			await RenderingServer.frame_post_draw
			var image:=viewport.get_texture().get_image();var background:=image.get_pixel(0,0);var foreground:=0
			for y in range(0,image.get_height(),2):
				for x in range(0,image.get_width(),2):
					var pixel:=image.get_pixel(x,y)
					if absf(pixel.r-background.r)+absf(pixel.g-background.g)+absf(pixel.b-background.b)>.09:foreground+=1
			check(foreground>100,"The original tractor beam did not render")
			if args.size()==4:
				DirAccess.make_dir_recursive_absolute(args[3])
				check(image.save_png(args[3].path_join("tractor-%d.png"%id))==OK,"Could not save the tractor capture")
		ship=apply_actor(ship,state.frame.actor_changes)
		if not device.advance(0,player(),ship,cargo):check(false,device.error);geometry.free();break
		prepared=geometry.prepare_world(device)
		if prepared.is_empty():check(false,geometry.error);geometry.free();break
		geometry.commit_world(prepared)
		check(not geometry.beam.visible and device.snapshot().frame.phase=="pickup","Pickup kept the beam visible")
		check(presenter.prepare_tractor(device.snapshot().frame).operations==[{"action":"stop","source_id":0},{"action":"start","source_id":4}],"Pickup lost the stop-loop/collection sound order")
		# The shared model clock wraps at absolute end, retaining the start offset.
		var loop:=Recovery.new();var distant:=actor(0,Vector3(0,0,20000))
		if not loop.configure(rules,cat,loadout([id,81]),library) or not loop.queue_acquired_wreck(distant) or not loop.advance(0,player(),distant,cargo):check(false,loop.error);geometry.free();break
		for tick in 10:
			if not loop.advance(100,player(),distant,cargo):check(false,loop.error);break
			distant=apply_actor(distant,loop.snapshot().frame.actor_changes)
		check(loop.snapshot().beam.playback.time_ms==1033,"Animation wrapped at its inclusive end key")
		check(loop.advance(100,player(),distant,cargo) and loop.snapshot().beam.playback.time_ms==133,"Tractor animation changed the shared source loop arithmetic")
		check(loop.advance(0,player(),{},cargo) and presenter.prepare_tractor(loop.snapshot().frame).operations==[{"action":"stop","source_id":0}],"A vanished wreck failed to stop the beam loop")
		geometry.free()
	var unsupported:=Recovery.new()
	check(not unsupported.configure(rules,cat,loadout([194,81]),library),"Expansion tractor silently discarded its animated UV/color channels")
	check(presenter.prepare_tractor({"events":[{"kind":"sound","source_id":15}]}).is_empty(),"Tractor playback accepted an unrelated sound")
	check(presenter.prepare_tractor({"events":[{"kind":"stop_sound","source_id":4}]}).is_empty(),"Tractor playback stopped its one-shot pickup event")
	presenter.free();viewport.free()
