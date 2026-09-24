extends SceneTree
## Explicit detached encounter inputs exercise damage and actor frame ownership.
## They do not manufacture an earned loadout, campaign departure or save.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Rules=preload("res://src/content/kappa_population_definitions.gd")
const Construction=preload("res://src/simulation/opening_npc_construction.gd")
const Group=preload("res://src/simulation/opening_combat_group.gd")
const Guidance=preload("res://src/simulation/opening_npc_guidance.gd")
const ActorControl=preload("res://src/simulation/combat_training_control.gd")
const Reputation=preload("res://src/simulation/faction_reputation.gd")
const Resources=preload("res://src/content/npc_destruction_resources.gd")
const Radio=preload("res://src/simulation/radio_sequence.gd")
const RadioResources=preload("res://src/presentation/opening_radio_resources.gd")
const Rescue=preload("res://src/simulation/kappa_rescue.gd")
const Bombs=preload("res://src/simulation/emp_bombs.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected explicit content/binding/visual triples")
	for i in range(0,args.size()-2,3):verify(args[i],args[i+1])
	print("Kappa combat: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(content: String,pack: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	if not Rules.KappaLife.available(bindings):
		check(not Group.new().configure_kappa_rescue(bindings,cat,null,Reputation.initial(bindings)),"Legacy pack enabled Kappa combat")
		check(not ActorControl.new().configure_kappa_rescue(bindings,cat,null,Reputation.initial(bindings)),"Legacy pack enabled Kappa control")
		check(not Resources.new().configure_kappa_rescue(library,bindings,null),"Legacy pack enabled Kappa destruction")
		return
	var owner:=construction(bindings,cat,0.5)
	if owner==null:return
	var packet: Dictionary=owner.snapshot()
	var resources:=Resources.new();var dialogue:=RadioResources.new();var radio:=Radio.new()
	if not resources.configure_kappa_rescue(library,bindings,owner) or not library.select_language("gb") or not dialogue.prepare(library,bindings,null,21) or not radio.configure(bindings,library,dialogue.line_counts,21):check(false,resources.error+library.error+dialogue.error+radio.error);return
	check(resources.snapshot().cargo_models.size()==4 and resources.snapshot().cargo_models.all(func(model):return model.model_id==16992),"Kappa lost original Terran cargo art")
	for standing in [-100,-70,0,70,100]:
		var group:=active_group(bindings,cat,owner,standing)
		if group==null:return
		var history: Dictionary=group.snapshot().reputation
		check(history.get("kappa_rescue")==true and not history.has("spawn_generations"),"The authored rescue acquired recyclable traffic accounting")
		var restored:=Reputation.new()
		check(restored.restore(bindings,history) and restored.snapshot()==history,"Retained rescue reputation lost its encounter classification")
		for id in 4:
			var actor: Dictionary=group.snapshot().actors[id]
			check(actor.hostile==(id==0 or standing< -70) and actor.friendly==(id>0 and standing>70),"Kappa standing threshold or mission hostility changed")
	verify_reactions(bindings,cat,owner,radio)
	verify_control(bindings,cat,owner,resources,radio)
	var standard:=construction(bindings,cat,1.0)
	if standard!=null:
		var group:=active_group(bindings,cat,standard,0)
		if group!=null:
			check(not group.systems_hit(0,40).is_empty() and group.current_reputation().axes==[-2,0],"Normal difficulty incorrectly acquired the hardest-difficulty reputation multiplier")
	check(owner.snapshot()==packet,"Combat mutated retained construction or detached loadout")

func construction(bindings: RefCounted,cat: RefCounted,difficulty: float) -> RefCounted:
	var seed:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"station_id":55,"system_id":11,"ship_id":0,"equipment_ids":[22,86,81,55]}
	var context:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":21,"station_id":55,"system_id":11,"rank":0,"difficulty":difficulty,"mission_kind":4,"mission_story":true,"mission_completed":false}
	var owner:=Construction.new()
	if not owner.configure_kappa_rescue(bindings,cat,seed,context) or owner.generate({"state":42}).is_empty():check(false,owner.error);return null
	return owner

func player(bindings: RefCounted,position: Vector3) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"ship_id":0,"pose":Transform3D(Basis.IDENTITY,position),"active":true,"hull":150,"special_flight":false,"targeting_blocked":false,"alternate_position":null}

