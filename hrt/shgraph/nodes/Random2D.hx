package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Random2D")
@description("Gives a random vec2 from a vec2 seed")
@width(80)
@group("Math")
class Random2D extends ShaderNodeHxsl {
	static var SRC = {
		@sginput(0.0) var seed : Vec2;
		@sgoutput var output : Vec2;
		function fragment() {
			output = vec2(fract(sin(dot(seed, vec2(12.9898,78.233)))*43758.5453123),
			              fract(sin(dot(seed, vec2(1572.9898,132.237)))*157468.33458));
		}
	};
}