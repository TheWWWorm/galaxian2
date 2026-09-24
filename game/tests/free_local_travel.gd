extends "res://tests/free_application.gd"
## Earned18 application travel. Navigation and docking use ordinary controls;
## the checkpoint records the preceding tutorial and campaign test path.
const ArrivalEnvironment=preload("res://src/simulation/local_arrival_environment.gd")
const ArrivalRules=preload("res://src/content/local_arrival_environment_definitions.gd")

func verify_free_application() -> void:
	var original: Dictionary=app.session.station_owner().snapshot()
	print("Retained ordinary career: ",original.progress)
	if not ArrivalRules.available(definitions):
		check(not load("res://src/content/mido_travel_definitions.gd").free_local_navigation(definitions.mido_travel,18),"Earlier bindings exposed unfinished ordinary travel")
		return
	var initial_stock: Dictionary=app.session.location_owner().location(98).stock
	var mission_markers:=[]
	for mission in [original.mission,original.contracts.mission]:
		var destination: int=mission.get("station_id",-1)
		if catalogue.tables.systems[19].station_ids.has(destination) and not mission_markers.has(destination):mission_markers.append(destination)
	mission_markers.sort()
	app.show();app.present_session();await process_frame;resume_application_focus()
	for destination in local_destinations():
		var mobile: bool=destination==96
		root.size=Vector2i(960,540) if mobile else Vector2i(1280,720)
		app.set_mobile_layout(mobile);TouchInput.set_preference(app,mobile)
		if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
		if not await release_application_flight():return
		check(app.touch_overlay.visible==mobile and app._pause_button.visible==mobile,"Ordinary local travel ignored the touch-controls preference")
		var unready: RefCounted=app.session.flight_owner()
		var unready_state: Dictionary=unready.snapshot()
		check(unready.construct_local_arrival(definitions,catalogue,4096,1789100000)==null and unready.snapshot()==unready_state,"Arrival bypassed actual planet acquisition and flight")
		if not app.open_map():check(false,app.status.text);return
		var map: Dictionary=app.map_panel.snapshot()
		check(map.system_id==19 and map.rows.map(func(row):return row.station_id)==[95,96,97,98,99],"Augmenta map lost its actual station membership")
		check(map.rows.filter(func(row):return row.supported).size()==4 and map.rows.filter(func(row):return row.mission_target).map(func(row):return row.station_id)==mission_markers,"Ordinary map disabled travel or changed its retained story/contract markers")
		app.map_panel.select_station(destination);app.map_panel.request_confirmation()
		await capture_free_application("free-local-map-%d"%destination)
		if not app.close_map(now_us):check(false,app.status.text);return
		if not await acquire_application_planet(destination):return
		var departing: Dictionary=app.session.snapshot()
		var old_frame: RefCounted=app.session.flight_owner()
		var old_state: Dictionary=old_frame.snapshot()
		if not app.enter_local_arrival(now_us,4096,1789100000):check(false,app.status.text);return
		var arrived: Dictionary=app.session.snapshot()
		check(old_frame.snapshot()==old_state,"Preparing arrival mutated the departing flight")
		check(arrived.arrival_from_station_id==departing.location.station_id,"Local arrival lost its actual origin")
		check(arrived.campaign_cursor==18 and arrived.location.station_id==destination and arrived.location.system_id==19,"Ordinary arrival changed its location or campaign")
		check(arrived.mission==original.mission and arrived.contracts.mission==departing.contracts.mission and arrived.contracts.credits==original.contracts.credits and arrived.contracts.completed_side_missions==4,"Local travel changed the story, wallet or earned job count")
		check(arrived.cargo==departing.cargo and arrived.player.equipment_ids==departing.player.equipment_ids and arrived.player.ship_id==departing.player.ship_id,"Local arrival changed cargo or the equipped ship")
		check(arrived.player.vitals.hull==departing.player.vitals.hull and arrived.player.vitals.armor==departing.player.vitals.armor and arrived.player.vitals.shield==float(int(departing.player.vitals.shield)),"Local arrival replaced current player pools")
		check(arrived.player.gamma==float(int(departing.player.gamma)),"Local arrival lost the retained gamma value")
		check(arrived.contracts.progress==arrived.progress,"Local arrival lost the live career")
		check(arrived.progress.capital_ship_kills==departing.progress.capital_ship_kills,"Local travel dropped a retained convoy statistic")
		var environment:=ArrivalEnvironment.new()
		if not environment.configure(definitions,catalogue,destination,app.session.flight_owner().contract_owner().location_owner()):check(false,environment.error);return
		check(arrived.player_pose.origin==environment.snapshot().position,"Application arrival missed its generated gate or cached-planet position")
		check((destination==95 and environment.snapshot().source=="gate") or (destination!=95 and environment.snapshot().source=="cached_planet"),"The journey did not exercise both source arrival paths")
		if destination!=95:check(arrived.player_pose.basis.z.dot(-arrived.player_pose.origin.normalized())>0.99999,"Ordinary planet arrival did not face the origin")
		await capture_free_application("free-local-arrival-%d"%destination)
		if not await release_application_flight() or not await dock_application():return
		var landed: Dictionary=app.session.snapshot()
		check(landed.phase=="free_play_required" and landed.campaign_cursor==18 and landed.loadout.station_id==destination and not landed.dialogue.visible and landed.reward_credits==0,"Ordinary destination docking invented dialogue, progress or a reward")
		check(landed.cargo==arrived.cargo and landed.contracts.credits==original.contracts.credits and landed.mission==original.mission and landed.equipment.ship_affiliation==0,"Docking changed retained inventory, affiliation, credits or pending story")
		check(app.session.geometry.definition.row==0,"Augmenta dock used another faction's hangar")
		await capture_free_application("free-local-dock-%d"%destination)
		print("Ordinary application arrived and docked at%d; retained%d credits"%[destination,landed.contracts.credits])
		if failures:return
	await after_local_journeys(original,initial_stock)

func local_destinations() -> Array:return [95,96,98]

func after_local_journeys(_original: Dictionary,initial_stock: Dictionary) -> void:
	check(app.session.location_owner().location(98).stock==initial_stock,"Returning to cached Alioth regenerated its stock")
	check(app.session.location_owner().snapshot().locations.map(func(row):return row.station_id)==[98,95,96],"The round trip reordered a FIFO cache hit")
