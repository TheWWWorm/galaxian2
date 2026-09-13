extends SceneTree
const Motion = preload("res://src/simulation/opening_player_motion.gd")
const Definitions = preload("res://src/content/opening_player_motion_definitions.gd")
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Staging = preload("res://src/simulation/opening_staging.gd")
var failures := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	check(not args.is_empty() and args.size()%3==0,"Pass content/bindings/visuals triples")
	for i in range(0,args.size()-2,3): check_profile(args[i],args[i+1])
	print("Opening player motion checks: %d failures" % failures)
	quit(1 if failures else 0)

func check_profile(content: String, path: String) -> void:
	var library := Library.new();var bindings := Bindings.new();var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(path,library.manifest) or not catalogues.open(library):
		check(false,library.error+bindings.error+catalogues.error);return
	var motion := Motion.new();var stage := Staging.new()
	check(stage.configure(bindings,catalogues,bindings.base_content_id),stage.error)
	if bindings.opening_staging.get("player_motion",{}).is_empty():
		check(not motion.configure(bindings),"Legacy pack invented scripted player movement")
		return
	check(motion.configure(bindings),motion.error)
	var scene: Dictionary=stage.snapshot()
	var initial: Dictionary=scene.duplicate(true)
	for phase in 4:
		for delta in [0,1,100,150]:
			var moved: Dictionary=motion.evaluate(scene,phase,delta)
			check(not moved.is_empty(),motion.error)
			if moved.is_empty(): return
			check(moved.prior_pose==scene.player_pose and moved.pose.origin==Vector3(0,0,-60000+2*delta),"Scripted forward displacement disagrees with source units")
			check(moved.pose.basis==scene.player_pose.basis,"Cinematic translation changed heading")
	var turned: Dictionary=scene.duplicate(true)
	turned.player_pose=Transform3D(Basis(Vector3(0,0,-1),Vector3.UP,Vector3.RIGHT),Vector3(40,50,60))
	check(motion.evaluate(turned,2,150).pose.origin==Vector3(340,50,60),"Scripted cruise ignored the current local forward")
	for phase in [-1,4,true,null,0.5]: check(motion.evaluate(scene,phase,100).is_empty(),"Unsupported phase accepted")
	for delta in [-1,151,true,null,0.5]: check(motion.evaluate(scene,0,delta).is_empty(),"Unsupported frame duration accepted")
	for key in ["base_content_id","binding_id"]:
		var bad: Dictionary=scene.duplicate(true);bad[key]="0".repeat(64)
		check(motion.evaluate(bad,0,100).is_empty(),"Cross-content motion accepted")
	var invalid: Dictionary=scene.duplicate(true);invalid.player_pose.basis=Basis.IDENTITY.scaled(Vector3(2,1,1))
	check(motion.evaluate(invalid,0,100).is_empty(),"Scaled simulation basis accepted")
	check(scene==initial and stage.snapshot()==initial,"Motion evaluation mutated its scene")
	var candidate: RefCounted=stage.fork_for_frame()
	var moved: Dictionary=motion.evaluate(scene,0,100)
	check(candidate.adopt_player_motion(moved),candidate.error)
	var after: Dictionary=candidate.snapshot()
	check(not candidate.adopt_player_motion(moved) and candidate.snapshot()==after,"Stale movement applied twice")
	check(stage.snapshot()==initial,"Candidate adoption mutated original stage")
	var flags := [];flags.resize(bindings.opening_dialogue.events.size());flags.fill(false);flags[2]=true
	check(candidate.update({"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"finished":flags}),candidate.error)
	check(candidate.snapshot().player_pose.origin==Vector3(18000,-12000,-40000),"Formation failed to replace the earlier player displacement")
	var architecture: String="armv7" if library.manifest.profile.edition=="ios-hd" else "x86_64"
	var data: Dictionary=bindings.opening_staging.player_motion
	check(Definitions.validate(data,10000000,architecture,bindings.opening_staging).is_empty(),"Actual declaration rejected")
	for key in data.provenance:
		var bad: Dictionary=data.duplicate(true);bad.provenance[key].offset+=2
		check(not Definitions.validate(bad,10000000,architecture,bindings.opening_staging).is_empty(),"Disconnected declaration accepted")
	print(library.manifest.profile.edition,": scripted travel, current heading, handoff boundary, relocation and stale-frame rejection verified")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)
