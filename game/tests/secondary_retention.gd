extends "res://tests/secondary_weapons.gd"
## Explicit detached flight records exercise ammunition publication, not a
## campaign departure, a station purchase or an earned save. Targets are built
## through the original Kappa population factory; primary guns use real mounts.
const PlayerState=preload("res://src/simulation/opening_player_state.gd")
const EquipmentState=preload("res://src/simulation/station_equipment.gd")
const Primaries=preload("res://src/simulation/primary_weapons.gd")
const TargetInventory=preload("res://src/simulation/opening_target_inventory.gd")
const Mounts=preload("res://src/content/weapon_mounts.gd")
const PlayerCache=preload("res://src/simulation/flight_player_cache.gd")

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/binding/visual triples")
	for i in range(0,args.size()-2,3):verify_retention(args[i],args[i+1])
	print("Secondary player retention: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_retention(content: String,pack: String) -> void:
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(content) or not bindings.open(pack,lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	var owner:=Ownership.new()
	if not OwnershipRules.available(bindings):
		check(not owner.configure(bindings,cat,{}),"Legacy content enabled equipped secondary retention")
		check(owner.evaluate_retention(null,null,null,null).is_empty(),"Unconfigured retention accepted missing owners")
		return
	var built:=construction(bindings,cat,0.5)
	if built==null:return
	var initial:=equipped(bindings,cat,[{"item_id":41,"slot":0,"quantity":2}])
	var views:=detached_views(bindings,cat,lib,initial,built.snapshot().random_state)
	if views.is_empty() or not owner.configure(bindings,cat,initial):check(false,owner.error);return
	var group:=active_group(bindings,cat,built,0)
	if group==null:return
	var pose:=Transform3D(Basis.IDENTITY,group.snapshot().actors[0].position-Vector3(0,0,400))
	var order:=[0,1,2,3]
	var step:=owner.evaluate_advance(1,group,order)
	if step.is_empty():check(false,owner.error);return
	owner=step.owner
	var before:=view_snapshot(views);var owner_before:=owner.snapshot();var group_before: Dictionary=group.snapshot()
	for blocked in ["input","inactive","dead"]:
		var player_copy: RefCounted=views.player.fork_for_frame()
		if blocked=="inactive":player_copy.set_permissions(false,true)
		if blocked=="dead":player_copy._state.vitals.hull=0
		var blocked_before: Dictionary=player_copy.snapshot()
		var denied:=owner.evaluate_player_trigger(pose,41,group,order,player_copy,views.equipment,views.primaries,views.targets,blocked!="input")
		check(not denied.is_empty() and denied.events.is_empty() and denied.owner.snapshot()==owner_before and denied.player.snapshot()==blocked_before,"Blocked player input spent ammo or changed pools: "+blocked)
		check(view_snapshot(views)==before and group.snapshot()==group_before,"Blocked input mutated retained views")
	for corruption in ["price_count","price_item","price_type","negative_price","overflow_price","empty_price","cache","target_order","player_inventory","shopping"]:
		var broken:=fork_views(views)
		var slot: int=owner.snapshot().guns[0].slot_index
		match corruption:
			"price_count":broken.equipment._state.prices.installed.pop_back()
			"price_item":broken.equipment._state.prices.installed[slot].item_id=42
			"price_type":broken.equipment._state.prices.installed[slot].unit_price=true
			"negative_price":broken.equipment._state.prices.installed[slot].unit_price=-1
			"overflow_price":broken.equipment._state.prices.installed[slot].unit_price=2147483648
			"empty_price":
				var empty: int=initial.slots.find(null)
				broken.equipment._state.prices.installed[empty]={"item_id":41,"unit_price":65}
			"cache":broken.player._flight_cache.binding_id="foreign"
			"target_order":broken.targets._state.loadout.equipment_ids.reverse()
			"player_inventory":broken.player._loadout.slots[slot].quantity=1
			"shopping":broken.equipment._state.ordinary_shopping_open=true
		var broken_before:=view_snapshot(broken)
		check(owner.evaluate_player_trigger(pose,41,group,order,broken.player,broken.equipment,broken.primaries,broken.targets).is_empty(),"Invalid retained state accepted a launch: "+corruption)
		check(view_snapshot(broken)==broken_before and owner.snapshot()==owner_before and group.snapshot()==group_before,"Rejected launch partially committed: "+corruption)
	var fired:=owner.evaluate_player_trigger(pose,41,group,order,views.player,views.equipment,views.primaries,views.targets)
	if fired.is_empty():check(false,owner.error);return
	check(view_snapshot(views)==before and owner.snapshot()==owner_before and group.snapshot()==group_before,"Preparing a launch changed its retained inputs")
	check(fired.events.size()==1 and fired.events[0].action=="launched" and fired.owner.snapshot().launches==1,"Player launch failed to retain its actual launcher event")
	var slot: int=fired.owner.snapshot().guns[0].slot_index
	var expected:=initial.duplicate(true);expected.slots[slot].quantity=1
	verify_views(fired,expected,before,false)
	var retained:=view_snapshot(fired)
	var repeated: Dictionary=fired.owner.evaluate_retention(fired.player,fired.equipment,fired.primaries,fired.targets)
	check(not repeated.is_empty() and view_snapshot(repeated)==retained,"Applying accepted ammunition twice changed inventory")
	check(owner.evaluate_retention(fired.player,fired.equipment,fired.primaries,fired.targets).is_empty() and view_snapshot(fired)==retained,"An older launcher restored spent ammunition")
	owner=fired.owner;group=fired.combat;views=fired
	# A failed post-launch inventory check must also roll back a prospective EMP
	# detonation and its reputation/system effects, not only the ammunition view.
	var broken:=fork_views(views);broken.equipment._state.prices.installed[slot].item_id=42
	var pulse_before: Dictionary=group.snapshot();var flying_before:=owner.snapshot()
	check(owner.evaluate_player_trigger(pose,41,group,order,broken.player,broken.equipment,broken.primaries,broken.targets).is_empty() and group.snapshot()==pulse_before and owner.snapshot()==flying_before,"Rejected pulse changed systems, reputation or the live bomb")
	var pulse:=owner.evaluate_player_trigger(pose,41,group,order,views.player,views.equipment,views.primaries,views.targets)
	if pulse.is_empty():check(false,owner.error);return
	check(pulse.combat.snapshot().actors[0].systems.disabled and pulse.combat.snapshot().actors[0].vitals==group_before.actors[0].vitals,"Player EMP did not disable the constructed target without normal damage")
	check(view_snapshot(pulse)==retained and pulse.events[0].audio.is_empty(),"Detonation consumed another round or repeated launch audio")
	owner=pulse.owner;group=pulse.combat;views=pulse
	step=owner.evaluate_advance(6001,group,order)
	if step.is_empty():check(false,owner.error);return
	owner=step.owner;group=step.combat
	fired=owner.evaluate_player_trigger(pose,41,group,order,views.player,views.equipment,views.primaries,views.targets)
	if fired.is_empty():check(false,owner.error);return
	expected.slots[slot]=null;expected.equipment_ids=[22]
	verify_views(fired,expected,before,true)
	verify_depleted_death_loadout(initial,fired,owner)
	check(fired.owner.snapshot().guns[0].ammunition==0 and fired.owner.snapshot().guns[0].bomb.shot.phase=="flying","Removing the last stack destroyed its still-live bomb")
	check(fired.targets.validate_loadout(fired.primaries.snapshot().loadout),"Last-round removal broke primary contact identity")
	var last_pulse: Dictionary=fired.owner.evaluate_player_trigger(pose,41,fired.combat,order,fired.player,fired.equipment,fired.primaries,fired.targets)
	check(not last_pulse.is_empty() and last_pulse.events.size()==1 and last_pulse.events[0].action=="detonated" and last_pulse.owner.snapshot().launches==2 and view_snapshot(last_pulse)==view_snapshot(fired),"The player could not detonate a bomb after removing the last installed round")
	var prior_guns: Array=before.primaries.guns
	check(fired.primaries.snapshot().guns==prior_guns,"Spending an EMP reset primary timers, projectiles, mounts or cached audio")
	for candidate in [null,RefCounted.new()]:
		var fresh:=fork_views(views);var old:=view_snapshot(fresh)
		check(not fresh.player.retain_secondary_ammunition(candidate) and not fresh.equipment.retain_secondary_ammunition(candidate) and not fresh.primaries.retain_secondary_ammunition(candidate) and not fresh.targets.retain_secondary_ammunition(candidate),"A non-launcher rewrote ammunition")
		check(view_snapshot(fresh)==old,"A rejected owner mutated retained inventory")
	var canonical: Dictionary=fired.primaries.snapshot().loadout
	for key in ["base_content_id","binding_id","ship_id","slots","equipment_ids"]:
		var malformed:=canonical.duplicate(true);malformed.erase(key)
		check(fired.owner.reconcile_weapon_loadout(malformed).is_empty(),"Canonical loadout accepted a missing identity field: "+key)
	canonical.extra=true
	check(fired.owner.reconcile_weapon_loadout(canonical).is_empty(),"Canonical loadout accepted unrelated metadata")

func verify_depleted_death_loadout(initial: Dictionary,fired: Dictionary,older: RefCounted) -> void:
	# Exercise only the death-entry inventory boundary with this detached
	# departure and the actual two launches above; no death or career is earned.
	var death=load("res://src/simulation/player_destruction.gd").new()
	death._state={"equipment_ids":initial.equipment_ids.duplicate()}
	death._departure_loadout=initial.duplicate(true)
	var depleted: Array=fired.player.snapshot().equipment_ids
	var before: Dictionary=fired.owner.snapshot()
	check(death._accepts_equipment(initial.equipment_ids),"An unchanged death loadout now requires a secondary launcher")
	check(not death._accepts_equipment(depleted),"Unexplained missing equipment passed the lethal boundary")
	check(not death._accepts_equipment(depleted,older),"A stale launcher falsely explained the final round's removal")
	check(death._accepts_equipment(depleted,fired.owner),"Actual last-round consumption blocked player destruction")
	for invalid in [null,[],[41],[22,194],[194]]:
		check(not death._accepts_equipment(invalid,fired.owner),"A launcher authorized unrelated lethal equipment")
	check(death.fork_for_frame()._accepts_equipment(depleted,fired.owner),"A frame fork lost the immutable departure template")
	death._departure_loadout.ship_id+=1
	check(not death._accepts_equipment(depleted,fired.owner),"A foreign ship's launcher explained depleted equipment")
	check(fired.owner.snapshot()==before,"Checking game-over eligibility mutated the launcher")

func detached_views(bindings: RefCounted,cat: RefCounted,lib: RefCounted,initial: Dictionary,random_state: Dictionary) -> Dictionary:
	# These are explicit component inputs, not a restored career. No serialized
	# save, station route, reward, mission acknowledgement or fitting is created.
	var player:=PlayerState.new();player._loadout=initial.duplicate(true)
	player._state={"base_content_id":initial.base_content_id,"binding_id":initial.binding_id,"campaign_cursor":initial.campaign_cursor,"ship_id":initial.ship_id,"equipment_ids":initial.equipment_ids.duplicate(),"active":true,"damage_allowed":true,"vitals":{"hull":73,"armor":17,"shield":12.5},"contact":true,"impact_vector":Vector3(2,3,4),"gamma":8.25}
	var cache:={"campaign_cursor":initial.campaign_cursor,"values":{"hull":73,"armor":17,"shield":12,"gamma":8}}
	for key in PlayerCache.IDENTITY_KEYS:cache[key]=initial[key]
	player._flight_cache=cache.duplicate(true)
	var equipment:=EquipmentState.new();var held:=initial.duplicate(true);held.erase("campaign_cursor")
	var prices:=[]
	for row in held.slots:prices.append(null if row==null else {"item_id":row.item_id,"unit_price":65 if row.item_id==41 else 91})
	equipment._state={"loadout":held,"prices":{"installed":prices,"cargo":[{"item_id":22,"unit_price":104}]},"training_inventory_released":true,"prototype_drill_replaced":true,"transactions":12,"credit_delta":-77,"stock":[{"item_id":41,"quantity":8,"unit_price":0}],"cargo":{"entries":[{"item_id":22,"quantity":1}],"used":1},"cargo_cache_stale":false}
	equipment._rules={"weapon_category":0,"armor_subtype":10}
	equipment._items={22:{"category":0,"subtype":0},41:{"category":1,"subtype":6}}
	var primary:=Primaries.new();var mounts:=Mounts.new()
	# The shared weapon utility supports detached loadouts without a mission;
	# do not relax the still-guarded Kappa campaign-entry constructor for a test.
	var seed:=held.duplicate(true)
	if not mounts.open(lib,cat) or not primary.configure(bindings,cat,mounts,seed):check(false,mounts.error+primary.error);return {}
	if primary.advance(1).is_empty():check(false,primary.error);return {}
	var fired:=primary.fire(Transform3D.IDENTITY,true,random_state)
	if fired.is_empty():check(false,primary.error);return {}
	check(fired.weapons.size()==1 and fired.weapons[0].result.fired,"Retention fixture did not create a live primary projectile")
	if primary.advance(5).is_empty():check(false,primary.error);return {}
	var targets:=TargetInventory.new()
	targets._state={"base_content_id":initial.base_content_id,"binding_id":initial.binding_id,"station_id":initial.station_id,"system_id":initial.system_id,"ship_id":initial.ship_id,"equipment_ids":initial.equipment_ids.duplicate(),"npc_ids":[0,1,2,3],"scenery_indices":[0,1],"loadout":primary.snapshot().loadout}
	targets._actors=[{"actor_id":0}];targets._scenery=[{"index":0,"position":Vector3.ONE}]
	return {"player":player,"equipment":equipment,"primaries":primary,"targets":targets}

func fork_views(views: Dictionary) -> Dictionary:
	return {"player":views.player.fork_for_frame(),"equipment":views.equipment.fork(),"primaries":views.primaries.fork_state(),"targets":views.targets.fork_for_frame()}

func view_snapshot(views: Dictionary) -> Dictionary:
	return {"player":views.player.snapshot(),"loadout":views.player.loadout(),"cache":views.player.cache_snapshot(),"equipment":views.equipment.snapshot(),"primaries":views.primaries.snapshot(),"targets":views.targets.snapshot()}

func verify_views(views: Dictionary,expected: Dictionary,before: Dictionary,exhausted: bool) -> void:
	check(views.player.loadout()==expected,"Player ammunition disagrees with the successful launches")
	var held:=expected.duplicate(true);held.erase("campaign_cursor")
	check(views.equipment.snapshot().loadout==held,"Retained station inventory disagrees with flight ammunition")
	var state: Dictionary=before.player.duplicate(true);state.equipment_ids=expected.equipment_ids
	check(views.player.snapshot()==state,"Ammunition retention changed damage, permissions or contact state")
	var cache: Dictionary=before.cache.duplicate(true);cache.equipment_ids=expected.equipment_ids
	check(views.player.cache_snapshot()==cache and PlayerCache.matches(cache,expected,21),"Ammunition retention reset cached pools or lost restoration identity")
	var equipment: Dictionary=before.equipment.duplicate(true);equipment.loadout=held
	for i in held.slots.size():
		if held.slots[i]==null:equipment.prices.installed[i]=null
	check(views.equipment.snapshot()==equipment,"Ammunition retention changed cargo, stock, prices, transactions or credits")
	check(views.targets.validate_loadout(views.primaries.snapshot().loadout),"Ammunition retention broke contact validation")
	check(views.targets.snapshot().npc_ids==before.targets.npc_ids and views.targets.snapshot().scenery_indices==before.targets.scenery_indices,"Ammunition consumption changed target ordering")
	check(views.primaries.snapshot().guns==before.primaries.guns,"Ammunition consumption rebuilt primary projectile ownership")
	if exhausted:check(not views.player.snapshot().equipment_ids.has(41),"Empty EMP stack remained in equipped modifiers")
