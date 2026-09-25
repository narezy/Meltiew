shader_type sky;
// Sky for studio places: a gradient with sun, stars and soft clouds,
// or six custom images (Sky.Preset = Custom).

uniform vec3 top_color : source_color = vec3(0.44, 0.66, 0.94);
uniform vec3 horizon_color : source_color = vec3(0.85, 0.93, 1.0);
uniform vec3 bottom_color : source_color = vec3(0.62, 0.68, 0.74);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.8);
uniform float sun_size = 0.035;
uniform bool sun_visible = true;
uniform float stars = 0.0;
uniform float clouds = 0.0;
uniform float time_scale = 0.01;

uniform bool custom = false;
uniform sampler2D face_up : source_color, filter_linear;
uniform sampler2D face_down : source_color, filter_linear;
uniform sampler2D face_front : source_color, filter_linear;
uniform sampler2D face_back : source_color, filter_linear;
uniform sampler2D face_left : source_color, filter_linear;
uniform sampler2D face_right : source_color, filter_linear;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec3 cube_face(vec3 d) {
	vec3 a = abs(d);
	if (a.y >= a.x && a.y >= a.z) {
		vec2 uv = d.y > 0.0 ? vec2(d.x, d.z) / a.y : vec2(d.x, -d.z) / a.y;
		uv = uv * 0.5 + 0.5;
		return d.y > 0.0 ? texture(face_up, uv).rgb : texture(face_down, uv).rgb;
	} else if (a.x >= a.z) {
		vec2 uv = vec2(d.x > 0.0 ? d.z : -d.z, -d.y) / a.x * 0.5 + 0.5;
		return d.x > 0.0 ? texture(face_right, uv).rgb : texture(face_left, uv).rgb;
	}
	vec2 uv = vec2(d.z > 0.0 ? -d.x : d.x, -d.y) / a.z * 0.5 + 0.5;
	return d.z > 0.0 ? texture(face_back, uv).rgb : texture(face_front, uv).rgb;
}

void sky() {
	vec3 d = EYEDIR;
	if (custom) {
		COLOR = cube_face(d);
	} else {
		float h = d.y;
		vec3 col = h > 0.0 ? mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.6)) : mix(horizon_color, bottom_color, clamp(-h * 3.0, 0.0, 1.0));
		if (stars > 0.0 && h > 0.0) {
			vec2 g = d.xz / (h + 0.4) * 180.0;
			float s = step(0.996, hash(floor(g))) * smoothstep(0.0, 0.3, h);
			col += vec3(s) * stars;
		}
		if (clouds > 0.0 && h > 0.02) {
			vec2 p = d.xz / h * 1.4 + vec2(TIME * time_scale, 0.0);
			float n = noise(p) * 0.6 + noise(p * 2.3) * 0.3 + noise(p * 5.1) * 0.1;
			float c = smoothstep(0.55, 0.8, n) * smoothstep(0.02, 0.25, h) * clouds;
			col = mix(col, vec3(1.0), c * 0.85);
		}
		if (sun_visible) {
			float sd = distance(d, -LIGHT0_DIRECTION);
			col += sun_color * (smoothstep(sun_size, sun_size * 0.6, sd) + 0.25 * smoothstep(sun_size * 6.0, 0.0, sd)) * LIGHT0_ENERGY;
		}
		COLOR = col;
	}
}
