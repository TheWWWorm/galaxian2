extends "res://tests/free_local_travel.gd"
## Actual earned18 local flight reaches Gome C. The shared session then flies
## its outgoing gate and stages Dis. Map and confirmation inputs pass through
## the application; successful journeys use the ordinary guidance and clocks.
const GateArrival=preload("res://src/content/gate_arrival_definitions.gd")
const FlightConstruction=preload("res://src/simulation/first_flight_construction.gd")
const FlightFrame=preload("res://src/simulation/first_flight_frame.gd")
const SceneryBodies=preload("res://src/content/scenery_body_resources.gd")
const SceneryEffects=preload("res://src/content/scenery_effect_resources.gd")

func local_destinations() -> Array:return [95]

func after_local_journeys(original: Dictionary,_initial_stock: Dictionary) -> void:
	if not GateArrival.available(definitions):check(false,"Gate arrival needs its explicit content capability");return
	var origin_stock: Dictionary=app.session.location_owner().location(95).stock
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	if not await release_application_flight():return
	var unready: RefCounted=app.session.flight_owner();var unready_state: Dictionary=unready.snapshot()
	check(unready.construct_gate_arrival(definitions,catalogue,4096,1789100000)==null and unready.snapshot()==unready_state,"Gate arrival bypassed its actual flight and animation")
	check(not app.session.select_gate_destination(56) and app.session.flight_owner().snapshot()==unready_state,"Unsupported pending story destination changed live flight")
	if not await choose_gate_course():return
	if not await reach_gate_confirmation():return
	if failures:return
	var modal: Dictionary=app.session.snapshot()
	check(not modal.station_autopilot.active and modal.contracts.travel_statistics.jumpgates_used==0,"Gate contact retained guidance or committed an early career increment")
	var source_frame: RefCounted=app.session.flight_owner()
	var map_branch: RefCounted=source_frame.choose_gate_confirmation(1)
	if map_branch==null:check(false,source_frame.error);return
	var map_state: Dictionary=map_branch.snapshot()
	check(map_branch.close_gate_map(true,56)==null and map_branch.snapshot()==map_state,"Unsupported gate map destination changed a retained frame")
	var cancelled: RefCounted=map_branch.close_gate_map(false)
	if cancelled==null:check(false,map_branch.error);return
	var resumed: Dictionary=cancelled.snapshot();var outgoing: Dictionary=resumed.gate_environment.objects[0]
	check(resumed.player_pose.origin==outgoing.pose.origin+Vector3(0,0,-8000) and resumed.player_pose.basis==outgoing.pose.basis and not cancelled.cinematic_input_blocked(),"Gate map cancellation lost the source resumed pose or controls")
	check(resumed.contracts==modal.contracts and source_frame.snapshot()==app.session.flight_owner().snapshot(),"A detached cancellation changed the live career or confirmation")
	now_us+=1000000
	check(app.session.step(now_us) and app.session.snapshot()==modal,"Waiting for gate confirmation advanced the world")
	app.present_session()
	for tick in 3:await process_frame
	check(app.gate_panel.visible and app.gate_panel.snapshot().text==source.strings[563]+": Dis\n"+source.strings[410],"Application omitted the original gate question or destination")
	check(Rect2(Vector2.ZERO,app.gate_panel.size).encloses(app.gate_panel._panel.get_rect()) and app.gate_panel._panel.size.y<app.gate_panel.size.y/2,"The desktop gate question did not settle into its compact panel")
	app._controls.accept(gate_key_event(KEY_SPACE,true));app.present_session()
	check(not app._controls.snapshot().held.fire,"A held flight action crossed into gate confirmation")
	app._unhandled_input(gate_key_event(KEY_ENTER,false))
	check(app.session.status=="gate_confirmation_required","Releasing a key accepted the gate")
	await capture_free_application("gate-contact-95")
	await capture_gate_interface_mobile("gate-confirmation-mobile")
	var frozen: Dictionary=app.session.snapshot()
	app.set_user_paused(true);app._unhandled_input(gate_key_event(KEY_ENTER,true))
	check(app.session.snapshot()==frozen and not app.gate_panel._active,"Paused gate confirmation accepted input")
	app.set_user_paused(false);app._unhandled_input(gate_key_event(KEY_ESCAPE,true))
	check(app.session.status=="gate_map_required" and app.map_panel.visible and app.map_panel.snapshot().system_id==14 and app.map_panel.snapshot().route_mode=="gate","Gate refusal did not open the destination map")
	await capture_free_application("gate-destination-map")
	app._unhandled_input(gate_key_event(KEY_ESCAPE,true))
	check(app.session.can_control() and app.session.snapshot().contracts.travel_statistics.jumpgates_used==0 and not app.map_panel.visible,"Cancelling the gate map did not restore uncharged flight")
	var before_coast: Dictionary=app.session.snapshot()
	app.session.rebase_time(now_us);now_us+=100000
	if not app.session.step(now_us):check(false,app.session.error);return
	check(is_equal_approx(app.session.snapshot().input_throttle,2.0/float(definitions.cruise.speed_units_per_millisecond)) and absf(app.session.snapshot().player_pose.origin.distance_to(before_coast.player_pose.origin)-200.0)<0.1,"The first flight frame after map cancellation replaced source speed2")
	if not await choose_gate_course() or not await reach_gate_confirmation():return
	var accept:=InputEventJoypadButton.new();accept.pressed=true;accept.button_index=JOY_BUTTON_A
	app._unhandled_input(accept)
	app.session.rebase_time(now_us)
	var start: Dictionary=app.session.snapshot()
	check(start.gate_transit.speed==2.0 and not start.player.damage_allowed and not start.scenery_collision_enabled and not app.session.can_control(),"Gate cinematic retained manual control or damage permissions")
	var camera_matches:=true;var jump_visible:=false
	for tick in 90:
		if app.session.status!="running":break
		now_us+=100000
		if not app.session.step(now_us,Vector2.ONE,true):check(false,app.session.error);return
		var moving: Dictionary=app.session.snapshot()
		if moving.gate_transit.phase=="departing":camera_matches=camera_matches and moving.camera_view.eye==moving.gate_transit.camera_position and moving.camera_view.look==moving.player_pose.origin
		if moving.gate_transit.animation.objects[0].active:
			jump_visible=jump_visible or not app.session.scene.gates.objects[1].layers[2].visible
		if tick in [0,20,45]:await capture_free_application("gate-cinematic-%d"%tick)
	check(app.session.status=="gate_arrival_transition_required" and camera_matches and jump_visible,"Live gate cinematic lost its camera, original animation or arrival boundary")
	if failures:return
	var frame: RefCounted=app.session.flight_owner()
	var before: Dictionary=frame.snapshot()
	var career: RefCounted=frame._objective.retained_for_arrival(frame._encounter)
	if career==null:check(false,frame._objective.error);return
	var objective: Dictionary=frame._objective.snapshot();objective.progress=career.snapshot().progress;objective.station_response_flags=frame.station_response_flags()
	var transit: RefCounted=frame._gate_transit.fork_for_frame()
	var construction:=FlightConstruction.new()
	var completed: Dictionary=transit.snapshot()
	check(completed.phase=="ready","Native gate animation did not finish")
	var settings: Dictionary=app.BASE_STOCK_SETTINGS.duplicate(true);settings.ship_price_percent=0
	if not career.select_location(definitions,catalogue,source,70,settings,frame._random,1789100000):check(false,career.error);return
	var retained: Dictionary=career.snapshot();var equipment: Dictionary=frame._equipment.snapshot();var player: Dictionary=frame._player.snapshot()
	var bodies:=SceneryBodies.new();var effects:=SceneryEffects.new()
	if not bodies.configure(source,definitions) or not effects.configure(source,definitions):check(false,bodies.error+effects.error);return
	if not construction.prepare_gate_arrival(definitions,catalogue,transit,frame._player,frame._equipment,4096,1789100000,true,bodies,effects,objective,career):check(false,construction.error);return
	var arrived: Dictionary=construction.snapshot();var arrived_career: RefCounted=construction.contract_owner()
	check(arrived.location.station_id==70 and arrived.location.system_id==14 and arrived.campaign_cursor==18,"Prospective gate arrival lost its actual destination")
	check(arrived.departure.from_station_id==95 and arrived.departure.arrival_environment.source=="gate","Dis arrival missed the original incoming gate")
	check(arrived.departure.contracts.travel_statistics=={"jumpgates_used":1} and retained.travel_statistics=={"jumpgates_used":0},"Gate arrival failed to increment exactly once on its detached career")
	check(arrived.departure.mission==original.mission and arrived.departure.contracts.credits==7850 and arrived.departure.contracts.completed_side_missions==4,"Gate arrival changed the pending story, wallet or earned jobs")
	for key in ["mission","progress","delivery_statistics","passengers","difficulty","rank","reputation"]:
		check(arrived.departure.contracts[key]==retained[key],"Gate arrival changed retained career field: "+key)
	var moved:=equipment.duplicate(true);moved.loadout.station_id=70;moved.loadout.system_id=14
	check(construction.equipment_owner().snapshot()==moved,"Gate arrival changed inventory beyond its location")
	check(arrived.player.vitals.hull==player.vitals.hull and arrived.player.vitals.armor==player.vitals.armor and arrived.player.vitals.shield==float(int(player.vitals.shield)) and arrived.player.gamma==float(int(player.gamma)),"Gate arrival refilled or lost a current player pool")
	check(career.snapshot()==retained and frame._equipment.snapshot()==equipment and frame._player.snapshot()==player and frame.snapshot()==before and transit.snapshot()==completed,"Preparing arrival mutated a departing owner")
	var packet:=GateArrival.packet(definitions,catalogue,transit.arrival_request())
	var once: Dictionary=arrived_career.snapshot()
	check(not arrived_career.rebase_gate_arrival(definitions,catalogue,construction.equipment_owner(),packet) and arrived_career.snapshot()==once,"Replaying the same arrival incremented the career again")
	check(not construction.prepare_gate_arrival(definitions,catalogue,transit,frame._player,frame._equipment,-1,1789100000,true,bodies,effects,objective,career) and construction.snapshot()==arrived,"Failed destination construction replaced a prepared world")
	var invalid: RefCounted=career.fork();invalid._state.erase("travel_statistics")
	check(not construction.prepare_gate_arrival(definitions,catalogue,transit,frame._player,frame._equipment,4096,1789100000,true,bodies,effects,objective,invalid) and construction.snapshot()==arrived,"Missing earned history was silently initialized during travel")
	check(frame.snapshot()==before and career.snapshot()==retained and transit.snapshot()==completed,"Rejected arrival changed the live departure")
	var prospective:=FlightFrame.new()
	if not prospective.configure(definitions,catalogue,source,construction,"F",0.5,Vector2i(1280,720),false,false,"Q"):check(false,prospective.error);return
	check(prospective.snapshot().location.station_id==70 and prospective.snapshot().contracts.travel_statistics.jumpgates_used==1,"Destination frame lost its committed gate career")
	check(prospective.snapshot().mission==original.mission and prospective.snapshot().arrival_from_station_id==95 and prospective.snapshot().player_pose.origin==arrived.departure.arrival_environment.position,"Destination frame activated pending story or lost incoming placement")
	if not app.enter_gate_arrival(now_us,4096,1789100000):check(false,app.status.text);return
	check(app.session.snapshot().contracts.travel_statistics.jumpgates_used==1 and app.session.snapshot().location.station_id==70,"The destination session lost its accepted gate transaction")
	await capture_free_application("gate-arrival-dis-70")
	if not await release_application_flight() or not await dock_application():return
	var landed: Dictionary=app.session.snapshot()
	check(landed.loadout.station_id==70 and landed.loadout.system_id==14 and landed.contracts.travel_statistics.jumpgates_used==1,"Dis docking lost the earned gate journey")
	check(landed.contracts.credits==7850 and landed.mission==original.mission and landed.contracts.completed_side_missions==4 and landed.reward_credits==0,"Dis docking changed the retained story, wallet or job count")
	await capture_free_application("gate-dock-dis-70")
	print("Live gate arrival and docking: Dis70,7850credits,4jobs,pending156,jump count1")
	if failures==0:await return_gate_journey(original,origin_stock)

