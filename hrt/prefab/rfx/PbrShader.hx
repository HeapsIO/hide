package hrt.prefab.rfx;

class PbrShader extends h3d.shader.ScreenShader {

	static var SRC = {

		@global var depthMap : Channel;
		@global var occlusionMap : Channel;
		@global var hdrMap : Channel;
		@global var camera : {
			var position : Vec3;
			var inverseViewProj : Mat4;
		};
		@global var global : {
			var time : Float;
		};

		function getPositionAt( uv: Vec2 ) : Vec3 {
			var depth = depthMap.get(uv);
			var uv2 = uvToScreen(uv);
			var temp = vec4(uv2, depth, 1) * camera.inverseViewProj;
			var originWS = temp.xyz / temp.w;
			return originWS;
		}

		function getPosition() : Vec3 {
			return getPositionAt(calculatedUV);
		}

	};

}