// Pixel-art lighting over the launch world (same light model as the cruise's light_shade +
// light_glow, but quantised per world pixel with Bayer dithering so it stays pixel art):
// Sun-side shading + vignette (multiply), stepped glow pools from the engine flame and the pad
// floodlights (add), sun rays, a red edge pulse at max-Q, and a white flash on explosions.
shader_type canvas_item;

uniform vec2 sun_pos = vec2(78.0, 54.0);   // in viewport pixels
uniform float sun_power = 1.0;
uniform float space = 0.0;                  // 0 on the ground .. 1 in space (deeper vignette)
uniform int light_count = 0;
uniform vec4 lights[4];                     // x, y, radius, strength (viewport pixels)
uniform vec4 light_colors[4];
uniform float stress = 0.0;                 // 0..1 max-Q structural stress
uniform float flash = 0.0;
uniform float time = 0.0;

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[x + y * 4]) + 0.5) / 16.0;
}

void fragment() {
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 px = floor(UV * size);
	vec3 c = texture(TEXTURE, (px + 0.5) * TEXTURE_PIXEL_SIZE).rgb;
	float b = bayer4(px);
	vec2 center = size * 0.5;
	vec2 cc = (px - center) / center;

	// Multiply: far side from the Sun a bit darker, vignette deeper in space.
	vec2 sdir = normalize(sun_pos - center);
	float lit = smoothstep(-1.1, 0.9, dot(cc * vec2(1.0, 0.56), sdir));
	float shade = mix(1.0 - 0.22 * sun_power, 1.0, lit);
	float v = length(cc * vec2(1.0, 0.9));
	shade *= 1.0 - (0.28 + 0.25 * space) * pow(clamp(v * 0.8, 0.0, 1.0), 2.6);
	shade = floor(shade * 14.0 + b) / 14.0;
	c *= shade;

	// Add: light pools (flame, floodlights), stepped.
	vec3 add = vec3(0.0);
	for (int i = 0; i < light_count; i++) {
		float k = 1.0 - smoothstep(0.0, lights[i].z, length((px - lights[i].xy) * vec2(1.0, 0.85)));
		float g = lights[i].w * k * k;
		add += light_colors[i].rgb * floor(g * 7.0 + b) / 7.0;
	}
	// Sun rays, faint, from the Sun's corner.
	vec2 to_sun = px - sun_pos;
	float ang = atan(to_sun.y, to_sun.x);
	float rays = pow(0.5 + 0.5 * sin(ang * 31.0 + time * 0.2), 12.0) * exp(-length(to_sun) / 220.0);
	add += vec3(1.0, 0.9, 0.7) * floor(rays * sun_power * (1.0 - space) * 5.0 + b) / 5.0 * 0.07;
	c += add;

	// Max-Q: the screen edges pulse red.
	float edge = smoothstep(0.55, 1.15, v);
	float pulse = 0.5 + 0.5 * sin(time * 12.0);
	c = mix(c, vec3(1.0, 0.18, 0.12), floor(stress * edge * pulse * 4.0 + b) / 4.0 * 0.55);

	c += vec3(1.0, 0.9, 0.7) * flash;
	COLOR = vec4(c, 1.0);
}
