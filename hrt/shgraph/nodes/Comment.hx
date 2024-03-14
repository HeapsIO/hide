package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Comment")
@description("A box that allows you to comment your graph")
@group("Comment")
class Comment extends ShaderNode {
	@prop() public var comment : String = "";
	@prop() public var width : Int = 200;
	@prop() public var height : Int = 200;

	override public function getShaderDef(domain: ShaderGraph.Domain, getNewIdFn : () -> Int, ?inputTypes: Array<Type>) : ShaderGraph.ShaderNodeDef {
		return {
			expr: {e:TBlock([]), t:TVoid, p: null},
			inVars: [],
			outVars: [],
			inits: [],
			externVars: [],
		};
	}

	override function canHavePreview():Bool {
		return false;
	}
}