import package::fullscreen_vertex_shader::FullscreenVertexOutput;
@if(SRGB_TO_LINEAR) import bevy_render::color_operations::srgb_to_linear;
@if(OKLAB_TO_LINEAR) import bevy_render::color_operations::oklab_to_linear_rgb;

@group(0) @binding(0) var in_texture: texture_2d<f32>;
@group(0) @binding(1) var in_sampler: sampler;
// NVForever HDR output: x the HUD's white in nits over scRGB's 80 (blit/mod.rs).
@group(0) @binding(2) var<uniform> nvf_hdr_scale: vec4<f32>;

@fragment
fn fs_main(in: FullscreenVertexOutput) -> @location(0) vec4<f32> {
    var color = textureSample(in_texture, in_sampler, in.uv);
    @if(SRGB_TO_LINEAR)
    color = vec4(srgb_to_linear(color.rgb), color.a);
    @if(OKLAB_TO_LINEAR)
    color = vec4(oklab_to_linear_rgb(color.rgb), color.a);
    // NVForever HDR output, gamma: the game was made for SDR screens that decode with gamma
    // 2.2; linear values decoded from sRGB's curve lift the shadows. Within 0..1 the value is
    // encoded with sRGB's curve and decoded with 2.2; above 1 (highlights) it stays.
    @if(NVF_HDR_GAMMA22)
    {
        let c = clamp(color.rgb, vec3(0.0), vec3(1.0));
        let enc = select(1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, c * 12.92, c <= vec3(0.0031308));
        color = vec4(select(color.rgb, pow(enc, vec3(2.2)), color.rgb <= vec3(1.0)), color.a);
    }
    // NVForever HDR output: scRGB's 1.0 is 80 nits; display-referred 1.0 goes to the HUD's white.
    @if(NVF_HDR_PAPER_WHITE)
    color = vec4(color.rgb * nvf_hdr_scale.x, color.a);
    // NVForever HDR10: scRGB (Rec.709, 1.0 = 80 nits) to BT.2020 primaries and SMPTE ST 2084 PQ.
    @if(NVF_HDR_PQ)
    {
        let rgb = max(color.rgb, vec3(0.0));
        let p2020 = vec3(
            dot(rgb, vec3(0.627404, 0.329283, 0.043313)),
            dot(rgb, vec3(0.069097, 0.919540, 0.011362)),
            dot(rgb, vec3(0.016391, 0.088013, 0.895595)));
        let y = pow(clamp(p2020 * (80.0 / 10000.0), vec3(0.0), vec3(1.0)), vec3(0.1593017578125));
        let pq = pow((0.8359375 + 18.8515625 * y) / (1.0 + 18.6875 * y), vec3(78.84375));
        // Dither of +-0.5 code value of 10 bits (a hash of the pixel), so smooth skies do not band.
        let h = fract(52.9829189 * fract(dot(in.position.xy, vec2(0.06711056, 0.00583715))));
        color = vec4(clamp(pq + (h - 0.5) / 1023.0, vec3(0.0), vec3(1.0)), color.a);
    }
    return color;
}
