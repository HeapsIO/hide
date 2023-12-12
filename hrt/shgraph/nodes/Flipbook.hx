package hrt.shgraph.nodes;


using hxsl.Ast;

@name("Flipbook")
@description("Animate UV by as a flipbook animation")
@width(100)
@group("UV")
class Flipbook extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(calculatedUV) var uv : Vec2;
        @sginput(2) var width : Float;
        @sginput(2) var height : Float;
        @sginput(0) var frame : Float;
        

		@sgoutput var output : Vec2;
		function fragment() {
            var f = mod(floor(frame), (height * width)); 
            var x = mod(f, width);
            var y = floor(f / width);

            var dim = vec2(width, height);
            var uv2 = uv/dim + vec2(x,y)/dim;

			output = uv2;
		}
	};

}