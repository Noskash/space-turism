// Assembly hangar lighting: one pass over the whole world (map, rocket, crew, decor, gantry),
// below the prompts and the UI. Reads what is already drawn and relights it:
//   - dim ambient with a soft vignette, cool blue shadows
//   - warm ceiling lamp pools, the orange glow out of the launch silo, role-coloured shelf glow,
//     screen glow (board, computers, planner console), the radio pulsing with the beat
//   - skylight shafts falling across the bay (dust motes are drawn by HangarDecor.Motes)
//   - a rotating beacon at the launch door (amber, green when every player is READY)
// Pixel-art rules: light is computed once per 480x270 game pixel and quantised into hard bands
// with a 4x4 Bayer dither, so there are no smooth gradients even at canvas_items resolution.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float time = 0.0;
uniform float ambient = 0.6;
uniform int light_count = 0;
uniform vec4 lights[16];          // x, y, radius, strength
uniform vec4 light_colors[16];    // rgb, unused
uniform vec2 beacon_pos = vec2(466.0, 3.0);
uniform float beacon_angle = 0.0;
uniform vec4 beacon_color = vec4(1.0, 0.65, 0.15, 0.0);   // rgb, strength
uniform float shafts = 1.0;

varying vec2 world;

void vertex() {
	world = VERTEX;
}

float bayer2(vec2 a) {
	a = floor(a);
	return fract(dot(a, vec2(0.5, a.y * 0.75)));
}

float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

float shaft(float u, float centre, float half_w) {
	return 1.0 - smoothstep(half_w * 0.4, half_w, abs(u - centre));
}

void fragment() {
	vec2 px = floor(world) + 0.5;                    // one light value per game pixel
	vec3 base = texture(screen_tex, SCREEN_UV).rgb;

	vec2 c = (px - vec2(240.0, 135.0)) / vec2(240.0, 135.0);
	float vig = smoothstep(0.5, 1.3, length(c));
	vec3 light = vec3(ambient) * (1.0 - 0.42 * vig);

	for (int i = 0; i < light_count; i++) {
		float k = clamp(1.0 - length(px - lights[i].xy) / lights[i].z, 0.0, 1.0);
		light += light_colors[i].rgb * lights[i].w * k * k;
	}

	if (beacon_color.a > 0.0) {
		vec2 d = px - beacon_pos;
		float a = atan(d.y, d.x);
		float diff = abs(mod(a - beacon_angle + PI, TAU) - PI);
		float cone = (1.0 - smoothstep(0.08, 0.38, diff)) * clamp(1.0 - length(d) / 170.0, 0.0, 1.0);
		light += beacon_color.rgb * beacon_color.a * cone;
	}

	// Skylight shafts over the bay, slanting down-left, fading towards the floor.
	float u = px.x + px.y * 0.55;
	float s = shaft(u, 292.0 + sin(time * 0.31) * 2.0, 13.0)
			+ 0.6 * shaft(u, 318.0 + sin(time * 0.37 + 1.3) * 2.0, 6.0)
			+ 0.85 * shaft(u, 352.0 + sin(time * 0.27 + 2.1) * 2.0, 10.0);
	s *= clamp(1.0 - px.y / 240.0, 0.0, 1.0) * (0.85 + 0.15 * sin(time * 0.7));
	light += vec3(0.72, 0.84, 1.0) * 0.28 * s * shafts;

	// Hard bands + ordered dither: pixel-art lighting.
	light = floor(light * 12.0 + bayer4(px)) / 12.0;

	vec3 col = base * light;
	float lum = clamp(dot(light, vec3(0.3, 0.5, 0.2)), 0.0, 1.0);
	col = mix(col * vec3(0.78, 0.86, 1.2), col, lum);    // cool blue shadows, neutral in the light
	col += max(light - vec3(1.0), vec3(0.0)) * 0.16;      // bright pools bloom a touch
	COLOR = vec4(col, 1.0);
}
