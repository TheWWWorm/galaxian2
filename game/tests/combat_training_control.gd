extends "res://tests/combat_training.gd"
## Actual station/equipment prerequisite, followed by disclosed synthetic flight
## positions for source boundary checks. No campaign completion is fabricated.
const LiveTraining=preload("res://src/simulation/combat_training_control.gd")
const LiveRules=preload("res://src/content/combat_training_control_definitions.gd")
const LiveBody=preload("res://src/simulation/opening_combat_actor.gd")
const LiveGroup=preload("res://src/simulation/opening_combat_group.gd")
const LiveGuidance=preload("res://src/simulation/opening_npc_guidance.gd")
const TrainingRandom=preload("res://src/simulation/seeded_random.gd")

func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:await verify(args)
	if is_instance_valid(host):host.free()
	print("Combat-training control: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func after_second_return(args: PackedStringArray):
	await super.after_second_return(args)
	var before: Dictionary=host.session.snapshot()
	var equipment: RefCounted=host.session._world.equipment_owner()
	verify_training_control(args,equipment)
	check_training_station_retained(before,"control")

func verify_training_control(args: PackedStringArray, equipment: RefCounted):
	var cat:=Catalogues.new()
	if not cat.open(lib):check(false,cat.error);return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	if header.reader=="resource-registration-v118":check(LiveRules.parameters(bindings.combat_training_control),"Current pack omitted training control")
	if not LiveRules.parameters(bindings.combat_training_control):
		check(not LiveTraining.new().configure(bindings,cat,TrainingWorld.new(),0,.5),"Earlier pack invented live training control")
		return
	var data: Dictionary=bindings.combat_training_control
	check(LiveRules.validate(data,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.combat_training,bindings.opening_actors).is_empty(),"Training control proof refused its source context")
	for key in LiveRules.VALUES:
		var bad:=data.duplicate(true);bad[key]=null
		check(not LiveRules.parameters(bad),"Changed training control rule accepted: "+key)
	for key in LiveRules.SPANS:
		var bad:=data.duplicate(true);bad.provenance[key].offset+=1
		check(not LiveRules.validate(bad,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.combat_training,bindings.opening_actors).is_empty(),"Changed training control extent accepted: "+key)
	var world:=TrainingWorld.new()
	check(world.configure_combat_training(bindings,cat,equipment,Vector3(10,10,10000),{"companions_empty":true,"location_match":false,"special_placement":false}),world.error)
	check(not world.generate({"state":int(TRAINING_GOLDEN[0].input_state)}).is_empty(),world.error)
	var retained:=world.snapshot()
	var live:=LiveTraining.new()
	for rank in [-1,2,0.0,true]:check(not live.configure(bindings,cat,world,rank,.5) and live.snapshot().is_empty(),"Unsupported training rank constructed bodies")
	for difficulty in [-1,11,INF,NAN,"normal"]:check(not live.configure(bindings,cat,world,0,difficulty),"Unsupported training difficulty constructed bodies")
	for rank in [0,1]:
		check(live.configure(bindings,cat,world,rank,.5),live.error)
		var initial:=live.snapshot()
		check(initial.combat.actors.size()==4 and initial.random_state==retained.random_state,"Live control changed constructor population or RNG boundary")
		for id in 4:
			var body: Dictionary=initial.combat.actors[id]
			check(body.actor_kind==(3 if id==3 else 8) and body.hull_catalogue_id==(30 if id==3 else 2) and body.factory_hull==48+14*rank,"Mixed actor kind or rank-scaled factory hull changed")
			check(body.vitals.hull==(9999999 if id==3 else body.factory_hull) and body.max_hull==body.vitals.hull and body.hull_percent==100,"Gunant hull override or maximum was replaced with immunity")
			check(not body.hostile and body.friendly==(id==3) and body.active==(id==3) and body.actor_mode==(0 if id==3 else 5),"Training initial hostility, activity or mode changed")
			check(body.targeting_blocked==(id!=3) and not body.statistics_targeting_blocked and body.model_draw_enabled and body.node_draw_requested and body.engine_draw_enabled,"Independent actor/model/statistics flags were conflated")
			check(initial.guidance[id].previous_hull==body.factory_hull and initial.guidance[id].target_index==0,"Guidance lost pre-override hull sample or initial target")
	check(live.configure(bindings,cat,world,0,.5),live.error)
	var before:=live.snapshot();var player:=training_player(Vector3(10,10,10000))
	var first:=live.advance(16,player)
	check(not first.is_empty(),live.error)
	if first.is_empty():return
	check(first.decisions[3].initializing and first.decisions[3].target_kind=="route" and not first.decisions[3].travel_enabled and first.combat.actors[3].actor_mode==1,"Gunant skipped his source initialization pass")
	check(first.combat.actors[3].pose==before.combat.actors[3].pose and first.firing_requests.is_empty(),"Initialization moved or fired a ship")
	for id in 3:check(first.decisions[id].holding and first.combat.actors[id].pose==before.combat.actors[id].pose and not first.combat.actors[id].node_draw_requested,"Distant pirate moved or retained its held node request")
	var second:=live.advance(16,player)
	check(not second.is_empty(),live.error)
	if second.is_empty():return
	check(second.decisions[3].travel_enabled and second.decisions[3].target_kind=="route" and second.combat.actors[3].position!=first.combat.actors[3].position,"Gunant did not begin native route flight after initialization")
	check(absf(second.combat.actors[3].position.distance_to(first.combat.actors[3].position)-32.0)<.02,"Ordinary native speed or source milliseconds changed")
	verify_live_rollback(live,player)
	verify_activation_boundaries(cat,world)
	verify_mixed_targets(cat,world)
	verify_training_route_end(cat,world)
	verify_training_random(cat,world)
	check(world.snapshot()==retained and world.route(3).snapshot().index==0,"Live controller modified retained construction or station progress")

func training_player(position: Vector3) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"pose":Transform3D(Basis.IDENTITY,position),
		"active":true,"hull":100,"ship_id":0,"targeting_blocked":false,"special_flight":false,"alternate_position":null}

