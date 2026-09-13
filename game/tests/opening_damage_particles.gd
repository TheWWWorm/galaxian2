extends SceneTree
const Particles=preload("res://src/simulation/opening_damage_particles.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Library=preload("res://src/content/library.gd")
const Definitions=preload("res://src/content/damage_particle_owner_definitions.gd")
var failures:=0
var checks:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	for index in range(0,args.size(),3):
		var library:=Library.new();var bindings:=Bindings.new()
		if not library.open(args[index]) or not bindings.open(args[index+1],library.manifest):check(false,library.error+bindings.error);continue
		var group:=Particles.new();var combat:=population(bindings)
		if bindings.damage_particles.get("owners",{}).is_empty():
			check(not group.configure(bindings,combat,42),"Legacy pack invented particle ownership")
			continue
		check(group.configure(bindings,combat,42),group.error)
		verify_transitions(group,combat,bindings.damage_particles.owners)
		verify_clock_and_reset(bindings,combat)
		verify_atomicity(bindings,combat)
		verify_root_pose(bindings,combat)
		verify_opening_release(bindings,combat)
		verify_breakup_detail(bindings,combat)
		var rules: Dictionary=bindings.damage_particles.owners.duplicate(true)
		var architecture:="x86_64" if library.manifest.profile.edition=="mac-full-hd" else "armv7"
		check(Definitions.validate(rules,100000000,architecture)=="","Source ownership failed validation")
		for key in rules.provenance:
			var changed:=rules.duplicate(true);changed.provenance[key].bytes+=1
			check(Definitions.validate(changed,100000000,architecture)!="","Changed source extent was accepted")
	print("Opening damage particles: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)

func population(bindings: RefCounted) -> Dictionary:
	var result:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"actors":[]}
	for id in 3:result.actors.append({"actor_id":id,"pose":Transform3D(Basis.IDENTITY,Vector3(id*1000,0,0)),"actor_mode":int(bindings.opening_actors.npc_initialization.holding.actor_mode),"max_hull":100,"vitals":{"hull":100}})
	return result

func events() -> Array:
	var result:=[]
	for id in 3:result.append({"actor_id":id,"decision":{"holding":true},"movement":{}})
	return result

func verify_transitions(group: RefCounted,combat: Dictionary,rules: Dictionary) -> void:
	var held:=combat.duplicate(true);held.actors[0].actor_mode=9;held.actors[0].vitals.hull=32
	check(group.advance(Transform3D.IDENTITY,1),group.error)
	check(group.finish_npc_pass(held,held,events(),1,0),group.error)
	check(group.snapshot().owners.npc0.damaged and not group.snapshot().owners.npc0.smoke.enabled,"Damaged holding actor emitted")
	var active:=held.duplicate(true);active.actors[0].actor_mode=1
	check(group.finish_npc_pass(active,active,events(),0,0),group.error)
	check(group.snapshot().owners.npc0.smoke.enabled and group.snapshot().owners.npc0.fire.enabled,"Release at zero detail omitted damaged trails")
	var healed:=active.duplicate(true);healed.actors[0].vitals.hull=34
	check(group.finish_npc_pass(healed,healed,events(),0,0),group.error)
	check(not group.snapshot().owners.npc0.damaged and not group.snapshot().owners.npc0.smoke.enabled,"Restored hull kept damage emission")
	check(group.finish_npc_pass(active,active,events(),0,0),group.error)
	check(group.snapshot().owners.npc0.smoke.enabled==not rules.npc_uses_detail_gate,"Edition-specific detail gate changed")
	# Increasing detail alone does not retrigger the already-set damaged flag.
	check(group.finish_npc_pass(active,active,events(),0,1),group.error)
	check(group.snapshot().owners.npc0.smoke.enabled==not rules.npc_uses_detail_gate,"Detail change retriggered a source transition")
	check(group.finish_npc_pass(held,held,events(),0,1),group.error)
	check(not group.snapshot().owners.npc0.smoke.enabled,"Return to holding kept emission")
	check(group.finish_npc_pass(active,active,events(),0,1),group.error)
	check(group.advance(Transform3D.IDENTITY,100),group.error)
	check(group.snapshot().births.npc0==[1,1] and group.snapshot().births.player==[0,0],"NPC activation also enabled player effects")
	var lethal:=active.duplicate(true);lethal.actors[0].vitals.hull=0
	var dead:=lethal.duplicate(true);dead.actors[0].actor_mode=3
	var event:=events();event[0].destruction=death_event("tumble",true,false)
	check(group.finish_npc_pass(lethal,dead,event,0,1),group.error)
	check(group.snapshot().owners.npc0.smoke.enabled,"Lethal damage stopped trails before breakup")
	var exploded:=dead.duplicate(true);exploded.actors[0].actor_mode=4
	event[0].destruction=death_event("explosion",false,true)
	check(group.finish_npc_pass(dead,exploded,event,0,1),group.error)
	check(not group.snapshot().owners.npc0.smoke.enabled and not group.snapshot().owners.npc0.fire.enabled,"Breakup kept emission")
	check(live(group.snapshot().owners.npc0.smoke)>0,"Stopping emission erased existing smoke")
	# A strict 33% comparison: for hull maximum 100, binary32 multiplication
	# rounds the source threshold to 33, so equality clears the flag.
	var equality:=active.duplicate(true);equality.actors[0].vitals.hull=33
	check(group.finish_npc_pass(equality,equality,events(),0,1),group.error)
	check(not group.snapshot().owners.npc0.damaged,"Threshold equality remained damaged")

func verify_clock_and_reset(bindings: RefCounted,combat: Dictionary) -> void:
	var group:=Particles.new();check(group.configure(bindings,combat,42),group.error)
	var pose:=Transform3D.IDENTITY;var initial: Dictionary=group.snapshot()
	check(group.advance(pose,0) and group.snapshot()==initial,"Zero particle time changed baselines or clocks")
	var cue:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"frame":{"ship_restore":true}}
	check(group.apply_controller(cue),group.error)
	check(group.advance(pose,3),group.error)
	check(group.snapshot().manager_ms==3 and group.snapshot().births.player==[0,0],"Fresh particle baseline created births")
	pose.origin=Vector3(0,0,100)
	check(group.advance(pose,6),group.error)
	check(group.snapshot().manager_ms==9,"Sub-ten-millisecond manager remainder was discarded")
	check(group.advance(pose,1) and group.snapshot().manager_ms==0,"Manager clock did not reset at ten milliseconds")
	check(group.advance(pose,100),group.error)
	var before: Dictionary=group.snapshot()
	check(live(before.owners.player.smoke)>0,"Restored player did not produce smoke")
	cue.frame={"world_change":{"destination":"test"}}
	check(group.apply_controller(cue),group.error)
	var reset: Dictionary=group.snapshot()
	check(reset.resets==1 and reset.manager_ms==before.manager_ms,"Relocation reset the shared manager clock")
	for key in reset.owners:
		for kind in ["smoke","fire"]:
			var a: Dictionary=before.owners[key][kind];var b: Dictionary=reset.owners[key][kind]
			check(live(b)==0 and b.dirty and b.cursor==a.cursor and b.random==a.random and b.enabled==a.enabled,"Relocation erased emitter identity, flags, ring or RNG")
	pose.origin=Vector3(500000,0,0)
	check(group.advance(pose,100),group.error)
	check(group.snapshot().births.player==[0,0] and group.snapshot().owners.player.smoke.baseline==pose.origin,"Relocation emitted a jump-length trail")
	check(group.advance(pose,100) and group.snapshot().births.player==[1,1],"Emission did not resume after relocation baseline capture")

