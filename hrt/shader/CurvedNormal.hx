package hrt.shader;

class CurvedNormal extends hxsl.Shader {

	static var SRC = {

		@const var VERTEX : Bool = true;
		@param var curvature : Float;

		@global var camera : {
			var view : Mat4;
		}

		@global var global : {
			@perObject var modelView : Mat4;
		};

		var relativePosition: Vec3;

		var transformedNormal : Vec3;
		var localNormal : Vec3;
		var localTangent : Vec3;

		function computeNormal() {
			var uv = relativePosition.xy * 2.0;
			var n = vec3(uv, sqrt(1. - clamp(dot(uv, uv), 0., 1.)));
			localNormal = normalize(mix(vec3(0,0,1), n, curvature));
			transformedNormal = normalize(localNormal * global.modelView.mat3());
			var rVec = vec3(0,1,0);
			localTangent = normalize(rVec - localNormal * dot(rVec, localNormal));
		}

		function fragment() {
			if( !VERTEX ) {
				computeNormal();
			}
		}

		function vertex() {
			if( VERTEX ) {
				computeNormal();
			}
		}
	};

	public function new( curvature : Float = 1.0 ) {
		super();
		this.curvature = curvature;
	}

}