func gate_key_event(code: int,pressed: bool) -> InputEventKey:
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=pressed;return event

func choose_gate_course(from_system:=19,to_system:=14,destination:=70,label:="gate-course") -> bool:
	check(choose_free_keyboard_flight_action(KEY_E,"map"),"E action menu did not open the map")
	check(app.session.map_active() and app.map_panel.snapshot().system_id==from_system,"Keyboard map did not retain the current system")
	if failures:return false
	var frozen: Dictionary=app.session.snapshot()
	var system_button:=InputEventJoypadButton.new();system_button.pressed=true;system_button.button_index=JOY_BUTTON_RIGHT_SHOULDER
	app._unhandled_input(system_button)
	check(app.map_panel.snapshot().system_id==to_system and app.map_panel.snapshot().rows.map(func(row):return row.station_id)==Array(catalogue.tables.systems[to_system].station_ids),"Controller did not display the other system's original destinations")
	app.map_panel._systems.get_child(0).pressed.emit()
	check(app.map_panel.snapshot().system_id==from_system,"The original-style system button did not return to the current system")
	app.map_panel._systems.get_child(1).pressed.emit()
	check(app.map_panel.snapshot().system_id==to_system,"The original-style system button did not select the destination system")
	check(app.session.snapshot()==frozen,"Browsing another system mutated the current flight")
	app._unhandled_input(gate_key_event(KEY_RIGHT,true));app._unhandled_input(gate_key_event(KEY_ENTER,true))
	check(app.map_panel.snapshot().get("selected_station_id")==destination and app.map_panel.snapshot().get("confirmation_visible",false),"Keyboard destination skipped the map confirmation")
	await capture_free_application(label+"-desktop")
	await capture_gate_interface_mobile(label+"-mobile")
	app._unhandled_input(gate_key_event(KEY_ENTER,true))
	check(app.session.can_control() and not app.map_panel.visible and app.session.snapshot().station_autopilot.target_kind=="gate","Confirmed system course did not start native gate guidance")
	app.session.rebase_time(now_us)
	return failures==0

