extends SceneTree
const Combat = preload("res://src/simulation/opening_combat_group.gd")
const Timeline = preload("res://src/simulation/opening_timeline.gd")
const Resolver = preload("res://src/simulation/weapon_loadout.gd")
const Projectiles = preload("res://src/simulation/ordinary_projectiles.gd")
const Definitions = preload("res://src/content/ordinary_hit_definitions.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Library = preload("res://src/content/library.gd")
var failures := 0

func _initialize() -> void:
	check_synthetic()
	var args := OS.get_cmdline_user_args()
	check(args.size()%3==0,"Expected content/binding/visual triples")
	for i in range(0,args.size()-2,3):check_profile(args[i],args[i+1])
	print("Ordinary hit policy checks: %d failures" % failures)
	quit(1 if failures else 0)

func check_synthetic() -> void:
	var bindings := Bindings.new()
	bindings.base_content_id="a".repeat(64);bindings.binding_id="b".repeat(64)
	bindings.weapon_parameters={"damage_property":49,"interval_property":51,"lifetime_property":52,"speed_property":53,"interval_percent_property":79,"damage_percent_property":80,"low_damage_threshold":10,"item_type_value_index":5,"item_category_value_index":3,"primary_category":0,"modifier_type":26,"percent_divisor":100.0,"default_multiplier":1.0,"missing_multiplier":-999.0,"low_damage_interval_scale":0.7,"launch_modes":{"alternate_item_ids":[9,10,11,228],"provenance":{}},"projectile_capacity":{"slots":20,"provenance":{}}}
	var catalogues := Catalogues.new()
	catalogues.content_id=bindings.base_content_id
	catalogues.tables.items=[{"arrays":[[],[],[0,0,1,0,2,0]],"properties":{49:6,51:380,52:2000,53:20}},
		{"arrays":[[],[],[0,0,1,3,2,26]],"properties":{79:0,80:20}}]
	var resolver := Resolver.new()
	check(resolver.configure(bindings,catalogues,catalogues.content_id),resolver.error)
	check(not resolver.resolve(0,[]).has("ordinary_hit_policy"),"Legacy weapon invented hit policy")
	var policy := {"additional_damage_property":17,"missing_additional_damage":-1234,"nonplayer_damage_scale":1.0,"provenance":{}}
	bindings.weapon_parameters.ordinary_hit_policy=policy
	check(resolver.configure(bindings,catalogues,catalogues.content_id),resolver.error)
	var result: Dictionary = resolver.resolve(0,[1])
	check(result.ordinary_hit_policy=={"additional_damage":-1234,"additional_damage_required":false,"nonplayer_damage":7},"Absent property or modified ordinary damage lost")
	var projectiles := Projectiles.new()
	check(projectiles.configure(result),projectiles.error)
	check(projectiles.snapshot().weapon.ordinary_hit_policy==result.ordinary_hit_policy,"Projectile ownership discarded policy")
	result.ordinary_hit_policy.nonplayer_damage=1
	check(projectiles.snapshot().weapon.ordinary_hit_policy.nonplayer_damage==7,"Returned weapon policy aliases live gun")
	check(not projectiles.configure(result) and projectiles.snapshot().is_empty(),"Conflicting policy damage retained projectile owner")
	for value in [-1234,0,12,-3]:
		catalogues.tables.items[0].properties[17]=value
		check(resolver.configure(bindings,catalogues,catalogues.content_id),resolver.error)
		result=resolver.resolve(0,[])
		check(result.ordinary_hit_policy.additional_damage==value and result.ordinary_hit_policy.additional_damage_required==(value!=-1234),"Explicit additional property confused with absence")
	for bad in [true,null,"0",0.5,2147483648]:
		catalogues.tables.items[0].properties[17]=bad
		check(resolver.configure(bindings,catalogues,catalogues.content_id),resolver.error)
		check(resolver.resolve(0,[]).is_empty(),"Malformed additional property silently ignored")
	for key in policy:
		var bad := policy.duplicate(true);bad.erase(key)
		check(not Definitions.parameters(bad),"Missing policy field accepted")
	for bad_scale in [0,2,true,NAN]:
		var bad := policy.duplicate(true);bad.nonplayer_damage_scale=bad_scale
		check(not Definitions.parameters(bad),"Unsupported damage scaling accepted")
	bindings.weapon_parameters.ordinary_hit_policy={}
	catalogues.tables.items[0].properties.erase(17)
	check(resolver.configure(bindings,catalogues,catalogues.content_id),resolver.error)
	check(not resolver.resolve(0,[]).has("ordinary_hit_policy"),"Empty unsupported scope invented hit policy")

func check_profile(content: String,pack: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error);return
	var resolver := Resolver.new()
	check(resolver.configure(bindings,catalogues,catalogues.content_id),resolver.error)
	var policy: Dictionary = bindings.weapon_parameters.get("ordinary_hit_policy",{})
	if policy.is_empty():
		check(not resolver.resolve(2,[]).has("ordinary_hit_policy"),"Legacy source pack inferred ordinary hit policy")
		print(library.manifest.profile.edition,": legacy weapon behavior retained without inferred hit policy")
		return
	var architecture := "armv7" if library.manifest.profile.edition=="ios-hd" else "x86_64"
	check(Definitions.validate(policy,64000000,architecture,bindings.weapon_parameters).is_empty(),"Source policy rejected")
	for key in policy.provenance:
		var bad := policy.duplicate(true);bad.provenance[key].bytes+=1
		check(not Definitions.validate(bad,64000000,architecture,bindings.weapon_parameters).is_empty(),"Invalid source proof extent accepted")
	var ordinary := []
	for id in catalogues.tables.items.size():
		var item: Dictionary = catalogues.tables.items[id]
		if resolver.item_value(item,3)!=0 or resolver.item_value(item,5)!=0:continue
		var weapon: Dictionary = resolver.resolve(id,[])
		check(not weapon.is_empty(),resolver.error)
		if weapon.is_empty():continue
		if weapon.launch_mode!="ordinary":
			check(not weapon.has("ordinary_hit_policy") and not weapon.has("collision_bounds"),"Alternate weapon inferred ordinary hit behavior")
			continue
		ordinary.append(id)
		if not bindings.weapon_parameters.get("collision_bounds",{}).is_empty():
			check(weapon.get("collision_bounds")=={"mode":"target"},"Ordinary weapon lost source bounds selection")
		else:
			check(not weapon.has("collision_bounds"),"Legacy weapon invented source bounds")
		check(weapon.ordinary_hit_policy.additional_damage==-979797979 and not weapon.ordinary_hit_policy.additional_damage_required,"Source ordinary item unexpectedly requires additional damage")
		check(weapon.ordinary_hit_policy.nonplayer_damage==weapon.damage,"Non-player damage differs from resolved weapon")
		var projectiles := Projectiles.new()
		check(projectiles.configure(weapon),projectiles.error)
		check(projectiles.fork_state().snapshot().weapon.ordinary_hit_policy==weapon.ordinary_hit_policy,"Gun fork lost resolved hit policy")
	check(ordinary==[0,1,2,3,4,5,6,7,8,183,229],"Ordinary source population changed")
	check_combat(library,bindings,catalogues,resolver)
	print(library.manifest.profile.edition,": all 11 ordinary weapons carry verified non-player damage and absent additional property")

func check_combat(library: RefCounted, bindings: RefCounted, catalogues: RefCounted, resolver: RefCounted) -> void:
	check(library.select_language("gb"),library.error)
	var counts := [];counts.resize(23);counts.fill(1)
	var timeline := Timeline.new();var group := Combat.new()
	check(timeline.configure(bindings,catalogues,library,counts),timeline.error)
	check(group.configure(bindings,catalogues,0.5),group.error)
	var weapon: Dictionary = resolver.resolve(2,[])
	check(not group.weapon_hit(0,weapon).accepted,"Inactive source actor accepted a weapon hit")
	var scene: Dictionary = timeline.snapshot().scene
	var radio: Dictionary = timeline.snapshot().radio
	radio.finished[7]=true
	check(group.update(scene,3,radio),group.error)
	var hit: Dictionary = group.weapon_hit(0,weapon)
	check(hit.accepted and group.snapshot().actors[0].vitals.hull==144 and group.snapshot().actors[1].vitals.hull==150,"Resolved source gun did not damage only its named active NPC")
	var before: Dictionary = group.snapshot()
	for key in ["identity","binding","additional","hidden_additional","missing","kind","damage","malformed"]:
		var bad := weapon.duplicate(true)
		match key:
			"identity":bad.base_content_id="c".repeat(64)
			"binding":bad.binding_id="c".repeat(64)
			"additional":bad.ordinary_hit_policy.additional_damage_required=true;bad.ordinary_hit_policy.additional_damage=0
			"hidden_additional":bad.ordinary_hit_policy.additional_damage=0
			"missing":bad.erase("ordinary_hit_policy")
			"kind":bad.kind=11
			"damage":bad.ordinary_hit_policy.nonplayer_damage=600
			"malformed":bad.damage=true
		check(group.weapon_hit(0,bad).is_empty() and group.snapshot()==before,"Unsupported weapon hit changed NPC state: "+key)
	check(group.weapon_hit(3,weapon).is_empty() and group.snapshot()==before,"Absent target accepted source hit")
	check(group._actors[0].set_permissions(true,false,true),"Cannot set damage permission")
	check(not group.weapon_hit(0,weapon).accepted and group.snapshot().actors[0].vitals.hull==144,"Resolved hit bypassed damage gate")
	check(group._actors[0].set_permissions(true,true,true),"Cannot restore damage permission")
	var deaths := 0
	for i in 25:
		if group.weapon_hit(0,weapon).destroyed_now:deaths+=1
	check(deaths==1 and group.snapshot().actors[0].vitals.hull==0,"Resolved weapon hit repeated death")
	check(group.update(scene,3,radio) and group.snapshot().actors[0].vitals.hull==0,"Placement/activation resurrected hit target")

func check(condition: bool,message: String) -> void:
	if not condition:failures+=1;push_error(message)
