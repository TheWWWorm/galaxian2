extends "res://tests/mido_ambient_construction.gd"
## Uses the earned equipment fixture and source-generated population. Combat
## cases explicitly place actors/shots and supply reputation; no live departure
## or freighter destruction is implied by these component checks.
const Group=preload("res://src/simulation/opening_combat_group.gd")
const Actor=preload("res://src/simulation/opening_combat_actor.gd")
const Contacts=preload("res://src/simulation/ordinary_npc_contacts.gd")
const Shots=preload("res://src/simulation/ordinary_projectiles.gd")
const Resolver=preload("res://src/simulation/weapon_loadout.gd")
const HitGeometry=preload("res://src/simulation/ordinary_hit_geometry.gd")
const Reputation=preload("res://src/simulation/faction_reputation.gd")
const REPUTATION={"axes":[30,-6],"override":-1}
var tested_contacts:=false

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Mido ambient combat: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_population(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,construction: RefCounted) -> void:
	if bindings.ambient_combat.is_empty():
		check(not Group.new().configure_ambient(bindings,catalogues,construction,0,0.5,equipment,REPUTATION),"Earlier pack invented mixed-traffic combat");return
	var packet: Dictionary=construction.snapshot()
	for vector in [[0,0.5,64,320],[1,0.5,78,390],[2,0.5,92,460],[0,1.0,96,480],[1,1.0,117,585],[2,1.0,138,690]]:
		var group:=fresh(bindings,catalogues,equipment,construction,vector[0],vector[1])
		if group==null:return
		var state: Dictionary=group.snapshot()
		check(state.campaign_cursor==11 and state.provocation.station_id==79 and state.current_reputation==REPUTATION,"Mixed combat lost its location or retained reputation")
		for row in packet.actors:
			var actor: Dictionary=state.actors[row.actor_id]
			var freight: bool=row.population_group=="freighter"
			check(actor.max_hull==vector[3 if freight else 2] and actor.vitals.hull==actor.max_hull and actor.hull_percent==100,"Independent rank/difficulty hull vector changed")
			var parked: bool=not bindings.ambient_lifecycle.is_empty() and row.population_group=="travel"
			check(actor.vitals.armor==0 and actor.vitals.shield==0.0 and actor.active!=parked and actor.actor_mode==(4 if parked else 0),"Ambient actor invented armor/shields or changed initial activity")
			check(actor.position==row.statistics_pose.origin and actor.pose==row.statistics_pose and actor.body_pose==row.body_pose,"Combat changed the generated actor pose")
			check(group.collision_context(row.actor_id).path==("point_geometry" if freight else "bounds"),"A freighter borrowed fighter bounds")
		check(construction.snapshot()==packet,"Combat mutated the construction stream")
	for invalid in [[-1,0.5],[3,0.5],[true,0.5],[0,1.5],[0,NAN]]:
		check(not Group.new().configure_ambient(bindings,catalogues,construction,invalid[0],invalid[1],equipment,REPUTATION),"Ambient combat accepted an unsupported rank/difficulty")
	var body:=Actor.new()
	if not body.configure_ambient(bindings,catalogues,construction,0,0,0.5):check(false,body.error);return
	var before:=body.snapshot()
	check(body.normal_hit(1).is_empty() and body.snapshot()==before,"An unconnected ambient body bypassed faction reactions")
	check(not Group.new().configure_ambient(bindings,catalogues,construction,0,0.5,equipment,{}),"Ambient combat invented retained reputation")
	if tested_contacts:return
	var freighter:=-1
	for row in packet.actors:
		if row.population_group=="freighter":freighter=row.actor_id;break
	if freighter<0:return
	tested_contacts=true
	verify_reactions(bindings,catalogues,equipment,construction,freighter)
	verify_contacts(bindings,catalogues,equipment,construction,freighter)

func fresh(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,construction: RefCounted,rank:=0,difficulty:=0.5,reputation: Dictionary=REPUTATION) -> RefCounted:
	var group:=Group.new()
	if not group.configure_ambient(bindings,catalogues,construction,rank,difficulty,equipment,reputation):check(false,group.error);return null
	if not group.begin_contact_pass(construction.snapshot().random_state,true):check(false,group.error);return null
	return group

func damage(group: RefCounted,id: int,amount: int,npc:=false) -> Dictionary:
	var result: Dictionary=group.normal_hit(id,amount,npc)
	check(not result.is_empty(),group.error)
	return result

