shader_type spatial;
render_mode unshaded, cull_back;
#include "res://src/presentation/material_sampling.gdshaderinc"

// Native one-light opaque texturing, used by the original local-map models.
uniform vec3 light_position = vec3(0.0);
uniform vec3 ambient_color = vec3(0.0);
uniform vec3 diffuse_color = vec3(1.0);
varying vec3 illumination;

void vertex() {
	vec3 point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 surface_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	float facing = max(0.0, dot(surface_normal, normalize(light_position - point)));
	illumination = ambient_color + facing * diffuse_color;
	imported_vertex_color = vec4(1.0);
}
void fragment() {
	ALBEDO = source_diffuse(UV).rgb * illumination;
}