func active_group(bindings: RefCounted,cat: RefCounted,owner: RefCounted,standing: int) -> RefCounted:
	var group:=Group.new()
	if not group.configure_kappa_rescue(bindings,cat,owner,{"axes":[standing,0],"override":-1}) or not group.begin_contact_pass(owner.snapshot().random_state,true):check(false,group.error);return null
	for id in 4:
		if not group.refresh_hostility(id):check(false,group.error);return null
		var ai:=Guidance.new()
		if not ai.configure_kappa_rescue(bindings,cat,owner,id):check(false,ai.error);return null
		var actor: Dictionary=group.snapshot().actors[id]
		var decision:=ai.update(0,actor,actor.body_pose,player(bindings,actor.pose.origin+Vector3(1000,0,0)),owner.snapshot().random_state,group.snapshot().actors)
		if decision.is_empty() or not group.apply_kappa_guidance(decision):check(false,ai.error+group.error);return null
	return group

func verify_reactions(bindings: RefCounted,cat: RefCounted,owner: RefCounted,radio: RefCounted) -> void:
	var group:=active_group(bindings,cat,owner,0)
	if group==null:return
	var baseline: Dictionary=group.snapshot();var random: Dictionary=group.contact_random_state()
	var partial: Dictionary=group.systems_hit(1,13)
	if partial.is_empty():check(false,group.error);return
	check(partial.accepted and partial.after.integrity==27 and not group.snapshot().provocation.warning_issued,"EMP warning ignored its strict integer one-third boundary")
	partial=group.systems_hit(1,1)
	check(not partial.is_empty() and group.snapshot().provocation.warning_issued and group.snapshot().actors[1].forced_hostile and not group.snapshot().actors[1].script_hostile,"EMP warning failed to retain temporary force separately")
	check(group.snapshot().provocation.systems_requested_damage==[0,14,0,0] and group.snapshot().provocation.requested_damage==[0,0,0,0],"EMP and ordinary requested damage counters leaked")
	check(group.snapshot().provocation.pending_radio.is_empty() and group.contact_random_state()==random and group.current_reputation().axes==[0,0],"Partial EMP invented story radio, RNG draws or reputation")
	check(group.snapshot().actors.map(func(actor):return actor.vitals)==baseline.actors.map(func(actor):return actor.vitals),"EMP changed hull, armor or shields")
	var first: Dictionary=group.systems_hit(1,26)
	if first.is_empty():check(false,group.error);return
	check(first.disabled_now and first.first_disable_by_player and group.current_reputation().axes==[-2,0],"First depletion lost its event or faction penalty")
	check(group.snapshot().actors.all(func(actor):return actor.script_hostile and actor.hostile and actor.forced_hostile) and not group.snapshot().provocation.response_issued and not group.snapshot().provocation.station_response_flag,"EMP faction response changed persistent hostility or issued ordinary radio/station alert")
	check(not group.snapshot().actors[1].systems_disabled and group.advance_systems(1,0) and group.snapshot().actors[1].systems_disabled,"Systems radio flag updated before the actor pass")
	var retained: Dictionary=group.snapshot()
	check(not group.systems_hit(1,80).accepted and group.snapshot()==retained,"EMP depleted a zero-integrity target twice")
	if not group.advance_systems(1,1000):check(false,group.error);return
	var repeat: Dictionary=group.systems_hit(1,80)
	check(not repeat.is_empty() and not repeat.first_disable_by_player and group.current_reputation().axes==[-4,0],"Depletion during recovery lost its separate reputation change or counted a first disable")
	check(group.snapshot().provocation.systems_requested_damage[1]==40,"Persistent hostility did not bypass further reaction accumulation")
	var history:=Reputation.new()
	check(history.restore(bindings,group.snapshot().reputation) and history.apply_to({"axes":[0,0],"override":-1})==group.current_reputation(),"Retained EMP history changed standing")
	var history_before:=history.snapshot()
	check(not history.record_systems_depletion(group.snapshot().actors[1],repeat) and history.snapshot()==history_before,"The same systems hit was recorded twice")
	var corrupt:=history_before.duplicate(true);corrupt.events.append(corrupt.events[-1].duplicate())
	check(not history.restore(bindings,corrupt) and history.snapshot()==history_before,"Duplicate retained depletion changed history")
	var lethal: Dictionary=group.normal_hit(1,group.snapshot().actors[1].vitals.hull)
	check(not lethal.is_empty() and lethal.destroyed_now and group.current_reputation().axes==[-9,0],"EMP history suppressed the separate lethal-hit penalty")
	var dead_history: Dictionary=group.snapshot().reputation.duplicate(true)
	var impossible: Dictionary=dead_history.events[0].duplicate();impossible.hit_serial=100
	dead_history.events.append(impossible)
	check(not history.restore(bindings,dead_history) and history.snapshot()==history_before,"Retained history accepted systems depletion after death")
	retained=group.snapshot()
	check(group.systems_hit(-1,80).is_empty() and group.systems_hit(0,-1).is_empty() and group.systems_hit(0,80,"player").is_empty() and group.snapshot()==retained,"Invalid systems hit partially committed")
	var fork: RefCounted=group.fork_for_frame()
	check(not fork.systems_hit(0,80).is_empty() and group.snapshot()==retained,"Prospective EMP mutated retained combat")
	var script:=active_group(bindings,cat,owner,0)
	if script==null:return
	check(not script.systems_hit(0,80).is_empty() and script.current_reputation().axes==[-2,0] and script.snapshot().provocation.systems_requested_damage==[0,0,0,0] and script.snapshot().provocation.permanent_hostile==[true,false,false,false],"Mission-hostile target acquired ordinary faction reactions or lost reputation")
	var other:=active_group(bindings,cat,owner,0)
	if other==null:return
	var npc_hit: Dictionary=other.systems_hit(1,80,true)
	check(not npc_hit.is_empty() and npc_hit.accepted and not npc_hit.first_disable_by_player and other.current_reputation().axes==[0,0] and other.snapshot().provocation==baseline.provocation,"Nonplayer EMP provoked a faction or awarded player credit")
	check(not other.normal_hit(1,other.snapshot().actors[1].vitals.hull,true).is_empty() and other.current_reputation().axes==[0,0],"NPC lethal damage after disable changed player reputation")
	var normal:=active_group(bindings,cat,owner,0)
	if normal==null:return
	check(not normal.normal_hit(1,52).is_empty() and not normal.snapshot().actors[1].forced_hostile,"Ordinary retaliation ignored strict half-hull threshold")
	check(not normal.normal_hit(1,1).is_empty() and normal.snapshot().actors[1].forced_hostile and not normal.snapshot().actors[1].script_hostile,"Ordinary individual force incorrectly became persistent faction force")
	check(not normal.normal_hit(1,15).is_empty() and not normal.snapshot().provocation.response_issued,"Ordinary faction response ignored the source 0.66 threshold")
	check(not normal.normal_hit(1,1).is_empty() and normal.snapshot().provocation.response_issued and normal.snapshot().provocation.station_response_flag and normal.snapshot().actors.all(func(actor):return actor.script_hostile),"Ordinary faction response did not retain persistent force")
	check(normal.snapshot().provocation.systems_requested_damage==[0,0,0,0] and normal.snapshot().provocation.requested_damage==[0,69,0,0],"Normal damage entered the EMP counter")
	var cue_group:=active_group(bindings,cat,owner,0);var rescue:=Rescue.new()
	if cue_group==null or not rescue.configure(bindings):check(false,rescue.error);return
	if cue_group.systems_hit(1,14).is_empty() or not cue_group.refresh_hostility(1) or not rescue.advance(radio,cue_group.snapshot()) or not cue_group.apply_kappa_sequence(rescue):check(false,cue_group.error+rescue.error);return
	check(cue_group.snapshot().actors.all(func(actor):return actor.script_hostile),"Actual escort provocation did not connect the source rescue cue")
	var stale:=Group.new()
	if not stale.configure_kappa_rescue(bindings,cat,owner,{"axes":[0,0],"override":-1}):check(false,stale.error);return
	retained=stale.snapshot()
	check(stale.systems_hit(0,80).is_empty() and stale.snapshot()==retained,"EMP accepted a missing world random state")