func verify_atomicity(bindings: RefCounted,combat: Dictionary) -> void:
	var group:=Particles.new();check(group.configure(bindings,combat,42),group.error)
	var before: Dictionary=group.snapshot();var copied: Dictionary=group.snapshot()
	copied.owners.player.smoke.slots[0].appearance.age_ms=15
	check(group.snapshot()==before,"Snapshot shared live particle slots")
	check(not group.advance(Transform3D.IDENTITY,1001) and group.snapshot()==before,"Invalid time partially advanced emitters")
	var next: RefCounted=group.fork_for_frame();check(next.advance(Transform3D.IDENTITY,1),next.error)
	check(group.snapshot()==before and next.snapshot()!=before,"Fork shared particle clocks")
	var active:=combat.duplicate(true);active.actors[0].actor_mode=1;active.actors[0].vitals.hull=20
	var late:=events();late[2].movement={"root_pose":"invalid"}
	check(not group.finish_npc_pass(active,active,late,1,1) and group.snapshot()==before,"Late invalid root retained an earlier emission flag")
	var cue:={"base_content_id":"0".repeat(64),"binding_id":bindings.binding_id,"frame":{"ship_restore":true}}
	check(not group.apply_controller(cue) and group.snapshot()==before,"Foreign controller enabled particles")

