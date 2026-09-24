extends RefCounted
## Target HUD geometry for an ordinary, already oriented flight viewport.
## Render visibility and marker placement are deliberately separate: the source
## uses the center frame ellipse for failed projections, including rear targets.
## This component neither chooses targets nor advances a scanner clock.
const Definitions = preload("res://src/content/flight_projection_definitions.gd")
# Keep extreme offscreen displacements within both float32 and signed pixels.
# This limit is far outside every supported viewport and preserves direction.
const SCREEN_DELTA_LIMIT := 1073741824.0
const STABLE_ELLIPSE_DISTANCE := 1048576.0
var error := ""
var _size := Vector2i.ZERO
var _center := Vector2i.ZERO
var _tangents := Vector2.ZERO
var _inverse_squared_radii := Vector2.ZERO
var _near := 0.0

func configure(data: Dictionary, viewport_size: Vector2i, frame_radii := Vector2.ONE) -> bool:
	clear()
	if not Definitions.parameters(data): return reject("Target projection requires imported flight perspective")
	if viewport_size.x < 1 or viewport_size.y < 1 or viewport_size.x > 32767 or viewport_size.y > 32767:
		return reject("Target projection requires a positive supported viewport")
	if not frame_radii.is_finite() or frame_radii.x < 1 or frame_radii.y < 1 or frame_radii.x > 32767 or frame_radii.y > 32767:
		return reject("Target projection requires finite center-frame radii")
	# The source metrics retain single-precision sine/cosine and aspect products.
	var half_fov := single(single(float(data.vertical_fov_radians)) / 2.0)
	var vertical := single(single(sin(half_fov)) / single(cos(half_fov)))
	_tangents = Vector2(single(single(float(viewport_size.x) / viewport_size.y) * vertical),vertical)
	if not _tangents.is_finite() or _tangents.x <= 0 or _tangents.y <= 0:
		return reject("Target perspective exceeds supported precision")
	_inverse_squared_radii = Vector2(single(1.0 / single(frame_radii.x * frame_radii.x)),single(1.0 / single(frame_radii.y * frame_radii.y)))
	_size = viewport_size
	_center = Vector2i(viewport_size.x >> 1,viewport_size.y >> 1)
	_near = single(float(data.near))
	return true

func project_point(camera: Transform3D, position: Vector3) -> Dictionary:
	error = ""
	if _size == Vector2i.ZERO: return failure("Configure target projection before projecting")
	if not camera.is_finite() or not position.is_finite() or not camera.basis.is_equal_approx(camera.basis.orthonormalized()) or camera.basis.determinant() <= 0:
		return failure("Target projection requires a finite proper camera and world position")
	# Evaluate the rigid inverse as rotated point plus rotated translation. This
	# preserves source precision for large translated worlds; subtracting the eye
	# first produces different cancellation at pixel and acquisition boundaries.
	var local := Vector3.ZERO
	for axis in 3:
		local[axis] = single(dot_single(camera.basis[axis],position) - dot_single(camera.basis[axis],camera.origin))
	if not local.is_finite(): return failure("Target camera coordinates exceed source precision")
	var x := float(local.x)
	var y := float(local.y)
	var projected := false
	# This is the recovered HUD predicate. Godot's near clip and behind-camera
	# helpers have different behavior: the source accepts Z equal to +near.
	var depth := Vector2(single(_tangents.x * local.z),single(_tangents.y * local.z))
	if local.z <= _near and depth.x != 0 and depth.y != 0:
		x = -float(_size.x) * (float(local.x) / 2.0 / depth.x) + _center.x
		y = float(_size.y) * (float(local.y) / 2.0 / depth.y) + _center.y
		projected = true
	# A finite target crossing the camera plane can have arbitrarily large
	# projected coordinates. Bound its displacement radially in double precision
	# before float32 storage/integer conversion; it stays offscreen and retains
	# the same ellipse intersection. Ordinary pixel positions remain unchanged.
	var dx := x - _center.x
	var dy := y - _center.y
	var magnitude := maxf(absf(dx),absf(dy))
	if magnitude > SCREEN_DELTA_LIMIT:
		var scale := SCREEN_DELTA_LIMIT / magnitude
		x = _center.x + dx * scale
		y = _center.y + dy * scale
	var screen := Vector2(single(x),single(y))
	if not screen.is_finite(): return failure("Target projection exceeds source precision")
	var in_view := projected and screen.x >= 0 and screen.y >= 0 and screen.x < _size.x and screen.y < _size.y
	return {"camera_position":local,"projected":projected,"in_view":in_view,"screen_position":screen}

func project(camera: Transform3D, position: Vector3) -> Dictionary:
	var result := project_point(camera,position)
	if result.has("error"): return result
	var local: Vector3 = result.camera_position
	var screen: Vector2 = result.screen_position
	var in_view: bool = result.in_view
	if not safe_pixel(screen.x) or not safe_pixel(screen.y): return failure("Target projection exceeds signed pixel coordinates")
	var pixels := Vector2i(int(screen.x),int(screen.y))
	var clamped := false
	if not in_view:
		# A failed early projection retains camera X/Y as the ellipse input and
		# camera X/-Y as its fallback. Do not turn every failure into an edge arrow.
		var fallback := Vector2(local.x,-local.y)
		var delta := Vector2(float(_center.x)-pixels.x,float(_center.y)-pixels.y)
		if not safe_pixel(delta.x) or not safe_pixel(delta.y): return failure("Target ellipse displacement exceeds signed pixel coordinates")
		if maxf(absf(delta.x),absf(delta.y)) > STABLE_ELLIPSE_DISTANCE:
			# Adding nearly opposite large float32 values loses the small marker
			# offset. Normalize first, then add the viewport center instead.
			var distance := sqrt(float(delta.x)*delta.x*_inverse_squared_radii.x + float(delta.y)*delta.y*_inverse_squared_radii.y)
			fallback = Vector2(single(_center.x-float(delta.x)/distance),single(_center.y-float(delta.y)/distance))
			clamped = true
		else:
			var q := single(single(single(delta.x * delta.x) * _inverse_squared_radii.x) + single(single(delta.y * delta.y) * _inverse_squared_radii.y))
			if is_finite(q) and q > 0:
				var weight := single(single(q - single(sqrt(q))) / q)
				if weight >= 0 and weight <= 1:
					fallback = Vector2(single(float(pixels.x) + single(delta.x * weight)),single(float(pixels.y) + single(delta.y * weight)))
					clamped = true
		if not safe_pixel(fallback.x) or not safe_pixel(fallback.y): return failure("Target marker exceeds signed pixel coordinates")
		pixels = Vector2i(int(fallback.x),int(fallback.y))
	result.pixels=pixels;result.ellipse_clamped=clamped
	return result

func clear() -> void:
	error = ""
	_size = Vector2i.ZERO
	_center = Vector2i.ZERO
	_tangents = Vector2.ZERO
	_inverse_squared_radii = Vector2.ZERO
	_near = 0.0

static func single(value: float) -> float:
	return PackedFloat32Array([value])[0]

static func dot_single(axis: Vector3, point: Vector3) -> float:
	return single(single(single(axis.x * point.x) + single(axis.y * point.y)) + single(axis.z * point.z))

static func safe_pixel(value: float) -> bool:
	# Values outside this range have architecture-dependent integer conversions.
	return is_finite(value) and value > -2147483648.0 and value < 2147483648.0

func reject(message: String) -> bool:
	error = message
	return false

func failure(message: String) -> Dictionary:
	reject(message)
	return {"error":message}