func verify_control(bindings: RefCounted,cat: RefCounted,owner: RefCounted,resources: RefCounted,radio: RefCounted) -> void:
	var control:=ActorControl.new()
	if not control.configure_kappa_rescue(bindings,cat,owner,{"axes":[0,0],"override":-1}) or not control.set_destruction(bindings,resources):check(false,control.error);return
	var dormant: Dictionary=control.snapshot();var target:=player(bindings,dormant.combat.actors[0].body_pose.origin+Vector3(0,0,-10000))
	if control.advance(0,target).is_empty():check(false,control.error);return
	check(control.snapshot().combat.actors[0].active,"Actual actor pass did not proximity-activate the target")
	var combat: RefCounted=control.combat_owner()
	var bombs:=Bombs.new()
	if not bombs.configure(bindings,cat,41,[22,86,81,55,41]):check(false,bombs.error);return
	var candidates: Array=combat.snapshot().actors.map(func(row):return {"actor_id":row.actor_id,"position":row.position,"active":row.active,"emp_immune":row.scenery})
	var muzzle:=Transform3D(Basis.IDENTITY,combat.snapshot().actors[0].position-Vector3(0,0,400))
	if bombs.advance(1,candidates).is_empty() or bombs.trigger(muzzle,1,candidates).get("action")!="launched":check(false,bombs.error);return
	var pulse:=bombs.trigger(muzzle,0,candidates)
	if pulse.is_empty():check(false,bombs.error);return
	check(pulse.action=="detonated" and pulse.blast.hits.size()==1 and pulse.blast.hits[0].actor_id==0,"Actual EMP pulse did not select the active rescue target")
	if not combat.begin_contact_pass(control.snapshot().random_state,true):check(false,combat.error);return
	for hit in pulse.blast.hits:
		if combat.systems_hit(hit.actor_id,hit.system_damage).is_empty():check(false,combat.error);return
	var before: Dictionary=combat.snapshot().actors[0]
	var first: Dictionary=control.advance(0,target,combat,combat.contact_random_state())
	if first.is_empty():check(false,control.error);return
	check(control.snapshot().combat.actors[0].systems_disabled and control.snapshot().accounting.events.is_empty(),"EMP actor pass lost the disabled flag or counted a death")
	var turning: RefCounted=control.fork_for_frame()
	var offset:=player(bindings,before.position+Vector3(10000,0,-10000))
	for frame in 3:
		if turning.advance(100,offset).is_empty():check(false,turning.error);return
	var banked: Dictionary=turning.snapshot()
	check(banked.flight[0].pose!=banked.combat.actors[0].pose and banked.combat.actors[0].pose==before.pose and banked.combat.actors[0].body_pose==before.body_pose,"Disabled turning lost visual banking or moved collision statistics")
	var firing:=0
	for ms in range(0,15000,100):
		var step:=control.advance(100,target)
		if step.is_empty():check(false,control.error);return
		firing+=step.firing_requests.filter(func(event):return event.actor_id==0).size()
	var state: Dictionary=control.snapshot();var actor: Dictionary=state.combat.actors[0]
	check(actor.body_pose==before.body_pose and actor.pose==before.pose and actor.systems.integrity==40 and actor.systems.disabled and actor.systems_disabled,"Disabled flight moved its root/statistics or recovered at equality")
	check(firing>0 and state.accounting.events.is_empty() and actor.vitals==before.vitals,"EMP suppressed source firing desire or granted damage/kill credit")
	for i in 4:
		if control.advance(100,target).is_empty():check(false,control.error);return
	actor=control.snapshot().combat.actors[0]
	check(not actor.systems.disabled and not actor.systems_disabled and actor.body_pose!=before.body_pose,"Systems recovery failed to resume normal movement")
	var retained: Dictionary=control.snapshot()
	check(control.advance(load("res://src/simulation/frame_clock.gd").simulation_limit(bindings)+1,target).is_empty() and control.snapshot()==retained,"Overlong actor frame partially committed")
	combat=control.combat_owner()
	if not combat.begin_contact_pass(retained.random_state,true) or combat.normal_hit(0,actor.vitals.hull).is_empty():check(false,combat.error);return
	var rescue:=Rescue.new()
	if not rescue.configure(bindings) or not rescue.advance(radio,combat.snapshot()):check(false,rescue.error);return
	check(not rescue.snapshot().failure_ready,"Zero hull failed rescue before original retirement")
	if control.advance(0,target,combat,combat.contact_random_state()).is_empty():check(false,control.error);return
	var times:=0
	while control.snapshot().combat.actors[0].actor_mode!=4 and times<20000:
		if control.advance(100,target).is_empty():check(false,control.error);return
		times+=100
	state=control.snapshot()
	if not rescue.advance(radio,state.combat):check(false,rescue.error);return
	check(state.combat.actors[0].actor_mode==4 and rescue.snapshot().failure_ready and state.accounting.events.size()==1,"Original breakup did not retire the target and enable rescue failure exactly once")
	check(state.destruction[0].cargo.model_id==16992 and state.combat.current_reputation.axes==[-7,0] and state.defeat_status.is_empty(),"Kappa death changed faction cargo, reputation or invented success")
	var counters: Dictionary=state.accounting
	if control.advance(100,target).is_empty():check(false,control.error);return
	check(control.snapshot().accounting==counters,"Retired target counted its death twice")
	print("Kappa disabled firing requests: ",firing,"; target retirement: ",times,"ms")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