func verify_reactions(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,construction: RefCounted,id: int) -> void:
	var group:=fresh(bindings,catalogues,equipment,construction)
	if group==null:return
	var random:=Random.new();random.restore(group.contact_random_state())
	damage(group,id,105)
	check(not group.snapshot().provocation.warning_issued and group.contact_random_state()==random.snapshot(),"Freighter warned below its 320-hull threshold")
	var warning:=damage(group,id,1);var selection:=random.next_int(3)
	check(warning.reactions.size()==1 and warning.reactions[0].text_id==415+selection and warning.reactions[0].voice_event_id==645+selection,"Freighter warning changed original text/voice or random order")
	damage(group,id,54)
	check(not group.snapshot().provocation.forced_hostile[id],"Exact half freighter hull triggered strict retaliation")
	damage(group,id,1)
	check(group.snapshot().provocation.forced_hostile[id] and not group.snapshot().actors[id].hostile,"Freighter retaliation lost deferred hostility refresh")
	check(group.refresh_hostility(id) and group.snapshot().actors[id].hostile,group.error)
	damage(group,id,50)
	check(not group.snapshot().provocation.response_issued,"Freighter triggered faction response below 0.66 hull")
	var response:=damage(group,id,1);selection=random.next_int(3)
	check(response.reactions.size()==1 and response.reactions[0].text_id==418+selection,"Freighter failed to request the source station response")
	check(group.snapshot().provocation.forced_hostile.all(func(value):return value) and group.snapshot().provocation.station_response_flag,"Freighter attack omitted patrol/travel/freighter faction allies or station consequences")
	check(group.contact_random_state()==random.snapshot(),"Freighter reactions consumed extra randomness")
	var before: Dictionary=group.snapshot();var copy: RefCounted=group.fork_for_frame()
	check(damage(copy,id,108).destroyed_now and copy.current_reputation().axes==[30,-1],"Freighter lethal did not record exactly one original +5 faction change")
	check(group.snapshot()==before,"Prospective freighter lethal damaged committed state")
	var dead: Dictionary=copy.snapshot()
	check(not damage(copy,id,1).accepted and copy.snapshot()==dead,"Repeated dead freighter hit repeated career consequences")
	var history:=Reputation.new()
	check(history.restore(bindings,dead.reputation) and history.snapshot()==dead.reputation,history.error)
	check(not copy.apply_destruction(id,{}) and copy.snapshot()==dead,"Freighter borrowed the small-ship breakup lifecycle")
	var npc:=fresh(bindings,catalogues,equipment,construction)
	check(damage(npc,id,320,true).destroyed_now and npc.current_reputation()==REPUTATION and npc.snapshot().actors[id].nonplayer_kill,"Nonplayer freighter lethal changed player reputation or lost attribution")
	check(npc.snapshot().provocation.requested_damage.all(func(value):return value==0),"NPC fire provoked a player crime")
	var hostile:=fresh(bindings,catalogues,equipment,construction,0,0.5,{"axes":[30,71],"override":-1})
	hostile.refresh_hostility(id);damage(hostile,id,212)
	check(not hostile.snapshot().provocation.warning_issued and not hostile.snapshot().provocation.station_response_flag,"Hostile freighter issued a friendly warning")
	var held: Dictionary=group.snapshot()
	check(group.normal_hit(id,-1).is_empty() and group.snapshot()==held,"Invalid damage partly committed freighter reactions")

