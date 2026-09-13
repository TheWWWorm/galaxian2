uniform vec2 uv_offset = vec2(0.0);
uniform vec2 uv_scale = vec2(1.0);
uniform float uv_angle = 0.0;

vec2 source_uv(vec2 input_uv) {
	vec2 centered = input_uv * uv_scale - vec2(0.5);
	float c = cos(uv_angle);
	float s = sin(uv_angle);
	return mat2(vec2(c, s), vec2(-s, c)) * centered + vec2(0.5) + uv_offset;
}
