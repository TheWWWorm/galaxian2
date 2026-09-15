extends "res://tests/mido_traffic_control.gd"
## Component fixtures disclose synthetic incoming reputation, direct damage and
## overlapping shot placement. This is not an earned or integrated local trip.
const Group=preload("res://src/simulation/opening_combat_group.gd")
const Guns=preload("res://src/simulation/opening_npc_weapons.gd")
const DeathResources=preload("res://src/content/npc_destruction_resources.gd")
const LocalRadio=preload("res://src/simulation/local_traffic_radio.gd")
const Metrics=preload("res://src/content/image_font.gd")
const Layout=preload("res://src/presentation/source_text_layout.gd")
const Portraits=preload("res://src/presentation/portrait_compositor.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Primaries=preload("res://src/simulation/primary_weapons.gd")
const Mounts=preload("res://src/content/weapon_mounts.gd")
const Targets=preload("res://src/simulation/opening_target_inventory.gd")
const Audio=preload("res://src/content/audio_resources.gd")
const INCOMING_REPUTATION={"axes":[30,-6],"override":-1}
var source: RefCounted
var catalogue: RefCounted
var equipped: RefCounted
var generated: RefCounted

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [3,4],"Expected explicit Mac content, bindings, visuals and optional capture directory")
	if args.size() in [3,4]:verify(args.slice(0,3))
	print("Mido traffic combat: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_field(library: RefCounted, bindings: RefCounted, cat: RefCounted, equipment: RefCounted) -> void:
	source=bindings;catalogue=cat;equipped=equipment
	generated=World.new()
	if not generated.configure_local_traffic(bindings,cat,equipment,1,CONDITIONS) or generated.generate({"state":9999}).is_empty():check(false,generated.error);return
	verify_reactions()
	verify_difficulty_thresholds()
	verify_suppression()
	verify_radio(library)
	verify_control(library)
	verify_weapons(library)

func fresh(reputation: Dictionary=INCOMING_REPUTATION) -> RefCounted:
	var owner:=Group.new()
	if not owner.configure_local_traffic(source,catalogue,generated,0,0.5,equipped,reputation):check(false,owner.error);return null
	if not owner.begin_contact_pass(generated.snapshot().random_state,true):check(false,owner.error);return null
	return owner

func hit(owner: RefCounted, amount: int, id: int=0, npc:=false) -> Dictionary:
	var result: Dictionary=owner.normal_hit(id,amount,npc)
	check(not result.is_empty(),owner.error)
	return result

func verify_reactions() -> void:
	var owner:=fresh()
	if owner==null:return
	var initial: Dictionary=owner.snapshot();var random:=Random.new();random.restore(owner.contact_random_state())
	check(initial.current_reputation==INCOMING_REPUTATION and initial.actors[0].max_hull==60,"Local combat discarded retained reputation or normal factory hull")
	hit(owner,19)
	check(not owner.snapshot().provocation.warning_issued and owner.contact_random_state()==random.snapshot(),"Subthreshold hit issued a warning or consumed random values")
	var warning:=hit(owner,1)
	var selection:=random.next_int(3)
	check(warning.reactions.size()==1 and warning.reactions[0].text_id==415+selection and warning.reactions[0].voice_event_id==645+selection,"Warning text or fallback voice changed")
	check(owner.contact_random_state()==random.snapshot(),"Warning consumed portrait draws before presentation")
	hit(owner,10)
	check(owner.snapshot().provocation.requested_damage[0]==30 and not owner.snapshot().provocation.forced_hostile[0],"Exact half hull triggered strict retaliation")
	hit(owner,1)
	check(owner.snapshot().provocation.forced_hostile==[true,false,false,false] and not owner.snapshot().actors[0].hostile,"Hit refreshed hostility before the actor pass")
	check(owner.refresh_hostility(0) and owner.snapshot().actors[0].hostile and not owner.snapshot().actors[0].friendly,owner.error)
	hit(owner,8)
	check(not owner.snapshot().provocation.response_issued,"Faction retaliation fired below its binary32 threshold")
	var response:=hit(owner,1)
	selection=random.next_int(3)
	check(response.reactions.size()==1 and response.reactions[0].text_id==418+selection and response.reactions[0].voice_event_id==650+selection,"Faction response text or voice changed")
	check(owner.snapshot().provocation.forced_hostile==[true,true,true,true] and owner.snapshot().provocation.station_response_flag,"Faction response omitted another ship or current station")
	check(owner.snapshot().provocation.pending_radio==response.reactions[0] and owner.snapshot().provocation.radio_serial==2,"Queued response did not replace the warning")
	check(owner.contact_random_state()==random.snapshot(),"World warning/response consumed unexpected random values")
	var copy: RefCounted=owner.fork_for_frame();var held: Dictionary=owner.snapshot()
	check(hit(copy,999,2).destroyed_now and owner.snapshot()==held,"A prospective local lethal changed accepted state")
	check(copy.current_reputation().axes==[30,-1] and copy.snapshot().reputation.events.size()==1,"Local lethal failed to apply its single +5 reputation event")
	check(hit(copy,999,3,true).destroyed_now and copy.current_reputation().axes==[30,-1],"NPC-attributed local lethal changed career reputation")
	var dead: Dictionary=copy.snapshot()
	check(not hit(copy,999,2).accepted and copy.snapshot()==dead,"Repeated damage to a dead local ship repeated consequences")
	check(copy.normal_hit(0,-1).is_empty() and copy.snapshot()==dead,"Invalid local hit partially committed consequences")
	check(not copy.begin_contact_pass({"state":-1},true) and copy.snapshot()==dead,"Invalid hit stream partially committed consequences")
	var overflow:=fresh()
	hit(overflow,1);hit(overflow,2147483647)
	check(overflow.snapshot().provocation.requested_damage[0]==-2147483648 and not overflow.snapshot().provocation.warning_issued and not overflow.snapshot().provocation.forced_hostile[0],"Requested damage failed to wrap before source threshold comparison")
	check(overflow.snapshot().actors[0].vitals.hull==0 and overflow.current_reputation().axes==[30,-1],"Overflowing accumulator incorrectly suppressed ordinary lethal damage")

func verify_suppression() -> void:
	var owner:=fresh();var stream: Dictionary=owner.contact_random_state()
	hit(owner,40,1,true)
	check(owner.snapshot().provocation.requested_damage==[0,0,0,0] and owner.contact_random_state()==stream,"Nonplayer damage provoked the faction")
	check(owner.begin_contact_pass(stream,false),owner.error)
	hit(owner,40)
	check(owner.snapshot().provocation.warning_issued and owner.snapshot().provocation.response_issued and owner.snapshot().provocation.pending_radio.is_empty(),"Missing HUD changed world reaction flags or fabricated radio")
	check(owner.contact_random_state()==stream and owner.snapshot().provocation.station_response_flag,"Suppressed radio consumed random values or lost station consequences")
	check(owner.begin_contact_pass(stream,true),owner.error);hit(owner,1)
	check(owner.snapshot().provocation.pending_radio.is_empty() and owner.contact_random_state()==stream,"A later HUD replayed already-consumed world reactions")
	var hostile:=fresh({"axes":[30,71],"override":-1})
	check(hostile.refresh_hostility(0) and hostile.snapshot().actors[0].hostile,hostile.error)
	hit(hostile,40)
	check(hostile.snapshot().provocation.requested_damage[0]==0 and not hostile.snapshot().provocation.warning_issued,"An already-hostile unforced ship issued a friendly warning")
	for value in [-71,-70,70,71]:
		var faction:=fresh({"axes":[30,value],"override":-1});faction.refresh_hostility(0)
		check(faction.snapshot().actors[0].hostile==(value>70) and faction.snapshot().actors[0].friendly==(value< -70),"Local reputation lost strict hostile/friendly boundaries")
	check(not Group.new().configure_local_traffic(source,catalogue,generated,0,0.5,equipped,{}),"Local combat invented a missing retained career reputation")

func verify_difficulty_thresholds() -> void:
	for vector in [[0,0.5,60,19,30,39],[1,0.5,74,24,37,48],[0,1.0,90,29,45,59],[1,1.0,111,36,55,73],[2,0.5,88,29,44,58],[2,1.0,132,43,66,87]]:
		var owner:=Group.new()
		if not owner.configure_local_traffic(source,catalogue,generated,vector[0],vector[1],equipped,INCOMING_REPUTATION):check(false,owner.error);return
		owner.begin_contact_pass(generated.snapshot().random_state,true)
		check(owner.snapshot().actors[0].max_hull==vector[2],"Local difficulty/rank changed factory hull")
		hit(owner,vector[3]);check(not owner.snapshot().provocation.warning_issued,"Local warning fired below its difficulty-scaled hull threshold")
		hit(owner,1);check(owner.snapshot().provocation.warning_issued,"Local warning missed its first integer threshold crossing")
		hit(owner,vector[4]-vector[3]-1);check(not owner.snapshot().provocation.forced_hostile[0],"Local retaliation fired below its hull threshold")
		hit(owner,1);check(owner.snapshot().provocation.forced_hostile[0],"Local retaliation missed its first integer threshold crossing")
		hit(owner,vector[5]-vector[4]-1);check(not owner.snapshot().provocation.response_issued,"Local faction response fired below its hull threshold")
		hit(owner,1);check(owner.snapshot().provocation.response_issued,"Local faction response missed its first integer threshold crossing")

func verify_radio(library: RefCounted) -> void:
	if not library.select_language("gb"):check(false,library.error);return
	var metrics:=Metrics.new();var layout:=Layout.new()
	if not metrics.open_selected(library,source,0) or not layout.configure_from_bindings(metrics,350,5,source):check(false,metrics.error+layout.error);return
	var radio:=LocalRadio.new()
	if not radio.configure(source,library,layout):check(false,radio.error);return
	var owner:=fresh();hit(owner,40)
	var random:=Random.new();random.restore(owner.contact_random_state())
	var family:=0 if random.next_int(4)==0 else 2;var parts:=[]
	for i in 4:parts.append(random.next_int(11 if family==0 else 5))
	var started:=radio.evaluate(100,owner.snapshot().provocation,owner.contact_random_state())
	if started.is_empty():check(false,radio.error);return
	check(radio.snapshot().last_serial==0,"Prospective radio altered accepted state")
	radio=started.radio
	check(started.events.size()==1 and started.events[0].kind=="started" and radio.snapshot().message.kind=="response","Unstarted warning survived its replacement")
	check(started.random_state==random.snapshot() and radio.snapshot().portrait=={"status":"fixed","family":family,"parts":parts},"Portrait did not consume exactly its five deferred source draws")
	var visuals:=Visuals.new();var compositor:=Portraits.new()
	if not visuals.open(OS.get_cmdline_user_args()[2],library.manifest):check(false,visuals.error);return
	var portrait:=compositor.compose_definition(library,source,visuals,21,"baseline",radio.snapshot().portrait)
	check(not portrait.is_empty(),compositor.error)
	for kind in [0,2]:
		var bounds: Array=source.mido_travel.traffic_combat.radio.portrait_part_bounds[str(kind)]
		portrait=compositor.compose_definition(library,source,visuals,21,"baseline",{"status":"fixed","family":kind,"parts":bounds.map(func(value):return int(value)-1)})
		check(not portrait.is_empty(),compositor.error)
		if not portrait.is_empty() and OS.get_cmdline_user_args().size()==4:
			check(portrait.image.save_png(OS.get_cmdline_user_args()[3].path_join("mido-family-%d.png"%kind))==OK,"Could not capture assembled Mido portrait")
	var audio:=Audio.new()
	if not audio.configure_local_traffic(library,source):check(false,audio.error);return
	for id in [645,646,647,650,651,652]:
		var clip:=audio.prepare(id)
		check(not clip.is_empty() and not clip.has("unsupported"),"Unsupported faction voice %d: %s"%[id,audio.error+str(clip.get("unsupported",""))])
	var next:=radio.evaluate(2100,owner.snapshot().provocation,started.random_state)
	check(not next.is_empty() and not next.radio.snapshot().visible and next.events.is_empty(),"Radio ignored strict display delay")
	next=next.radio.evaluate(2101,owner.snapshot().provocation,next.random_state)
	check(next.events.size()==1 and next.events[0].kind=="display" and next.events[0].voice_event_id==radio.snapshot().message.voice_event_id,"Displayed local radio omitted its voice cue")
	# An active warning finishes while the replacement response remains pending.
	radio=LocalRadio.new();check(radio.configure(source,library,layout),radio.error)
	owner=fresh();hit(owner,20)
	next=radio.evaluate(0,owner.snapshot().provocation,owner.contact_random_state());radio=next.radio
	check(owner.begin_contact_pass(next.random_state,true),owner.error);hit(owner,20)
	next=radio.evaluate(1,owner.snapshot().provocation,owner.contact_random_state());radio=next.radio
	check(radio.snapshot().message.kind=="warning" and radio.snapshot().pending.kind=="response" and next.random_state==owner.contact_random_state(),"Replacement interrupted an active warning or generated its next portrait early")
	var lines: int=layout.wrap(library.strings[radio.snapshot().text_id]).size()
	var finish:=2000+1500+2000*lines
	next=radio.evaluate(finish,owner.snapshot().provocation,next.random_state);radio=next.radio
	check(radio.snapshot().active_event==0,"Radio finished on its strict time boundary")
	next=radio.evaluate(finish+1,owner.snapshot().provocation,next.random_state);radio=next.radio
	check(radio.snapshot().active_event==-1 and not radio.snapshot().pending.is_empty(),"Radio started the replacement during its predecessor's finish pass")
	next=radio.evaluate(finish+1,owner.snapshot().provocation,next.random_state)
	check(next.radio.snapshot().message.kind=="response" and next.events[0].kind=="started","Pending response never began after warning completion")
	var held: Dictionary=radio.snapshot()
	check(radio.evaluate(-1,owner.snapshot().provocation,next.random_state).is_empty() and radio.snapshot()==held,"Invalid radio time partially committed presentation")
	if not library.select_language("de") or not audio.configure_local_traffic(library,source):check(false,library.error+audio.error);return
	for id in [645,646,647,650,651,652]:
		var clip:=audio.prepare(id)
		check(not clip.is_empty() and not clip.has("unsupported"),"Unsupported German faction voice %d"%id)
	check(library.select_language("gb"),library.error)

func verify_control(library: RefCounted) -> void:
	var resources:=DeathResources.new()
	if not resources.configure_local_traffic(library,source):check(false,resources.error);return
	var controller:=TrafficControl.new()
	if not controller.configure_local_traffic(source,catalogue,generated,0,0.5,equipped,INCOMING_REPUTATION) or not controller.set_destruction(source,resources):check(false,controller.error);return
	var combat: RefCounted=controller.combat_owner();combat.begin_contact_pass(generated.snapshot().random_state,true)
	hit(combat,999)
	var target:=player_target(source)
	var first:=controller.advance(0,target,combat,combat.contact_random_state())
	if first.is_empty():check(false,controller.error);return
	check(first.decisions[0].dying and first.combat.actors[0].actor_mode==3,"Ordinary mode0 lethal did not enter the shared death sequence")
	check(controller.snapshot().accounting.counter_deltas.player_kills==1 and controller.snapshot().accounting.counter_deltas.pirate_kills==0,"Mido ship death was counted as a pirate")
	check(controller.snapshot().accounting.counter_deltas.nonhostile_remaining==0 and first.combat.current_reputation.axes==[30,-1],"Retaliation hostility or lethal reputation reached death in the wrong order")
	var ready:=false
	for frame in 100:
		var result:=controller.advance(150,target)
		if result.is_empty():check(false,controller.error);return
		if result.combat.actors[0].actor_mode==4:ready=true;break
	check(ready,"Local destruction never reached its explosion mode")
	var death: Dictionary=controller.destruction_owner(0).snapshot()
	check(death.cargo.entries==generated.snapshot().npc_construction.actors[0].cargo and death.cargo.model_id==16990,"Local death lost generated cargo or its Mido container")
	check(controller.snapshot().accounting.events.size()==1 and controller.defeat_status().is_empty(),"Local death repeated accounting or invented story completion")
	var guns:=Guns.new()
	check(guns.configure_local_traffic(source,catalogue,generated,0,0.5),guns.error)
	var operation:=controller.evaluate(controller.combat_owner(),guns,0,target,controller.snapshot().random_state)
	check(not operation.is_empty(),controller.error)
	# A nonplayer lethal never provokes the group, so its fresh actor remains
	# neutral during the death-accounting pass.
	controller=TrafficControl.new();controller.configure_local_traffic(source,catalogue,generated,0,0.5,equipped,INCOMING_REPUTATION);controller.set_destruction(source,resources)
	combat=controller.combat_owner();combat.begin_contact_pass(generated.snapshot().random_state,true);hit(combat,999,0,true)
	first=controller.advance(0,target,combat,combat.contact_random_state())
	check(not first.is_empty(),controller.error)
	check(controller.snapshot().accounting.counter_deltas.nonhostile_remaining==-1 and controller.snapshot().accounting.counter_deltas.player_kills==0 and controller.snapshot().accounting.counter_deltas.hostile_deaths==0,"Neutral local death borrowed hostile kill accounting")
	controller=TrafficControl.new();controller.configure_local_traffic(source,catalogue,generated,0,0.5,equipped,INCOMING_REPUTATION);controller.set_destruction(source,resources)
	target.pose=controller.combat_owner().snapshot().actors[1].pose.translated_local(Vector3(0,0,1000))
	first=controller.advance(0,target)
	if first.is_empty():check(false,controller.error);return
	combat=controller.combat_owner();combat.begin_contact_pass(controller.snapshot().random_state,true);hit(combat,40,1)
	guns=Guns.new();guns.configure_local_traffic(source,catalogue,generated,0,0.5);guns.advance(581)
	operation=controller.evaluate(combat,guns,0,target,combat.contact_random_state())
	if operation.is_empty():check(false,controller.error);return
	check(operation.actors[1].decision.target_kind=="player" and operation.actors[1].decision.fire_requested and operation.actors[1].firing.actors[0].outcome.fired,"Provoked traffic did not acquire and fire at the player through shared guidance")

func verify_weapons(library: RefCounted) -> void:
	var guns:=Guns.new();var player:=Player.new();var combat:=fresh()
	if not guns.configure_local_traffic(source,catalogue,generated,0,0.5) or not player.configure_local_travel(source,catalogue,equipped):check(false,guns.error+player.error);return
	for row in guns.snapshot().actors:
		var weapon: Dictionary=row.projectiles.weapon
		check(weapon.item_id==25 and weapon.damage==3 and weapon.interval_ms==580 and weapon.kind==0 and weapon.campaign_cursor==10 and row.projectiles.slots.size()==4,"Traffic inherited training cursor or catalogue weapon behavior")
		check(player.supports_weapon_hit(weapon) and combat.supports_weapon_hit(weapon),player.error+combat.error)
	hit(combat,40)
	for id in 4:combat.refresh_hostility(id)
	check(not guns.advance(581).is_empty(),guns.error)
	var pose: Transform3D=combat.snapshot().actors[1].pose
	var fired:=guns.fire_combat_training(combat,[{"actor_id":1,"target_actor_id":-1,"pose":pose}])
	check(not fired.is_empty() and fired.actors[0].outcome.fired,guns.error)
	var old: Dictionary=player.snapshot()
	var contacts:=guns.evaluate_combat_training_update(player,pose,combat,false,0)
	if contacts.is_empty():check(false,guns.error);return
	check(contacts.player.snapshot().vitals!=old.vitals and contacts.actors[1].npc_contacts.is_empty(),"Ordinary traffic shot missed the overlapping player or hit excluded same-kind targets")
	var bodies:=Bodies.new();var effects:=Effects.new();var field:=Scenery.new()
	if not bodies.configure(library,source) or not effects.configure(library,source) or not field.configure_local_departure(source,catalogue,equipped,player.cache_snapshot(),CONDITIONS,1,true,bodies,effects):check(false,bodies.error+effects.error+field.error);return
	var inventory:=Targets.new();var mounts:=Mounts.new();var primary:=Primaries.new()
	if not inventory.configure_local_travel(source,catalogue,player,field) or not mounts.open(library,catalogue) or not primary.configure(source,catalogue,mounts,player.loadout()):check(false,inventory.error+mounts.error+primary.error);return
	primary.advance(2000)
	var shot:=primary.fire(Transform3D.IDENTITY,true,field.snapshot().random_state)
	if shot.is_empty():check(false,primary.error);return
	var point: Vector3=primary.snapshot().guns[0].projectiles.slots[0].position
	combat=fresh()
	hit(combat,19)
	for id in 4:combat.set_pose(id,Transform3D(Basis.IDENTITY,point if id==0 else point+Vector3(100000*id,0,0)))
	var pending: Dictionary=combat.snapshot()
	var untouched: Dictionary=field.snapshot()
	check(field.evaluate_primary_contacts(primary,Random.new(),inventory,0,shot.random_state,true).is_empty() and field.snapshot()==untouched,"An invalid combat owner partially committed local contacts")
	check(field.evaluate_primary_contacts(primary,combat,inventory,0,{"state":-1},true).is_empty() and field.snapshot()==untouched,"An invalid shared stream partially committed local contacts")
	var result:=field.evaluate_primary_contacts(primary,combat,inventory,0,shot.random_state,true)
	if result.is_empty():check(false,field.error);return
	check(result.combat.snapshot().actors[0].vitals.hull<pending.actors[0].vitals.hull and combat.snapshot()==pending,"Local player projectile failed its prospective ordinary contact pass")
	check(result.combat.snapshot().provocation.requested_damage[0]>0 and result.random_state==result.combat.contact_random_state(),"Player contacts bypassed provocation or dropped the shared stream")
	var random:=Random.new();random.restore(shot.random_state);random.next_int(3)
	check(result.combat.snapshot().provocation.warning_issued and result.random_state==random.snapshot(),"Real primary contact did not advance the warning stream after projectile spread")
