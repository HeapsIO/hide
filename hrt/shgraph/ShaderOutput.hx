
package hrt.shgraph;

using hxsl.Ast;

@name("Outputs")
@description("Parameters outputs, it's dynamic")
@group("Output")
@color("#A90707")
class ShaderOutput extends ShaderNode {

	@prop("Variable") public var variable : TVar = ShaderNode.availableVariables[0];

	var components = [X, Y, Z, W];

	public var generatePreview = false;

	override function getShaderDef(domain: ShaderGraph.Domain, getNewIdFn : () -> Int, ?inputTypes: Array<Type>):hrt.shgraph.ShaderGraph.ShaderNodeDef {
		var pos : Position = {file: "", min: 0, max: 0};

		var inVar : TVar = {name: "input", id: getNewIdFn(), type: this.variable.type, kind: Param, qualifiers: []};
		var output : TVar = {name: variable.name, id: getNewIdFn(), type: this.variable.type, kind: Local, qualifiers: []};
		var finalExpr : TExpr = {e: TBinop(OpAssign, {e:TVar(output), p:pos, t:output.type}, {e: TVar(inVar), p: pos, t: output.type}), p: pos, t: output.type};

		//var param = getParameter(inputNode.parameterId);
		//inits.push({variable: inVar, value: param.defaultValue});
		var inVars = [{v: inVar, internal: false, isDynamic: false}];

		if (variable.name == "pixelColor") {
			var vec3 = TVec(3, VFloat);
			inVar.type = vec3;
			finalExpr =
				{
					e: TBinop(
					OpAssign,
						{
							e: TSwiz(
									{
										e: TVar(output),
										p: pos,
										t: vec3,
									},
									[X,Y,Z]
								),
							p:pos,
							t:vec3
						},
						{
							e: TVar(inVar),
							p: pos,
							t: vec3
						}
					),
					p: pos,
					t: vec3
				};
		} else if (variable.name == "alpha") {
			var flt = TFloat;
			inVar.type = flt;
			output.name = "pixelColor";
			output.type = TVec(4, VFloat);
			finalExpr =
				{
					e: TBinop(
					OpAssign,
						{
							e: TSwiz(
									{
										e: TVar(output),
										p: pos,
										t: flt,
									},
									[W]
								),
							p:pos,
							t:flt
						},
						{
							e: TVar(inVar),
							p: pos,
							t: flt
						}
					),
					p: pos,
					t: flt
				};
		}
		// if (generatePreview && variable.name == "pixelColor") {
		// 	var outputSelect : TVar = {name: "__sg_PREVIEW_output_select", id: getNewIdFn(), type: TInt, kind: Param, qualifiers: []};

		// 	finalExpr = {
		// 		e: TIf(
		// 				{
		// 					e: TBinop(
		// 						OpEq,
		// 						{e:TVar(outputSelect),p:pos, t:TInt},
		// 						{e:TConst(CInt(0)), p:pos, t:TInt}
		// 					),
		// 					p:pos,
		// 					t:TInt
		// 				},
		// 				finalExpr,
		// 				null
		// 			),
		// 		p: pos,
		// 		t:null
		// 	};

		// 	inVars.push( {v: outputSelect, internal: true, isDynamic: false});
		// }

		return {expr: finalExpr, inVars: inVars, outVars:[{v: output, internal: true, isDynamic: false}], externVars: [], inits: []};
	}

	/*override public function checkValidityInput(key : String, type : hxsl.Ast.Type) : Bool {
		return ShaderType.checkConversion(type, variable.type);
	}*/

	// override public function build(key : String) : TExpr {
	// 	return {
	// 			p : null,
	// 			t : TVoid,
	// 			e : TBinop(OpAssign, {
	// 				e: TVar(variable),
	// 				p: null,
	// 				t: variable.type
	// 			}, input.getVar(variable.type))
	// 		};

	// }

