extends "res://tests/convoy_flight.gd"
## Actual earned contract career -> convoy -> original Alioth station conversation.
const Alioth=preload("res://src/content/alioth_arrival_definitions.gd")
const StationView=preload("res://src/content/station_presentation_definitions.gd")
const AliothStation=preload("res://src/simulation/station_entry.gd")
const AliothScene=preload("res://src/presentation/station_session.gd")
const AliothPanel=preload("res://src/presentation/station_dialogue_panel.gd")
const Navigation=preload("res://src/content/base_contract_navigation_definitions.gd")

func after_convoy(frame: RefCounted,live: Node3D) -> void:
	if failures:return
	check(Alioth.available(definitions),"The original Alioth arrival declarations are absent")
	if failures:return
	var rules: Dictionary=definitions.mido_travel.alioth_arrival
	var before: Dictionary=frame.snapshot()
	var original_career: Dictionary=frame.convoy_career_owner().snapshot()
	var stock_settings: Dictionary={}
	if Navigation.available(definitions):
		stock_settings={"difficulty":0.5,"valkyrie_owned":false,"supernova_owned":false,"energy_availability_percent":0,"missile_availability_percent":0,"ship_price_percent":0}
	var packet: Dictionary=frame.prepare_convoy_station()
	check(not packet.is_empty() and packet.player_cache==before.player_cache,"Capture replaced the retained entry cache with live damage")
	var too_early: RefCounted=frame.fork_for_frame()
	too_early._convoy._state.phase=Capture.Stage.DISABLED
	# The owner must accept only its terminal stage, even if the old packet exists.
	check(too_early.prepare_convoy_station().is_empty(),"A nonterminal capture prepared a station")
	var station:=AliothStation.new()
	if not stock_settings.is_empty():
		var invalid:=stock_settings.duplicate(true);invalid.ship_price_percent=null
		check(not station.configure_return(definitions,catalogue,source,frame,invalid,1789423200) and station.snapshot().is_empty() and frame.snapshot()==before,"Failed Alioth generation changed the accepted career")
	if not station.configure_return(definitions,catalogue,source,frame,stock_settings,1789423200):check(false,station.error);return
	var arrived: Dictionary=station.snapshot()
	check(arrived.campaign_cursor==15 and arrived.phase=="conversation" and arrived.loadout.station_id==98 and arrived.loadout.system_id==19,"Capture did not reach actual Alioth")
	check(arrived.mission=={"kind":11,"station_id":98,"reward":0,"bonus":0,"source_parameter":0},"Capture invented a mission or reward")
	for key in ["ship_id","slots","equipment_ids"]:check(arrived.loadout[key]==before.equipment.loadout[key],"Alioth replaced earned equipment: "+key)
	check(arrived.cargo==before.cargo and arrived.equipment.prices==before.equipment.prices,"Capture repriced or removed cargo")
	check(arrived.player_cache.values==before.player_cache.values,"Alioth did not retain the source entry cache")
	for key in ["credits","completed_side_missions","passengers","mission","active_offer_id"]:check(arrived.contracts[key]==original_career[key],"Alioth changed the independent career: "+key)
	for key in ["player_kills","pirate_kills","capital_ship_kills","debris_destroyed","other_score","reputation"]:check(arrived.progress.get(key)==before.progress.get(key),"Alioth lost a flight counter: "+key)
	check(frame.snapshot()==before,"Preparing Alioth modified the committed capture")
	if not stock_settings.is_empty():
		var old_cache: Dictionary=original_career.lounges
		var new_cache: Dictionary=arrived.contracts.lounges
		var actual_location: Dictionary=station.contract_owner().location_owner().location(98)
		check(new_cache.locations.slice(0,-1)==old_cache.locations.slice(-2) and new_cache.current_station_id==98,"Alioth did not preserve the source FIFO location history")
		check(actual_location.stock.context.station_id==98 and actual_location.population.context.station_id==98,"The live captured station lost its stock or contacts")
		check(actual_location.population.initial_history==old_cache.history and actual_location.stock.random==actual_location.population.initial_random,"Alioth's actual arrival skipped stock or mission-type history")
		check(not arrived.contracts.get("location_generation_pending",false),"Alioth retained a pending-generation flag after success")
	var saved: Dictionary=definitions.mido_travel
	definitions.mido_travel=saved.duplicate(true);definitions.mido_travel.erase("alioth_arrival")
	check(not station.configure_return(definitions,catalogue,source,frame) and station.snapshot()==arrived,"Missing Alioth capability changed an accepted station")
	check(StationView.select(definitions,98,15).is_empty(),"Older packs inferred Alioth presentation")
	definitions.mido_travel=saved
	var view:=StationView.select(definitions,98,15)
	check(view.hangar_row==0 and view.camera.position==[1076,900,-2273] and view.light.ambient==[.25,.25,.25],"Alioth reused the Mido station camera or light")
	check(StationView.select(definitions,98,13).is_empty(),"Alioth appeared at an unsupported story cursor")
	for language in source.manifest.languages:
		if not source.select_language(language):check(false,source.error);return
		var localized:=AliothStation.new()
		if not localized.configure_return(definitions,catalogue,source,frame,stock_settings,1789423200):check(false,localized.error);return
		for index in rules.events.size():
			var line: Dictionary=localized.snapshot().dialogue
			check(line.text_id==int(rules.events[index].text_id) and line.text==source.strings[line.text_id] and localized.snapshot().campaign_cursor==15,"Alioth language/order changed before acknowledgement: "+language)
			if not localized.acknowledge():check(false,localized.error);return
		check(localized.snapshot().campaign_cursor==16 and not localized.snapshot().dialogue.visible,"Alioth final acknowledgement did not select the next mission")
	if not source.select_language("gb"):check(false,source.error);return
	var scene:=AliothScene.new();root.add_child(scene)
	if not scene.configure_return(source,definitions,visual,frame,now_us,791,stock_settings,1789423200):check(false,scene.error);scene.free();return
	var panel:=AliothPanel.new();root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not panel.configure_station_return(source,definitions,visual,15):check(false,panel.error);scene.free();panel.free();return
	check(scene.audio.snapshot().history.is_empty() and not scene.snapshot().conversation_started,"Alioth spoke before activation")
	live.hide()
	if not scene.activate():check(false,scene.error);scene.free();panel.free();return
	for tick in 11:
		now_us+=100000
		if not scene.step(now_us):check(false,scene.error);return
	if not panel.present(scene.snapshot()):check(false,panel.error);return
	check(panel.size==Vector2(root.size) and panel._body.text==source.strings[1800] and panel._portrait.texture!=null,"Alioth dialogue is not visible in its full viewport")
	check(panel._art!=null and panel.get_theme_font("font")==panel._art.font and panel._panel.get_theme_stylebox("panel").has_meta("source_image_ids"),"Alioth omitted the original interface artwork")
	check(scene.snapshot().conversation_started and scene.audio.snapshot().history[0].source_id==224,"Alioth omitted its source entry delay or recording")
	var paused: Dictionary=scene.snapshot()
	check(scene.set_pause("user",true,now_us),scene.error)
	check(scene.step(now_us+1000000) and scene.snapshot()==paused,"Pausing Alioth changed its camera or story")
	check(scene.set_pause("user",false,now_us+1000000),scene.error);now_us+=1000000
	await capture_view("alioth-arrival-desktop")
	root.size=Vector2i(960,540);panel.set_mobile_layout(true)
	if not panel.present(scene.snapshot()):check(false,panel.error);return
	await capture_view("alioth-arrival-phone-landscape")
	root.size=Vector2i(1280,720);panel.set_mobile_layout(false)
	for index in rules.events.size():
		check(scene.snapshot().dialogue.index==index and scene.snapshot().campaign_cursor==15,"Alioth skipped an acknowledged line")
		if index==1:
			await capture_view("alioth-character-desktop")
			root.size=Vector2i(960,540);panel.set_mobile_layout(true)
			await capture_view("alioth-character-phone-landscape")
			root.size=Vector2i(1280,720);panel.set_mobile_layout(false)
		if not scene.navigate("next",panel):check(false,scene.error);return
	var complete: Dictionary=scene.snapshot()
	check(complete.campaign_cursor==16 and complete.boundary=="alioth_departure_required" and complete.mission=={"kind":4,"station_id":98,"reward":0,"bonus":0,"source_parameter":0},"Alioth acknowledgement fabricated the next encounter")
	check(complete.contracts.credits==original_career.credits and complete.contracts.completed_side_missions==original_career.completed_side_missions and complete.cargo==before.cargo,"Alioth conversation awarded credits or removed earned cargo")
	if not stock_settings.is_empty():
		check(scene.location_owner().snapshot()==complete.contracts.lounges and complete.contracts.lounges==arrived.contracts.lounges,"Alioth's final acknowledgement replaced its generated location")
	check(scene.audio.snapshot().history.map(func(event):return event.source_id)==rules.events.map(func(event):return int(event.voice_event_id)),"Alioth played the wrong original recordings")
	check(not scene.navigate("next",panel) and scene.snapshot()==complete,"Repeated acknowledgement advanced Alioth twice")
	check(scene.prepare_departure(definitions,catalogue).is_empty(),"An unsupported Alioth encounter was fabricated")
	check(frame.snapshot()==before,"Alioth scene mutated the accepted convoy frame")
	print("Original Alioth arrival:11 acknowledged lines, retained ",complete.contracts.credits," credits; next cursor16")
	panel.free();scene.free();live.show()
