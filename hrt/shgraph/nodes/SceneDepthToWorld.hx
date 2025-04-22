package hrt.shgraph.nodes;

using hxsl.Ast;

@name("SceneDepthToWorld")
@description("Transform a scene depth to a world space position")
@group("Property")
class SceneDepthToWorld extends ShaderNodeHxsl {

	static var SRC = {
		@sginput var depth : Float;
		@sgoutput var output : Vec3;

		@global var camera : {
			var inverseViewProj : Mat4;
		};

        var screenUV : Vec2;

		function fragment() {
			var ruv = vec4(uvToScreen(screenUV), depth, 1);
			var ppos = ruv * camera.inverseViewProj;
			output = ppos.xyz / ppos.w;
		}
	};
}
