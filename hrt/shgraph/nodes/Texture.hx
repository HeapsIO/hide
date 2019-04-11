package hrt.shgraph.nodes;

import hxsl.*;

using hxsl.Ast;

@name("Texture")
@description("Create a texture from a file")
@group("AAAA")
class Texture extends ShaderNode {

	@output("texture") var texture = SType.Sampler;

	@prop("Variable") public var variable : TVar;

	@prop() var fileTexture : String;

	override public function computeOutputs() {
		addOutput("rgba", TSampler2D);
	}

	override public function getOutput(key : String) : TVar {
		return variable;
	}

	override public function build(key : String) : TExpr {
		return null;
	}

}