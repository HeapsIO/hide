package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Text")
@description("Only UI, to add text")
@group("Other")
@width(200)
@color("#c7c700")
@noheader()
class Text extends ShaderNode {

	@prop() var text : String = "";

	override function getShaderDef(domain: ShaderGraph.Domain, getNewIdFn : () -> Int, ?inputTypes: Array<Type>):hrt.shgraph.ShaderGraph.ShaderNodeDef {
		return {expr: null, inVars: [], outVars: [], inits: [], externVars: []};
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		var element = new hide.Element('<div style="width: ${width-35}px; height: 35px"></div>');
		element.append(new hide.Element('<input type="text" id="value" style="width: ${width-35}px; height: 22px; font-size: 16px;" placeholder="Name" value="${this.text}" />'));

		var input = element.children("input");
		input.on("keydown", function(e) {
			e.stopPropagation();
		});
		input.on("change", function(e) {
			this.text = input.val();
		});

		elements.push(element);

		return elements;
	}
	#end

}