func training_seed(value: int) -> Dictionary:
	var rng:=TrainingRandom.new();rng.seed_from(value);return rng.snapshot()

func training_pair(cat: RefCounted, world: RefCounted, id: int, initial_mode: bool=false) -> Dictionary:
	var combat:=LiveGroup.new();var guidance:=LiveGuidance.new()
	check(combat.configure_combat_training(bindings,cat,world,0,.5),combat.error)
	check(guidance.configure_combat_training(bindings,cat,world,id,0,.5),guidance.error)
	for actor_id in 4:check(combat.refresh_hostility(actor_id),combat.error)
	var rows: Array=combat.snapshot().actors
	for index in 4:
		rows[index].pose=Transform3D(Basis.IDENTITY,Vector3(100000+index*10000,0,100000))
		rows[index].position=rows[index].pose.origin
	rows[id].pose=Transform3D.IDENTITY;rows[id].position=Vector3.ZERO
	if id==3 and not initial_mode:rows[id].actor_mode=1
	return {"guidance":guidance,"rows":rows,"id":id}

func training_decide(pair: Dictionary, delta: int, player: Dictionary, rng: Dictionary) -> Dictionary:
	var row: Dictionary=pair.rows[pair.id]
	return pair.guidance.update(delta,row,row.pose,player,rng,pair.rows)