	static var availableOutputs = [
		{
			parent: null,
			id: 0,
			kind: Var,
			name: "calculatedUV",
			type: TVec(2, VFloat)
		},
		{
			parent: null,
			id: 0,
			kind: Var,
			name: "transformedNormal",
			type: TVec(3, VFloat)
		},
		{
			parent: null,
			id: 0,
			kind: Var,
			name: "metalnessValue",
			type: TFloat
		},
		{
			parent: null,
			id: 0,
			kind: Var,
			name: "roughnessValue",
			type: TFloat
		},
		{
			parent: null,
			id: 0,
			kind: Var,
			name: "emissiveValue",
			type: TFloat
		}
	];

	override public function loadProperties(props : Dynamic) {
		var type: Type;
		if(props.type != null) {
			var args = [];
			if(props.type == "TVec") {
				args.push(props.vecSize);
				args.push(VecType.createByName(props.vecType));
			}
			type = hxsl.Ast.Type.createByName(props.type, args);
		}
		else @:deprecated {
			var paramVariable : Array<Dynamic> = Reflect.field(props, "variable");
			if( paramVariable[0] == null)
				return;

			for (c in ShaderNode.availableVariables) {
				if (c.name == paramVariable[0]) {
					this.variable = c;
					return;
				}
			}
			for (c in ShaderOutput.availableOutputs) {
				if (c.name == paramVariable[0]) {
					this.variable = c;
					return;
				}
			}
			type = haxe.EnumTools.createByName(Type, paramVariable[1], paramVariable[2]);
		}
		this.variable = {
			parent: null,
			id: 0,
			kind: Local,
			name: props.name,
			type: type,
		};
	}

	override public function saveProperties() : Dynamic {
		if (this.variable == null) {
			this.variable = ShaderNode.availableVariables[0];
		}
		var parameters : Dynamic = {
			name: variable.name,
			type: variable.type.getName(),
		};
		switch variable.type {
			case TVec(size, t):
				parameters.vecSize = size;
				parameters.vecType = t.getName();
			default:
		}
		return parameters;
	}


	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		var element = new hide.Element('<div style="width: 110px; height: 30px"></div>');
		element.append(new hide.Element('<select id="variable"></select>'));

		if (this.variable == null) {
			this.variable = ShaderNode.availableVariables[0];
		}
		var input = element.children("select");
		var indexOption = 0;
		var selectingDefault = false;
		for (c in ShaderNode.availableVariables) {
			input.append(new hide.Element('<option value="${indexOption}">${c.name}</option>'));
			if (this.variable.name == c.name) {
				input.val(indexOption);
				selectingDefault = true;
			}
			indexOption++;
		}
		for (c in ShaderOutput.availableOutputs) {
			input.append(new hide.Element('<option value="${indexOption}">${c.name}</option>'));
			if (this.variable.name == c.name) {
				input.val(indexOption);
				selectingDefault = true;
			}
			indexOption++;
		}
		var maxIndex = indexOption;
		input.append(new hide.Element('<option value="${maxIndex}">Other...</option>'));
		var initialName : String = null;
		var initialType : Type = null;
		if( !selectingDefault ) {
			input.val(maxIndex);
			initialName = this.variable.name;
			initialType = this.variable.type;
		}

		var customVarChooser = new CustomVarChooser(element, initialName, initialType, function(val) {
			this.variable = val;
		});

		if( !selectingDefault )
			customVarChooser.show();
		else
			customVarChooser.hide();

		input.on("change", function(e) {
			var value = input.val();
			if (value < ShaderNode.availableVariables.length) {
				this.variable = ShaderNode.availableVariables[value];
			} else if (value < maxIndex) {
				this.variable = ShaderOutput.availableOutputs[value-ShaderNode.availableVariables.length];
			}
			if (value == maxIndex) {
				customVarChooser.show();
				if (customVarChooser.variable != null) {
					this.variable = customVarChooser.variable;
				}
			} else {
				customVarChooser.hide();
			}
		});

		elements.push(element);

		return elements;
	}
	#end
}