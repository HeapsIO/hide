package hrt.shgraph.nodes;

@name("Alpha Over")
@description("Output is A if A.")
@width(100)
@group("Operation")
class AlphaOver extends Operation {

	static var SRC = {
		@sginput(0.0) var a : Vec4;
		@sginput(0.0) var b : Vec4;
        @sginput(1.0) var opacity : Float;
		@sgoutput var output : Vec4;
		function fragment() {
            var alpha = opacity * a.a;
			output.rgb = a.rgb * alpha + b.rgb * (1.0 - alpha);
            output.a = clamp(alpha + b.a,0.0, 1.0);
		}
	}
}