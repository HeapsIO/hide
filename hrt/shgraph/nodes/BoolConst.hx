package hrt.shgraph.nodes;

import hide.Element;
using hxsl.Ast;

@name("Bool")
@description("Boolean input, it's static")
@group("Input")
@width(75)
class BoolConst extends ShaderConst {

	@output() var fakeOutput = SType.Bool;

	@param() var value : Bool = true;

	override public function getOutputTExpr(key : String) : TExpr {
		return {
					e: TConst(CBool(value)),
					p: null,
					t: TBool
				};
	}

	override public function build(key : String) : TExpr {
		return null;
	}

	#if editor
	override public function getParametersHTML(width : Float) : Array<Element> {
		var elements = super.getParametersHTML(width);
		var element = new Element('<div style="width: 15px; height: 30px"></div>');
		element.append(new Element('<input type="checkbox" id="value" ></select>'));

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