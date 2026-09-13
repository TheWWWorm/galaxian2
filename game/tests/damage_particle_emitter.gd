extends SceneTree
const Emitter=preload("res://src/simulation/damage_particle_emitter.gd")
const Appearance=preload("res://src/presentation/damage_particle_appearance.gd")
const Definitions=preload("res://src/content/damage_particle_definitions.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Library=preload("res://src/content/library.gd")
var failures:=0
var checks:=0

func _initialize() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/damage_particle_emission_vectors.json"))
	var bindings:=Bindings.new();bindings.binding_id="b".repeat(64);bindings.base_content_id="a".repeat(64)
	bindings.damage_particles=fixture.definition
	for vector in fixture.vectors:
		var emitter:=Emitter.new()
		var preset: Dictionary=fixture.definition.presets[int(vector.preset_index)]
		check(emitter.configure(bindings,bindings.base_content_id,preset.preset_id,int(fixture.seed)),emitter.error)
		var basis:=Basis(vec(vector.axes[0]),vec(vector.axes[1]),vec(vector.axes[2]))
		check(emitter.advance(Transform3D(basis,vec(vector.start)),1,1).get("births")==0,"Initial baseline emitted particles")
		emitter.set_emitting(true)
		var result:=emitter.advance(Transform3D(basis,vec(vector.end)),250,250)
		check(result.get("births")==vector.slots.size(),"Wrong birth count for "+vector.name+str(preset.preset_id))
		var state:=emitter.snapshot()
		check(state.random.state==int(vector.random_state),"Birth did not consume seven bounded independent draws")
		check(state.velocity==vec(vector.velocity),"Emitter velocity refresh changed")
		for index in vector.slots.size():
			var expected: Dictionary=vector.slots[index];var slot: Dictionary=state.slots[index]
			check(slot.appearance.age_ms==expected.age_ms and slot.appearance["size"]==expected["size"],"Newborn age or size differs from motion example")
			check(slot.velocity==vec(expected.velocity),"Wrong inherited particle velocity")
			check(slot.position==vec(expected.position),"Birth position, scatter or residual travel differs: "+str(slot.position)+" versus "+str(vec(expected.position)))
		var snapshot:=emitter.snapshot()
		for slot in state.slots:Appearance.sample(preset,slot.appearance)
		check(emitter.snapshot()==snapshot,"Appearance sampling consumed emitter randomness")
		state.slots[0].appearance.age_ms=777
		check(emitter.snapshot()==snapshot,"Snapshot shared particle state with its owner")
	verify_lifecycle(bindings)
	verify_velocity_clock(bindings)
	verify_invalid(bindings)
	for index in range(0,OS.get_cmdline_user_args().size(),3):
		var args:=OS.get_cmdline_user_args();verify_source(args[index],args[index+1])
	print("Damage particle emitters: ",fixture.vectors.size()," birth examples, ",checks," checks; ",failures," failures")
	quit(0 if failures==0 else 1)

func verify_lifecycle(bindings: RefCounted) -> void:
	var emitter:=Emitter.new();check(emitter.configure(bindings,bindings.base_content_id,15,42),emitter.error)
	var origin:=Transform3D.IDENTITY
	emitter.set_emitting(true)
	check(emitter.advance(origin,0,0).get("births")==0 and emitter.snapshot().dirty,"Pause modified pending baseline")
	check(emitter.advance(origin,1,1).get("births")==0,"Initial update emitted particles")
	# At rest, a full second consumes eight emission intervals but creates one.
	check(emitter.advance(origin,1000,1000).get("births")==1,"Stationary emitter produced a burst")
	check(emitter.snapshot().remainder_ms==0 and emitter.snapshot().cursor==1,"Short-movement timer retained discarded births")
	check(emitter.advance(origin,50,50).get("births")==0 and emitter.snapshot().remainder_ms==50,"Partial timer was not retained")
	var before:=emitter.snapshot();emitter.set_emitting(false)
	check(emitter.advance(origin,50,50).get("births")==0,"Disabled emitter created a particle")
	var after:=emitter.snapshot()
	check(after.slots[0].appearance.age_ms==before.slots[0].appearance.age_ms+50,"Disabling emission froze existing particles")
	check(after.random==before.random and after.remainder_ms==50,"Disabled emission advanced timer or RNG")
	emitter.set_emitting(true)
	check(emitter.snapshot().remainder_ms==0,"Reenabled emission retained its old timer")
	emitter.set_update_existing(false)
	before=emitter.snapshot()
	check(emitter.advance(origin,250,250).get("births")==1,"Frozen existing particles blocked new emission")
	after=emitter.snapshot()
	check(after.slots[0]==before.slots[0] and after.slots[1].appearance.age_ms==0,"Existing-update flag changed wrong particle")
	# Reset affects sprites, timer and pending baseline, preserving ownership and
	# cursor/random state even while existing-particle updates are disabled.
	before=emitter.snapshot();emitter.reset();after=emitter.snapshot()
	check(after.cursor==before.cursor and after.random==before.random and after.enabled and not after.update_existing,"Reset changed independent emitter ownership state")
	check(after.dirty and after.remainder_ms==0,"Reset failed to invalidate the movement baseline")
	for slot in after.slots:check(slot.appearance.age_ms==-1 and slot.appearance["size"]==0 and slot.position==Emitter.RESET_POSITION,"Reset left a live sprite")
	origin.origin=Vector3(700000,-50000,1000000)
	check(emitter.advance(origin,250,250).get("births")==0,"Relocation emitted a jump-length trail")
	check(emitter.snapshot().baseline==origin.origin and emitter.snapshot().velocity==Vector3.ZERO,"Relocation did not capture its new baseline")
	check(emitter.advance(origin,250,250).get("births")==1,"Emitter did not recover after relocation")
	before=emitter.snapshot();emitter.set_visible(false);after=emitter.snapshot()
	check(after.random==before.random and after.cursor==before.cursor and after.dirty and not after.visible,"Visibility change did not use sprite reset")
	check(emitter.advance(origin,250,250).get("births")==0 and emitter.advance(origin,250,250).get("births")==0,"Invisible emitter produced particles")
	emitter.set_visible(true);emitter.set_update_existing(true)
	# Moving at least one source unit permits every requested birth. Frozen
	# slots are overwritten by insertion order, never by a free-slot search.
	var moving:=Transform3D.IDENTITY
	emitter.reset();emitter.advance(moving,1,1)
	var cursor:=int(emitter.snapshot().cursor)
	for tick in 5:
		moving.origin.z+=100
		check(emitter.advance(moving,1000,1000).get("births")==8,"Moving emitter dropped timed births")
	check(emitter.snapshot().cursor==(cursor+40)%18,"Particle insertion ring did not wrap")
	before=emitter.snapshot();var fork:=emitter.fork_for_frame();fork.advance(moving,1000,1000)
	check(emitter.snapshot()==before and fork.snapshot()!=before,"Staged emitter frame mutated its source")
	emitter.set_emitting(false)
	check(emitter.advance(moving,1000,1000).get("births")==0,"Disabled emitter restarted")
	for slot in emitter.snapshot().slots:check(slot.appearance.age_ms==-1,"Old particles survived beyond their source lifetime")

func verify_velocity_clock(bindings: RefCounted) -> void:
	var emitter:=Emitter.new();emitter.configure(bindings,bindings.base_content_id,15,1)
	var pose:=Transform3D.IDENTITY
	emitter.advance(pose,2,2)
	pose.origin.z=1;emitter.advance(pose,2,4)
	check(emitter.snapshot().velocity.z==250,"Forced refresh ignored shared manager time")
	pose.origin.z=3;emitter.advance(pose,2,6)
	check(emitter.snapshot().velocity.z==250 and emitter.snapshot().baseline.z==1,"Velocity refreshed before the strict manager threshold")
	pose.origin.z=6;emitter.advance(pose,3,9)
	check(emitter.snapshot().baseline.z==1,"Velocity refreshed at nine milliseconds")
	pose.origin.z=11;emitter.advance(pose,1,10)
	check(emitter.snapshot().velocity.z==1000 and emitter.snapshot().baseline.z==11,"Ten-millisecond velocity refresh did not use retained translation")

func verify_invalid(bindings: RefCounted) -> void:
	var emitter:=Emitter.new();emitter.configure(bindings,bindings.base_content_id,15,1)
	emitter.set_emitting(true);emitter.advance(Transform3D.IDENTITY,1,1)
	var before:=emitter.snapshot()
	for delta in [null,"1",-1,0.5,1001,INF,NAN]:
		check(emitter.advance(Transform3D.IDENTITY,delta,1001).has("error") and emitter.snapshot()==before,"Invalid frame changed emitter state")
	for elapsed in [null,"1",-1,0,1.5,11,1011,INF,NAN]:
		check(emitter.advance(Transform3D.IDENTITY,1,elapsed).has("error") and emitter.snapshot()==before,"Invalid manager interval changed emitter state")
	for pose in [null,Transform3D(Basis.IDENTITY,Vector3(INF,0,0)),Transform3D(Basis.IDENTITY,Vector3(1e30,0,0))]:
		check(emitter.advance(pose,1,1).has("error") and emitter.snapshot()==before,"Invalid or overflowing pose consumed a frame")
	check(not emitter.set_visible(1) and not emitter.set_emitting(1) and not emitter.set_update_existing(1) and emitter.snapshot()==before,"Invalid control flag changed emitter state")
	check(not emitter.configure(bindings,"c".repeat(64),15,1) and emitter.snapshot().is_empty(),"Emitter accepted the wrong content identity")
	check(not emitter.configure(bindings,bindings.base_content_id,14,1),"Missing preset was invented")
	check(not emitter.configure(bindings,bindings.base_content_id,15,1.0),"Fractional-typed seed accepted")
	var original: Dictionary=bindings.damage_particles
	var invalid:=original.duplicate(true);invalid.erase("emitter_defaults");bindings.damage_particles=invalid
	check(not emitter.configure(bindings,bindings.base_content_id,15,1),"Legacy sprite overrides invented emitter defaults")
	invalid=original.duplicate(true);invalid.emitter_defaults.velocity_size_factor=1;bindings.damage_particles=invalid
	check(not emitter.configure(bindings,bindings.base_content_id,15,1),"Unsupported defaults accepted")
	bindings.damage_particles=original

func verify_source(content: String,pack: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new()
	check(library.open(content),library.error);check(bindings.open(pack,library.manifest),bindings.error)
	if not Definitions.emitter_parameters(bindings.damage_particles):
		var unsupported:=Emitter.new()
		check(not unsupported.configure(bindings,bindings.base_content_id,15,1),"Legacy pack invented an emitter")
		print("Emitter unavailable in legacy ",library.manifest.profile.edition);return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack+"/bindings.json"))
	check(Definitions.validate(bindings.damage_particles,int(header.source_executable_bytes),header.architecture).is_empty(),"Valid emitter defaults rejected")
	for preset in bindings.damage_particles.presets:
		var emitter:=Emitter.new();var unrelated:=Emitter.new()
		check(emitter.configure(bindings,bindings.base_content_id,preset.preset_id,33),emitter.error)
		check(unrelated.configure(bindings,bindings.base_content_id,preset.preset_id,44),unrelated.error)
		var isolated:=unrelated.snapshot();var pose:=Transform3D.IDENTITY
		emitter.set_emitting(true);emitter.advance(pose,1,1)
		for step in 20:
			pose.origin.z+=1000
			var result:=emitter.advance(pose,50,50)
			check(result.get("births")==1,"Source emitter failed its 20 Hz motion window")
		check(emitter.snapshot().cursor==20%int(preset.capacity),"Source emitter capacity lost ring order")
		check(unrelated.snapshot()==isolated,"Particle emission consumed another emitter's RNG")
		for slot in emitter.snapshot().slots:
			if slot.appearance.age_ms>=0:check(not Appearance.sample(preset,slot.appearance).has("error"),"Source particle cannot be sampled")
	print("Source emitters verified for ",library.manifest.profile.edition)

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)

func vec(array: Array) -> Vector3:return Vector3(array[0],array[1],array[2])
