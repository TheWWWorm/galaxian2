extends SceneTree
## Isolated device/observation fixtures using real catalogue rows. No fixture is
## a career save, earned equipment transaction or supported campaign checkpoint.
const Recovery=preload("res://src/simulation/tractor_recovery.gd")
const Definitions=preload("res://src/content/tractor_recovery_definitions.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Frames=preload("res://src/simulation/frame_clock.gd")
const Cargo=preload("res://src/simulation/flight_cargo.gd")
class ComponentBindings extends RefCounted:
	var base_content_id:=""
	var binding_id:=""
	var mido_travel:={}
	var frame_clock:={}
	var fast_forward:={}
var checks:=0
var failures:=0
var rules: RefCounted
var cat: RefCounted

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:check(false,"Expected an identified content/binding/visual triple")
	else:
		var library:=Library.new();var source:=Bindings.new();cat=Catalogues.new()
		if not library.open(args[0]) or not source.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+source.error+cat.error)
		else:
			rules=ComponentBindings.new();rules.base_content_id=source.base_content_id
			rules.binding_id=("tractor isolated component "+source.binding_id).sha256_text()
			rules.mido_travel={"tractor_recovery":Definitions.VALUES.duplicate(true)}
			rules.frame_clock=source.frame_clock.duplicate(true);rules.fast_forward=source.fast_forward.duplicate(true)
			verify_equipment();verify_acquisition();verify_pull();verify_transfers();verify_rollback();verify_retained_cargo();verify_scenery_clock_independence()
	print("Tractor recovery: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func identity() -> Dictionary:return {"base_content_id":rules.base_content_id,"binding_id":rules.binding_id}
func loadout(ids: Array) -> Dictionary:
	var value:=identity();value.merge({"ship_id":0,"equipment_ids":ids.duplicate()});return value
func owner(ids: Array=[68,81]) -> RefCounted:
	var value:=Recovery.new();check(value.configure(rules,cat,loadout(ids)),value.error);return value
func player(autopilot:=false) -> Dictionary:
	var value:=identity();value.merge({"pose":Transform3D.IDENTITY,"autopilot":autopilot});return value
func actor(id:=0,position:=Vector3(0,0,1300)) -> Dictionary:
	var value:=identity()
	value.merge({"actor_id":id,"actor_mode":4,"actor_kind":8,"hull":0,"active":true,"cargo_eligible":true,
		"cargo_model_exists":true,"retire_on_transfer":false,"statistics_exempt":false,"body_motion_blocked":false,
		"body_motion_detached":false,"friendly":false,"special_cargo":false,
		"body_pose":Transform3D(Basis.IDENTITY,position+Vector3(10,20,30)),"cargo_pose":Transform3D(Basis.IDENTITY,position),
		"cargo_entries":[{"item_id":118,"quantity":5},{"item_id":112,"quantity":7}],"collision_centers":[Vector3i(1,-1,2)]})
	return value
func hold(capacity:=20,used:=0,entries: Array=[]) -> Dictionary:
	var value:=identity();value.merge({"capacity":capacity,"used":used,"entries":entries.duplicate(true)});return value
func marker(id:=0,pixel:=Vector2i(500,400),mode:=4) -> Dictionary:
	var value:=identity()
	value.merge({"actor_id":id,"actor_mode":mode,"active":true,"cargo_eligible":mode in [3,4],"excluded":false,
		"scan_blocked":false,"priority":false,"pixels":pixel,"in_view":true});return value
func gates() -> Dictionary:
	var value:=identity()
	value.merge({"enabled":true,"guidance_active":false,"alternate_operation_active":false,"mining_approach_active":false,
		"alternate_approach_active":false,"autopilot":false,"other_target_selected":false,"ordinary_scan_enabled":true,
		"ordinary_scan_blocked":false,"aim_pixels":Vector2(500,400),"viewport_size":Vector2i(900,800)})
	return value
func apply_actor(before: Dictionary,changes: Dictionary) -> Dictionary:
	var value:=before.duplicate(true);value.merge(changes.duplicate(true),true);return value
func pickup(ship: Dictionary,cargo: Dictionary) -> Dictionary:
	var tractor:=owner()
	if not tractor.queue_acquired_wreck(ship) or not tractor.advance(0,player(),ship,cargo) or not tractor.advance(0,player(),ship,cargo):check(false,tractor.error);return {}
	return tractor.snapshot().frame
func kind_events(events: Array,kind: String) -> Array:return events.filter(func(event):return event.kind==kind)

func verify_equipment() -> void:
	var absent:=owner([90,81])
	check(absent.snapshot().equipment_id==-1 and not absent.queue_acquired_wreck(actor()),"Starter drill/scanner silently granted a tractor")
	check(absent.acquire(1,[marker()],gates()) and absent.snapshot().request_actor_id==-1 and absent.snapshot().frame.events==[{"kind":"notification","source_id":9,"actor_id":0}],"Missing tractor lost source notification or acquired cargo")
	for vector in [[68,0,4000,14232],[69,0,1800,14233],[70,1,0,14234],[194,2,0,14235]]:
		var device:=owner([vector[0],81]);var state: Dictionary=device.snapshot()
		check([state.equipment_id,state.mode,state.duration_ms,state.beam.model_id]==vector,"Original tractor catalogue mode/duration/model changed")
	var first:=owner([69,68,81])
	check(first.snapshot().equipment_id==69,"Equipment lookup did not retain the first matching installed slot")
	var before: Dictionary=first.snapshot();var wrong:=loadout([68,81]);wrong.ship_id=44
	check(not first.configure(rules,cat,wrong) and first.snapshot()==before,"Unsupported hull partly reconfigured tractor")
	wrong=loadout([68,81]);wrong.binding_id="0".repeat(64)
	check(not first.configure(rules,cat,wrong) and first.snapshot()==before,"Cross-identity loadout was accepted")
	var definition: Dictionary=rules.mido_travel.tractor_recovery.duplicate(true)
	rules.mido_travel.tractor_recovery.pull.distance=401
	check(not first.configure(rules,cat,loadout([68,81])) and first.snapshot()==before,"Unproved pickup radius was accepted")
	rules.mido_travel.tractor_recovery=definition

func verify_acquisition() -> void:
	var tractor:=owner();var context:=gates();var row:=marker()
	for ignored in 40:
		if not tractor.acquire(100,[row],context):check(false,tractor.error);return
	check(tractor.snapshot().elapsed_ms==4000 and tractor.snapshot().request_actor_id==-1,"Exact acquisition duration completed early")
	check(tractor.acquire(1,[row],context) and tractor.snapshot().request_actor_id==0 and tractor.snapshot().elapsed_ms==0,"Strict acquisition completion was lost")
	check(not tractor.snapshot().active,"HUD request advanced the player tractor in the same phase")
	tractor=owner();row.pixels=Vector2i(450,400)
	check(tractor.acquire(150,[row],context) and tractor.snapshot().candidate_actor_id==-1,"Lower scan-window equality was accepted")
	row.pixels=Vector2i(550,400)
	check(tractor.acquire(150,[row],context) and tractor.snapshot().candidate_actor_id==-1,"Upper scan-window equality was accepted")
	row=marker();check(tractor.acquire(150,[row],context),tractor.error)
	check(tractor.acquire(100,[marker(1)],context) and tractor.snapshot().elapsed_ms==100,"Candidate change retained the previous acquisition clock")
	row.in_view=false
	check(tractor.acquire(150,[row],context) and tractor.snapshot().elapsed_ms==0,"Aim loss did not clear the unqueued cargo clock")
	tractor=owner([68]);check(tractor.acquire(150,[marker()],context) and tractor.snapshot().candidate_actor_id==-1,"Ship tractor acquisition bypassed missing scanner")
	tractor=owner([70,81]);row=marker(2,Vector2i(10,10))
	check(tractor.acquire(0,[row],context) and tractor.snapshot().request_actor_id==2,"Visible-auto mode incorrectly required the center window")
	tractor=owner([70,81]);row.in_view=false
	check(tractor.acquire(150,[row],context) and tractor.snapshot().request_actor_id==-1,"Visible-auto mode acquired an offscreen wreck")
	tractor=owner([194,81]);context.guidance_active=true
	check(tractor.acquire(0,[row],context) and tractor.snapshot().request_actor_id==2,"All-direction auto mode lost its offscreen/guidance branch")
	tractor=owner([70,81]);context=gates()
	check(tractor.acquire(150,[marker(7,Vector2i(500,400),0),marker(3)],context) and tractor.snapshot().request_actor_id==-1 and tractor.snapshot().frame.ordinary_candidate_actor_id==7,"A later automatic wreck stole an earlier ordinary candidate")
	tractor=owner([194,81])
	check(tractor.acquire(150,[marker(7,Vector2i(500,400),0),marker(3)],context) and tractor.snapshot().request_actor_id==3,"Mode2 did not preserve its independent request priority")
	for device in [68,70,194]:
		tractor=owner([device,81])
		check(tractor.acquire(150,[marker(0,Vector2i(500,400),3)],context) and tractor.snapshot().request_actor_id==-1 and tractor.snapshot().candidate_actor_id==-1,"NPC acquisition pulled a still-tumbling actor")
	for gate in ["enabled","guidance_active","alternate_operation_active","mining_approach_active","alternate_approach_active","autopilot","other_target_selected"]:
		tractor=owner();context=gates();context[gate]=false if gate=="enabled" else true
		check(tractor.acquire(150,[marker()],context) and tractor.snapshot().elapsed_ms==0,"Acquisition ignored gate "+gate)
	tractor=owner();context=gates();check(tractor.acquire(100,[marker(9),marker(1)],context),tractor.error)
	check(tractor.snapshot().candidate_actor_id==9,"NPC cargo targeting sorted IDs or chose a nearest target")
	var invalid:=marker(2);invalid.active="bad";var before: Dictionary=tractor.snapshot()
	check(not tractor.acquire(100,[marker(3),invalid],context) and tractor.snapshot()==before,"Invalid late target partly changed acquisition")

func verify_pull() -> void:
	var tractor:=owner();var ship:=actor();var cargo:=hold();var original:=ship.duplicate(true)
	check(tractor.queue_acquired_wreck(ship) and tractor.advance(150,player(),ship,cargo),tractor.error)
	check(tractor.snapshot().frame.phase=="started" and tractor.snapshot().frame.actor_changes.is_empty() and tractor.snapshot().beam.animation_elapsed_ms==0 and ship==original,"Start frame moved/picked cargo or mutated observations")
	check(tractor.advance(150,player(true),ship,cargo),tractor.error)
	var frame: Dictionary=tractor.snapshot().frame
	check(frame.phase=="pulling" and frame.actor_changes.cargo_pose.origin==Vector3(0,0,-200) and tractor.snapshot().beam.scale==Vector3(.5,.5,1300),"Pull clamped overshoot or used post-motion beam depth")
	check(frame.actor_changes.body_pose.origin==Vector3(10,20,-170) and not frame.actor_changes.has("statistics_pose"),"Pull lost physical hull/statistics separation")
	check(kind_events(frame.events,"sound")==[{"kind":"sound","source_id":0}],"Pull loop did not start once")
	ship=apply_actor(ship,frame.actor_changes)
	check(tractor.advance(0,player(true),ship,cargo) and tractor.snapshot().frame.phase=="pickup","Continuing autopilot blocked an already active tractor")
	check(tractor.snapshot().frame.events.slice(-2)==[{"kind":"stop_sound","source_id":0},{"kind":"sound","source_id":4}],"Pickup audio order changed")
	tractor=owner();ship=actor(0,Vector3(300,400,1200))
	check(tractor.queue_acquired_wreck(ship) and tractor.advance(7,player(),ship,cargo) and tractor.advance(7,player(),ship,cargo),tractor.error)
	frame=tractor.snapshot().frame
	check(frame.actor_changes.cargo_pose.origin==Vector3(283.8461608886719,378.4615478515625,1135.3846435546875),"Pull changed independently derived binary32 coordinates")
	check(frame.actor_changes.collision_centers==[Vector3i(-15,-22,-62)],"Collision-box translation changed signed truncation")
	ship=apply_actor(ship,frame.actor_changes)
	check(tractor.advance(0,player(),ship,cargo) and tractor.snapshot().frame.events.is_empty(),"Zero-time continuing pull restarted its loop")
	tractor=owner();ship=actor();ship.cargo_model_exists=false;ship.actor_kind=9
	check(tractor.queue_acquired_wreck(ship) and tractor.advance(100,player(),ship,cargo),tractor.error)
	frame=tractor.snapshot().frame
	check(frame.actor_changes.cargo_model_id==16916 and frame.actor_changes.cargo_pose==Transform3D(Basis.IDENTITY,ship.body_pose.origin) and frame.actor_changes.statistics_pose==frame.actor_changes.cargo_pose,"Missing model recreation lost source kind/pose/statistics binding")
	check(tractor.advance(100,player(),ship,cargo) and tractor.snapshot().frame.phase=="cancelled" and not tractor.snapshot().active,"Continuing missing model failed to cancel")
	tractor=owner();ship=actor();check(tractor.queue_acquired_wreck(ship),tractor.error)
	check(tractor.advance(0,player(true),ship,cargo) and tractor.snapshot().frame.phase=="cancelled" and tractor.snapshot().request_actor_id==-1,"Autopilot failed to reject a new request")
	for exempt in [false,true]:
		tractor=owner();ship=actor();check(tractor.queue_acquired_wreck(ship) and tractor.advance(0,player(),ship,cargo),tractor.error)
		ship.active=false;ship.statistics_exempt=exempt
		check(tractor.advance(1,player(),ship,cargo) and tractor.snapshot().frame.phase==("pulling" if exempt else "cancelled"),"Statistics-exemption continuation gate changed")
	for gate in ["body_motion_blocked","body_motion_detached"]:
		tractor=owner();ship=actor();ship[gate]=true
		check(tractor.queue_acquired_wreck(ship) and tractor.advance(0,player(),ship,cargo) and tractor.advance(1,player(),ship,cargo),tractor.error)
		check(not tractor.snapshot().frame.actor_changes.has("body_pose") and tractor.snapshot().frame.actor_changes.has("cargo_pose"),"Cargo/body translation exclusion changed")
	tractor=owner();ship=actor();ship.actor_mode=0
	check(not tractor.queue_acquired_wreck(ship),"Living theft became an ordinary wreck request")
	tractor=owner();ship=actor(0,Vector3(0,0,400.000030517578125))
	check(tractor.queue_acquired_wreck(ship) and tractor.advance(0,player(),ship,cargo) and tractor.advance(0,player(),ship,cargo) and tractor.snapshot().frame.phase=="pulling","Distance immediately above400 picked up early")

func verify_transfers() -> void:
	var ship:=actor(0,Vector3(0,0,400));var cargo:=hold(2)
	ship.cargo_entries.push_front({"item_id":111,"quantity":0})
	var original:=ship.duplicate(true);var original_hold:=cargo.duplicate(true)
	var frame:=pickup(ship,cargo)
	if frame.is_empty():return
	var plan: Dictionary=frame.transfer
	check(plan.item_id==118 and plan.quantity==2 and plan.accepted_quantity==2 and plan.remaining_entries==[{"item_id":111,"quantity":0},{"item_id":118,"quantity":3},{"item_id":112,"quantity":7}],"Transfer did not use only first positive row and available capacity")
	check(plan.inventory_entries==[{"item_id":118,"quantity":2}] and plan.used==2 and plan.refresh_used,"Ordinary first stack failed to recalculate hold")
	check(kind_events(plan.events,"world_cargo_quantity")==[{"kind":"world_cargo_quantity","quantity":2}],"Condition22 counted attempted quantity or containers")
	check(not frame.actor_changes.cargo_eligible and not frame.actor_changes.cargo_model_exists and frame.actor_changes.active,"Transfer did not retire access to remaining cargo while retaining active stats")
	check(ship==original and cargo==original_hold,"Transfer mutated public actor/hold input")
	for used in [2,3]:
		frame=pickup(ship,hold(2,used,[{"item_id":118,"quantity":used}]))
		check(frame.transfer.quantity==1 and frame.transfer.accepted_quantity==0 and frame.transfer.remaining_entries[1].quantity==4 and frame.transfer.used==used,"Full/overfull hold did not lose exactly one wreck unit")
		check(kind_events(frame.events,"world_cargo_quantity").is_empty() and kind_events(frame.events,"cargo_notification")[0].rejected,"Rejected capacity transfer emitted accepted cargo progress")
	ship.retire_on_transfer=true
	check(not pickup(ship,cargo).actor_changes.active,"Retirement-ready wreck remained active after transfer")
	ship=actor(0,Vector3.ZERO);ship.actor_mode=3
	check(pickup(ship,cargo).transfer.accepted_quantity==2,"Already source-acquired dying wreck transfer was rejected")
	var fast_item:=-1
	for item in cat.tables.items:
		if item.properties.get(1)==1:fast_item=int(item.id);break
	check(fast_item>=0,"Catalogue lacks source fast-stack item kind")
	ship.cargo_entries=[{"item_id":fast_item,"quantity":4}]
	cargo=hold(100,5,[{"item_id":fast_item,"quantity":2},{"item_id":fast_item,"quantity":3}])
	frame=pickup(ship,cargo);plan=frame.transfer
	check(plan.matching_indices==[0,1] and plan.inventory_entries==[{"item_id":fast_item,"quantity":6},{"item_id":fast_item,"quantity":7}] and plan.used==5 and not plan.refresh_used and plan.accepted_quantity==4,"Fast-stack all-match/cache semantics changed")
	ship.cargo_entries=[{"item_id":118,"quantity":4}]
	cargo=hold(100,5,[{"item_id":118,"quantity":2},{"item_id":118,"quantity":3}])
	plan=pickup(ship,cargo).transfer
	check(plan.matching_indices==[0] and plan.inventory_entries==[{"item_id":118,"quantity":6},{"item_id":118,"quantity":3}] and plan.used==9 and plan.refresh_used,"Ordinary merge lost first-match order or cache refresh")
	ship.actor_kind=9;plan=pickup(ship,hold()).transfer
	check(kind_events(plan.events,"world_cargo_quantity").size()==1 and kind_events(plan.events,"kind9_cargo_quantity").size()==1,"Kind9's separate quantity replaced the world count")
	ship.actor_kind=8;ship.cargo_entries=[{"item_id":132,"quantity":1}]
	check(kind_events(pickup(ship,hold()).events,"item_recovery_flag")==[{"kind":"item_recovery_flag","index":0}],"Source item flag range was dropped or relabelled")
	ship.actor_kind=3;ship.friendly=true;ship.special_cargo=true;ship.cargo_entries=[{"item_id":116,"quantity":1}]
	plan=pickup(ship,hold(0)).transfer
	check(plan.events[0].kind=="friendly_cargo_taken" and plan.events[1].kind=="faction_cargo_taken" and kind_events(plan.events,"special_cargo_rejected").size()==1,"Capacity failure lost preceding friendly/faction or special-actor effects")
	plan=pickup(ship,hold()).transfer
	check(kind_events(plan.events,"special_cargo_accepted").size()==1 and kind_events(plan.events,"cargo_notification")[0].special and plan.created_item_flag and plan.new_entry_index==0,"Special accepted cargo did not retain its separate flag")
	check(plan.inventory_entries==[{"item_id":116,"quantity":1,"mission":true}],"The newly copied source item lost the shared mission-item flag")
	plan=pickup(ship,hold(10,1,[{"item_id":116,"quantity":1}])).transfer
	check(plan.created_item_flag and plan.new_entry_index==-1 and plan.matching_indices==[0],"Special copied-item flag was attached to a pre-existing merged stack")
	check(not plan.inventory_entries[0].has("mission"),"Merging special cargo incorrectly marked the existing inventory row")

func component_cargo(capacity: int,used: int,entries: Array) -> RefCounted:
	# Isolated owner composition using the explicit synthetic identity above.
	# This is not a career, an equipped player or an earned gameplay fixture.
	var result:=Cargo.new();result._state=hold(capacity,used,entries);result._state.ship_id=0
	result._item_count=cat.tables.items.size();result._equipment_ids=[68,81]
	result._recovery_cargo_ids=[116,117]
	return result

func stage_pickup(tractor: RefCounted,ship: Dictionary,cargo: RefCounted) -> RefCounted:
	var next: RefCounted=tractor.fork_for_frame()
	if not next.queue_acquired_wreck(ship) or not next.advance(0,player(),ship,cargo.snapshot()) or not next.advance(0,player(),ship,cargo.snapshot()):check(false,next.error);return null
	return next

func verify_retained_cargo() -> void:
	var fast_item:=-1
	for item in cat.tables.items:
		if item.properties.get(1)==1:fast_item=int(item.id);break
	if fast_item<0:check(false,"No source fast-stack item");return
	var cargo:=component_cargo(25,5,[{"item_id":fast_item,"quantity":2},{"item_id":fast_item,"quantity":3}])
	var tractor:=owner();var ship:=actor(0,Vector3.ZERO);ship.cargo_entries=[{"item_id":fast_item,"quantity":4}]
	var before: Dictionary=cargo.snapshot()
	check(cargo.bind_recovery(tractor),cargo.error)
	check(not cargo.bind_recovery(tractor),"A bound cargo history could be reset")
	var pickup_owner:=stage_pickup(tractor,ship,cargo)
	if pickup_owner==null:return
	var next: RefCounted=cargo.fork_for_frame()
	check(next.retain_recovery(pickup_owner),next.error)
	check(next.snapshot().entries==[{"item_id":fast_item,"quantity":6},{"item_id":fast_item,"quantity":7}] and next.snapshot().used==5 and next.snapshot().free_space==20,"The native hold normalized the original all-match stale cache")
	check(cargo.snapshot()==before and tractor.snapshot().transfer_serial==0,"Prospective recovery mutated an accepted parent")
	var accepted: Dictionary=next.snapshot()
	check(not next.retain_recovery(pickup_owner) and next.snapshot()==accepted,"Replaying a tractor sample duplicated recovered cargo")
	var forged: Dictionary=pickup_owner.snapshot();forged.frame.transfer.inventory_entries[0].quantity=99
	check(next.snapshot()==accepted and pickup_owner.snapshot().frame.transfer.inventory_entries[0].quantity==6,"A public transfer snapshot changed the retained hold or owner")
	var replacement:=owner();var other:=stage_pickup(replacement,ship,cargo)
	check(other!=null and not cargo.fork_for_frame().retain_recovery(other),"An identically configured replacement tractor borrowed the accepted history")
	var wrong: RefCounted=cargo.fork_for_frame();check(wrong.add_entries([{"item_id":118,"quantity":1}]),wrong.error)
	var wrong_before: Dictionary=wrong.snapshot()
	check(not wrong.retain_recovery(pickup_owner) and wrong.snapshot()==wrong_before,"A transfer prepared before another inventory change overwrote that change")
	ship=actor(1,Vector3.ZERO);ship.cargo_entries=[{"item_id":118,"quantity":1}]
	var ordinary:=stage_pickup(pickup_owner,ship,next)
	if ordinary==null:return
	check(next.retain_recovery(ordinary) and next.snapshot().used==14 and next.snapshot().free_space==11,"Ordinary recovery did not refresh the source cache after the earlier fast merge")
	var full:=component_cargo(1,1,[{"item_id":118,"quantity":1}]);var full_tractor:=owner()
	check(full.bind_recovery(full_tractor),full.error)
	ship=actor(0,Vector3.ZERO);var rejected:=stage_pickup(full_tractor,ship,full)
	if rejected==null:return
	var full_before: Dictionary=full.snapshot()
	check(rejected.snapshot().frame.transfer.accepted_quantity==0 and full.retain_recovery(rejected) and full.snapshot()==full_before,"Capacity rejection changed inventory or could not consume its native transfer")
	check(not full.retain_recovery(rejected) and full.snapshot()==full_before,"A quantity-zero pickup could replay because the hold was unchanged")
	var special:=component_cargo(25,0,[]);var special_tractor:=owner();check(special.bind_recovery(special_tractor),special.error)
	ship=actor(0,Vector3.ZERO);ship.special_cargo=true;ship.cargo_entries=[{"item_id":116,"quantity":1}]
	var marked:=stage_pickup(special_tractor,ship,special)
	if marked==null:return
	check(special.retain_recovery(marked) and special.snapshot().entries==[{"item_id":116,"quantity":1,"mission":true}],"The native hold dropped a newly recovered source-protected item")
	var unequal:=component_cargo(25,0,[]);unequal._equipment_ids=[90,81]
	check(not unequal.bind_recovery(owner()),"Cargo bound a tractor absent from its retained equipment")
	var reset:=owner();var bound:=component_cargo(25,0,[]);check(bound.bind_recovery(reset),bound.error)
	reset.clear();check(not bound.retain_recovery(reset),"Clearing a tractor retained its old transfer authority")

func verify_rollback() -> void:
	var tractor:=owner();var ship:=actor(0,Vector3.ZERO);var cargo:=hold()
	check(tractor.queue_acquired_wreck(ship) and tractor.advance(0,player(),ship,cargo),tractor.error)
	var parent: Dictionary=tractor.snapshot();var branch: RefCounted=tractor.fork_for_frame();var nested: RefCounted=branch.fork_for_frame()
	var bad:=cargo.duplicate(true);bad.entries=[{"item_id":233,"quantity":1}]
	check(not branch.advance(100,player(),ship,bad) and branch.snapshot()==parent and tractor.snapshot()==parent,"Late pickup failure partly committed animation/target state")
	check(branch.advance(0,player(),ship,cargo) and tractor.snapshot()==parent and nested.snapshot()==parent,"Fork pickup mutated parent or sibling")
	var child: Dictionary=branch.snapshot();check(tractor.advance(1,player(),ship,cargo) and branch.snapshot()==child,"Parent pickup mutated existing child")
	var public: Dictionary=branch.snapshot();public.frame.transfer.inventory_entries.clear();public.frame.actor_changes.cargo_entries.clear();public.beam.scale.x=99
	check(branch.snapshot()==child,"Public tractor snapshot exposed mutable transaction aliases")
	check(not nested.advance(Frames.simulation_limit(rules)+1,player(),ship,cargo) and nested.snapshot()==parent,"Invalid frame duration changed retained tractor")
	bad=ship.duplicate(true);bad.actor_id=1
	check(not nested.advance(0,player(),bad,cargo) and nested.snapshot()==parent,"Different actor replaced the retained request")
	var huge:=hold(2147483647,0,[{"item_id":118,"quantity":2147483647}])
	check(not nested.advance(100,player(),ship,huge) and nested.snapshot()==parent,"Stack overflow partly committed a pickup")
	check(nested.advance(0,player(),ship,cargo),nested.error)
	var changed:=apply_actor(ship,nested.snapshot().frame.actor_changes)
	check(not nested.queue_acquired_wreck(changed),"Remaining rows recreated already-consumed wreck access")
	tractor.clear();check(branch.snapshot()==child and tractor.snapshot().is_empty(),"Clear mutated a retained fork")
	check(tractor.configure(rules,cat,loadout([70,81])) and branch.snapshot()==child,"Reconfigure mutated a retained fork")

func verify_scenery_clock_independence() -> void:
	var tractor:=owner([69,81])
	check(tractor.acquire(100,[marker(3)],gates()),tractor.error)
	var before: Dictionary=tractor.snapshot()
	var scenery:=actor(0,Vector3.ZERO);scenery.target_group="scenery"
	check(tractor.queue_acquired_wreck(scenery) and tractor.snapshot().candidate_actor_id==3 and tractor.snapshot().elapsed_ms==100,"A scenery request replaced the independent NPC candidate or clock")
	check(tractor.advance(0,player(),scenery,hold()) and tractor.advance(0,player(),scenery,hold()),tractor.error)
	check(tractor.snapshot().frame.phase=="pickup" and tractor.snapshot().candidate_actor_id==before.candidate_actor_id and tractor.snapshot().elapsed_ms==before.elapsed_ms,"Finishing scenery recovery discarded an unrelated NPC acquisition")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
