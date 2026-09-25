shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Stylized lighting for the playground: soft two-tone diffuse, gentle rim,
// colors come from vertex colors (world batches) or the `tint` uniform.
uniform vec4 tint : source_color = vec4(1.0);
uniform bool use_vertex_color = true;
uniform float rim_strength = 0.18;

void fragment() {
	vec3 base = use_vertex_color ? COLOR.rgb : vec3(1.0);
	ALBEDO = base * tint.rgb;
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = ALBEDO * rim * rim_strength;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// Wrapped, slightly banded lambert keeps shadows colorful instead of black.
	float wrap = smoothstep(-0.35, 0.75, ndl);
	wrap = mix(wrap, floor(wrap * 3.0 + 0.5) / 3.0, 0.25);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * ATTENUATION * wrap;
}
