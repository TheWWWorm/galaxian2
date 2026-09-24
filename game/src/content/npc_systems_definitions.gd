extends RefCounted
## Compose ordinary ships from the shared factory and reaction declarations.
## These spans are already verified by the imported fighter/lifecycle readers.
const Fighters=preload("res://src/content/kappa_fighters_definitions.gd")
const Reactions=preload("res://src/content/kappa_lifecycle_definitions.gd")
const EMP=preload("res://src/content/emp_bombs_definitions.gd")
const Lifecycle=preload("res://src/content/ambient_lifecycle_definitions.gd")
const Standing=preload("res://src/content/free_lifecycle_definitions.gd")
const Freighter=preload("res://src/content/freighter_destruction_definitions.gd")

static func available(bindings: RefCounted) -> bool:
	return Fighters.available(bindings) and Reactions.available(bindings) and EMP.available(bindings) and Lifecycle.recycling_parameters(bindings.ambient_lifecycle) and Standing.available(bindings) and Freighter.parameters(bindings.freighter_destruction)

static func systems(bindings: RefCounted,rank: int,subtype: int) -> Dictionary:
	if not available(bindings) or subtype not in [0,1]:return {}
	var result:=Fighters.systems(bindings,rank)
	if result.is_empty():return {}
	# The same verified factory triples both values for subtype one. This is
	# independent of its separate hull and difficulty scaling.
	if subtype==1:
		result.capacity*=3;result.recovery_ms*=3
	return result

static func reputation(bindings: RefCounted,faction: int) -> Dictionary:
	if not available(bindings):return {}
	var standing: Dictionary=bindings.mido_travel.free_lifecycle.standing
	if faction<0 or faction>=standing.axes.size():return {"axis":0,"change":0}
	return {"axis":int(standing.axes[faction]),"change":absi(int(bindings.mido_travel.kappa_lifecycle.systems.reputation_change))*int(standing.hostile_signs[faction])}
