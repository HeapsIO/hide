package hrt.shgraph;

using hxsl.Ast;

@name("Outputs")
@description("Parameters outputs, it's dynamic")
@group("Output")
@color("#A90707")
class ShaderOutput extends ShaderNode {

	@input("input") var input = SType.Variant;

	@prop("Variable") public var variable : TVar;

	var components = [X, Y, Z, W];

	override public function checkValidityInput(key : String, type : ShaderType.SType) : Bool {
		return ShaderType.checkConversion(type, ShaderType.getSType(variable.type));
	}

	override public function build(key : String) : TExpr {
		return {
				p : null,
				t : TVoid,
				e : TBinop(OpAssign, {
					e: TVar(variable),
					p: null,
					t: variable.type
				}, input.getVar(variable.type))
			};

	}

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
		this.variable = {
			parent: null,
			id: 0,
			kind: Local,
			name: paramVariable[0],
			type: haxe.EnumTools.createByName(Type, paramVariable[1], paramVariable[2]),
		};
	}

	override public function saveProperties() : Dynamic {
		var content : Array<Dynamic> = (variable == null) ? [null] : [
			variable.name,
			variable.type.getName(),
			variable.type.getParameters()
		];
		var parameters = {
			variable: content,
		};

		return parameters;
	}


	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		var element = new hide.Element('<div style="width: 110px; height: 70px"></div>');
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