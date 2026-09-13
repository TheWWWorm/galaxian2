#include "res://src/presentation/material_sampling.gdshaderinc"

void vertex() {
	imported_vertex_color = has_vertex_color ? CUSTOM0 : vec4(1.0);
}
