shader_type canvas_item;

// Screen-space glow shader for HDR 2D
// Works with BackBufferCopy or SCREEN_TEXTURE

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float glow_intensity : hint_range(0.0, 3.0) = 1.0;
uniform float glow_spread : hint_range(0.0, 10.0) = 3.0;
uniform vec4 glow_tint : source_color = vec4(0.6, 0.85, 1.0, 1.0);

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	
	// Multi-pass blur for smooth glow
	vec4 glow = vec4(0.0);
	float total_weight = 0.0;
	
	int samples = 12;
	for (int i = 0; i < samples; i++) {
		float angle = float(i) * 6.28318 / float(samples);
		
		for (int j = 1; j <= 3; j++) {
			float radius = float(j) * glow_spread;
			vec2 offset = vec2(cos(angle), sin(angle)) * radius * TEXTURE_PIXEL_SIZE;
			
			vec4 sample_color = texture(TEXTURE, UV + offset);
			float weight = 1.0 / float(j);
			
			glow += sample_color * weight;
			total_weight += weight;
		}
	}
	
	if (total_weight > 0.0) {
		glow /= total_weight;
		glow.rgb *= glow_tint.rgb;
		
		// Additive blending for glow
		COLOR = color + glow * glow_intensity;
	} else {
		COLOR = color;
	}
}

