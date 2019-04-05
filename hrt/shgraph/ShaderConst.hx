package hrt.shgraph;

using hxsl.Ast;

class ShaderConst extends ShaderNode {

	var const : TExpr;

	override public function getOutputType(key : String) : Type {
		return getOutputTExpr(key).t;
	}

	override public function build(key : String) : TExpr {
		return null;
	}
}