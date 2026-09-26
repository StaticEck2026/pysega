shader_type canvas_item;
// Draw an index texture (*.idx.png: pixel value = colour index 0-15) through a
// palette texture (*.pal.png: 16 x N, one row per palette line). Swapping the
// palette texture or the line reproduces Mega Drive palette tricks such as team
// kit colours and fades without touching the graphics.

uniform sampler2D palette : filter_nearest;
uniform int palette_line = 0;
uniform bool index0_transparent = true;

void fragment() {
	int idx = int(round(texture(TEXTURE, UV).r * 255.0));
	if (index0_transparent && idx == 0) {
		discard;
	}
	COLOR = texelFetch(palette, ivec2(idx, palette_line), 0);
}
