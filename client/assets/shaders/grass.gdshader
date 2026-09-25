shader_type spatial;
render_mode diffuse_burley, specular_disabled;

// Mown-lawn stripes plus a little value noise so the big ground plane isn't flat.
uniform vec3 grass_a : source_color = vec3(0.40, 0.72, 0.33);
uniform vec3 grass_b : source_color = vec3(0.37, 0.67, 0.30);
varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float stripe = smoothstep(0.45, 0.55, fract(world_pos.x / 5.0)) * smoothstep(1.0, 0.9, fract(world_pos.x / 5.0));
	vec3 col = mix(grass_a, grass_b, stripe);
	float n = noise(world_pos.xz * 0.35) * 0.6 + noise(world_pos.xz * 1.7) * 0.4;
	col *= 0.92 + n * 0.14;
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