func return_gate_journey(original: Dictionary,origin_stock: Dictionary) -> void:
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	if not await release_application_flight() or not await choose_gate_course(14,19,95,"gate-return-course") or not await reach_gate_confirmation():return
	# The return exercises the other source dispatch: refusing the question,
	# then accepting a destination in the gate map starts departure directly.
	app._unhandled_input(gate_key_event(KEY_ESCAPE,true))
	check(app.session.status=="gate_map_required" and app.map_panel.snapshot().system_id==19,"Return gate map lost Augmenta")
	app._unhandled_input(gate_key_event(KEY_RIGHT,true));app._unhandled_input(gate_key_event(KEY_ENTER,true))
	await capture_gate_interface_mobile("gate-return-map-mobile")
	app.map_panel._yes.pressed.emit();app.session.rebase_time(now_us)
	check(app.session.snapshot().gate_transit.phase=="departing" and not app.session.snapshot().gate_transit.reset_primary_fire_intervals,"Accepted gate map used the confirmation-only weapon reset")
	for tick in 90:
		if app.session.status!="running":break
		now_us+=100000
		if not app.session.step(now_us):check(false,app.session.error);return
	check(app.session.status=="gate_arrival_transition_required","The return gate animation never completed")
	if failures or not app.enter_gate_arrival(now_us,4096,1789100000):check(false,app.status.text);return
	await capture_free_application("gate-return-arrival-95")
	if not await release_application_flight() or not await dock_application():return
	var landed: Dictionary=app.session.snapshot()
	check(landed.loadout.station_id==95 and landed.loadout.system_id==19 and landed.contracts.travel_statistics.jumpgates_used==2,"The return docking lost its location or counted another jump")
	check(landed.contracts.credits==7850 and landed.mission==original.mission and landed.contracts.completed_side_missions==4 and landed.reward_credits==0,"The gate round trip changed the wallet, story or jobs")
	check(app.session.location_owner().location(95).stock==origin_stock,"Returning through the gate regenerated cached Gome C stock")
	await capture_free_application("gate-return-dock-95")
	print("Gate application round trip: Gome C95→Dis70→Gome C95; jump count2, retained stock/career")

