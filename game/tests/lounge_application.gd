extends "res://tests/contract_station.gd"
## Actual UI/session integration following the inherited native station visits.
## The inherited cursor-ten entry and hidden lounge RNG histories are explicit
## fixtures. Combat outcomes use disclosed placements/hits, not a playthrough.
const Host=preload("res://src/presentation/opening_preview.gd")
const StationSession=preload("res://src/presentation/station_session.gd")
const FlightSession=preload("res://src/presentation/first_flight_session.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const CaptureSupport=preload("res://tests/fixtures/model_capture.gd")
var source: RefCounted
var definitions: RefCounted
var catalogue: RefCounted
var visual: RefCounted
var origin: RefCounted
var app: Control
var now_us:=1000000
var completed_cases:=[]

func flight_world_seconds() -> int:
	return 1789100000

func _initialize() -> void:call_deferred("run_application")

func after_contract_intro(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted) -> void:
	definitions=bindings;catalogue=cat;source=library;origin=station.fork()

func run_application() -> void:
	var args:=CaptureSupport.arguments()
	check(args.size() in [3,4],"Expected explicit content, bindings, visuals and optional captures")
	if args.size() in [3,4]:verify(args.slice(0,3))
	if failures==0 and origin!=null:
		visual=Visuals.new()
		check(visual.open(args[2],source.manifest),visual.error)
	if failures==0:
		root.content_scale_size=Vector2i.ZERO
		root.size=Vector2i(1280,720)
		app=Host.new();root.add_child(app);app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		app.set_context(source,definitions,visual);app.set_process(false);app._focused=true
		await process_frame
		for kind in [0,4,7,12,11]:
			await verify_application_kind(kind,args)
			if failures:break
		check(completed_cases==[0,4,7,12,11],"The application did not verify all four contract flights and the passenger capacity guard")
	if is_instance_valid(app):app.free()
	print("Lounge application: %d checks; cases %s; %d failures"%[checks,str(completed_cases),failures])
	quit(1 if failures else 0)

func generated_fixture(kind: int) -> Dictionary:
	for seed_value in 128:
		var current: RefCounted=origin.fork()
		if not current.open_contracts(definitions,catalogue) or not prepare_lounge_fixture(definitions,catalogue,source,current,seed_value):check(false,current.error);return {}
		for contact in current.snapshot().contracts.population.contacts:
			if contact.offer.is_empty() or contact.offer.mission.kind!=kind:continue
			if kind==0 and contact.offer.mission.station_id!=75:continue
			var preview: Dictionary=current.contract_preview(contact.contact_id)
			if kind!=11 and not preview.get("can_accept",false):continue
			print("Lounge application fixture: kind %d, seed %d, contact %d, destination %d"%[kind,seed_value,contact.contact_id,contact.offer.mission.station_id])
			return {"owner":current,"contact_id":contact.contact_id}
	check(false,"No generated fixture for kind "+str(kind));return {}

func verify_application_kind(kind: int,args: PackedStringArray) -> void:
	var fixture:=generated_fixture(kind)
	if fixture.is_empty():return
	app.reset();app._focused=true
	var session:=StationSession.new();app.viewport.add_child(session)
	session._world=fixture.owner
	if not session._build_scene(source,definitions,visual,catalogue,now_us,42):check(false,session.error);session.free();return
	if not app.station_panel.configure_empty(source,definitions) or not session.activate():check(false,app.station_panel.error+session.error);session.free();return
	app.session=session;app.present_session()
	var before: Dictionary=session.snapshot()
	check(app.contract_action("open",-1),session.error)
	check(app.lounge_panel.visible and not app._launch_button.visible,"Opening the lounge did not select the retained contacts")
	check(app.lounge_panel.label_text(850)=="Accept this mission?" and app.lounge_panel.label_text(753)=="#C reward.","The lounge used another source's confirmation or reward text")
	check(app.lounge_panel.label_text(847)=="Okay." and app.lounge_panel.label_text(848)=="No thanks.","The lounge used another source's action labels")
	if session.lounge_scene==null:check(false,"The lounge has no original room");return
	for tick in 30:
		if not application_step():return
	check(not session.geometry.visible and session.lounge_scene.camera.current,"The lounge retained its hangar instead of its room camera")
	var room: Dictionary=session.lounge_scene.snapshot()
	check(room.room==3 and room.station_id==79 and room.sky.station_id==79 and room.planets.station_id==79,"The lounge lost its actual station background")
	check(room.visitors.size()==session.snapshot().contracts.population.contacts.size(),"The room lost its retained contacts")
	var hit_rows: Array=session.lounge_scene.screen_contacts().filter(func(row):return row.id==fixture.contact_id)
	if hit_rows.size()!=1:check(false,"The quoted contact is not selectable in the room");return
	var pointer:=InputEventMouseButton.new();pointer.button_index=MOUSE_BUTTON_LEFT;pointer.pressed=true;pointer.position=hit_rows[0].anchor
	app.lounge_panel._room_input(pointer)
	check(app.lounge_panel.snapshot().selected==fixture.contact_id,"Clicking the visitor did not select the original contact")
	if kind==11:
		var preview: Dictionary=session.station_owner().contract_preview(fixture.contact_id)
		check(not preview.can_accept and preview.reason_text_id==327 and not app.lounge_panel.snapshot().accept_visible,"The application sold nonexistent passenger places")
		var blocked: Dictionary=session.snapshot()
		app.lounge_panel.confirm()
		check(session.snapshot()==blocked,"Blocked passenger acceptance changed the career")
		completed_cases.append(kind);return
	if args.size()==4 and kind==0:
		await capture_lounge(args[3],"lounge-courier-desktop")
		app.lounge_panel.set_mobile_layout(true)
		root.size=Vector2i(844,390)
		await capture_lounge(args[3],"lounge-courier-mobile-landscape")
		check(app.lounge_panel._yes.custom_minimum_size.y>=44,"Landscape mobile lost its larger touch action")
		app.lounge_panel.set_mobile_layout(false)
		root.size=Vector2i(1280,720)
	var quoted: Dictionary=session.snapshot()
	app.lounge_panel.confirm()
	check(app.lounge_panel.snapshot().confirming and session.snapshot()==quoted,"Selecting a job bypassed acknowledgement")
	if failures:return
	app.lounge_panel.confirm()
	if app._transition_failed:check(false,app.status.text);return
	var accepted: Dictionary=session.snapshot()
	check(accepted.contracts.mission.kind==kind and accepted.contracts.offers[fixture.contact_id].consumed,"The actual lounge did not retain its accepted job")
	check(accepted.contracts.credits==before.contracts.credits and accepted.completed_side_missions==0 and accepted.mission==before.mission,"Acceptance paid, counted or replaced the story")
	check(accepted.contracts.accepted_contact.has("portrait"),"The original client portrait was not retained")
	check(not session.contract_action("accept",fixture.contact_id,app.lounge_panel) and session.snapshot()==accepted,"Repeated acceptance changed the accepted station")
	app.lounge_panel.back()
	check(not app.lounge_panel.visible and not session.snapshot().lounge_open,"Back failed to release the lounge")
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	print("Lounge application launch: kind "+str(kind))
	if not await release_application_flight():return
	print("Lounge application released: kind "+str(kind))
	var flight: Node=app.session
	check(flight.snapshot().contracts.mission==accepted.contracts.mission and flight.snapshot().contracts.accepted_contact==accepted.contracts.accepted_contact,"Launch lost the retained job or original client")
	var destination: int=accepted.contracts.mission.station_id
	if destination!=flight.snapshot().location.station_id:
		if not await travel_application(destination):return
		flight=app.session
	check(app.locations_snapshot().locations.any(func(row):return row.station_id==destination),"Contract arrival did not prepare its actual location stock and contacts")
	if kind==0:
		if not await dock_application():return
		if not application_step():return
		await verify_application_result(kind,args)
	else:
		if not damage_contract_targets(kind):return
		for tick in 100:
			if not app.session.snapshot().contracts.pending_result.is_empty():break
			if not application_step():return
		await verify_application_result(kind,args)
	if failures==0:completed_cases.append(kind)

func application_step() -> bool:
	# Render awaits can deliver desktop focus notifications. Focus-loss behavior
	# is covered separately; keep this deterministic input fixture resumed.
	resume_application_focus()
	now_us+=100000
	if not app.session.step(now_us):check(false,app.session.error);return false
	app.present_session()
	if app._transition_failed:check(false,app.status.text);return false
	return true

func release_application_flight() -> bool:
	app.session.rebase_time(now_us)
	for tick in 71:
		if not application_step():return false
	check(app.session.can_control() and app.session.flight_audio!=null,"Contract flight did not release controls and original sound")
	return failures==0

func travel_application(destination: int) -> bool:
	if not await acquire_application_planet(destination):return false
	var before: Dictionary=app.session.snapshot()
	if not app.enter_local_arrival(now_us,4096,flight_world_seconds()):check(false,app.status.text);return false
	print("Lounge application arrival: station "+str(destination))
	check(app.session.snapshot().location.station_id==destination and app.session.snapshot().contracts.mission==before.contracts.mission,"The actual arrival lost its destination or accepted contract")
	return await release_application_flight()

func acquire_application_planet(destination: int) -> bool:
	if not app.open_map():check(false,app.status.text);return false
	app.map_panel.select_station(destination);app.map_panel.request_confirmation()
	if not app.confirm_map_planet(destination,now_us):check(false,app.map_panel.error);return false
	print("Lounge application course: "+str(destination))
	app.session.rebase_time(now_us)
	for tick in 2000:
		if app.session.status=="local_arrival_transition_required":break
		if not application_step():return false
		if tick%400==0:print("Lounge application travelling: "+str(tick))
		if tick%100==0:await process_frame
	if app.session.status!="local_arrival_transition_required":
		var state: Dictionary=app.session.snapshot()
		check(false,"Contract planet guidance never arrived: "+str({"travel":state.get("local_travel"),"guidance":state.get("station_autopilot"),"pose":state.player_pose,"clock":state.world_elapsed_ms}));return false
	return true

func dock_application() -> bool:
	resume_application_focus()
	if not app.session.action("autopilot"):check(false,app.session.error);return false
	for tick in 2000:
		if app.session.status=="station_transition_required":break
		if not application_step():return false
		if tick%400==0:
			var state: Dictionary=app.session.snapshot()
			print("Lounge application docking: "+str({"tick":tick,"clock":state.world_elapsed_ms,"pose":state.player_pose.origin,"guidance_active":state.station_autopilot.active,"status":app.session.status}))
		if tick%100==0:await process_frame
	if app.session.status!="station_transition_required":
		var state: Dictionary=app.session.snapshot()
		check(false,"Contract station guidance never docked: "+str({"clock":state.world_elapsed_ms,"pose":state.player_pose.origin,"guidance_active":state.station_autopilot.active,"status":app.session.status}));return false
	if not app.enter_station(now_us,42):check(false,app.status.text);return false
	app.session.rebase_time(now_us)
	return true

func damage_contract_targets(kind: int) -> bool:
	# Explicit placements and lethal hits exercise the real presentation/audio
	# transaction and result poll. They do not claim manually won combat.
	var frame: RefCounted=app.session.flight_owner()
	if kind!=7:
		for actor in frame.snapshot().encounter.combat.actors:
			if kind==12 and actor.actor_id==0:continue
			frame._pose.origin=actor.pose.origin+Vector3(0,0,20000)
			for tick in 2:
				var next: RefCounted=frame.evaluate(0)
				if next==null:check(false,frame.error);return false
				if not app.session._commit(next,false):check(false,app.session.error);return false
				frame=app.session.flight_owner()
	if not app.session._commit(frame,false):check(false,app.session.error);return false
	frame=app.session.flight_owner()
	var combat: RefCounted=frame._encounter._combat
	if not combat.begin_contact_pass(frame.snapshot().random_state,true):check(false,combat.error);return false
	for actor in combat.snapshot().actors:
		if kind==12 and actor.actor_id==0:continue
		var hit: Dictionary=combat.normal_hit(actor.actor_id,actor.vitals.hull,false)
		if hit.is_empty() or not hit.destroyed_now:check(false,"Explicit contract hit: "+combat.error);return false
	var destroyed: RefCounted=frame.evaluate(0)
	if destroyed==null:check(false,frame.error);return false
	if not app.session._commit(destroyed,false):check(false,app.session.error);return false
	app.present_session()
	return true

func verify_application_result(kind: int,args: PackedStringArray,previous_credits: int=0,previous_count: int=0) -> void:
	var session: Node=app.session
	var pending: Dictionary=session.snapshot()
	var result: Dictionary=pending.contracts.pending_result
	check(not result.is_empty() and app.lounge_panel.visible,"The earned result did not open its acknowledged panel")
	if result.is_empty():return
	check(result.completed and pending.contracts.credits==previous_credits and pending.campaign_cursor==13,"Result opened with early payment or a fabricated story unlock")
	check(not app._launch_button.visible and not session.can_control(),"The result panel allowed departure or flight control")
	if args.size()==4:await capture_lounge(args[3],"lounge-result-"+str(kind))
	check(session.set_pause("user",true,now_us),session.error)
	check(not app.contract_action("result_close",result.serial),"Paused Close collected the reward")
	check(session.set_pause("user",false,now_us),session.error)
	if not application_step():return
	check(session.snapshot()==pending,"An open result advanced its world")
	check(not app.contract_action("result_close",result.serial+1) and session.snapshot()==pending,"Stale Close changed the actual result")
	app.lounge_panel.confirm()
	var closed: Dictionary=session.snapshot()
	var reward:=int(result.get("reward_credits",result.get("credit_delta",0)))
	check(closed.contracts.pending_result.is_empty() and not app.lounge_panel.visible,"Close left the completed result open")
	check(closed.contracts.credits==previous_credits+reward and closed.contracts.completed_side_missions==previous_count+1 and closed.contracts.mission.is_empty(),"Close lost the payment, completion count or side slot")
	check(closed.mission==pending.mission and closed.campaign_cursor==13,"Contract settlement bypassed the acknowledged story handoff")
	var audio: Node=session.audio if session is StationSession else session.flight_audio
	var sounds: Array=audio.snapshot().equipment_effects.filter(func(id):return id==36) if session is StationSession else audio.snapshot().history.filter(func(row):return row.get("source_id")==36)
	check(sounds.size()==1,"The result did not play exactly one original payment notification")
	check(not app.contract_action("result_close",result.serial) and session.snapshot()==closed,"Duplicate Close paid again")
	var after_sounds: Array=audio.snapshot().equipment_effects.filter(func(id):return id==36) if session is StationSession else audio.snapshot().history.filter(func(row):return row.get("source_id")==36)
	check(after_sounds.size()==1,"Duplicate Close replayed payment sound")
	if kind==7:check(audio.snapshot().history.any(func(row):return row.get("source_id")==22),"Destroyed Junk lost its original sound")
	if session is StationSession:
		check(closed.cargo.used==pending.cargo.used-int(pending.contracts.mission.quantity),"Courier Close retained delivered protected cargo")
		check(app.request_departure(),"The settled destination could not launch again")
		app.cancel_departure()
	else:
		if not application_step():return
		check(session.can_control() and session.snapshot().world_elapsed_ms>closed.world_elapsed_ms,"The acknowledged contract did not resume flight")
	print("Lounge application settled: kind %d, earned %d credits"%[kind,reward])

func capture_lounge(directory: String,label: String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	var rect: Rect2=app.lounge_panel.snapshot().panel_rect
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(rect),"Lounge panel escaped its landscape viewport")
	var path:=directory.path_join(label+".png")
	check(root.get_texture().get_image().save_png(path)==OK,"Could not write the requested local lounge capture")
	resume_application_focus()

func resume_application_focus() -> void:
	app._focused=true
	if app.session!=null and app.session._pauses.has("focus"):
		app.session.set_pause("focus",false,now_us)
		app.session.rebase_time(now_us)
	app.refresh_render_mode()
