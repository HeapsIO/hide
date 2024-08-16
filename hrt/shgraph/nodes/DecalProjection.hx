package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Decal Projection")
@description("Apply decal projection on UVs")
@group("UV")
class DecalProjection extends ShaderNodeHxsl {

	static var SRC = {
		@sginput("calculatedUV") var uv : Vec2;
		@sgoutput var output : Vec2;

        @global var camera : {
			var inverseViewProj : Mat4;
		};

		@global var global : {
			@perObject var modelViewInverse : Mat4;
		};

        @global var depthMap : Channel;

        var projectedPosition : Vec4;

		function fragment() {
            var matrix = camera.inverseViewProj * global.modelViewInverse;
            var screenPos = projectedPosition.xy / projectedPosition.w;
            var depth = depthMap.get(screenToUv(screenPos));
            var ruv = vec4( screenPos, depth, 1 );
            var wpos = ruv * matrix;
            var lpos = (wpos.xyz / wpos.w);
            output = lpos.xy + 0.5;
		}
	};

}
