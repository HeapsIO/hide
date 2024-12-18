package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Random")
@description("Gives a random number from a vec2 seed")
@width(80)
@group("Math")
class Random extends ShaderNodeHxsl {
	static var SRC = {
		@sginput(0.0) var seed : Vec2;
		@sgoutput var output : Float;
		function fragment() {
			output = fract(sin(dot(seed, vec2(12.9898,78.233)))*43758.5453123);
		}
	};
}