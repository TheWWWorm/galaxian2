extends SceneTree
const Notices=preload("res://src/simulation/flight_notices.gd")
const Definitions=preload("res://src/content/flight_notice_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Station=preload("res://src/simulation/station_entry.gd")
const Arrival=preload("res://src/simulation/arrival_world_frame.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Aim=preload("res://src/simulation/opening_aim.gd")
const Approach=preload("res://src/simulation/mining_approach.gd")
const Scene=preload("res://src/presentation/first_flight_scene.gd")
const NoticePanel=preload("res://src/presentation/flight_notice_panel.gd")
const Visuals=preload("res://src/content/visual_library.gd")
var checks:=0
var failures:=0
var lib: RefCounted
var bindings: RefCounted
var cat: RefCounted
var construction: RefCounted
var captures:={}
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected Mac content, bindings, visuals and optional capture directory")
	if args.size() in [3,4]:await verify(args)
	print("Flight notices: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)
func verify(args: Array):
	lib=Library.new();bindings=Bindings.new();cat=Catalogues.new();var bodies:=Bodies.new();var effects:=Effects.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb") or not bodies.configure(lib,bindings) or not effects.configure(lib,bindings):check(false,lib.error+bindings.error+cat.error+bodies.error+effects.error);return
	if bindings.flight_notices.is_empty():check(not Notices.new().configure(bindings,lib,Construction.new()),"Legacy pack invented flight notices");return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	check(Definitions.validate(bindings.flight_notices,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.first_flight).is_empty(),"Notice declarations were refused")
	for key in Definitions.VALUES:
		var bad: Dictionary=bindings.flight_notices.duplicate(true);bad[key]=null
		check(not Definitions.parameters(bad),"Changed notice parameter accepted: "+key)
	for key in Definitions.SPANS:
		var bad: Dictionary=bindings.flight_notices.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,header.source_executable_bytes,header.architecture,bindings.arrival_staging,bindings.first_flight).is_empty(),"Detached notice provenance accepted: "+key)
	var player:=Player.new();var handoff:=Handoff.new();check(player.configure(bindings,cat),player.error)
	var packet:=handoff.prepare(bindings,cat,Fixture.completed(bindings,player,3));var arrival:=Arrival.new()
	if not arrival.configure(bindings,cat,lib,packet,[1,1,1],1789100000):check(false,arrival.error);return
	for i in 500:
		arrival=arrival.evaluate(100)
		if arrival==null:check(false,"Could not prepare rescue fixture");return
		if not arrival.snapshot().boundary.is_empty():break
	var station:=Station.new();check(station.configure(bindings,cat,lib,arrival.prepare_station()),station.error)
	for i in 19:station.acknowledge()
	construction=Construction.new()
	if not construction.prepare(bindings,cat,station.prepare_departure(bindings,cat),4096,1789100000,true,bodies,effects):check(false,construction.error);return
	verify_queue()
	verify_languages()
	verify_flight()
	if args.size()==4 and failures==0:await verify_gpu(args)
func fresh() -> RefCounted:
	var notice:=Notices.new();check(notice.configure(bindings,lib,construction),notice.error);return notice
func advance_to(notice: RefCounted, target: int):
	var delta: int=target-int(notice.snapshot().elapsed_ms)
	while delta>0:
		var step:=mini(150,delta)
		if not notice.advance(step):check(false,notice.error);return
		delta-=step
func verify_queue():
	var queue:=fresh();var initial: Dictionary=queue.snapshot()
	check(initial.pending.is_empty() and not initial.visible and initial.elapsed_ms==0,"Notices began with unearned content")
	check(queue.enqueue(8) and queue.snapshot().current.text==lib.strings[528] and queue.snapshot().alpha==0,"Failure text or initial alpha differs")
	var values:={1:0,100:12,1000:127,2000:255,2001:255,3000:128,4000:0}
	for time in values:
		advance_to(queue,time);var state: Dictionary=queue.snapshot()
		check(state.alpha==values[time] and state.falling==(time>=2001) and state.visible,"Notice alpha/phase differs at "+str(time))
	check(queue.enqueue(8) and queue.snapshot().pending.size()==1 and queue.snapshot().elapsed_ms==4000,"Duplicate restarted or duplicated the fade")
	check(queue.enqueue(27) and queue.snapshot().pending.size()==2 and queue.snapshot().elapsed_ms==4000,"Queued notice reset the current clock")
	check(queue.advance(1) and queue.snapshot().current.source_id==27 and queue.snapshot().elapsed_ms==0 and queue.snapshot().alpha==0,"Strict retirement or next notice differs")
	check(queue.snapshot().current.rgb==[255,42,0],"Full hold lost its source warning color")
	advance_to(queue,4000);check(queue.advance(150) and queue.snapshot().pending.is_empty() and queue.snapshot().elapsed_ms==0 and not queue.snapshot().visible,"Retirement retained overshoot or an expired notice")
	check(queue.enqueue(8) and queue.snapshot().pending.size()==1,"Retired text remained in duplicate detection")
	advance_to(queue,1000);var before: Dictionary=queue.snapshot();var fork: RefCounted=queue.fork_for_frame()
	check(fork.advance(150,true) and fork.snapshot().elapsed_ms==1000 and not fork.snapshot().visible and fork.snapshot().suppressed and queue.snapshot()==before,"Drilling changed fade time or the accepted parent")
	var held: Dictionary=fork.snapshot();check(fork.advance(150,false,true) and fork.snapshot()==held,"Pause changed a held notice")
	check(fork.advance(100) and fork.snapshot().elapsed_ms==1100 and fork.snapshot().visible,"Notice did not resume after drilling")
	for invalid in [-1,151,1.5,"100"]:check(not queue.advance(invalid) and queue.snapshot()==before,"Invalid notice delta changed the queue")
	for invalid in [-1,7,65535,8.5,"8"]:check(not queue.enqueue(invalid) and queue.snapshot()==before,"Unsupported notice changed the queue")
	check(not queue.configure(bindings,lib,Construction.new()) and queue.snapshot()==before,"Failed notice configuration erased a live fade")
	var original: String=lib.strings[529];lib.strings[529]=lib.strings[528]
	var equal_text:=fresh();check(equal_text.enqueue(8) and equal_text.enqueue(9) and equal_text.snapshot().pending.size()==1,"Duplicate detection used IDs instead of localized text")
	lib.strings[529]=original
	check(equal_text.snapshot().current.text==lib.strings[528],"Restoring library text mutated a captured notice")
	queue.clear();check(queue.snapshot().is_empty() and not queue.enqueue(8),"Clear retained a configured queue")
func verify_languages():
	for language in lib.manifest.languages:
		check(lib.select_language(language),lib.error)
		var queue:=fresh()
		for id in [6,8,9,11,20,27]:
			var single:=fresh();check(single.enqueue(id) and not single.snapshot().current.text.is_empty(),"Missing localized notice "+language+"/"+str(id))
		check(queue.enqueue(11) and queue.snapshot().current.text==lib.strings[535]+": "+lib.strings[539],"Source target composition differs in "+language)
	check(lib.select_language("gb"),lib.error)
func verify_flight():
	var flight:=Frame.new();check(flight.configure(bindings,cat,lib,construction,"E",1.0,Vector2i(960,720)),flight.error)
	for i in 130:
		flight=flight.evaluate(100)
		if flight==null:check(false,"Could not prepare mining briefing");return
	for i in 5:flight=flight.navigate("next")
	var asteroid: Dictionary=construction.snapshot().scenery.bodies.objects[4]
	flight._pose=Transform3D(Basis(Vector3.UP,PI),asteroid.position+Vector3(0,0,float(int(Approach.f32(asteroid.scale*2500)))+10000))
	var data: Dictionary=bindings.camera_follow
	var eye: Vector3=flight._pose*Vector3(data.eye_offset[0],data.eye_offset[1],data.eye_offset[2]);var look: Vector3=flight._pose*Vector3(data.look_offset[0],data.look_offset[1],data.look_offset[2])
	flight._camera._state.eye=eye;flight._camera._state.look=look;flight._camera._state.pose=Transform3D.IDENTITY.looking_at(look-eye,Vector3.UP);flight._camera._state.pose.origin=eye
	flight._aim=Aim.new();flight._aim.configure(bindings)
	for i in 55:
		var next: RefCounted=flight.evaluate(100,Vector2.ZERO,0.0)
		if next==null:check(false,flight.error);return
		flight=next
	check(flight.snapshot().mining_targeting.selected_object_index==4 and flight.snapshot().flight_notices.pending.is_empty(),"Acquisition emitted an approach notice before its action")
	flight=flight.evaluate(0,Vector2.ZERO,1.0);var original: Dictionary=flight.snapshot()
	var running: RefCounted=flight.start_mining()
	if running==null:check(false,flight.error);return
	check(running.snapshot().flight_notices.current.source_id==11 and running.snapshot().flight_notices.elapsed_ms==0 and flight.snapshot()==original,"Approach action lost notice or changed its accepted parent")
	var full: RefCounted=flight.fork_for_frame();check(full._cargo.add_entries([{"item_id":asteroid.item_id,"quantity":25}]),full._cargo.error)
	var denied: RefCounted=full.start_mining()
	check(denied!=null and denied.snapshot().mining_approach.phase=="idle" and denied.snapshot().flight_notices.current.source_id==27 and denied.snapshot().cargo==full.snapshot().cargo and denied.snapshot().scenery==full.snapshot().scenery and denied.snapshot().random_state==full.snapshot().random_state,"Full hold moved, mined or lost its notice")
	var cancelled: RefCounted=running.cancel_mining()
	check(cancelled!=null and cancelled.snapshot().flight_notices.pending.size()==2 and cancelled.snapshot().flight_notices.pending[1].source_id==6 and cancelled.snapshot().mining_approach.phase=="idle","Cancellation lost its ordered notice")
	for i in 20:running=running.evaluate(100,Vector2.ZERO,0.0)
	var current: Dictionary=running.snapshot();captures["notice-target"]=running
	check(current.flight_notices.elapsed_ms==2000 and current.flight_notices.alpha==255 and current.player_pose!=original.player_pose,"Timed notice paused movement or has wrong peak")
	check(running.evaluate(100,Vector2.ZERO,0.0,true).snapshot()==current,"Pause changed live notices")
	var invalid: RefCounted=running.fork_for_frame();invalid._targeting._field_identity=RefCounted.new();var invalid_before: Dictionary=invalid.snapshot()
	check(invalid.evaluate(100)==null and invalid.snapshot()==invalid_before,"Late frame failure advanced an accepted notice")
	for i in 150:
		var next: RefCounted=running.evaluate(100,Vector2.ZERO,0.0)
		if next==null:check(false,running.error);return
		running=next
		if not running.snapshot().mining_session.drill.is_empty():break
	var docked: Dictionary=running.snapshot();check(not docked.mining_session.drill.is_empty() and docked.flight_notices.suppressed,"Drilling did not suppress the timed notice queue")
	# A pending source notice is an explicit queue fixture for drill-clock testing.
	check(running._notices.enqueue(6),running._notices.error);var started: Dictionary=running.snapshot()
	var failed: RefCounted=running
	for i in 300:
		var next: RefCounted=failed.evaluate(100,Vector2.ZERO,0.0,false,Vector2i.ZERO,Vector2.ONE)
		if next==null:check(false,failed.error);return
		if not next.snapshot().mining_session.drill.is_empty():
			if next.snapshot().flight_notices.elapsed_ms!=started.flight_notices.elapsed_ms:check(false,"Drilling consumed pending notice time");return
		failed=next
		if failed.snapshot().mining_session.phase=="finished":break
	var failure: Dictionary=failed.snapshot()
	check(failure.mining_session.last_drill.phase=="failed" and failure.flight_notices.pending[-1].source_id==8 and failure.flight_notices.elapsed_ms==100 and not failure.flight_notices.suppressed,"Failure lost its one-time notice or did not resume the queue")
	var count: int=failure.flight_notices.pending.size()
	for i in 5:failed=failed.evaluate(100)
	check(failed.snapshot().flight_notices.pending.size()==count,"The completed session repeatedly enqueued its old failure event")
	for i in 20:denied=denied.evaluate(100,Vector2.ZERO,0.0)
	captures["notice-full-hold"]=denied
	# Let existing notices retire, then capture the actual emitted failure at peak.
	for i in 100:
		var state: Dictionary=failed.snapshot().flight_notices
		if not state.current.is_empty() and state.current.source_id==8 and state.elapsed_ms>=2000:break
		failed=failed.evaluate(100)
	captures["notice-failure"]=failed
	check(failed.snapshot().flight_notices.current.source_id==8 and failed.snapshot().campaign_cursor==2 and failed.snapshot().progress==original.progress and failed.snapshot().cargo.used==0,"Failure notice completed the mission or granted cargo")
func verify_gpu(args: Array):
	var visuals:=Visuals.new();check(visuals.open(args[2],lib.manifest),visuals.error)
	var canvas:=SubViewport.new();canvas.size=Vector2i(960,720);canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;canvas.own_world_3d=true;root.add_child(canvas)
	var scene:=Scene.new();canvas.add_child(scene);check(scene.build(lib,bindings,visuals,cat,captures["notice-target"]),scene.error)
	for name in captures:
		check(scene.present(captures[name]),scene.error)
		check(scene.notice_panel.visible and scene.notice_panel.snapshot()==captures[name].snapshot().flight_notices,"Scene notice differs from the accepted queue")
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		check(canvas.get_texture().get_image().save_png(args[3].path_join(name+".png"))==OK,"Could not save notice capture")
	var before: Dictionary=scene.notice_panel.snapshot();var damaged: RefCounted=captures["notice-target"].fork_for_frame();damaged._notices._messages={};damaged._notices._pending[0].rgb=[999,1,1]
	check(not scene.present(damaged) and scene.notice_panel.snapshot()==before,"Failed notice presentation did not roll back the complete scene")
	canvas.free()
	check(lib.select_language("de"),lib.error);var german:=fresh();check(german.enqueue(27),german.error);advance_to(german,2000)
	var phone:=SubViewport.new();phone.size=Vector2i(420,800);phone.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(phone)
	var panel:=NoticePanel.new();phone.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	check(panel.configure(lib,bindings,visuals),panel.error);panel.set_mobile_layout(true);check(panel.present(german.snapshot()),panel.error)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	check(panel._label.get_line_count()==panel._label.get_visible_line_count() and panel._bar.get_rect().end.x<=420 and panel._bar.get_rect().end.y<=800,"Phone notice is clipped")
	check(panel._bar.get_rect().encloses(panel._label.get_rect()),"Localized text escaped its notice bar")
	check(phone.get_texture().get_image().save_png(args[3].path_join("notice-full-hold-phone-de.png"))==OK,"Could not save localized phone notice")
	for language in lib.manifest.languages:
		check(lib.select_language(language),lib.error)
		check(panel.configure(lib,bindings,visuals),panel.error)
		for id in [6,8,9,11,20,27]:
			var queue:=fresh();check(queue.enqueue(id),queue.error);advance_to(queue,2000)
			for mobile in [false,true]:
				phone.size=Vector2i(420,800) if mobile else Vector2i(960,720);panel.set_mobile_layout(mobile)
				check(panel.present(queue.snapshot()),panel.error)
				await process_frame;await process_frame
				check(panel._bar.get_rect().encloses(panel._label.get_rect()) and panel._label.get_visible_line_count()==panel._label.get_line_count() and panel._label.get_content_height()<=panel._label.size.y,"Localized notice is clipped: "+language+"/"+str(id)+"/"+str(mobile))
				if language=="zs" and id==20 and mobile:
					await RenderingServer.frame_post_draw
					check(phone.get_texture().get_image().save_png(args[3].path_join("notice-missing-drill-phone-zs.png"))==OK,"Could not save CJK notice")
	phone.free();lib.select_language("gb")
func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)
