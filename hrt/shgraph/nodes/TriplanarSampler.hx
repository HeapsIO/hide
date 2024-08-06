package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Triplanar sampler")
@description("Sample a texture using triplanar params")
@width(160)
@group("Math")
class TriplanarSampler extends Sampler {

	static var SRC = {
		@sginput var texture : Sampler2D;
		@sginput var weight : Vec3;
		@sginput var uvX : Vec2;
		@sginput var uvY : Vec2;
		@sginput var uvZ : Vec2;
		@sgoutput var RGBA : Vec4;

		function fragment() {
			RGBA = texture.get(uvX) * weight.x 
				+ texture.get(uvY) * weight.y
				+ texture.get(uvZ) * weight.z;
		}
	};
}