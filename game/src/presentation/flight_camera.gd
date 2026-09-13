extends RefCounted
## Native perspective presentation. The scene supplies the recovered location
## comparison result explicitly; this component never infers it from an actor ID.
const Definitions = preload("res://src/content/flight_projection_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
var _settings := {}

func configure(data: Dictionary, campaign_cursor: Variant, matching_location: Variant) -> String:
	_settings = {}
	if not Definitions.parameters(data): return "Flight projection is unavailable or invalid"
	if not Numbers.integer(campaign_cursor, 0, 2147483647) or not matching_location is bool:
		return "Flight projection requires verified campaign and location state"
	var far_plane: float = data.matching_location_early_far if matching_location and campaign_cursor < data.early_cursor_limit else data.far
	_settings = {"fov_degrees": rad_to_deg(data.vertical_fov_radians), "near": float(data.near), "far": far_plane}
	return ""

func settings() -> Dictionary:
	return _settings.duplicate(true)

func apply(camera: Camera3D, view: Dictionary) -> String:
	if _settings.is_empty(): return "Flight projection has not been configured"
	if not is_instance_valid(camera): return "Flight camera is missing"
	var pose: Variant = view.get("pose")
	if not pose is Transform3D or not pose.origin.is_finite() or not pose.basis.is_finite(): return "Flight view is invalid"
	if not pose.basis.is_equal_approx(pose.basis.orthonormalized()) or pose.basis.determinant() <= 0.0:
		return "Flight view must have a proper camera orientation"
	# Godot manages viewport size and device rotation. KEEP_HEIGHT preserves the
	# source vertical field of view while horizontal coverage changes with aspect.
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.set_perspective(_settings.fov_degrees, _settings.near, _settings.far)
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	camera.global_transform = pose
	return ""
