extends SceneTree
## Explicit Mac component checks. These do not claim particles are connected to
## the second-flight frame, scene or application.
const Emitter=preload("res://src/simulation/damage_particle_emitter.gd")
const Appearance=preload("res://src/presentation/damage_particle_appearance.gd")
const Damage=preload("res://src/content/damage_particle_definitions.gd")
const Definitions=preload("res://src/content/full_hold_particle_definitions.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Library=preload("res://src/content/library.gd")
const Geometry=preload("res://src/presentation/opening_damage_geometry.gd")
var checks:=0
var failures:=0
var bindings:=Bindings.new()
var library:=Library.new()

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected an explicit Mac content, binding and visual triple")
	if args.size()==3:verify(args)
	print("Second-flight particle emitters: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest):check(false,library.error+bindings.error);return
	check(bindings.source_architecture=="x86_64","This verification is Mac only")
	var unrelated:=Emitter.new()
	check(unrelated.configure(bindings,bindings.base_content_id,15,33),unrelated.error)
	var before:=unrelated.snapshot()
	if bindings.full_hold_particles.is_empty():
		for id in [9,11]:
			var missing:=Emitter.new()
			check(not missing.configure_full_hold(bindings,bindings.base_content_id,id,33) and missing.snapshot().is_empty(),"Legacy pack invented a second-flight sprite")
		return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	verify_declarations(header)
	verify_reader(args[1],header)
	verify_trail()
	verify_burst()
	verify_invalid()
	check(unrelated.snapshot()==before,"Second-flight sprites consumed the opening emitter's random stream")

func validate(data: Variant,header: Dictionary,arch:="x86_64",flight: Variant=null) -> String:
	return Definitions.validate(data,int(header.source_executable_bytes),arch,bindings.arrival_staging,bindings.full_hold_flight if flight==null else flight,bindings.player_destruction,bindings.damage_particles)

func verify_declarations(header: Dictionary) -> void:
	var rules: Dictionary=bindings.full_hold_particles
	check(validate(rules,header).is_empty(),"Valid second-flight sprite declarations rejected")
	check(not validate(rules,header,"armv7").is_empty() and not validate(rules,header,"x86_64",{}).is_empty(),"Sprites accepted a different source or absent flight context")
	check(validate({},header).is_empty() and not validate(null,header).is_empty(),"Optional declarations confused empty with malformed")
	check(rules.player_preset==9 and rules.npc_preset==9 and rules.npc_count==1 and rules.player_smoke_fire_max_cursor==1,"Second trip inherited the opening population")
	check(rules.burst_count==1 and rules.burst_position=="statistics_before_death_spin","Player burst lost its count or statistics position")
	for key in Definitions.VALUES:
		var bad:=rules.duplicate(true);bad[key]=null
		check(not Definitions.parameters(bad),"Changed sprite declaration accepted: "+key)
	for key in Definitions.SPANS:
		var bad:=rules.duplicate(true);bad.provenance[key].offset+=1
		check(not validate(bad,header).is_empty(),"Detached sprite provenance accepted: "+key)
	var material: Dictionary=bindings.resolve_material(20099)
	check(material.get("render_type")==2 and material.get("texture_ids",[])[0]==11601 and not material.texture_paths[0].is_empty(),"Shared general sprite material lost its imported texture")
	check(Damage.preset(rules.presets[0]) and not Damage.preset(rules.presets[1]) and Damage.sprite_preset(rules.presets[1]),"Manual burst weakened the legacy continuous-preset contract")
	var bad: Dictionary=rules.presets[1].duplicate(true);bad.even_spacing=1
	check(not Damage.sprite_preset(bad),"Manual sprite accepted unsupported spacing")

func configured(id: int) -> RefCounted:
	var emitter:=Emitter.new()
	check(emitter.configure_full_hold(bindings,bindings.base_content_id,id,33),emitter.error)
	return emitter

func verify_reader(pack: String,header: Dictionary) -> void:
	var body: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var directory:=OS.get_cache_dir().path_join("gof2-full-hold-particles-%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	for scenario in ["missing","type","preset","position","extent","death_absent","defaults_absent","empty"]:
		var changed:=body.duplicate(true);var metadata:=header.duplicate(true)
		match scenario:
			"missing":changed.erase("full_hold_particles")
			"type":changed.full_hold_particles=false
			"preset":changed.full_hold_particles.presets[1].flags=0x02000021
			"position":changed.full_hold_particles.burst_position="physical"
			"extent":changed.full_hold_particles.provenance.manual_emission.offset+=1
			"death_absent":
				changed.player_destruction={};changed.game_over_presentation={}
			"defaults_absent":changed.damage_particles.erase("emitter_defaults");changed.damage_particles.provenance.erase("defaults")
			"empty":changed.full_hold_particles={}
		var serialized:=JSON.stringify(changed,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		var reader:=Bindings.new();check(reader.open(pack,library.manifest),reader.error)
		var accepted:=reader.open(directory,library.manifest)
		check(accepted and reader.full_hold_particles.is_empty() if scenario=="empty" else not accepted and reader.binding_id.is_empty() and reader.full_hold_particles.is_empty(),"Malformed particle pack retained accepted state: "+scenario)
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func verify_trail() -> void:
	var trail:=configured(9);var pose:=Transform3D.IDENTITY
	check(not trail.snapshot().enabled and trail.snapshot().visible and trail.snapshot().slots.size()==16,"Death trail ignored source registration flags or capacity")
	check(trail.advance(pose,1,1).get("births")==0,"Initial trail baseline created a sprite")
	trail.set_emitting(true);pose.origin.z=125
	check(trail.advance(pose,125,125).get("births")==1,"Moving death trail lost its 8/s rate")
	var state: Dictionary=trail.snapshot();var slot: Dictionary=state.slots[0]
	# Independent bounded LCG example: seed 33, bounds 500,600,600,600,1000x3
	# produce 3,219,203,107,978,973,143. Seven draws; the last birth has no residual age.
	check(slot.position==Vector3(-81,-193,-219) and slot.velocity==Vector3(0,0,1000),"Trail local offset/scatter or inherited velocity changed")
	check(slot.appearance=={"slot":0,"age_ms":0,"size":1078} and state.random.state==102929287504013,"Trail used the wrong size or independent random order")
	trail.set_emitting(false)
	check(trail.advance(pose,700,700).get("births")==0,"Disabled death trail emitted")
	state=trail.snapshot();slot=state.slots[0]
	check(slot.appearance.age_ms==700 and slot.appearance["size"]==1428 and slot.position==Vector3(-81,-193,481.00006103515625),"Trail inclusive lifetime, growth or binary32 drift changed")
	check(Appearance.sample(state.preset,slot.appearance).frame==15,"Trail final atlas tile ended early")
	trail.advance(pose,1,1)
	check(trail.snapshot().slots[0].appearance.age_ms==-1,"Death trail survived beyond 700 ms")
	trail.set_emitting(true);trail.advance(pose,125,125)
	state=trail.snapshot();trail.set_visible(false);trail.set_emitting(true)
	check(not trail.snapshot().visible and trail.snapshot().enabled,"Post-breakup poll restored drawing")
	trail.advance(pose,1000,1000);trail.advance(pose,1000,1000)
	check(trail.snapshot().random==state.random and trail.snapshot().cursor==state.cursor and trail.snapshot().remainder_ms==0,"Hidden trail consumed births after breakup")
	for row in trail.snapshot().slots:check(row.appearance.age_ms==-1,"Hidden trail retained a sprite")
	state=trail.snapshot()
	check(trail.emit_once(Vector3.ZERO).has("error") and trail.snapshot()==state,"Continuous trail accepted a manual burst")

func verify_burst() -> void:
	var burst:=configured(11);var origin:=Vector3(200,-30,400);var pose:=Transform3D.IDENTITY
	var initial: Dictionary=burst.snapshot()
	check(initial.enabled and initial.visible and initial.slots.size()==10 and initial.preset.emission_per_second==500,"Manual burst lost its source defaults")
	check(burst.emit_once(origin).get("births")==1,"Burst request did not create exactly one particle")
	var state: Dictionary=burst.snapshot()
	check(state.slots[0]=={"appearance":{"slot":0,"age_ms":0,"size":2003},"position":origin,"velocity":Vector3.ZERO},"Burst moved, scattered or used an overridden size")
	check(state.random.state==235172764540153 and state.cursor==1,"Burst did not consume exactly three private size draws")
	check(state.dirty and state.remainder_ms==initial.remainder_ms and state.baseline==initial.baseline,"Direct birth advanced its manager or baseline")
	var sample:=Appearance.sample(state.preset,state.slots[0].appearance)
	var quad:=Geometry.sprite(origin,sample)
	check(sample.frame==0 and sample.color==Color.WHITE and quad.vertices[0]==Vector3(-801,-1031,400),"Burst cannot share the sprite appearance/odd-size geometry")
	check(burst.snapshot()==state,"Rendering a burst changed its emitter")
	check(burst.advance(pose,0,0).get("births")==0 and burst.snapshot()==state,"Pause changed a manual birth")
	for tick in 3:
		pose.origin+=Vector3(1000,2000,3000)
		check(burst.advance(pose,500,500).get("births")==0,"Manual preset emitted from its inherited 500/s field")
	state=burst.snapshot();sample=Appearance.sample(state.preset,state.slots[0].appearance)
	check(state.slots[0].appearance.age_ms==1500 and state.slots[0].appearance["size"]==2753 and state.slots[0].position==origin,"Manual sprite lost its stationary inclusive lifetime or size growth")
	check(sample.frame==15 and sample.active and state.random.state==235172764540153 and state.remainder_ms==0,"Manual sprite animation or automatic emission gate changed")
	burst.advance(pose,1,1)
	check(burst.snapshot().slots[0].appearance.age_ms==-1,"Manual sprite survived beyond 1500 ms")
	burst.set_visible(false);burst.set_emitting(false)
	state=burst.snapshot();burst.emit_once(origin)
	check(burst.snapshot().slots[1].appearance.age_ms==0 and not burst.snapshot().visible and not burst.snapshot().enabled,"Direct burst incorrectly consulted owner flags")
	burst.advance(pose,100,100)
	check(burst.snapshot().slots[1].appearance.age_ms==100,"Hidden manual sprite stopped aging")
	burst.set_update_existing(false);state=burst.snapshot();burst.advance(pose,100,100)
	check(burst.snapshot().slots==state.slots and burst.snapshot().random==state.random,"Frozen manual sprite advanced or spawned automatically")
	for index in 12:burst.emit_once(Vector3(index,0,0))
	state=burst.snapshot()
	check(state.cursor==4 and state.slots[3].position==Vector3(11,0,0) and state.slots[4].position==Vector3(2,0,0),"Manual insertion failed to wrap its ten-slot ring")
	var fork: RefCounted=burst.fork_for_frame();fork.emit_once(Vector3.ZERO)
	check(burst.snapshot()==state and fork.snapshot()!=state,"Staged burst changed the accepted owner")
	state.slots[0].appearance["size"]=30000
	check(burst.snapshot().slots[0].appearance["size"]!=30000,"Burst snapshot shared slot storage")

func verify_invalid() -> void:
	var burst:=configured(11);var before: Dictionary=burst.snapshot()
	for position in [null,Transform3D.IDENTITY,Vector3(INF,0,0),Vector3(0,NAN,0)]:
		check(burst.emit_once(position).has("error") and burst.snapshot()==before,"Invalid burst consumed a random draw or slot")
	for id in [15,42,8,12,null,9.5]:
		check(not burst.configure_full_hold(bindings,bindings.base_content_id,id,33) and burst.snapshot().is_empty(),"Second-flight owner accepted an unavailable or noninteger preset")
	check(not burst.configure_full_hold(bindings,"a".repeat(64),11,33),"Burst accepted a foreign content identity")
	check(not burst.configure_full_hold(bindings,bindings.base_content_id,11,33.0),"Burst accepted a noninteger seed")
	check(not burst.configure(bindings,bindings.base_content_id,11,33),"Legacy emitter entry point invented a manual preset")
	var saved: Dictionary=bindings.full_hold_particles
	bindings.full_hold_particles=saved.duplicate(true);bindings.full_hold_particles.presets[1].relative_velocity_factor=1
	check(not burst.configure_full_hold(bindings,bindings.base_content_id,11,33),"Unverified moving manual preset accepted")
	bindings.full_hold_particles=saved
	check(not burst.configure_full_hold(null,bindings.base_content_id,11,33),"Missing bindings accepted")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
