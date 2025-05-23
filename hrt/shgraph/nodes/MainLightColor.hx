package hrt.shgraph.nodes;

using hxsl.Ast;

@name("MainLightColor")
@description("Get the main light color")
@group("Property")
class MainLightColor extends ShaderNodeHxsl {

	static var SRC = {
		@sgoutput var output : Vec3;

        @global var mainLightColor : Vec3;
        @global var mainLightPower : Float;

		function fragment() {
			output = mainLightColor * mainLightPower;
		}
	};
}
