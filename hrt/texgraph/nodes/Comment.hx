package hrt.texgraph.nodes;

#if editor
import hide.view.GraphInterface;
#end

@name("Comment")
@description("A box that allows you to comment your graph")
@group("Comment")
class Comment extends TexNode {
	@prop() public var comment : String = "Comment";
	@prop() public var width : Float = 200;
	@prop() public var height : Float = 200;

	public function new () {}

	override function apply(vars : Dynamic) : Array<h3d.mat.Texture> {
		return null;
	}

	#if editor
	override function getInfo() : GraphNodeInfo {
		var info = super.getInfo();
		info.comment = {
			getComment: () -> comment,
			setComment: (v:String) -> comment = v,
			getSize: (p: h2d.col.Point) -> p.set(width, height),
			setSize: (p: h2d.col.Point) -> { width = p.x; height = p.y; },
		};
		info.preview = null;
		return info;
	}
	#end
}