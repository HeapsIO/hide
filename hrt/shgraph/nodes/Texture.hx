package hrt.shgraph.nodes;

import hxsl.*;

using hxsl.Ast;

@name("Texture")
@description("Create a texture from a file")
@group("AAAA")
class Texture extends ShaderNode {

	@output("texture") var texture = SType.Sampler;

	@prop() var fileTexture : String;

	override public function createOutputs() {
		addOutput("rgba", TSampler2D);
	}

	override public function build(key : String) : TExpr {
		return null;
	}

}