package hrt.shgraph.nodes;

import hide.Element;
using hxsl.Ast;

@name("Condition")
@description("Create a custom condition between two inputs")
@group("Condition")
class Cond extends ShaderNode {

	@input("left") var leftVar = SType.Number;
	@input("right") var rightVar = SType.Number;

	@output("boolean") var output = SType.Bool;

	@prop() var condition : Binop;

	override public function checkValidityInput(key : String, type : ShaderType.SType) : Bool {

		if (key == "leftVar" && rightVar != null)
			return ShaderType.checkCompatibilities(type, ShaderType.getType(rightVar.getType()));

		if (key == "rightVar" && leftVar != null)
			return ShaderType.checkCompatibilities(type, ShaderType.getType(leftVar.getType()));

		return true;
	}

	override public function createOutputs() {
		if (leftVar != null && leftVar.getType() != null && rightVar != null && rightVar.getType() != null) {
			var type = leftVar.getVar(rightVar.getType()).t;
			switch(type) {
				case TVec(s, t):
					throw "Vector of bools not supported";//addOutput("output", TVec(s, VBool));
				case TFloat:
					addOutput("output", TBool);
				default:
					removeOutput("output");
			}
		} else
			removeOutput("output");
	}

	override public function build(key : String) : TExpr {

		return {
				p : null,
				t : output.type,
				e : TBinop(OpAssign, {
						e: TVar(output),
						p: null,
						t: output.type
					}, {e: TBinop(this.condition,
							leftVar.getVar(rightVar.getType()),
							rightVar.getVar(leftVar.getType())),
						p: null, t: output.type })
			};
	}

	var availableConditions = [OpEq, OpNotEq, OpGt, OpGte, OpLt, OpLte, OpAnd, OpOr];
	var conditionStrings 	= ["==", "!=",    ">",  ">=",  "<",  "<=",  "AND", "OR"];

	override public function loadProperties(props : Dynamic) {
		this.condition = std.Type.createEnum(Binop, Reflect.field(props, "condition"));
	}

	override public function saveProperties() : Dynamic {
		var properties = {
			condition: this.condition.getName()
		};

		return properties;
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<Element> {
		var elements = super.getPropertiesHTML(width);
		var element = new Element('<div style="width: ${width * 0.8}px; height: 40px"></div>');
		element.append('<span>Condition</span>');
		element.append(new Element('<select id="condition"></select>'));

		if (this.condition == null) {
			this.condition = availableConditions[0];
		}
		var input = element.children("select");
		var indexOption = 0;
		for (c in conditionStrings) {
			input.append(new Element('<option value="${indexOption}">${c}</option>'));
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