func verify_root_pose(bindings: RefCounted,combat: Dictionary) -> void:
	var group:=Particles.new();check(group.configure(bindings,combat,42),group.error)
	var active:=combat.duplicate(true);active.actors[0].actor_mode=1;active.actors[0].vitals.hull=20
	var root:=Transform3D(Basis(Vector3.UP,0.2),Vector3(200,300,400))
	active.actors[0].pose=root*Transform3D(Basis(Vector3.BACK,0.7),Vector3.ZERO)
	var event:=events();event[0].movement={"root_pose":root}
	check(group.finish_npc_pass(active,active,event,1,1),group.error)
	check(group.snapshot().owners.npc0.root_pose==root,"NPC emitter inherited visual bank")
	check(group.advance(Transform3D.IDENTITY,1),group.error)
	check(group.snapshot().owners.npc0.smoke.baseline==root.origin,"Particle manager sampled another NPC root")
	var later:=root;later.origin.z+=100
	event[0].movement.root_pose=later
	check(group.finish_npc_pass(active,active,event,100,1),group.error)
	check(group.snapshot().owners.npc0.smoke.baseline==root.origin,"NPC pass advanced particle sampling a second time")

func death_event(phase: String,started: bool,breakup: bool) -> Dictionary:
	return {"state":{"phase":phase,"pose":Transform3D.IDENTITY,"spin":Vector3.ZERO},"started":started,"breakup":breakup}

func verify_opening_release(bindings: RefCounted,combat: Dictionary) -> void:
	var group:=Particles.new();check(group.configure(bindings,combat,42),group.error)
	var active:=combat.duplicate(true);active.actors[0].actor_mode=1;active.actors[0].vitals.hull=20
	check(group.finish_npc_pass(active,active,events(),0,0),group.error)
	check(group.snapshot().owners.npc0.smoke.enabled==not bindings.damage_particles.owners.npc_uses_detail_gate,"Opening mode-five activation was mistaken for mode-nine release")

func live(emitter: Dictionary) -> int:
	var count:=0
	for slot in emitter.slots:
		if slot.appearance.age_ms>=0:count+=1
	return count

func verify_breakup_detail(bindings: RefCounted,combat: Dictionary) -> void:
	var group:=Particles.new();check(group.configure(bindings,combat,42),group.error)
	var active:=combat.duplicate(true);active.actors[0].actor_mode=1;active.actors[0].vitals.hull=20
	check(group.finish_npc_pass(active,active,events(),0,1),group.error)
	var dead:=active.duplicate(true);dead.actors[0].actor_mode=3;dead.actors[0].vitals.hull=0
	var event:=events();event[0].destruction=death_event("tumble",true,false)
	check(group.finish_npc_pass(dead,dead,event,0,1),group.error)
	var exploded:=dead.duplicate(true);exploded.actors[0].actor_mode=4
	event[0].destruction=death_event("explosion",false,true)
	check(group.finish_npc_pass(dead,exploded,event,0,0),group.error)
	check(group.snapshot().owners.npc0.smoke.enabled==bindings.damage_particles.owners.npc_uses_detail_gate,"Breakup ignored its edition-specific detail gate")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
