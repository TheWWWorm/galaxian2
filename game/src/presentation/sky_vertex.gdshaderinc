#include "res://src/presentation/material_sampling.gdshaderinc"
void vertex() {
	imported_vertex_color = has_vertex_color ? CUSTOM0 : vec4(1.0);
	// Camera and world translation are intentionally absent. Preserve the source
	// orientation and perspective while placing the background at far depth.
	vec3 direction = mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX) * VERTEX;
	POSITION = PROJECTION_MATRIX * vec4(direction, 1.0);
	POSITION.z = CLIP_SPACE_FAR * POSITION.w;
}
