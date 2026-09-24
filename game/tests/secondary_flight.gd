extends "res://tests/secondary_retention.gd"
## Detached equipped records join the actual encounter weapon and NPC owners.
## This checks live-frame plumbing, not an earned Kappa departure or campaign.
const Encounter=preload("res://src/simulation/full_hold_encounter.gd")
const WorldFrame=preload("res://src/simulation/first_flight_frame.gd")
const NPCWeapons=preload("res://src/simulation/opening_npc_weapons.gd")
const ProjectileState=preload("res://src/simulation/projectile_visual_state.gd")
const ImpactState=preload("res://src/simulation/ordinary_impact_state.gd")
const Sound=preload("res://src/presentation/opening_audio.gd")

func _initialize() -> void:call_deferred("run_flight")

func run_flight() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected one content/binding/visual triple")
	if args.size()==3:verify_flight(args[0],args[1])
	await process_frame
	print("Secondary encounter/frame wiring: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_flight(content: String,pack: String) -> void:
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(content) or not bindings.open(pack,lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	if not OwnershipRules.available(bindings):
		check(not Encounter.new().configure_secondaries(bindings,cat,null,null),"Legacy content enabled secondary flight")
		return
	var built:=construction(bindings,cat,0.5)
	if built==null:return
	var initial:=equipped(bindings,cat,[{"item_id":41,"slot":0,"quantity":2}])
	var views:=detached_views(bindings,cat,lib,initial,built.snapshot().random_state)
	if views.is_empty():return
	verify_kappa_composition(bindings,cat,lib,views.equipment,built.snapshot().kappa_context)
	var encounter:=detached_encounter(bindings,cat,lib,built,views)
	if encounter==null:return
	var before: Dictionary=encounter.snapshot()
	var missing: RefCounted=encounter.fork_for_frame();missing._inventory=views.targets.fork_for_frame();missing._inventory._state.npc_ids=[0,1,2]
	check(not missing.configure_secondaries(bindings,cat,views.player,views.equipment) and encounter.snapshot()==before,"Secondary attachment accepted incomplete target membership")
	var bad_library:=Library.new()
	check(not encounter.configure_secondaries(bindings,cat,views.player,views.equipment,bad_library) and not encounter.has_secondaries() and encounter.snapshot()==before,"Rejected burst resources partially attached live secondaries")
	if not encounter.configure_secondaries(bindings,cat,views.player,views.equipment,lib):check(false,encounter.error);return
	check(encounter.secondary_owner().has_detonations() and encounter.snapshot().secondaries.detonation_audio.is_empty(),"Equipped flight did not prepare its original burst wrappers")
	check(encounter.snapshot().selected_secondary==-1 and encounter.secondary_choices()==[{"item_id":41,"quantity":2,"slot_index":int(cat.tables.ships[0].stats.primary_slots)}],"Attachment fabricated a weapon selection or lost installed ammunition")
	check(not encounter.configure_secondaries(bindings,cat,views.player,views.equipment) and encounter.select_secondary(42)==null,"Attachment repeated or selected unowned ammunition")
	check(encounter.next_secondary_id()==41,"Explicit selection did not start at the actual equipped launcher")
	encounter=encounter.select_secondary(encounter.next_secondary_id())
	if encounter==null:check(false,"Cannot select the equipped EMP");return
	check(encounter.next_secondary_id()==-1,"Explicit secondary selection lost its None choice")
	var random: Dictionary=built.snapshot().random_state
	var pose:=Transform3D(Basis.IDENTITY,encounter.snapshot().combat.actors[0].position-Vector3(0,0,400))
	var equal: Dictionary=encounter.evaluate_secondary_fire(views.player,views.equipment,pose,true,true,random,false)
	if equal.is_empty():check(false,encounter.error);return
	check(equal.encounter.snapshot().secondary_events.is_empty(),"EMP launched at interval equality")
	var motion: Dictionary=encounter.evaluate_secondary_motion(1,random,false)
	if motion.is_empty():check(false,encounter.error);return
	encounter=motion.encounter
	var retained: Dictionary=encounter.snapshot();var inventory:=view_snapshot(views)
	for enabled in [false,true]:
		var no_press: Dictionary=encounter.evaluate_secondary_fire(views.player,views.equipment,pose,false,enabled,random,false)
		check(not no_press.is_empty() and no_press.encounter.snapshot().secondaries==retained.secondaries,"No input edge launched or detonated an EMP")
	var fired: Dictionary=encounter.evaluate_secondary_fire(views.player,views.equipment,pose,true,true,random,false)
	if fired.is_empty():check(false,encounter.error);return
	check(encounter.snapshot()==retained and view_snapshot(views)==inventory,"Prospective encounter fire mutated retained inputs")
	check(fired.encounter.snapshot().secondary_events.size()==1 and fired.encounter.snapshot().secondary_events[0].action=="launched" and fired.encounter.snapshot().secondaries.guns[0].ammunition==1,"Encounter failed to consume exactly one launch")
	check(fired.player.loadout().slots==fired.equipment.snapshot().loadout.slots and fired.random_state==random,"Encounter launch lost inventory or consumed gameplay randomness")
	verify_sound(lib,bindings,fired.encounter.snapshot())
	var frame:=WorldFrame.new()
	frame._encounter=fired.encounter;frame._player=fired.player;frame._equipment=fired.equipment;frame._pose=pose;frame._random=fired.random_state
	var stable: Dictionary=frame._encounter.snapshot()
	if not frame._apply_secondary_input(false,true):check(false,frame.error);return
	check(frame._encounter.snapshot().secondaries==stable.secondaries,"A held frame detonated without an edge")
	frame._encounter.clear_secondary_events()
	var bad: RefCounted=frame._equipment.fork();var slot: int=frame._encounter.snapshot().secondaries.guns[0].slot_index
	bad._state.prices.installed[slot].item_id=42
	var actual: RefCounted=frame._equipment;frame._equipment=bad
	var combat_before: Dictionary=frame._encounter.snapshot()
	check(not frame._apply_secondary_input(true,true) and frame._encounter.snapshot()==combat_before,"Rejected flight inventory committed a pulse or reputation")
	frame._equipment=actual
	if not frame._apply_secondary_input(true,true):check(false,frame.error);return
	var pulse: Dictionary=frame._encounter.snapshot()
	check(pulse.combat.actors[0].systems.disabled and not pulse.combat.actors[0].systems_disabled and pulse.secondaries.guns[0].ammunition==1,"Late pulse lost systems damage or projected the NPC flag too early")
	check(pulse.secondary_events.size()==1 and pulse.secondary_events[0].audio.is_empty(),"Detonation repeated launch audio")
	var actors: Dictionary=frame._encounter.evaluate_world(frame._player,pose,0,frame._random)
	if actors.is_empty():check(false,frame._encounter.error);return
	frame._encounter=actors.encounter;frame._random=actors.random_state
	check(frame._encounter.snapshot().combat.actors[0].systems_disabled and frame._encounter.snapshot().combat.actors[0].vitals==combat_before.combat.actors[0].vitals,"Later NPC pass did not project disable without ordinary damage")
	frame._encounter.clear_secondary_events()
	check(frame._encounter.snapshot().secondary_events.is_empty() and frame._encounter.snapshot().secondaries==pulse.secondaries,"Clearing modal audio cues changed bomb lifetime")
	motion=frame._encounter.evaluate_secondary_motion(16,frame._random,false,frame._pose.origin)
	if motion.is_empty():check(false,frame._encounter.error);return
	frame._encounter=motion.encounter;frame._random=motion.random_state
	var burst: Dictionary=frame._encounter.snapshot().secondaries
	check(burst.detonation_audio.size()==1 and burst.detonation_audio[0].source_id==15 and burst.guns[0].detonation.effect.active,"Live encounter did not publish the next-update EMP burst and sound")
	# Dialogue-only flight frames start a new audio revision without visiting
	# the weapon pass. Reset transient cues, not the retained projectile/effect.
	var modal: RefCounted=frame._encounter.fork_for_frame()
	var silent: Dictionary=burst.duplicate(true);silent.detonation_audio=[];silent.detonation_camera=[]
	modal.clear_secondary_events()
	check(modal.snapshot().secondaries==silent and modal.snapshot().secondary_events.is_empty() and frame._encounter.snapshot().secondaries==burst,"Dialogue-only frame retained an EMP cue or changed accepted burst lifetime")
	var modal_audio:=Sound.new();root.add_child(modal_audio)
	if modal_audio.configure(lib,bindings,123):
		var modal_sound: Dictionary=modal_audio.prepare_secondaries(modal.snapshot())
		check(not modal_sound.is_empty() and modal_sound.operations.is_empty(),"Dialogue-only frame replayed an earlier detonation sound")
	else:check(false,modal_audio.error)
	modal_audio.clear();modal_audio.free()
	verify_mixed_weapon_audio(lib,bindings,frame)
	for i in 41:
		motion=frame._encounter.evaluate_secondary_motion(150,frame._random,false)
		if motion.is_empty():check(false,frame._encounter.error);return
		frame._encounter=motion.encounter;frame._random=motion.random_state
	if not frame._apply_secondary_input(true,true):check(false,frame.error);return
	check(frame._encounter.snapshot().secondaries.guns[0].ammunition==0 and frame._player.loadout().slots[slot]==null and frame._equipment.snapshot().prices.installed[slot]==null,"Last launch did not update all retained views")
	check(frame._encounter.select_secondary(41)==null,"Exhausted ammunition remained available for a new selection")
	if not frame._apply_secondary_input(true,true):check(false,frame.error);return
	check(frame._encounter.snapshot().secondaries.guns[0].bomb.shot.phase=="detonated","Last launched round could not be manually detonated")
	for i in 41:
		motion=frame._encounter.evaluate_secondary_motion(150,frame._random,false,frame._pose.origin)
		if motion.is_empty():check(false,frame._encounter.error);return
		frame._encounter=motion.encounter;frame._random=motion.random_state
	if not frame._apply_secondary_input(true,true):check(false,frame.error);return
	check(frame._encounter.snapshot().selected_secondary==-1 and frame._encounter.snapshot().secondaries.launches==2,"Empty attempt failed to clear selection or fabricated ammunition")
	var end: Dictionary=frame._encounter.snapshot()
	check(frame._encounter.evaluate_secondary_motion(751 if not bindings.fast_forward.is_empty() else 151,frame._random).is_empty() and frame._encounter.snapshot()==end,"Oversized secondary frame partially committed")

func prepare_kappa_composition(bindings: RefCounted,cat: RefCounted,lib: RefCounted,equipment: RefCounted,context: Dictionary) -> Dictionary:
	# Only the equipment record is a detached component input. The field,
	# player pools/cache, complete targets, projectile clocks and encounter
	# below must all be produced by their native public constructors.
	var body_resources: RefCounted=load("res://src/content/scenery_body_resources.gd").new()
	var effect_resources: RefCounted=load("res://src/content/scenery_effect_resources.gd").new()
	if not body_resources.configure(lib,bindings) or not effect_resources.configure(lib,bindings):check(false,body_resources.error+effect_resources.error);return {}
	var scenery: RefCounted=load("res://src/simulation/opening_scenery.gd").new()
	var conditions:={"companions_empty":true,"location_match":false,"special_placement":false}
	var held: Dictionary=equipment.snapshot()
	if not scenery.configure_kappa_rescue(bindings,cat,equipment,context,conditions,123,true,body_resources,effect_resources):check(false,"Kappa scenery composition: "+scenery.error);return {}
	var world: RefCounted=scenery.world_initialization_owner()
	var player:=PlayerState.new()
	if not player.configure_kappa_rescue(bindings,cat,equipment,world.npc_construction_owner()):check(false,"Kappa player composition: "+player.error);return {}
	check(player.cache_snapshot().campaign_cursor==21 and player.cache_snapshot().station_id==55 and player.snapshot().vitals.hull>0,"Kappa player lost its native departure cache or pools")
	check(equipment.snapshot()==held and scenery.snapshot().random_state==world.snapshot().random_state,"Kappa composition changed equipment or reseeded after world construction")
	var encounter:=Encounter.new()
	if not encounter.configure_kappa_rescue(bindings,cat,lib,player,scenery,equipment,{"axes":[0,0],"override":-1}):check(false,"Kappa encounter composition: "+encounter.error);return {}
	return {"encounter":encounter,"player":player,"scenery":scenery,"equipment":equipment,"random_state":scenery.random_state()}

func verify_kappa_composition(bindings: RefCounted,cat: RefCounted,lib: RefCounted,equipment: RefCounted,context: Dictionary) -> void:
	var prepared:=prepare_kappa_composition(bindings,cat,lib,equipment,context)
	if prepared.is_empty():return
	var encounter: RefCounted=prepared.encounter;var player: RefCounted=prepared.player;var scenery: RefCounted=prepared.scenery
	var held: Dictionary=equipment.snapshot()
	var fresh: Dictionary=encounter.snapshot()
	check(fresh.combat.actors.size()==4 and fresh.combat.actors.all(func(actor):return not actor.active),"Kappa composition omitted its cast or activated it before the NPC pass")
	check(fresh.projectile_visuals.models.size()==5 and fresh.impact_visuals.weapons.size()==5 and encounter.has_secondaries(),"Kappa composition did not prepare all primary/NPC/EMP visual owners")
	var inventory: Dictionary=encounter._inventory.snapshot()
	check(inventory.npc_ids==[0,1,2,3] and inventory.scenery_indices.size()==scenery.snapshot().objects.size() and not inventory.scenery_indices.is_empty(),"Kappa targets omitted the generated cast or scenery")
	check(not encounter.configure_kappa_rescue(bindings,cat,lib,player,scenery,equipment,{"axes":[0,0],"override":-1}) and encounter.snapshot()==fresh,"Repeated composition replaced an accepted Kappa encounter")
	var changed: RefCounted=equipment.fork();changed._state.loadout.slots[0].quantity=2
	check(not Encounter.new().configure_kappa_rescue(bindings,cat,lib,player,scenery,changed,{"axes":[0,0],"override":-1}) and encounter.snapshot()==fresh,"Kappa accepted divergent retained equipment")
	var foreign: RefCounted=player.fork_for_frame();foreign._state.kappa_context.rank=1
	check(not Encounter.new().configure_kappa_rescue(bindings,cat,lib,foreign,scenery,equipment,{"axes":[0,0],"override":-1}),"Kappa accepted a player from a different generated encounter")
	var bad_context:=context.duplicate(true);bad_context.station_id=56
	var conditions:={"companions_empty":true,"location_match":false,"special_placement":false}
	check(not load("res://src/simulation/opening_scenery.gd").new().configure_kappa_rescue(bindings,cat,equipment,bad_context,conditions,123),"Kappa scenery accepted a different mission location")
	var pose:=Transform3D(Basis.IDENTITY,fresh.combat.actors[0].position-Vector3(0,0,400))
	player.set_permissions(true,true)
	var random: Dictionary=scenery.snapshot().random_state
	var step: Dictionary=encounter.evaluate_weapons(player,pose,1,scenery,random,false,false)
	if step.is_empty():check(false,"Kappa first weapon pass: "+encounter.error);return
	check(encounter.snapshot()==fresh and equipment.snapshot()==held,"Prospective Kappa contact pass mutated accepted inputs")
	encounter=step.encounter;player=step.player;scenery=step.scenery;random=step.random_state
	step=encounter.evaluate_world(player,pose,0,random)
	if step.is_empty():check(false,"Kappa first NPC pass: "+encounter.error);return
	encounter=step.encounter;random=step.random_state
	check(encounter.snapshot().combat.actors[0].active,"Kappa target did not activate through the native proximity update")
	encounter=encounter.select_secondary(41)
	if encounter==null:check(false,"Native Kappa encounter could not select its installed EMP");return
	step=encounter.evaluate_secondary_fire(player,equipment,pose,true,true,random,false)
	if step.is_empty():check(false,"Kappa launch: "+encounter.error);return
	encounter=step.encounter;player=step.player;equipment=step.equipment;random=step.random_state
	var ordinary: Dictionary=encounter.snapshot().combat.actors[0].vitals
	step=encounter.evaluate_secondary_fire(player,equipment,pose,true,true,random,false)
	if step.is_empty():check(false,"Kappa detonation: "+encounter.error);return
	encounter=step.encounter;player=step.player;equipment=step.equipment;random=step.random_state
	check(encounter.snapshot().combat.actors[0].systems.disabled and encounter.snapshot().combat.actors[0].vitals==ordinary,"Native Kappa EMP lost its systems-only damage")
	step=encounter.evaluate_weapons(player,pose,16,scenery,random,false,true)
	if step.is_empty():check(false,"Kappa post-EMP weapon pass: "+encounter.error);return
	encounter=step.encounter;player=step.player;scenery=step.scenery;random=step.random_state
	check(encounter.snapshot().secondaries.detonation_audio.size()==1,"Native Kappa weapon pass lost the original EMP burst cue")
	verify_camera_frame(bindings,encounter,player,equipment,pose,random)
	step=encounter.evaluate_world(player,pose,0,random)
	if step.is_empty():check(false,"Kappa post-EMP NPC pass: "+encounter.error);return
	encounter=step.encounter;random=step.random_state
	check(encounter.snapshot().combat.actors[0].systems_disabled,"Native Kappa actor pass did not project its disabled systems")
	step=encounter.evaluate_primary_fire(player,pose,true,true,random)
	if step.is_empty():check(false,"Kappa primary input: "+encounter.error);return
	encounter=step.encounter;random=step.random_state
	for i in 40:
		step=encounter.evaluate_weapons(player,pose,16,scenery,random,false,false)
		if step.is_empty():check(false,"Kappa primary contact pass: "+encounter.error);return
		encounter=step.encounter;player=step.player;scenery=step.scenery;random=step.random_state
	var hit: Dictionary=encounter.snapshot().combat.actors[0].vitals
	check(hit.hull+hit.armor+hit.shield<ordinary.hull+ordinary.armor+ordinary.shield,"Kappa ordinary primaries could not damage the disabled target through real contacts")
	var retained_loadout: Dictionary=equipment.snapshot().loadout.duplicate(true)
	retained_loadout.campaign_cursor=21
	check(retained_loadout==player.loadout(),"Kappa weapon passes lost retained ammunition or identity")

func verify_camera_frame(bindings: RefCounted,encounter: RefCounted,player: RefCounted,equipment: RefCounted,pose: Transform3D,random_state: Dictionary) -> void:
	var frame:=WorldFrame.new()
	frame._encounter=encounter.fork_for_frame();frame._player=player.fork_for_frame();frame._equipment=equipment.fork();frame._pose=pose;frame._random=random_state.duplicate(true)
	frame._camera=load("res://src/simulation/camera_rig.gd").new()
	frame._shot={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"mode":"fixed_eye","target":"player","actor_id":-1,"eye":pose*Vector3(0,150,-800),"inherit_target_up":true}
	var scene:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"player_pose":pose}
	if not frame._camera.configure(bindings) or not frame._camera.update(0,frame._shot,scene,frame._shot):check(false,frame._camera.error);return
	var view: Dictionary=frame._camera.snapshot()
	var native_player: Dictionary=player.snapshot();var held: Dictionary=equipment.snapshot();var native_encounter: Dictionary=encounter.snapshot()
	check(frame._advance_follow_camera(0,scene) and frame._camera.snapshot()==view and frame._random==random_state,"Zero camera frame changed view history or consumed EMP randomness")
	var bad_scene:=scene.duplicate();bad_scene.player_pose=Transform3D(Basis.IDENTITY,Vector3(NAN,0,0))
	check(not frame._advance_follow_camera(16,bad_scene) and frame._camera.snapshot()==view and frame._random==random_state,"Rejected camera frame committed its prospective random samples")
	var expected: Dictionary=encounter.secondary_owner().evaluate_camera(random_state)
	if expected.is_empty():check(false,"Native camera fixture has no valid retained EMP commands");return
	var plain: RefCounted=frame._camera.fork_for_frame()
	if not plain.update(16,frame._shot,scene) or not frame._advance_follow_camera(16,scene):check(false,plain.error+frame.error);return
	# The earlier wrapper writes a real nonzero request, but ordinary flight
	# overwrites that field before its controller/follow-camera pass. Applying
	# the detached wrapper sample here would invent both jitter and RNG draws.
	check(expected.offset!=Vector3.ZERO and expected.random_state!=random_state,"Camera overwrite fixture did not retain an active, nonzero EMP request")
	check(frame._camera.snapshot()==plain.snapshot(),"Ordinary camera replayed the EMP write after the source vibration overwrite")
	check(frame._random==random_state,"Overwritten EMP camera write consumed extra world randomness")
	var direct: RefCounted=plain.fork_for_frame();var direct_plain: RefCounted=plain.fork_for_frame()
	if not direct_plain.update(16,frame._shot,scene) or not direct.update(16,frame._shot,scene,{},null,expected.offset):check(false,direct.error+direct_plain.error);return
	check(direct.snapshot().eye==direct_plain.snapshot().eye and direct.snapshot().pose.origin==direct_plain.snapshot().pose.origin and direct.snapshot().look.is_equal_approx(direct_plain.snapshot().look+expected.offset),"Explicit accepted camera perturbation changed the eye rather than its look-at point")
	check(frame._pose==pose and frame._player.snapshot()==native_player and frame._equipment.snapshot()==held and encounter.snapshot()==native_encounter,"Camera update changed player collision pose, ammunition or combat")
	var following: RefCounted=frame._camera.fork_for_frame();var plain_follow: RefCounted=frame._camera.fork_for_frame()
	var follow_shot: Dictionary=frame._shot.duplicate();follow_shot.mode="follow"
	if not plain_follow.update(16,follow_shot,scene) or not following.update(16,follow_shot,scene,{},null,expected.offset):check(false,plain_follow.error+following.error);return
	check(following.snapshot().eye==plain_follow.snapshot().eye and following.snapshot().look.is_equal_approx(plain_follow.snapshot().look+expected.offset),"Player-follow interpolation discarded EMP look jitter or changed the eye")
	var follow_history: Dictionary=following.snapshot()
	check(following.update(0,follow_shot,scene) and following.snapshot()==follow_history,"Zero-time follow update erased the retained perturbed look point")
	var frozen: Dictionary=frame._camera.snapshot();var sampled: Dictionary=frame._random.duplicate(true)
	check(not frame._camera.update(0,frame._shot,scene,{},null,Vector3.ONE) and frame._camera.snapshot()==frozen,"Zero-time camera accepted a new look perturbation")
	check(not frame._camera.update(16,frame._shot,scene,{},null,Vector3(NAN,0,0)) and frame._camera.snapshot()==frozen,"Invalid jitter partially changed the accepted view")
	frame._encounter.clear_secondary_events()
	check(frame._advance_follow_camera(16,scene) and frame._random==sampled,"A cue-free frame replayed an earlier camera burst")

func verify_mixed_weapon_audio(lib: RefCounted,bindings: RefCounted,frame: RefCounted) -> void:
	# Real detached primary ownership supplies the late shot. Neither weapon
	# event is hand-authored, and the accepted encounter remains unchanged.
	var primary: RefCounted=frame._encounter._primaries.fork_state()
	var wait_ms:=0
	for gun in primary.snapshot().guns:
		wait_ms=maxi(wait_ms,int(gun.projectiles.weapon.interval_ms)-int(gun.projectiles.elapsed_ms)+1)
	if primary.advance(wait_ms).is_empty():check(false,primary.error);return
	var fire: Dictionary=primary.fire(frame._pose,true,frame._random)
	if fire.is_empty():check(false,primary.error);return
	var world: Dictionary=frame._encounter.snapshot()
	world.primaries=primary.snapshot();world.primary_fire=fire;world.actor_events=[]
	var audio:=Sound.new();root.add_child(audio)
	if not audio.configure(lib,bindings,123):check(false,audio.error);audio.free();return
	var shot: Dictionary=audio.prepare_primaries(world)
	check(not shot.is_empty() and not shot.operations.is_empty(),"Mixed weapon audio fixture has no audible primary: "+str(fire.weapons)+" "+str(primary.snapshot().guns.map(func(gun):return gun.audio)))
	var before: Dictionary=audio.snapshot()
	var expected: Array=world.secondaries.detonation_audio.map(func(cue):return cue.source_id)
	if not shot.is_empty():expected.append_array(shot.operations.map(func(op):return op.source_id))
	var mixed: Dictionary=audio.prepare_combat(world,int(world.elapsed_ms))
	check(not mixed.is_empty() and mixed.operations.map(func(op):return op.source_id)==expected and audio.snapshot()==before,"Combat audio placed late primary input before the early EMP wrapper")
	audio.clear();audio.free()

func detached_encounter(bindings: RefCounted,cat: RefCounted,lib: RefCounted,built: RefCounted,views: Dictionary) -> RefCounted:
	var control:=ActorControl.new();var weapons:=NPCWeapons.new();var resources:=Resources.new()
	if not control.configure_kappa_rescue(bindings,cat,built,{"axes":[0,0],"override":-1}) or not weapons.configure_kappa_rescue(bindings,cat,built):check(false,control.error+weapons.error);return null
	if not resources.configure_kappa_rescue(lib,bindings,built) or not control.set_destruction(bindings,resources):check(false,resources.error+control.error);return null
	var group:=active_group(bindings,cat,built,0)
	if group==null:return null
	var result:=Encounter.new()
	result._identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":21}
	result._control=control;result._combat=group;result._weapons=weapons;result._resources=resources
	# Geometry and scenery are deliberately outside this component test. The
	# flight/session acceptance tests must configure their real resources.
	result._projectiles=ProjectileState.new();result._impacts=ImpactState.new()
	result._primaries=views.primaries;result._inventory=views.targets
	return result

func verify_sound(lib: RefCounted,bindings: RefCounted,state: Dictionary) -> void:
	var audio:=Sound.new();root.add_child(audio)
	if not audio.configure(lib,bindings,123):check(false,audio.error);audio.free();return
	var before: Dictionary=audio.snapshot()
	var prepared:=audio.prepare_secondaries(state)
	check(not prepared.is_empty() and prepared.operations.size()==1 and prepared.operations[0].source_id==6 and audio.snapshot()==before,"Preparing secondary audio played early or selected another sound")
	for corruption in ["source","item","position","duplicate","detonation"]:
		var bad:=state.duplicate(true)
		match corruption:
			"source":bad.secondary_events[0].audio.source_id=7
			"item":bad.secondary_events[0].item_id=42
			"position":bad.secondary_events[0].audio.position=Vector3(NAN,0,0)
			"duplicate":bad.secondary_events.append(bad.secondary_events[0].duplicate(true))
			"detonation":bad.secondary_events[0].action="detonated"
		check(audio.prepare_secondaries(bad).is_empty() and audio.snapshot()==before,"Invalid secondary sound partially played: "+corruption)
	var empty:=state.duplicate(true);empty.secondary_events=[]
	check(audio.prepare_secondaries(empty).operations.is_empty(),"A cue-free modal frame replayed the previous launch")
	audio.clear();audio.free()
