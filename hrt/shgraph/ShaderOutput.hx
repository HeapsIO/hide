
package hrt.shgraph;

using hxsl.Ast;

@name("Outputs")
@description("Parameters outputs, it's dynamic")
@group("Output")
@color("#A90707")
class ShaderOutput extends ShaderNode {

	@prop("Variable") public var variable : String = "_sg_out_color";

	var components = [X, Y, Z, W];

	public var generatePreview = false;

	public function new(variable = "_sg_out_color") {
		this.variable = variable;
	}

	override public function getAliases(name: String, group: String, description: String) {
		var aliases = [];
		for (key => output in hrt.shgraph.ShaderOutput.availableOutputs) {
			aliases.push({
				name : name + " - " + output.display,
				group: group,
				description: description,
				args: [key],
			});
		}
		return aliases;
	}

	public function getVariable() {
		return availableOutputs.get(variable).v;
	}

	override function getShaderDef(domain: ShaderGraph.Domain, getNewIdFn : () -> Int, ?inputTypes: Array<Type>):hrt.shgraph.ShaderGraph.ShaderNodeDef {
		var pos : Position = {file: "", min: 0, max: 0};

		var variable = availableOutputs.get(variable).v;

		var inVar : TVar = {name: "input", id: getNewIdFn(), type: variable.type, kind: Param, qualifiers: []};
		var output : TVar = {name: variable.name, id: getNewIdFn(), type: variable.type, kind: variable.kind, qualifiers: []};
		var finalExpr : TExpr = {e: TBinop(OpAssign, {e:TVar(output), p:pos, t:output.type}, {e: TVar(inVar), p: pos, t: output.type}), p: pos, t: output.type};

		//var param = getParameter(inputNode.parameterId);
		//inits.push({variable: inVar, value: param.defaultValue});
		var inVars = [{v: inVar, internal: false, isDynamic: false}];

		// if (variable.name == "pixelColor") {
		// 	var vec3 = TVec(3, VFloat);
		// 	inVar.type = vec3;
		// 	finalExpr =
		// 		{
		// 			e: TBinop(
		// 			OpAssign,
		// 				{
		// 					e: TSwiz(
		// 							{
		// 								e: TVar(output),
		// 								p: pos,
		// 								t: vec3,
		// 							},
		// 							[X,Y,Z]
		// 						),
		// 					p:pos,
		// 					t:vec3
		// 				},
		// 				{
		// 					e: TVar(inVar),
		// 					p: pos,
		// 					t: vec3
		// 				}
		// 			),
		// 			p: pos,
		// 			t: vec3
		// 		};
		// } else if (variable.name == "alpha") {
		// 	var flt = TFloat;
		// 	inVar.type = flt;
		// 	output.name = "pixelColor";
		// 	output.type = TVec(4, VFloat);
		// 	finalExpr =
		// 		{
		// 			e: TBinop(
		// 			OpAssign,
		// 				{
		// 					e: TSwiz(
		// 							{
		// 								e: TVar(output),
		// 								p: pos,
		// 								t: flt,
		// 							},
		// 							[W]
		// 						),
		// 					p:pos,
		// 					t:flt
		// 				},
		// 				{
		// 					e: TVar(inVar),
		// 					p: pos,
		// 					t: flt
		// 				}
		// 			),
		// 			p: pos,
		// 			t: flt
		// 		};
		// }
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

	public static var availableOutputs : Map<String, ShaderNode.VariableDecl> = [
		"_sg_out_color" => {display:"Pixel Color", v:{parent: null,id: 0,kind: Local,name: "_sg_out_color",type: TVec(3, VFloat)}},
		"_sg_out_alpha" => {display:"Alpha", v:{parent: null,id: 0,kind: Local,name: "_sg_out_alpha",type: TFloat}},
		"relativePosition" => {display:"Position (Object Space)", vertexOnly: true, v:{parent: null,id: 0,kind: Local,name: "relativePosition",type: TVec(3, VFloat)}},
		"transformedPosition" => {display:"Position (World Space)", vertexOnly: true, v:{parent: null,id: 0,kind: Local,name: "transformedPosition",type: TVec(3, VFloat)}},
		"projectedPosition" => {display: "Position (View Space)", vertexOnly: true, v: { parent: null, id: 0, kind: Local, name: "projectedPosition", type: TVec(4, VFloat) }},
		// Disabled because calculated UV need to be initialized in vertexShader for some reason
		"calculatedUV" => { display: "UV", v: { parent: null, id: 0, kind: Var, name: "calculatedUV", type: TVec(2, VFloat)}},
		"transformedNormal" => { display: "Normal (World Space)", vertexOnly: true, v: {parent: null, id: 0, kind: Local, name: "transformedNormal", type: TVec(3, VFloat)}},
		"metalness" => {display: "Metalness", v: {parent: null,id: 0,kind: Local,name: "metalness",type: TFloat}},
		"roughness" => {display: "Roughness", v: {parent: null, id: 0, kind: Local, name: "roughness", type: TFloat}},
		"emissive" => {display: "Emissive", v: {parent: null, id: 0, kind: Local, name: "emissive", type: TFloat}},
		"occlusion" => {display: "Occlusion", v: {parent: null, id: 0, kind: Local, name: "occlusion", type: TFloat}},
	];

	override function loadProperties(props:Dynamic) {
		super.loadProperties(props);
		var ivar = availableOutputs.get(this.variable);
		if (ivar == null) {
			for (k => v in availableOutputs) {
				variable = k;
				break;
			}
		}
	}

	/*override public function saveProperties() : Dynamic {
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
	}*/


	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		var element = new hide.Element('<div style="width: 110px; height: 30px"></div>');
		element.append(new hide.Element('<select id="variable"></select>'));

		if (this.variable == null) {
			variable = "__sg_out_color";
		}
		var input = element.children("select");
		var selectingDefault = false;
		for (k => c in ShaderOutput.availableOutputs) {
			input.append(new hide.Element('<option value="${k}">${c.display}</option>'));
		}
		input.val(variable);

		/*var maxIndex = indexOption;
		input.append(new hide.Element('<option value="${maxIndex}">Other...</option>'));
		var initialName : String = null;
		var initialType : Type = null;
		if( !selectingDefault ) {
			input.val(maxIndex);
			initialName = this.variable.name;
			initialType = this.variable.type;
		}*/

		/*var customVarChooser = new CustomVarChooser(element, initialName, initialType, function(val) {
			this.variable = val;
		});

		if( !selectingDefault )
			customVarChooser.show();
		else
			customVarChooser.hide();*/

		input.on("change", function(e) {
			variable = input.val();
			/*var value = input.val();
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
			}*/
		});

		elements.push(element);

		return elements;
	}
	#end
}