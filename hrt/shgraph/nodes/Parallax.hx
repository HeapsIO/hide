package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Parallax")
@description("Parallaxed uv offset")
@group("UV")
@width(100)
class Parallax extends ShaderNodeHxsl {

	static var SRC = {
		@sginput("camera.position") var cameraPosition : Vec3;
		@sginput(1.0) var range : Float;
		@sgoutput var output : Vec2;
		
		@global var global : {
			@perObject var modelView : Mat4;
		};

		@input var input : {
			var tangent : Vec3;
        };

		var transformedPosition : Vec3;
		var transformedNormal : Vec3;
		function fragment() {
			var viewWS = (cameraPosition - transformedPosition).normalize();
			var tanX = input.tangent * global.modelView.mat3();
			var tanY = normalize(transformedNormal.cross(tanX));
			var viewNS = vec3(viewWS.dot(tanX), viewWS.dot(tanY), viewWS.dot(transformedNormal)).normalize();

			output = -viewNS.xy * range;
		}
	};

}