func verify_activation_boundaries(cat: RefCounted, world: RefCounted):
	for axis in 3:
		for sign_value in [-1,1]:
			for distance in [24999,25000,25001,49999,50000,50001]:
				var pair:=training_pair(cat,world,0);var position:=Vector3.ZERO;position[axis]=distance*sign_value
				var result:=training_decide(pair,0,training_player(position),training_seed(4))
				check(not result.is_empty(),pair.guidance.error)
				if result.is_empty():return
				check(result.activation==("proximity" if distance<25000 else "target" if distance<50000 else "") and result.holding==(distance>=25000),"Training activation boundary changed on axis%d at%d"%[axis,distance*sign_value])
				check(result.travel_enabled==(distance<25000) and result.random_state==training_seed(4),"Holding dispatch moved on the wrong pass or consumed random draws")
	var pair:=training_pair(cat,world,0);var player:=training_player(Vector3(100000,0,100000));player.alternate_position=Vector3(0,0,20000)
	var result:=training_decide(pair,0,player,training_seed(4))
	check(result.activation=="proximity" and result.direction==Vector3(0,0,1) and not result.fire_requested,"Alternate player body did not control proximity/heading independently of firing range")
	pair=training_pair(cat,world,0);player=training_player(Vector3(0,0,30000));player.targeting_blocked=true
	result=training_decide(pair,0,player,training_seed(4))
	check(result.activation=="" and result.holding,"Target suppression failed to block longer-range activation")
	player.pose.origin.z=20000
	result=training_decide(pair,0,player,result.random_state)
	check(result.activation=="proximity" and result.travel_enabled and not result.fire_requested,"Suppression incorrectly blocked close activation or allowed firing")

func verify_mixed_targets(cat: RefCounted, world: RefCounted):
	var pair:=training_pair(cat,world,3);var player:=training_player(Vector3(0,0,1000))
	for id in 3:pair.rows[id].active=true;pair.rows[id].actor_mode=1;pair.rows[id].pose.origin=Vector3(0,0,15000+id*1000)
	var result:=training_decide(pair,0,player,training_seed(4))
	check(result.target_kind=="npc" and result.target_actor_id==0 and result.fire_requested,"Friendly Gunant did not select and aim at the first active pirate")
	check(pair.rows[0].targeting_blocked and not pair.rows[0].statistics_targeting_blocked,"Fixture must keep source E5 independent of statistics suppression")
	pair.rows[0].active=false
	result=training_decide(pair,0,player,result.random_state)
	check(result.target_actor_id==1,"Gunant retained an inactive pirate instead of the next eligible actor")
	pair.rows[1].vitals.hull=0
	result=training_decide(pair,0,player,result.random_state)
	check(result.target_actor_id==2,"Gunant selected a destroyed pirate")
	pair.rows[2].pose.origin.z=100000
	result=training_decide(pair,0,player,result.random_state)
	check(result.target_actor_id==2 and not result.fire_requested,"Nonplayer rescan incorrectly applied engagement range or bypassed firing range")
	pair.rows[2].pose.origin.z=15000;pair.rows[2].statistics_targeting_blocked=true
	result=training_decide(pair,0,player,result.random_state)
	check(not result.fire_requested and not pair.guidance.snapshot().fire_desired,"Statistics suppression failed to clear Gunant firing desire")
	pair=training_pair(cat,world,3);pair.rows[0].active=true;pair.rows[0].actor_mode=1
	for distance in [34999,35000,35001]:
		pair.rows[0].pose.origin=Vector3(0,0,distance)
		result=training_decide(pair,0,player,training_seed(4))
		check(result.fire_requested==(distance<35000),"Gunant firing box changed its strict boundary")
	# Special player flight must not enlarge the near box for an NPC target.
	pair.rows[0].pose.origin=Vector3(1000,0,10000);player.special_flight=true
	result=training_decide(pair,0,player,training_seed(4))
	check(not result.close_heading_preserved and result.direction.x>0,"Player special flight changed NPC-target close steering")

