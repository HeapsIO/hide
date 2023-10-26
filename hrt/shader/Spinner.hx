package hrt.shader;

class Spinner extends hxsl.Shader {

	static var SRC = {

		var pixelColor : Vec4;

		@param var shapeSDF : Sampler2D;
		@param var trailTexture : Sampler2D;


		@param var scaleX : Float = 1.0;
		@param var scaleY : Float = 1.0;
		@param var scaleTime : Float = 1.0;

		@param var timeOffset : Float = 0.0;

		@const var correctTextureNormals : Bool = false;


		@param var numTrails : Float = 3;

		@const var useTimeTexture : Bool = false;
		@param var timeTexture : Sampler2D;

		@const var debugShowShape : Bool = false;
		/*@const var debugShowUVs : Bool = false;
		@const var debugShowNorm : Bool = false;
		@const var debugShowUVSurface : Bool = false;
		@const var debugShowSDF : Bool = false;*/


		@global var global : {
			var time: Float;
		};

		var calculatedUV : Vec2;


		function dist(uv: Vec2) : Float {
			var c = shapeSDF.get(uv);
			return max(min(c.r, c.b), min(max(c.r, c.g), c.b)) - 0.5;
		}

        function fragment() {
			var uv = calculatedUV;
			var sdf = dist(uv);

			var uvSurface =  calculatedUV - vec2(0.5);
			if (correctTextureNormals) {
				var dd = vec3(1.0/shapeSDF.size().x, 1.0/shapeSDF.size().y, 0.0);
				var norm = normalize(vec2(
					dist(uv + dd.xz) - dist(uv - dd.xz),
					dist(uv + dd.zy) - dist(uv - dd.zy))
				);
				uvSurface -= norm * sdf * 0.25;
			};

			var g = useTimeTexture ? timeTexture.get(uv).r : atan(uvSurface.y, uvSurface.x) / (2*3.1415) + 0.5;

			var trueTime = global.time*scaleTime + timeOffset;
			var t = g - mod(trueTime, 1.0);

			t = 1.0-mod(t, 1.0);
			t = mod(t*numTrails, 1.0);

			var uvLocal = vec2(1.0-t, ((scaleY - sdf) / scaleY)/2.0);

			uvLocal.x = 1.0-(1.0-uvLocal.x)/scaleX;
			uvLocal = clamp(uvLocal, vec2(0.01), vec2(1.0));

			var trail = trailTexture.get(uvLocal);
			/*if (debugShowUVs) {
				trail.rgba = vec4(uvLocal.x, uvLocal.y, 1.0, 1.0);
			}
			if (debugShowUVSurface) {
				trail.rgba = vec4(uvSurface.x*0.5+0.5, uvSurface.y*0.5+0.5, 0.0, 1.0);
			}
			if (debugShowSDF) {
				trail.rgba = vec4(sdf, sdf ,sdf, 1.0);
			}*/

			if (debugShowShape) {
				pixelColor = mix(trail, vec4(1.0), 1.0-smoothstep(0.0, 0.01, abs(sdf)));
			}
			else {
				pixelColor = trail;
			}
        }
	};
}