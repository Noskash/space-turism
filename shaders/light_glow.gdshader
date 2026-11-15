// Additive pass: sunlight + soft god rays from the Sun's side, blue Earthshine fading behind us,
// orange Mars glow growing on approach, station light pools, and solar-storm shimmer.
shader_type canvas_item;
render_mode blend_add;

uniform vec2 sun_pos = vec2(-90.0, 135.0);
uniform float sun_power = 1.0;
uniform vec3 sun_color = vec3(1.0, 0.92, 0.75);
uniform vec2 earth_pos = vec2(14.0, 262.0);
uniform float earth_power = 1.0;
uniform vec2 mars_pos = vec2(470.0, 8.0);
uniform float mars_power = 0.0;
uniform float storm = 0.0;
uniform float time = 0.0;
uniform float wave = -1.0;         // radiation wave front 0..1 (from the Sun's side), <0 = none
uniform vec2 sun_dir = vec2(-1.0, 0.0);
uniform int light_count = 0;
uniform vec4 lights[8];        // x, y, radius, strength
uniform vec4 light_colors[8];

varying vec2 world;

void vertex() {
	world = VERTEX;
}

void fragment() {
	vec3 add = vec3(0.0);
	vec2 to_sun = world - sun_pos;
	float d = length(to_sun);
	add += sun_color * sun_power * 0.30 * exp(-d / 190.0);
	float angle = atan(to_sun.y, to_sun.x);
	float rays = pow(0.5 + 0.5 * sin(angle * 37.0 + time * 0.25), 10.0)
			* (0.6 + 0.4 * sin(angle * 11.0 - time * 0.4));
	add += sun_color * rays * sun_power * 0.10 * exp(-d / 260.0);

	add += vec3(0.25, 0.5, 1.0) * earth_power * 0.16 * exp(-length(world - earth_pos) / 110.0);
	add += vec3(1.0, 0.42, 0.18) * mars_power * 0.24 * exp(-length(world - mars_pos) / 150.0);

	for (int i = 0; i < light_count; i++) {
		float k = 1.0 - smoothstep(0.0, lights[i].z, length(world - lights[i].xy));
		add += light_colors[i].rgb * lights[i].w * k * k;
	}

	if (storm > 0.0) {
		vec2 dir = normalize(sun_pos - vec2(240.0, 135.0));
		float facing = smoothstep(-0.3, 1.0, dot((world - vec2(240.0, 135.0)) / 240.0, dir));
		float ripple = 0.5 + 0.5 * sin(dot(world, vec2(0.045, 0.03)) + time * 5.0)
				* sin(dot(world, vec2(-0.02, 0.05)) - time * 3.3);
		add += mix(vec3(0.3, 1.0, 0.6), vec3(0.7, 0.35, 1.0), ripple) * storm * 0.13 * ripple * facing;
	}
	if (wave >= 0.0) {
		// a bright green-white band sweeps across the ship, away from the Sun
		float along = dot((world - vec2(240.0, 135.0)) / vec2(240.0, 135.0), -sun_dir);
		float front = mix(-1.4, 1.4, wave);
		float band = exp(-pow((along - front) / 0.16, 2.0));
		float behind = smoothstep(0.0, -0.6, along - front) * 0.25;
		float crackle = 0.7 + 0.3 * sin(world.y * 0.9 + time * 40.0) * sin(world.x * 0.7 - time * 31.0);
		add += vec3(0.55, 1.0, 0.7) * (band * 0.55 * crackle + behind * 0.12);
	}
	COLOR = vec4(add, 1.0);
}
