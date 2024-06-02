package hrt.shgraph.nodes;

using hxsl.Ast;

import hrt.shgraph.AstTools.*;

@name("Condition")
@description("Create a custom condition between two inputs")
@group("Condition")
class Cond extends ShaderNode {

	override function getOutputs() {
		static var output : Array<ShaderNode.OutputInfo> = [{name: "output", type: SgBool}];
		return output;
	}

	override function getInputs() {
		static var inputs : Array<ShaderNode.InputInfo> =
			[
				{name: "a", type: SgFloat(1), def: Const(0.0)},
				{name: "b", type: SgFloat(1), def: Const(0.0)},
			];
		return inputs;
	}

	override function generate(ctx: NodeGenContext) {
		var a = ctx.getInput(0, Const(0.0));
		var b = ctx.getInput(1, Const(0.0));

		var expr = makeExpr(TBinop(condition, a, b), TBool);
		ctx.setOutput(0, expr);
		ctx.addPreview(expr);
	}


	@prop() var condition : Binop = OpEq;

	static var availableConditions = [OpEq, OpNotEq, OpGt, OpGte, OpLt, OpLte, OpAnd, OpOr];
	static var conditionStrings 	= ["==", "!=",    ">",  ">=",  "<",  "<=",  "AND", "OR"];

	override public function loadProperties(props : Dynamic) {
		if (Reflect.hasField(props, "condition"))
			this.condition = std.Type.createEnum(Binop, Reflect.field(props, "condition"));
		else
			this.condition = OpEq;
	}

	override public function saveProperties() : Dynamic {
		if (this.condition == null)
			this.condition = availableConditions[0];
		var properties = {
			condition: this.condition.getName()
		};

		return properties;
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		var element = new hide.Element('<div style="width: ${width * 0.8}px; height: 40px"></div>');
		element.append('<span>Condition</span>');
		element.append(new hide.Element('<select id="condition"></select>'));

		if (this.condition == null) {
			this.condition = availableConditions[0];
		}
		var input = element.children("select");
		var indexOption = 0;
		for (c in conditionStrings) {
			input.append(new hide.Element('<option value="${indexOption}">${c}</option>'));
			if (this.condition == availableConditions[indexOption]) {
				input.val(indexOption);
			}
			indexOption++;
		}
		input.on("change", function(e) {
			var value = input.val();
			this.condition = availableConditions[value];
		});

		elements.push(element);

		return elements;
	}
	#end

}