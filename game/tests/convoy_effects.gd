extends SceneTree
## Local source-backed sprites and shared renderer edge cases. Full flight is
## checked separately from an earned station in convoy_flight.gd.
const Bindings=preload("res://src/content/resource_bindings.gd")
const Library=preload("res://src/content/library.gd")
const Rules=preload("res://src/content/convoy_effect_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Damage=preload("res://src/content/damage_particle_definitions.gd")
const Emitter=preload("res://src/simulation/damage_particle_emitter.gd")
const Appearance=preload("res://src/presentation/damage_particle_appearance.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected explicit content/binding/visual triples")
	for i in range(0,args.size()-2,3):verify(args[i],args[i+1])
	print("Convoy EMP sprites: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(content: String,pack: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new()
	if not library.open(content) or not bindings.open(pack,library.manifest):check(false,library.error+bindings.error);return
	var emitter:=Emitter.new()
	if not Rules.available(bindings):
		check(not emitter.configure_convoy_emp(bindings,17,33) and emitter.snapshot().is_empty(),"Legacy pack invented EMP effects")
		return
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("bindings.json")))
	for key in Rules.SPANS:
		var changed: Dictionary=bindings.mido_travel.duplicate(true);changed.provenance[key].offset+=1
		check(not Travel.validate(changed,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Moved EMP proof accepted: "+key)
	for key in Rules.VALUES:
		var changed: Dictionary=bindings.mido_travel.duplicate(true);changed.convoy_effects[key]=null
		check(not Travel.parameters(changed),"Changed EMP content accepted: "+key)
	var descriptor: Dictionary=bindings.resolve_material(27260)
	check(descriptor.get("render_type")==2 and descriptor.get("texture_ids",[])[0]==33300 and not descriptor.texture_paths[0].is_empty(),"EMP sprites lost their original effects atlas")
	var rules: Dictionary=bindings.mido_travel.convoy_effects
	check(rules.preset_ids==[17.0,18.0] and rules.unassigned_handle_ignored and not rules.capture_view_stops_emp and rules.capture_view_stop_manager=="nozzle","EMP confused an unassigned handle or the separate nozzle manager")
	for preset in rules.presets:
		check(Damage.sprite_preset(preset),"Original short-lifetime/zero-animation sprite rejected")
		var invalid: Dictionary=preset.duplicate(true);invalid.material_id=20099
		check(not Damage.sprite_preset(invalid),"EMP exception changed ordinary sprite validation")
		for slot in 4:
			var state:=Appearance.start(preset,slot,0)
			var sample:=Appearance.sample(preset,state,true)
			var uv: Array=preset.uv_rect;var expected:=Vector4(uv[0],uv[1],uv[2],uv[3])
			if slot==1:expected=Vector4(uv[2],uv[1],uv[0],uv[3])
			if slot==3:expected=Vector4(uv[0],uv[3],uv[2],uv[1])
			check(sample.uv_rect==expected and sample.frame==0,"Unanimated sprite discarded its stable slot mirror")
			check(sample.color==Color(0,0,0,1),"EMP faded alpha instead of initial brightness")
			state=Appearance.advance(preset,state,150)
			sample=Appearance.sample(preset,state,true)
			var rgb:=0.3125 if preset.preset_id==17 else 0.125
			check(sample.uv_rect==expected and sample.color.is_equal_approx(Color(rgb,rgb,rgb,1)),"EMP changed tile or its two source color ramps")
			state=Appearance.advance(preset,state,int(preset.lifetime_ms)-150)
			check(Appearance.sample(preset,state,true).active,"EMP expired before its inclusive lifetime")
			state=Appearance.advance(preset,state,1)
			check(not Appearance.sample(preset,state,true).active,"EMP survived beyond its lifetime")
		if not emitter.configure_convoy_emp(bindings,int(preset.preset_id),33):check(false,emitter.error);return
		var initial: Dictionary=emitter.snapshot()
		var old_root:=Transform3D(Basis.IDENTITY,Vector3(1000,0,0))
		check(emitter.advance(old_root,100,100)=={"births":0},emitter.error)
		check(emitter.snapshot().random==initial.random and not emitter.snapshot().enabled,"Disabled registration emitted or consumed random samples")
		check(emitter.rebind_transform() and emitter.set_emitting(true),emitter.error)
		var target:=Transform3D(Basis(Vector3.UP,PI/2),Vector3(1500,0,0))
		check(emitter.advance(target,125,125)=={"births":1},"Source 8/s timer did not create its first sprite")
		var live: Dictionary=emitter.snapshot()
		check(live.baseline==target.origin and live.velocity==Vector3(4000,0,0) and live.fade_in_rgb,"Retarget reset the preceding root or lost its manager color mode")
		var fork: RefCounted=emitter.fork_for_frame()
		check(fork.advance(target,0,0)=={"births":0} and fork.snapshot()==live,"Paused EMP changed its timer, particles or RNG")
		check(fork.set_visible(false) and fork.snapshot().slots.all(func(s):return s.appearance.age_ms==-1) and emitter.snapshot()==live,"Prospective hide changed retained particles")
		check(emitter.set_emitting(false),emitter.error)
		check(emitter.advance(target,125,125)=={"births":0} and emitter.snapshot().slots[0].appearance.age_ms==125,"Stopped emitter deleted live particles or continued birthing")
		var before: Dictionary=emitter.snapshot()
		check(emitter.advance(target,-1,0).has("error") and emitter.snapshot()==before,"Invalid EMP frame changed accepted state")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