func reach_gate_confirmation() -> bool:
	var coasting:=false
	for tick in 1800:
		if app.session.status!="running":break
		resume_application_focus()
		now_us+=100000
		if not app.session.step(now_us):check(false,app.session.error);return false
		var frame: Dictionary=app.session.snapshot()
		if frame.player.vitals.hull<=0:
			check(false,"Gate approach was destroyed: "+str({"station":frame.location.station_id,"clock":frame.world_elapsed_ms,"vitals":frame.player.vitals,"pose":frame.player_pose.origin}))
			await capture_free_application("gate-approach-destroyed")
			return false
		coasting=coasting or frame.gate_transit.coasting
		if tick%100==0:await process_frame
	app.present_session()
	var observed: Dictionary=app.session.snapshot()
	var guide: Dictionary=observed.station_autopilot
	check(app.session.status=="gate_confirmation_required" and coasting,"Actual gate guidance did not coast into its source confirmation: "+str({"status":app.session.status,"station":observed.location.station_id,"coasting":coasting,"phase":observed.gate_transit.phase,"player":observed.player_pose.origin,"guidance":guide.player_pose.origin,"target":guide.target_position,"vitals":observed.player.vitals,"world_ms":observed.world_elapsed_ms}))
	return failures==0

func capture_gate_interface_mobile(label: String) -> void:
	root.size=Vector2i(960,540);app.set_mobile_layout(true);TouchInput.set_preference(app,true)
	for tick in 3:await process_frame
	resume_application_focus();app.present_session()
	if app.gate_panel.visible:
		check(Rect2(Vector2.ZERO,app.gate_panel.size).encloses(app.gate_panel._panel.get_rect()) and app.gate_panel._yes.size.y>=44,"Gate confirmation clips its landscape touch actions")
	if app.map_panel.visible:
		for button in [app.map_panel._yes,app.map_panel._no,app.map_panel._back]:
			check(Rect2(Vector2.ZERO,app.map_panel.size).encloses(button.get_rect()) and button.size.y>=44,"Gate destination map clips its landscape touch actions")
	await capture_free_application(label)
	root.size=Vector2i(1280,720);app.set_mobile_layout(false);app.set_touch_controls(false)
	for tick in 3:await process_frame
	resume_application_focus();app.present_session()
