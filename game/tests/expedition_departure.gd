extends "res://tests/expedition_application.gd"
## Resume an earned expedition station and launch its ordinary local flight.
const DepartureProjectiles=preload("res://src/simulation/projectile_visual_state.gd")
const DepartureContracts=preload("res://src/content/contract_world_definitions.gd")
const DepartureFlight=preload("res://src/content/ordinary_flight_definitions.gd")
const DepartureStory=preload("res://src/content/story_encounter_definitions.gd")

func verify_free_application() -> void:
	var landed: Dictionary=app.session.station_owner().snapshot()
	var cursor: int=landed.campaign_cursor
	var label: String="Thynome" if cursor==28 else "Dima"
	var expected_mission: Dictionary={"kind":4,"station_id":91,"reward":0,"bonus":0,"source_parameter":0} if cursor==28 else {"kind":11,"station_id":98,"reward":30000,"bonus":0,"source_parameter":0}
	check((cursor==28 and landed.loadout.station_id==10 or cursor==31 and landed.loadout.station_id==91) and landed.mission==expected_mission,"Resume an earned acknowledged Thynome28 or Dima31 station")
	check(landed.contracts.passengers==3 and landed.cargo.used>0 and landed.contracts.credits>=0,"The earned expedition station lacks its retained passengers, cargo or wallet")
	if failures:return
	app.show();app.present_session();await process_frame;resume_application_focus()
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	if not await release_application_flight():return
	var departed: Dictionary=app.session.snapshot()
	check(departed.campaign_cursor==cursor and departed.location.station_id==landed.loadout.station_id and departed.mission==landed.mission and not departed.has("void_portal") and not departed.has("void_probe"),"Ordinary expedition departure selected an authored cast or changed its pending story")
	check(departed.progress==landed.progress and departed.cargo==landed.cargo and departed.contracts.credits==landed.contracts.credits and departed.contracts.mission==landed.contracts.mission and departed.contracts.passengers==landed.contracts.passengers and departed.contracts.travel_statistics==landed.contracts.travel_statistics,"Ordinary departure lost earned progress, cargo, wallet, job or travel history")
	if failures:return
	var combat: Dictionary=departed.encounter.combat
	check(DepartureFlight.combat_population(definitions,combat) and not DepartureStory.combat_population(definitions,combat),"Expedition ordinary departure did not retain its verified generated population")
	var visuals: Dictionary=departed.encounter.projectile_visuals
	var impacts: Dictionary=departed.encounter.impact_visuals
	var weapons: Array=departed.encounter.weapons.actors
	var armed:=0
	for actor in weapons:
		if actor.projectiles.is_empty():continue
		armed+=1
		var key: String="npc:%d"%int(actor.actor_id)
		var weapon: Dictionary=actor.projectiles.weapon
		var faction: Array=definitions.early_contracts.ship_combat.weapons.factions.filter(func(row):return int(row.item_id)==int(weapon.item_id) and int(row.kind)==int(weapon.kind))
		check(faction.size()==1,"Ordinary NPC weapon is absent from its source faction rows")
		if faction.size()!=1:continue
		var shot: Array=visuals.models.filter(func(row):return row.key==key)
		var hit: Array=impacts.weapons.filter(func(row):return row.key==key)
		check(shot.size()==1 and hit.size()==1,"Armed ordinary NPC lacks projectile and impact effects")
		if shot.size()!=1 or hit.size()!=1:continue
		check(shot[0].model_id==int(faction[0].model_resource_id) and hit[0].model_id==DepartureContracts.impact_model(definitions,int(weapon.item_id)),"Ordinary NPC effects differ from the original faction resources")
	check(armed>0 and visuals.models.size()==impacts.weapons.size() and visuals.models.size()>=armed,"Expedition departure generated no ordinary projectile/effect population")
	var audio: Node3D=app.session.flight_audio
	check(audio!=null and audio._local_radio_rules==definitions.mido_travel.traffic_combat.radio and audio._travel_sounds==[int(definitions.mido_travel.travel.acquisition_sound_id),int(definitions.mido_travel.travel.launch_sound_id)] and audio._radio_identity.get("campaign_cursor")==cursor,"Ordinary expedition radio or travel audio was replaced with authored sound")
	check(departed.has("radio") and departed.has("local_travel") and audio.snapshot().unsupported.is_empty(),"Ordinary radio/travel owners or supported audio are missing")
	verify_selected_mapping_guards()
	await capture_free_application("earned-"+label.to_lower()+"-ordinary-departure")
	print("Earned ",label,cursor," station -> ordinary departure retains career and uses faction projectile, impact and radio/travel audio")

func verify_selected_mapping_guards() -> void:
	var void_weapon: Dictionary=definitions.mido_travel.sahi_encounter.weapons["void"]
	var weapon:={"campaign_cursor":28,"item_id":int(void_weapon.item_id),"category":0,"kind":int(void_weapon.kind),"projectile_capacity":int(definitions.early_contracts.ship_combat.weapons.capacity),"nonplayer_source":true}
	for impact in [false,true]:
		var model_id: int=int(void_weapon.impact_model_id if impact else void_weapon.model_resource_id)
		check(DepartureProjectiles.model_mapping(definitions,weapon,"npc:0",impact)=={"id":model_id,"resource":definitions.resolve(model_id,"mesh"),"captured_up":false},"Selected Dima fighter lost its exact Void model")
		check(DepartureProjectiles.model_mapping(definitions,weapon,"npc:5",impact).is_empty(),"Absent Dima fighter gained a Void effect")
		for cursor in [25,26,29]:
			weapon.campaign_cursor=cursor
			var ordinary:=weapon.duplicate();ordinary.item_id=0
			check(DepartureProjectiles.model_mapping(definitions,ordinary,"npc:0",impact).is_empty(),"Post-Sahi selected cast accepted an ordinary faction weapon")
		weapon.campaign_cursor=28
