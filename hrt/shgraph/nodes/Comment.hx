package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Comment")
@description("A box that allows you to comment your graph")
@group("Comment")
class Comment extends ShaderNode {
	@prop() public var comment : String = "";
	@prop() public var width : Int = 200;
	@prop() public var height : Int = 200;

	override function generate(ctx: NodeGenContext) {}

	override function canHavePreview():Bool {
		return false;
	}
}