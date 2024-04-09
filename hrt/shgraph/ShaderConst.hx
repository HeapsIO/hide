package hrt.shgraph;

using hxsl.Ast;

class ShaderConst extends ShaderNode {

	@prop() public var name : String = "";

	// override public function getOutputType(key : String) : Type {
	// 	return getOutputTExpr(key).t;
	// }

	override function generate(ctx:NodeGenContext) {

	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);

		var element = new hide.Element('<div style="width: 75px; height: 20px"></div>');
		element.append(new hide.Element('<input type="text" id="value" style="width: ${width*0.75}px" placeholder="Name" value="${this.name}" />'));

		var input = element.children("input");
		input.on("keydown", function(e) {
			e.stopPropagation();
		});
		input.on("change", function(e) {
			this.name = input.val();
		});

		elements.push(element);

		return elements;
	}
	#end
}