extends SceneTree
## Mac component verification with synthetic mission cursors and lethal hits.
## Construction is source-derived; this is not a second-trip playthrough.
const Fixtures=preload("res://tests/full_hold_control.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Definitions=preload("res://src/content/full_hold_appearance_definitions.gd")
const DeathPose=preload("res://src/presentation/npc_destruction_pose.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Resources=preload("res://src/content/npc_destruction_resources.gd")
const Combat=preload("res://src/simulation/opening_combat_group.gd")
const Guns=preload("res://src/simulation/opening_npc_weapons.gd")
const NpcControl=preload("res://src/simulation/opening_npc_control.gd")
var failures:=0
var checks:=0
var fixture: SceneTree
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Full-hold appearance: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	check(bindings.source_architecture=="x86_64","This check requires Mac content")
	fixture=Fixtures.new()
	var world:=Construction.new();var resources:=Resources.new()
	if not world.prepare(bindings,cat,fixture.packet_fixture(bindings,cat,3),4096,1789100000) or not resources.configure_full_hold(lib,bindings):check(false,world.error+resources.error);fixture.free();return
	var saved: Dictionary=world.snapshot();var pair:=owners(bindings,cat,world,resources)
	var player: Dictionary=fixture.target(bindings,Vector3(123.25,-88.5,910))
	player.pose.basis=Basis.from_euler(Vector3(.3,-.6,.2))
	if bindings.full_hold_appearance.is_empty():
		check(pair.control.apply_full_hold_appearance(pair.combat,5,player).is_empty(),"Legacy bindings invented an appearance")
		fixture.free();return
	verify_contract(args,lib,bindings)
	verify_placement(bindings,pair,player,false)
	var live:=owners(bindings,cat,world,resources)
	var near: Dictionary=fixture.target(bindings,Fixtures.ORIGIN+Vector3(10000,4000,20000))
	for i in 12:
		if not step(live,150,near):fixture.free();return
	check(absf(live.control.snapshot().actors[0].flight.bank)>0.01,"Active fixture failed to establish a separate bank")
	verify_placement(bindings,live,player,true)
	verify_banked_death(bindings,cat,world,resources,near)
	verify_first_death_after_cue(bindings,cat,world,resources,player)
	for stage in ["tumble","explosion","expired","retired"]:
		for other in [false,true]:verify_restart(bindings,cat,world,resources,near,player,stage,other)
	var empty:=Construction.new()
	if not empty.prepare(bindings,cat,fixture.packet_fixture(bindings,cat,3),4096,1789100043):check(false,empty.error)
	else:verify_restart(bindings,cat,empty,resources,near,player,"retired",false)
	check(world.snapshot()==saved,"Appearance modified construction, cargo, mission or rank")
	fixture.free()

func owners(bindings: RefCounted, cat: RefCounted, world: RefCounted, resources: RefCounted) -> Dictionary:
	var c:=NpcControl.new();var body:=Combat.new();var guns:=Guns.new()
	if not c.configure_full_hold(bindings,cat,world,.5) or not c.set_full_hold_destruction(resources) or not body.configure_full_hold(bindings,cat,world,.5) or not guns.configure_full_hold(bindings,cat,world):check(false,c.error+body.error+guns.error);return {}
	return {"control":c,"combat":body,"guns":guns,"random":world.snapshot().random_state,"last":{}}

func step(pair: Dictionary, dt: int, player: Dictionary) -> bool:
	var next: Dictionary=pair.control.evaluate(pair.combat,pair.guns,dt,player,pair.random)
	if next.is_empty():check(false,"Actor pass: "+pair.control.error);return false
	pair.control=next.controller;pair.combat=next.combat;pair.guns=next.weapons;pair.random=next.random_state;pair.last=next.actors[0]
	return true

func place(pair: Dictionary, cursor: Variant, player: Dictionary) -> bool:
	var next: Dictionary=pair.control.apply_full_hold_appearance(pair.combat,cursor,player)
	if next.is_empty():check(false,"Appearance: "+pair.control.error);return false
	pair.control=next.controller;pair.combat=next.combat
	return true

func verify_placement(bindings: RefCounted, pair: Dictionary, player: Dictionary, banked: bool):
	var before: Dictionary=pair.control.snapshot();var body: Dictionary=pair.combat.snapshot();var guns: Dictionary=pair.guns.snapshot();var random: Dictionary=pair.random.duplicate()
	var held: Dictionary=pair.control.apply_full_hold_appearance(pair.combat,4,player)
	check(not held.is_empty() and not held.applied and held.controller.snapshot()==before and held.combat.snapshot()==body,"Cursor4 performed an early mission appearance")
	for cursor in [true,5.0,3,6,null]:check(pair.control.apply_full_hold_appearance(pair.combat,cursor,player).is_empty(),"Invalid mission cursor performed an appearance")
	for field in ["binding_id","base_content_id","pose","ship_id"]:
		var bad:=player.duplicate(true);bad.erase(field)
		check(pair.control.apply_full_hold_appearance(pair.combat,5,bad).is_empty(),"Incomplete appearance player accepted: "+field)
	var bad:=player.duplicate(true);bad.pose.origin.x=INF
	check(pair.control.apply_full_hold_appearance(pair.combat,5,bad).is_empty(),"Nonfinite appearance partly moved a pirate")
	check(pair.control.snapshot()==before and pair.combat.snapshot()==body and pair.guns.snapshot()==guns,"Failed appearance mutated retained owners")
	var cue: Dictionary=pair.control.apply_full_hold_appearance(pair.combat,5,player)
	if cue.is_empty():check(false,pair.control.error);return
	check(cue.applied and pair.control.snapshot()==before and pair.combat.snapshot()==body,"Successful appearance modified input owners")
	pair.control=cue.controller;pair.combat=cue.combat
	var current: Dictionary=pair.combat.snapshot().actors[0];var state: Dictionary=pair.control.snapshot()
	var expected:=Vector3(5123.25,-88.5,30910)
	var old_root: Transform3D=before.actors[0].flight.root_pose if banked else body.actors[0].pose
	check(current.position==expected and current.body_pose.origin==expected,"Authored offset rotated with the player or changed source units")
	check(current.body_pose.basis.z.is_equal_approx(Vector3(-0.000000087422776,0,-1)) and current.body_pose.basis.y==Vector3.UP,"Appearance changed binary32 pi yaw")
	check(current.pose.basis==old_root.basis,"Immediate statistics lost the pre-yaw physical root basis")
	check(current.vitals==body.actors[0].vitals and current.targeting_blocked==body.actors[0].targeting_blocked and current.nonplayer_kill==body.actors[0].nonplayer_kill,"Appearance healed or changed combat attribution/permissions")
	check(current.active and current.actor_mode==1 and current.model_draw_enabled and current.node_draw_requested,"Appearance did not request the source living model")
	check(state.appearance=={"applied":true,"pending":true} and state.actors[0].guidance==before.actors[0].guidance,"Appearance advanced guidance or lost its pending statistics copy")
	check(state.actors[0].destruction.cargo==before.actors[0].destruction.cargo and state.actors[0].destruction.effect==before.actors[0].destruction.effect and state.death_accounting==before.death_accounting,"Appearance consumed cargo, effect clocks or kill counters")
	if banked:
		for field in ["bank","target_bank","history","history_cursor","history_wrapped"]:check(state.actors[0].flight[field]==before.actors[0].flight[field],"Appearance reset active bank state: "+field)
	check(pair.guns.snapshot()==guns and pair.random==random,"Appearance advanced weapons or random state")
	var repeat: Dictionary=pair.control.apply_full_hold_appearance(pair.combat,5,player)
	check(not repeat.is_empty() and not repeat.applied and repeat.controller.snapshot()==state and repeat.combat.snapshot()==pair.combat.snapshot(),"Appearance replay teleported or reset the pirate")
	check(pair.control.apply_full_hold_appearance(pair.combat,4,player).is_empty(),"Appearance accepted a regressed mission")
	check(pair.control.evaluate(pair.combat,pair.guns,16,player,{"state":-1}).is_empty() and pair.control.snapshot()==state,"Invalid next frame consumed pending appearance state")
	if not step(pair,0,player):return
	check(not pair.control.snapshot().appearance.pending and pair.combat.snapshot().actors[0].pose==pair.control.snapshot().actors[0].flight.pose,"Next actor pass failed to copy the banked yaw pose")
	if not step(pair,150,player):return
	check(pair.combat.snapshot().actors[0].body_pose==pair.control.snapshot().actors[0].flight.root_pose and pair.combat.snapshot().actors[0].pose==pair.control.snapshot().actors[0].flight.pose,"Living actor retained a stale appearance root")

func verify_banked_death(bindings: RefCounted, cat: RefCounted, world: RefCounted, resources: RefCounted, near: Dictionary):
	var pair:=owners(bindings,cat,world,resources)
	for i in 12:
		if not step(pair,150,near):return
	var before: Dictionary=pair.control.snapshot().actors[0].flight
	check(absf(before.bank)>0.01 and before.root_pose!=before.pose,"Death fixture has no physical/statistics basis difference")
	pair.combat.normal_hit(0,50)
	if not step(pair,0,near):return
	var death: Dictionary=pair.last.destruction.state
	check(death.pose==before.root_pose and death.statistics_pose==before.pose and death.forward==before.root_pose.basis.z,"Death captured the banked mesh as its physical root")
	check(pair.control.snapshot().actors[0].flight.history==before.history,"Death discarded retained bank history")
	var preceding: Transform3D=death.pose*Transform3D(death.bank_basis,Vector3.ZERO)
	if not step(pair,16,near):return
	check(pair.last.destruction.state.statistics_pose==preceding and pair.last.destruction.state.pose!=death.pose,"Tumble lost the banked pre-motion statistics copy")

func verify_first_death_after_cue(bindings: RefCounted, cat: RefCounted, world: RefCounted, resources: RefCounted, player: Dictionary):
	var pair:=owners(bindings,cat,world,resources)
	var detached: RefCounted=pair.control.destruction_owner(0)
	var original: Dictionary=detached.snapshot()
	check(not detached.reposition_full_hold({},Transform3D.IDENTITY,Transform3D.IDENTITY) and detached.snapshot()==original,"Unverified direct placement reset death state")
	var unprepared:=NpcControl.new();unprepared.configure_full_hold(bindings,cat,world,.5)
	check(unprepared.apply_full_hold_appearance(pair.combat,5,player).is_empty(),"Appearance bypassed destruction preparation")
	if not place(pair,5,player):return
	var cued: Dictionary=pair.control.snapshot();var body: Dictionary=pair.combat.snapshot()
	var damaged: RefCounted=pair.combat.fork_for_frame();damaged._actors[0]._state.body_pose.origin.x+=1
	check(pair.control.evaluate(damaged,pair.guns,0,player,pair.random).is_empty() and pair.control.snapshot()==cued and pair.combat.snapshot()==body,"Mismatched pending root was committed")
	detached=pair.control.destruction_owner(0);original=detached.snapshot()
	check(not detached.reposition_full_hold(bindings.full_hold_appearance,Transform3D.IDENTITY,Transform3D.IDENTITY) and detached.snapshot()==original,"Repeated direct placement reset retained clocks")
	check(pair.combat.normal_hit(0,50).destroyed_now,"Synthetic post-cue lethal hit failed")
	if not step(pair,0,player):return
	check(pair.last.destruction.started and not pair.last.death_accounting.has("scripted_restart") and pair.control.snapshot().death_accounting.events.size()==1,"First post-cue death was counted as an early-death restart")

func verify_restart(bindings: RefCounted, cat: RefCounted, world: RefCounted, resources: RefCounted, near: Dictionary, player: Dictionary, stage: String, other: bool):
	var pair:=owners(bindings,cat,world,resources)
	for i in 12:
		if not step(pair,150,near):return
	check(pair.combat.normal_hit(0,50,other).destroyed_now,"Synthetic early lethal hit failed")
	if not step(pair,100,near):return
	var reached:=false
	for i in 500:
		var life: Dictionary=pair.control.snapshot().actors[0].destruction
		reached=(stage=="tumble" and life.phase=="tumble") or (stage=="explosion" and life.phase=="explosion" and life.effect.elapsed_ms>=300 and life.effect.active) or (stage=="expired" and life.phase=="explosion" and not life.effect.active) or (stage=="retired" and life.phase=="retired")
		if reached:break
		if not step(pair,150,near):return
	check(reached,"Failed to reach source lifecycle fixture "+stage)
	if not reached:return
	var before: Dictionary=pair.control.snapshot();var old: Dictionary=before.actors[0].destruction;var actor: Dictionary=pair.combat.snapshot().actors[0]
	var previous_random: Dictionary=pair.random.duplicate()
	if not place(pair,5,player):return
	var cued: Dictionary=pair.control.snapshot();var new_actor: Dictionary=pair.combat.snapshot().actors[0];var pending: Dictionary=cued.actors[0].destruction
	check(new_actor.vitals.hull==0 and new_actor.vitals==actor.vitals and new_actor.active and new_actor.actor_mode==1,"Early-death appearance healed, skipped or failed to reactivate "+stage)
	check(pending.phase=="ready" and pending.effect==old.effect and pending.cargo==old.cargo and pending.cleanup_elapsed_ms==old.cleanup_elapsed_ms,"Early-death appearance reset retained lifetime state "+stage)
	check(new_actor.pose.basis==old.pose.basis and pending.pose==new_actor.body_pose,"Early-death appearance placed from cargo statistics instead of physical hull")
	check(cued.actors[0].guidance==before.actors[0].guidance and cued.actors[0].flight.bank==before.actors[0].flight.bank and cued.actors[0].flight.history==before.actors[0].flight.history,"Early-death appearance reset selection or bank history")
	check(cued.death_accounting==before.death_accounting and pair.random==previous_random,"Cue itself granted counters or drew random values")
	var presentation:=DeathPose.for_death(pair.control.destruction_owner(0),Transform3D.IDENTITY)
	check(not presentation.has("error") and presentation.body_visible and not presentation.effect_visible,"Immediate living-mode cue drew the retained explosion")
	if not step(pair,0,player):return
	var started: Dictionary=pair.last;var life: Dictionary=started.destruction.state
	check(started.destruction.started and life.phase=="tumble" and life.effect==old.effect and life.cargo==old.cargo and life.cleanup_elapsed_ms==old.cleanup_elapsed_ms,"Reactivated death lost old effect/cargo clocks")
	check(started.death_accounting.get("scripted_restart")==true and started.death_accounting.nonplayer_kill==other,"Repeated source callback lost retained attribution")
	var totals: Dictionary=pair.control.snapshot().death_accounting
	check(totals.events.size()==2 and totals.counter_deltas.hostile_remaining==-2 and totals.counter_deltas.hostile_deaths==2 and totals.counter_deltas.player_kills==(0 if other else 2) and totals.counter_deltas.world_other_kills==(2 if other else 0),"Reactivated source counters were clamped, duplicated or misattributed")
	var banked: Transform3D=pending.pose*Transform3D(life.bank_basis,Vector3.ZERO)
	check(life.pose==pending.pose and life.statistics_pose==banked,"Restarted death used stale or twice-banked root")
	check(pair.combat.snapshot().actors[0].model_draw_enabled and not pair.combat.snapshot().actors[0].engine_draw_enabled and pair.last.firing.is_empty(),"Restarted death hid its hull, fired or retained the engine mesh")
	presentation=DeathPose.for_death(pair.control.destruction_owner(0),Transform3D.IDENTITY)
	check(not presentation.has("error") and presentation.body_visible and presentation.effect_visible==old.effect.active,"Restarted tumble lost its hull or retained explosion rendering")
	if presentation.get("effect_visible",false):check(presentation.roots[0].origin==old.effect.position,"Restarted tumble moved its older explosion with the new hull")
	var fresh: Dictionary=pair.control.apply_full_hold_appearance(pair.combat,5,player)
	check(not fresh.is_empty() and not fresh.applied,"One-time cue repeated during restarted death")
	var broke:=false
	for i in 31:
		if not step(pair,100,player):return
		check(not pair.last.has("death_accounting"),"Restarted tumble awarded another callback")
		if pair.last.destruction.breakup:broke=true;break
	check(broke,"Restarted tumble failed to break up")
	if broke:
		life=pair.last.destruction.state
		check(life.effect.elapsed_ms==old.effect.elapsed_ms and life.cleanup_elapsed_ms==old.cleanup_elapsed_ms,"Retrigger reset retained effect/cleanup time")
		for i in life.effect.models.size():check(life.effect.models[i].time_ms==old.effect.models[i].time_ms and life.effect.models[i].playing,"Retrigger reset model animation time")
		check(life.cargo.entries==old.cargo.entries and life.cargo.model_exists==life.cargo.eligible,"Retrigger changed contents or omitted the replacement container")

func verify_contract(args: PackedStringArray, lib: RefCounted, bindings: RefCounted):
	var data: Dictionary=bindings.full_hold_appearance
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	check(Definitions.validate(data,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.full_hold_story,bindings.full_hold_destruction).is_empty(),"Valid appearance declaration rejected")
	for key in Definitions.VALUES:
		var bad:=data.duplicate(true);bad[key]=null
		check(not Definitions.parameters(bad),"Changed appearance value accepted: "+key)
	for key in Definitions.SPANS:
		var bad:=data.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.full_hold_story,bindings.full_hold_destruction).is_empty(),"Changed appearance provenance accepted: "+key)
	var body: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("registrations.json")))
	var directory:=OS.get_cache_dir().path_join("gof2-full-hold-appearance-%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	for scenario in ["missing","wrong_type","changed","extent","story_absent","death_absent","empty"]:
		var changed:=body.duplicate(true);var metadata:=header.duplicate(true)
		match scenario:
			"missing":changed.erase("full_hold_appearance")
			"wrong_type":changed.full_hold_appearance=false
			"changed":changed.full_hold_appearance.offset[0]=4000
			"extent":changed.full_hold_appearance.provenance.activation.offset+=1
			"story_absent":changed.full_hold_story={}
			"death_absent":changed.full_hold_destruction={}
			"empty":changed.full_hold_appearance={}
		var serialized:=JSON.stringify(changed,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		var reader:=Bindings.new();check(reader.open(args[1],lib.manifest),reader.error)
		var accepted:=reader.open(directory,lib.manifest)
		check(accepted and reader.full_hold_appearance.is_empty() if scenario=="empty" else not accepted and reader.binding_id.is_empty() and reader.full_hold_appearance.is_empty(),"Appearance reader failure or stale data: "+scenario)
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func check(ok: bool, message: String):
	checks+=1
	if not ok:failures+=1;push_error(message)
