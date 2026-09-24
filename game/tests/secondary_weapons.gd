extends "res://tests/kappa_combat.gd"
## Detached equipment cases share actual generated Kappa targets. They neither
## fit a player's ship nor create campaign progress or an earned save.
const Ownership=preload("res://src/simulation/secondary_weapons.gd")
const OwnershipRules=preload("res://src/content/secondary_ownership_definitions.gd")
const Categories=preload("res://src/simulation/opening_loadout.gd")
const AudioResources=preload("res://src/content/audio_resources.gd")
const Controls=preload("res://src/input/flight_controls.gd")

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected explicit content/binding/visual triples")
	for i in range(0,args.size()-2,3):verify(args[i],args[i+1])
	print("Equipped secondary weapons: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(content: String,pack: String) -> void:
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(content) or not bindings.open(pack,lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	if not OwnershipRules.available(bindings):
		check(not Ownership.new().configure(bindings,cat,{}),"Earlier bindings enabled secondary ammunition ownership")
		return
	var built:=construction(bindings,cat,0.5)
	if built==null:return
	var initial:=equipped(bindings,cat,[{"item_id":41,"slot":0,"quantity":1}])
	var owner:=Ownership.new();var audio:=AudioResources.new()
	if not owner.configure(bindings,cat,initial) or not audio.configure(lib,bindings,21):check(false,owner.error+audio.error);return
	for id in [6,7,8]:
		var sound:=audio.prepare(id)
		check(not sound.is_empty() and not sound.has("unsupported"),"Original EMP launch sound could not be decoded: "+str(id)+" "+str(sound.get("unsupported",audio.error)))
	var group:=active_group(bindings,cat,built,0)
	if group==null:return
	var targets:=[0,1,2,3];var pose:=Transform3D(Basis.IDENTITY,group.snapshot().actors[0].position-Vector3(0,0,400))
	var before:=owner.snapshot();var bodies: Dictionary=group.snapshot()
	var denied:=owner.evaluate_trigger(pose,41,group,targets)
	check(not denied.is_empty() and denied.events.is_empty() and denied.owner.snapshot()==before,"Secondary launched at interval equality")
	var step:=owner.evaluate_advance(1,group,targets)
	if step.is_empty():check(false,owner.error);return
	owner=step.owner
	var ready:=owner.snapshot()
	denied=owner.evaluate_trigger(pose,41,group,targets,false)
	check(not denied.is_empty() and denied.events.is_empty() and denied.owner.snapshot()==ready,"Blocked secondary input spent ammo or changed timers")
	var input:=Controls.new();var press:=InputEventKey.new();press.physical_keycode=KEY_R;press.pressed=true
	check(input.accept(press) and input.take_pressed()==["missiles"],"Keyboard secondary request was unavailable")
	var fired:=owner.evaluate_trigger(pose,41,group,targets)
	if fired.is_empty():check(false,owner.error);return
	check(owner.snapshot()==ready and group.snapshot()==bodies and initial==before.initial_loadout,"Prospective secondary fire changed a retained owner")
	owner=fired.owner;group=fired.combat
	check(fired.events.size()==1 and fired.events[0].action=="launched" and fired.events[0].ammunition_consumed==1 and owner.snapshot().launches==1,"Secondary did not consume exactly one successful launch")
	check(fired.events[0].audio=={"source_id":6,"position":pose.origin,"pitch_raw":0.0},"EMP launch lost its original sound, owner origin or constructor pitch")
	var slot: int=owner.snapshot().guns[0].slot_index
	check(owner.snapshot().loadout.slots[slot]==null and not owner.snapshot().loadout.equipment_ids.has(41) and owner.snapshot().guns[0].ammunition==0,"Last round did not remove the installed ammo stack")
	check(owner.reconcile_loadout(initial)==owner.snapshot().loadout and owner.reconcile_loadout(owner.snapshot().loadout)==owner.snapshot().loadout,"Actual ammunition consumption could not be retained idempotently")
	check(input.accept(press) and input.take_pressed().is_empty(),"Holding the same key repeated manual detonation input")
	press.pressed=false;input.accept(press);press.pressed=true;input.accept(press)
	check(input.take_pressed()==["missiles"],"Second key press did not request detonation")
	var pulse:=owner.evaluate_trigger(pose,41,group,targets)
	if pulse.is_empty():check(false,owner.error);return
	owner=pulse.owner;group=pulse.combat
	check(pulse.events.size()==1 and pulse.events[0].action=="detonated" and pulse.events[0].ammunition_consumed==0 and pulse.events[0].audio.is_empty(),"Manual detonation spent ammunition or replayed the launch sound")
	check(group.snapshot().actors[0].systems.disabled and group.current_reputation().axes==[-2,0] and group.snapshot().actors[0].vitals==bodies.actors[0].vitals,"Equipped EMP failed to disable the actual target without hull damage")
	step=owner.evaluate_advance(6000,group,targets)
	if step.is_empty():check(false,owner.error);return
	owner=step.owner;group=step.combat
	denied=owner.evaluate_trigger(pose,41,group,targets)
	check(not denied.is_empty() and not denied.selection_exhausted and denied.events.is_empty(),"Empty launcher cleared selection before its strict interval")
	step=owner.evaluate_advance(1,group,targets)
	if step.is_empty():check(false,owner.error);return
	owner=step.owner
	denied=owner.evaluate_trigger(pose,41,group,targets)
	check(not denied.is_empty() and denied.selection_exhausted and denied.events.is_empty(),"Failed empty launch did not report the original selection-clear condition")
	check(owner.snapshot().launches==1 and owner.snapshot().guns[0].bomb.shot.is_empty(),"Expired visual ownership revived an exhausted ammo stack")
	var retained:=owner.snapshot()
	for invalid in [-1,0,999]:
		check(owner.evaluate_contact(slot,invalid,group,targets).is_empty() and owner.snapshot()==retained,"Stale secondary contact changed state")
	check(owner.evaluate_trigger(pose,42,group,targets).is_empty() and owner.evaluate_advance(-1,group,targets).is_empty() and owner.evaluate_trigger(pose,41,group,[0,0]).is_empty() and owner.snapshot()==retained,"Invalid selection/time/target order changed equipped secondary state")
	for key in ["binding_id","equipment_ids","campaign_cursor","slots"]:
		var bad:=initial.duplicate(true)
		match key:
			"binding_id":bad.binding_id="foreign"
			"equipment_ids":bad.equipment_ids.reverse()
			"campaign_cursor":bad.campaign_cursor=20
			"slots":bad.slots[slot].quantity=2
		check(owner.reconcile_loadout(bad).is_empty() and owner.snapshot()==retained,"Ammo reconciliation accepted a changed inventory: "+key)
	verify_multiple(bindings,cat,built)
	verify_expiry(bindings,cat,built)

func equipped(bindings: RefCounted,cat: RefCounted,secondaries: Array,ship_id:=0) -> Dictionary:
	var counts:=[];var total:=0
	for property in Categories.SLOT_PROPERTIES:
		var count: int=cat.tables.ships[ship_id].stats[property]
		counts.append(count);total+=count
	var slots:=[];slots.resize(total)
	slots[0]={"item_id":22,"category":0,"slot":0,"quantity":1}
	for entry in secondaries:slots[counts[0]+entry.slot]={"item_id":entry.item_id,"category":1,"slot":entry.slot,"quantity":entry.quantity}
	var ids:=[]
	for slot in slots:
		if slot!=null:ids.append(slot.item_id)
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":21,"station_id":55,"system_id":11,"ship_id":ship_id,"slots":slots,"equipment_ids":ids}

func verify_multiple(bindings: RefCounted,cat: RefCounted,built: RefCounted) -> void:
	var ship:=-1
	for row in cat.tables.ships:
		if row.stats.primary_slots>0 and row.stats.secondary_slots>=2:ship=int(row.id);break
	if ship<0:check(false,"Catalogue has no multi-secondary test hull");return
	var loadout:=equipped(bindings,cat,[{"item_id":41,"slot":0,"quantity":1},{"item_id":42,"slot":1,"quantity":1}],ship)
	var owner:=Ownership.new();var group:=active_group(bindings,cat,built,0)
	if group==null or not owner.configure(bindings,cat,loadout):check(false,owner.error);return
	check(owner.snapshot().guns.map(func(gun):return gun.equipment.item_id)==[42,41],"Secondary category lost reverse firing order")
	var targets:=[0,1,2,3];var pose:=Transform3D(Basis.IDENTITY,group.snapshot().actors[0].position-Vector3(0,0,400))
	var operation:=owner.evaluate_advance(1,group,targets)
	if operation.is_empty():check(false,owner.error);return
	owner=operation.owner
	operation=owner.evaluate_trigger(pose,41,group,targets)
	if operation.is_empty():check(false,owner.error);return
	owner=operation.owner;group=operation.combat
	operation=owner.evaluate_trigger(pose,42,group,targets)
	if operation.is_empty():check(false,owner.error);return
	owner=operation.owner;group=operation.combat
	check(operation.events.size()==1 and operation.events[0].item_id==42 and owner.snapshot().guns.all(func(gun):return gun.bomb.shot.phase=="flying"),"Successful launch did not stop before a later live bomb")
	operation=owner.evaluate_trigger(pose,-1,group,targets)
	if operation.is_empty():check(false,owner.error);return
	check(operation.events.map(func(event):return event.item_id)==[42,41] and operation.events.all(func(event):return event.action=="detonated" and event.audio.is_empty()),"Unselected manual trigger did not detonate all live bombs in firing order")
	check(operation.combat.current_reputation().axes==[-2,0] and operation.combat.snapshot().reputation.events.size()==1,"Overlapping EMP pulses counted depleted systems twice")
	var bad:=loadout.duplicate(true);var first: int=owner.snapshot().guns[1].slot_index;var second: int=owner.snapshot().guns[0].slot_index
	bad.slots[second].item_id=41;bad.equipment_ids=[22,41,41]
	check(not Ownership.new().configure(bindings,cat,bad),"Repeated secondary item IDs bypassed the source stack owner")
	bad=loadout.duplicate(true);bad.slots[first].quantity=0
	check(not Ownership.new().configure(bindings,cat,bad),"Initial empty installed stack bypassed source removal")

func verify_expiry(bindings: RefCounted,cat: RefCounted,built: RefCounted) -> void:
	var owner:=Ownership.new();var group:=active_group(bindings,cat,built,0)
	if group==null or not owner.configure(bindings,cat,equipped(bindings,cat,[{"item_id":43,"slot":0,"quantity":2}])):check(false,owner.error);return
	var targets:=[0,1,2,3];var weapon: Dictionary=owner.snapshot().guns[0].bomb.weapon
	var distance: float=weapon.speed_units_per_millisecond*weapon.lifetime_ms
	var pose:=Transform3D(Basis.IDENTITY,group.snapshot().actors[0].position-Vector3(0,0,400+distance))
	var operation:=owner.evaluate_advance(1,group,targets)
	if operation.is_empty():check(false,owner.error);return
	owner=operation.owner
	operation=owner.evaluate_trigger(pose,43,group,targets)
	if operation.is_empty():check(false,owner.error);return
	owner=operation.owner;group=operation.combat
	check(operation.events[0].audio.source_id==8 and owner.snapshot().loadout.slots[owner.snapshot().guns[0].slot_index].quantity==1,"EMP Mk III lost its sound or remaining ammo stack")
	operation=owner.evaluate_advance(weapon.lifetime_ms,group,targets)
	if operation.is_empty():check(false,owner.error);return
	check(operation.events.size()==1 and operation.events[0].action=="detonated" and operation.events[0].blast.position.is_equal_approx(group.snapshot().actors[0].position) and operation.events[0].systems_hits[0].result.disabled_now,"Expiry did not move its full step and apply the blast")
	check(operation.owner.snapshot().launches==1 and operation.owner.snapshot().guns[0].ammunition==1 and operation.events[0].audio.is_empty(),"Automatic detonation spent a second round or repeated launch audio")
