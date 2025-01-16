package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Scene Pos")
@description("Get scene position behind current pixel")
@group("Property")
class ScenePos extends ShaderNodeHxsl {

	static var SRC = {
		@sgoutput var output : Vec3;

        @global var depthMap : Channel;

		@global var camera : {
			var zNear : Float;
			var zFar : Float;
			var inverseViewProj : Mat4;
		};

        var calculatedUV : Vec2;

		function fragment() {
			var depth = depthMap.get(calculatedUV);
			var ruv = vec4(uvToScreen(calculatedUV), depth, 1);
			var ppos = ruv * camera.inverseViewProj;
			output = ppos.xyz / ppos.w;
		}
	};
}
