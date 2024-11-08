
package hrt.shgraph.nodes;

@name("Project")
@description("Project the given world space vector into view space")
@width(100)
@group("Math")
class Project extends Operation {

	static var SRC = {
		@global var camera : {
			var viewProj: Mat4;
		};

		@sginput(0.0) var a : Vec3;
		@sgoutput var out : Vec4;

		function fragment() {
			out = vec4(a,0.0) * camera.viewProj * vec4(1.0,1.0,1.0,1.0);
		}
	}
}