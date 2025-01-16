package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Scene Normal")
@description("Get scene normal behind current pixel")
@group("Property")
class SceneNormal extends ShaderNodeHxsl {

	static var SRC = {
		@sgoutput var output : Vec3;

        @global var depthMap : Channel;

		@global var global : {
			var pixelSize : Vec2;
		}

		@global var camera : {
			var zNear : Float;
			var zFar : Float;
			var inverseViewProj : Mat4;
		};

        var calculatedUV : Vec2;

		// //! function not supported in shader graph
		// function getWPos(uv : Vec2) : Vec3 {
		// 	var depth = depthMap.get(uv);
		// 	var ruv = vec4(uvToScreen(uv), depth, 1);
		// 	var ppos = ruv * camera.inverseViewProj;
		// 	return ppos.xyz / ppos.w;
		// }

		function fragment() {
			var size = depthMap.size();

			var rightUV = calculatedUV + vec2(1.0, 0.0) * global.pixelSize.x;
			var botUV = calculatedUV + vec2(0.0, 1.0) * global.pixelSize.y;

			var depth = depthMap.get(calculatedUV);
			var ruv = vec4(uvToScreen(calculatedUV), depth, 1);
			var ppos = ruv * camera.inverseViewProj;
			var wpos = ppos.xyz / ppos.w;

			var depth = depthMap.get(rightUV);
			var ruv = vec4(uvToScreen(rightUV), depth, 1);
			var ppos = ruv * camera.inverseViewProj;
			var right = ppos.xyz / ppos.w;

			var depth = depthMap.get(botUV);
			var ruv = vec4(uvToScreen(botUV), depth, 1);
			var ppos = ruv * camera.inverseViewProj;
			var bot = ppos.xyz / ppos.w;

			// var wpos = getWPos(calculatedUV);
			// var right = getWPos(rightUV);
			// var bot = getWPos(botUV);
			output = cross(normalize(right - wpos), normalize(bot - wpos)).normalize();
		}
	};
}