func verify_contacts(bindings: RefCounted,catalogues: RefCounted,equipment: RefCounted,construction: RefCounted,id: int) -> void:
	var group:=fresh(bindings,catalogues,equipment,construction)
	if group==null:return
	var pose:=Transform3D(Basis(Vector3.UP,PI/2),Vector3.ZERO)
	check(group.set_pose(id,pose,pose),group.error)
	var resolver:=Resolver.new()
	if not resolver.configure(bindings,catalogues,catalogues.content_id):check(false,resolver.error);return
	var weapon:=resolver.resolve(0,[])
	if weapon.is_empty():check(false,resolver.error);return
	# This detached contact fixture supplies the generated encounter identity,
	# just as the primary-weapon owner does when preparing its shot records.
	weapon.campaign_cursor=int(construction.snapshot().campaign_cursor)
	var operation:=Contacts.new()
	# Original world-axis union, including the first of two overlapping boxes.
	for vector in [[Vector3(2249.5,-14,-98),true,1],[Vector3(2250,-14,-98),false,-1],
		[Vector3(-2250,-14,-98),false,-1],[Vector3(0,688.5,-98),false,-1],
		[Vector3(0,-716.5,-98),false,-1],[Vector3(0,-14,-4528),false,-1],
		[Vector3(0,-14,-4527.5),true,1],[Vector3(0,-199,5328),false,-1],
		[Vector3(0,-199,5327.5),true,0],[Vector3(0,-14,4200),true,0],
		[Vector3(0,900,0),false,-1]]:
		var shots:=shot(weapon,vector[0])
		if shots==null:return
		var before_group: Dictionary=group.snapshot();var before_shots: Dictionary=shots.snapshot()
		var result:=operation.evaluate(shots,group,[id],{"mode":"fixed","half_extent":300000})
		if result.is_empty():check(false,operation.error);return
		check(result.contacts.size()==(1 if vector[1] else 0),"Freighter collision face/union changed at "+str(vector[0]))
		if vector[1]:
			check(result.contacts[0].geometry.path=="point_geometry" and result.contacts[0].geometry.sample_position==vector[0] and result.contacts[0].geometry.box_index==vector[2],"Freighter point was shifted, rotated or selected the wrong box")
			check(result.combat.snapshot().actors[id].point_box_index==vector[2],"Successful contact lost its selected source box")
		else:check(result.combat.snapshot()==before_group and result.projectiles.snapshot()==before_shots,"Negative point result fell back to a weapon cube")
		check(group.snapshot()==before_group and shots.snapshot()==before_shots,"Contact preview mutated committed combat/projectiles")
	var shots:=shot(weapon,Vector3(0,-14,4200))
	var repeated:=operation.evaluate(shots,group,[id,id])
	check(not repeated.is_empty() and repeated.contacts.size()==2,"Repeated target reference was deduplicated")
	if repeated.is_empty():return
	check(repeated.combat.snapshot().actors[id].vitals.hull==320-2*int(weapon.ordinary_hit_policy.nonplayer_damage),"Repeated point contacts lost ordinary damage")
	check(repeated.projectiles.snapshot().slots[0].remaining_ms==-1000000,"Freighter hit retired a retained projectile too early")
	var denied: RefCounted=group.fork_for_frame();denied._actors[id].set_permissions(true,false,true)
	var immune:=operation.evaluate(shots,denied,[id])
	check(not immune.is_empty() and immune.contacts.size()==1 and not immune.contacts[0].damage.accepted and immune.combat.snapshot().actors[id].contact,"Damage immunity incorrectly suppressed contact marking")
	var near_death: RefCounted=group.fork_for_frame();damage(near_death,id,319,true)
	var late:=operation.evaluate(shots,near_death,[id,id])
	check(not late.is_empty() and late.contacts.size()==1 and late.contacts[0].damage.destroyed_now,"Later duplicate target ignored its newly exhausted hull")
	var two:=shot(weapon,Vector3.ZERO)
	two.advance(int(weapon.interval_ms)+1)
	var position: Vector3=two.snapshot().slots[0].position
	check(two.fire(position,Vector3.RIGHT,true).fired,two.error)
	var aligned: RefCounted=near_death.fork_for_frame()
	var moved:=Transform3D(Basis.IDENTITY,position-Vector3(0,-14,4200))
	check(aligned.set_pose(id,moved,moved),aligned.error)
	var pair:=operation.evaluate(two,aligned,[id])
	check(not pair.is_empty() and pair.contacts.size()==2,"Freighter death during a slot pass suppressed later retained projectiles")
	if not pair.is_empty() and pair.contacts.size()==2:
		check(pair.contacts[0].damage.destroyed_now and not pair.contacts[1].damage.accepted and pair.combat.snapshot().reputation.events.size()==1,"Two same-target hits repeated a lethal consequence")
	var wrong:=weapon.duplicate(true);wrong.campaign_cursor=10
	check(operation.evaluate(shot(wrong,Vector3.ZERO),group,[id]).is_empty(),"Wrong encounter weapon hit mixed traffic")
	var invalid: Dictionary=group.snapshot()
	check(operation.evaluate(shots,group,[id,999]).is_empty() and group.snapshot()==invalid,"Invalid later actor committed an earlier freighter hit")
	var geometry:=HitGeometry.new()
	var boxes: Array=group.collision_context(id).boxes
	boxes.append({"offset":Vector3.ZERO,"half_extents":Vector3.ZERO})
	check(geometry.box_geometry(Vector3.ZERO,Vector3.ZERO,boxes).is_empty(),"Malformed later box was ignored after an earlier point hit")
	# Binary32 rounds this upper boundary back to the center. Double-precision
	# subtraction would incorrectly include it in an otherwise tiny box.
	check(not geometry.box_geometry(Vector3(33554432,0,0),Vector3(33554432,0,0),[{"offset":Vector3.ZERO,"half_extents":Vector3.ONE}]).hit,"Box edges stopped following source binary32 rounding")

func shot(weapon: Dictionary,position: Vector3) -> RefCounted:
	var owner:=Shots.new()
	if not owner.configure(weapon) or owner.advance(1).is_empty() or not owner.fire(position,Vector3.RIGHT,true).get("fired",false):check(false,owner.error);return null
	return owner
