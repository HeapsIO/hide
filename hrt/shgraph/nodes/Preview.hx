package hrt.shgraph.nodes;

import h3d.scene.Mesh;

using Lambda;
using hxsl.Ast;


class AlphaPreview extends hxsl.Shader {
	static var SRC = {
		var pixelColor : Vec4;
		var screenUV : Vec2;
		function fragment() {
			var gray_lt = vec3(1.0);
			var gray_dk = vec3(229.0) / 255.0;
			var scale = 16.0;
			var localUV = screenUV * scale;

			var checkboard = floor(localUV.x) + floor(localUV.y);
			checkboard = fract(checkboard * 0.5) * 2.0;
			var alphaColor = vec3(checkboard * (gray_dk - gray_lt) + gray_lt);

			pixelColor.rgb = mix(pixelColor.rgb, alphaColor, 1.0 - pixelColor.a);
			pixelColor.a = 1.0;
		}
	}
}

@name("Preview")
@description("Preview node, just to debug :)")
@group("Output")
@width(100)
@noheader()
class Preview extends ShaderNode {

	public var previewID : Int = 1;

	override function getInputs() {
		static var inputs : Array<ShaderNode.InputInfo> = [{name: "input", type: SgFloat(4)}];
		return inputs;
	}

	override function generate(ctx:NodeGenContext) {
		var input = ctx.getInput(0, Const(0.0));
		ctx.addPreview(input);
	}
}