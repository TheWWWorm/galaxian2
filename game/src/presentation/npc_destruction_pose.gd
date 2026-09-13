extends RefCounted
## Type-zero explosion roots. Source body drawing lasts through mode-4 time 299.
## Attached additive geometry shares the primary root; debris is independent.
const Player = preload("res://src/simulation/player_destruction.gd")
const Death = preload("res://src/simulation/npc_destruction.gd")
const Billboard = preload("res://src/presentation/scenery_effect_pose.gd")
const Vectors = preload("res://src/simulation/source_vectors.gd")
const BODY_LAST_MS := 299

static func for_death(death: RefCounted, camera: Transform3D) -> Dictionary:
	if not (death is Death or death is Player) or death.presentation_identity()==null: return {"error":"NPC presentation requires its native death owner"}
	var state: Dictionary=death.snapshot()
	if not camera.is_finite(): return {"error":"NPC explosion camera must be finite"}
	var body: bool=state.body_visible if death is Player else state.phase in ["ready","tumble"] or (state.phase=="explosion" and state.countdown_ms<=BODY_LAST_MS)
	# The authored second-trip cue can reactivate an exhausted actor while an
	# older explosion remains active. Source draw submits that effect in both
	# death modes, retaining its position and animation clock through the tumble.
	var retained: bool=state.get("campaign_cursor")==4 and state.get("appearance_applied",false)
	if not state.effect.active or (retained and state.phase=="ready"): return {"body_visible":body,"effect_visible":false,"roots":[]}
	if (not death is Player and state.phase!="explosion" and not (retained and state.phase=="tumble")) or not state.effect.position is Vector3: return {"error":"Invalid NPC explosion phase or position"}
	var billboard := Billboard.alpha_root(camera,state.effect.position,1.0)
	if billboard.has("error"): return billboard
	var roots: Array[Transform3D]=[billboard.pose,billboard.pose]
	for fragment in state.fragments:
		var basis := Vectors.local_xyz(fragment.rotation_radians)
		for axis in 3: basis[axis]=Vectors.scaled(basis[axis],fragment.scale)
		var pose := Transform3D(basis,state.effect.position)
		if not pose.is_finite(): return {"error":"NPC fragment pose exceeded source precision"}
		roots.append(pose)
	return {"body_visible":body,"effect_visible":true,"roots":roots}
