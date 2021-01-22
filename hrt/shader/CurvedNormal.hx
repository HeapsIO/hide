package hrt.shader;

class CurvedNormal extends hxsl.Shader implements h3d.scene.MeshBatch.MeshBatchAccess {

	public var perInstance : Bool = false;

	static var SRC = {

		@const var VERTEX : Bool = true;
		@param var curvature : Float;

		@global var camera : {
			var view : Mat4;
		}

		@input var input : {
			var normal : Vec3;
		}

		@global var global : {
			@perObject var modelView : Mat4;
		};

		var relativePosition: Vec3;
		var transformedNormal : Vec3;

		function fragment() {
			if( !VERTEX ) {
				var uv = relativePosition.xy * 2.0;
				var n = vec3(uv, sqrt(1. - clamp(dot(uv, uv), 0., 1.)));
				transformedNormal = normalize(mix(input.normal, n, curvature));
				transformedNormal = normalize(transformedNormal * global.modelView.mat3());
			}
		}

		function vertex() {
			if( VERTEX ) {
				var uv = relativePosition.xy * 2.0;
				var n = vec3(uv, sqrt(1. - clamp(dot(uv, uv), 0., 1.)));
				transformedNormal = normalize(mix(input.normal, n, curvature));
				transformedNormal = normalize(transformedNormal * global.modelView.mat3());
			}
		}
	};

	public function new( curvature : Float = 1.0 ) {
		super();
		this.curvature = curvature;
	}

}