func verify_training_route_end(cat: RefCounted, world: RefCounted):
	var pair:=training_pair(cat,world,3);var player:=training_player(Vector3(0,0,-1000))
	var first:=Vector3(-4000,-3000,80000);var last:=Vector3(10000,7000,160000)
	var result:=training_decide(pair,0,player,training_seed(4))
	check(result.target_kind=="route" and pair.guidance.snapshot().desired_position==first,"Gunant lost his authored initial destination")
	pair.rows[3].pose.origin=first
	result=training_decide(pair,0,player,result.random_state)
	check(result.target_kind=="route" and pair.guidance.snapshot().route.index==1 and pair.guidance.snapshot().desired_position==last,"Gunant failed to advance the authored route")
	pair.rows[3].pose.origin=last-Vector3(0,0,1000)
	result=training_decide(pair,0,player,result.random_state)
	check(result.target_kind=="retained_position" and pair.guidance.snapshot().route.completed and pair.guidance.snapshot().desired_position==last and not result.fire_requested,"Final route advance lost its one-pass retained destination")
	result=training_decide(pair,0,player,result.random_state)
	check(result.target_kind=="player" and pair.guidance.snapshot().desired_position==player.pose.origin and pair.guidance.snapshot().route.index==2 and not result.fire_requested,"Exhausted route restarted or lost target-zero fallback")

func verify_training_random(cat: RefCounted, world: RefCounted):
	var pair:=training_pair(cat,world,0);var player:=training_player(Vector3(0,0,30000))
	pair.rows[3].pose.origin=Vector3(0,0,20000)
	var result:=training_decide(pair,5001,player,training_seed(17))
	check(result.random_state.state==196292338532073 and pair.guidance.snapshot().fire_desired and result.activation=="target","Mixed refresh did not consume the independently verified target-choice draws")
	# Holding replaces the selected pointer with player0; an active pirate keeps Gunant.
	pair=training_pair(cat,world,0);pair.rows[0].active=true;pair.rows[0].actor_mode=1;pair.rows[3].pose.origin=Vector3(0,0,20000)
	result=training_decide(pair,5001,player,training_seed(17))
	check(result.target_kind=="npc" and result.target_actor_id==3 and result.fire_requested,"Active pirate failed to target Gunant on the verified random branch")
	pair=training_pair(cat,world,0);pair.rows[3].active=false;player.active=false
	result=training_decide(pair,5001,player,training_seed(17))
	check(result.random_state.state==229750132535677 and not pair.guidance.snapshot().fire_desired,"Failed random selection did not consume exactly five candidate attempts")
	pair=training_pair(cat,world,3);player=training_player(Vector3(0,0,-1000))
	result=training_decide(pair,5001,player,training_seed(4))
	check(result.random_state.state==258595003278714 and not pair.guidance.snapshot().boost_active and result.speed==2.0,"Gunant's zero chance skipped the source roll or activated a random boost")

func verify_live_rollback(live: RefCounted, player: Dictionary):
	var before: Dictionary=live.snapshot()
	for delta in [-1,0.5,true,2147483647]:check(live.advance(delta,player).is_empty() and live.snapshot()==before,"Invalid frame partially committed training actors or RNG")
	for key in ["ship_id","active","hull","targeting_blocked","alternate_position"]:
		var bad:=player.duplicate(true);bad[key]=null
		if key=="alternate_position":bad[key]=Vector3(INF,0,0)
		check(live.advance(16,bad).is_empty() and live.snapshot()==before,"Invalid player partially committed a four-actor frame")
	var combat: RefCounted=live.combat_owner();var snapshot: Dictionary=combat.snapshot()
	check(not combat.normal_hit(3,1).is_empty(),combat.error)
	check(live.snapshot()==before and combat.snapshot()!=snapshot,"Detached hit escaped into live control")
	check(not live.advance(16,player,combat).is_empty() and live.snapshot().combat.actors[3].vitals.hull==9999998,"Finite Gunant damage did not survive a candidate frame")
	before=live.snapshot();combat=live.combat_owner()
	check(not combat.normal_hit(3,9999999).is_empty(),combat.error)
	check(live.advance(16,player,combat).is_empty() and live.snapshot()==before,"Unsupported destruction committed an invented lifecycle")
	var detached: RefCounted=live.fork_for_frame()
	check(not detached.advance(16,player).is_empty() and live.snapshot()==before,"Detached motion changed the live control owner")
