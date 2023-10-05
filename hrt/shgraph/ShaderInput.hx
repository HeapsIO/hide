package hrt.shgraph;

using hxsl.Ast;

@name("Inputs")
@description("Shader inputs of Heaps, it's dynamic")
@group("Property")
@color("#0e8826")
class ShaderInput extends ShaderNode {


	@prop("Variable") public var variable : TVar = availableInputs[0];

	// override public function getOutput(key : String) : TVar {
	// 	return variable;
	// }

	// override public function build(key : String) : TExpr {
	// 	return null;
	// }

	override function getShaderDef(domain: ShaderGraph.Domain, getNewIdFn : () -> Int ):hrt.shgraph.ShaderGraph.ShaderNodeDef {
		var pos : Position = {file: "", min: 0, max: 0};

		var inVar : TVar = Reflect.copy(variable);
		inVar.id = getNewIdFn();
		var output : TVar = {name: "output", id: getNewIdFn(), type: this.variable.type, kind: Local, qualifiers: []};
		var finalExpr : TExpr = {e: TBinop(OpAssign, {e:TVar(output), p:pos, t:output.type}, {e: TVar(inVar), p: pos, t: output.type}), p: pos, t: output.type};


		return {expr: finalExpr, inVars: [{v:inVar, internal: true}], outVars:[{v:output, internal: false}], externVars: [], inits: []};
	}

	public static var availableInputs : Array<TVar> = [
									{ parent: null, id: 0, kind: Input, name: "position", type: TVec(3, VFloat) },
									{ parent: null, id: 0, kind: Input, name: "color", type: TVec(3, VFloat) },
									{ parent: null, id: 0, kind: Input, name: "uv", type: TVec(2, VFloat) },
									{ parent: null, id: 0, kind: Input, name: "normal", type: TVec(3, VFloat) },
									{ parent: null, id: 0, kind: Input, name: "tangent", type: TVec(3, VFloat) },
									{ parent: null, id: 0, kind: Local, name: "relativePosition", type: TVec(3, VFloat) },
									{ parent: null, id: 0, kind: Local, name: "transformedPosition", type: TVec(3, VFloat) },
									{ parent: null, id: 0, kind: Local, name: "projectedPosition", type: TVec(4, VFloat) },
									{ parent: null, id: 0, kind: Local, name: "transformedNormal", type: TVec(3, VFloat) },
									{ parent: null, id: 0, kind: Local, name: "screenUV", type: TVec(2, VFloat) },
									{ parent: null, id: 0, kind: Local, name: "calculatedUV", type: TVec(2, VFloat) },
								];

	override public function loadProperties(props : Dynamic) {
		var paramVariable : String = Reflect.field(props, "variable");

		for (c in ShaderNode.availableVariables) {
			if (c.name == paramVariable) {
				this.variable = c;
				return;
			}
		}
		for (c in ShaderInput.availableInputs) {
			if (c.name == paramVariable) {
				this.variable = c;
				return;
			}
		}
	}

	override public function saveProperties() : Dynamic {
		var parameters = {
			variable: (variable == null) ? null : variable.name
		};

		return parameters;
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		var element = new hide.Element('<div style="width: 120px; height: 30px"></div>');
		element.append(new hide.Element('<select id="variable"></select>'));

		if (this.variable == null) {
			this.variable = ShaderNode.availableVariables[0];
		}
		var input = element.children("select");
		var indexOption = 0;
		for (c in ShaderNode.availableVariables) {
			var nameSplitted = c.name.split(".");
			input.append(new hide.Element('<option value="${indexOption}">${nameSplitted[nameSplitted.length-1]}</option>'));
			if (this.variable.name == c.name) {
				input.val(indexOption);
			}
			indexOption++;
		}
		for (c in ShaderInput.availableInputs) {
			input.append(new hide.Element('<option value="${indexOption}">${c.name}</option>'));
			if (this.variable.name == c.name) {
				input.val(indexOption);
			}
			indexOption++;
		}
		input.on("change", function(e) {
			var value = input.val();
			if (value < ShaderNode.availableVariables.length) {
				this.variable = ShaderNode.availableVariables[value];
			} else {
				this.variable = ShaderInput.availableInputs[value-ShaderNode.availableVariables.length];
			}
		});


		elements.push(element);

		return elements;
	}
	#end

}