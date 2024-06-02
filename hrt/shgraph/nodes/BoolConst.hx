package hrt.shgraph.nodes;

using hxsl.Ast;

@name("Bool")
@description("Boolean input (static)")
@group("Property")
@width(100)
@noheader()
class BoolConst extends ShaderConst {


	@prop() var value : Bool = true;

	override function getOutputs() {
		static var output : Array<ShaderNode.OutputInfo> = [{name: "output", type: SgBool}];
		return output;
	}

	override function generate(ctx: NodeGenContext) : Void {
		var output = makeExpr(TConst(CBool(value)), TBool);
		ctx.setOutput(0, output);
		ctx.addPreview(output);
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		var element = new hide.Element('<div style="width: 15px; height: 30px"></div>');
		element.append(new hide.Element('<input type="checkbox" id="value" />'));

		var input = element.children("input");
		input.on("change", function(e) {
			value = (input.is(":checked")) ? true : false;
		});
		if (this.value) {
			input.prop("checked", true);
		}

		elements.push(element);

		return elements;
	}
	#end

}