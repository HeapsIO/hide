package hrt.shgraph;

using hxsl.Ast;

@noheader()
@width(120)
@color("#d6d6d6")
class ShaderParam extends ShaderNode {

	@output() var output = SType.Variant;

	@prop() public var parameterId : Int;
	@prop() public var perInstance : Bool;

	override public function getOutputs2() : Map<String, TVar> {
		var outputs : Map<String, TVar> = [];
		outputs.set("output", this.variable);

		return outputs;
	}

	override function getShaderDef():hrt.shgraph.ShaderGraph.ShaderNodeDef {
		var pos : Position = {file: "", min: 0, max: 0};

		var inVar : TVar = {name: this.variable.name, id:0, type: this.variable.type, kind: Param, qualifiers: [SgInput]};
		var output : TVar = {name: "output", id:1, type: this.variable.type, kind: Local, qualifiers: [SgOutput]};
		var finalExpr : TExpr = {e: TBinop(OpAssign, {e:TVar(output), p:pos, t:output.type}, {e: TVar(inVar), p: pos, t: output.type}), p: pos, t: output.type};

		//var param = getParameter(inputNode.parameterId);
		//inits.push({variable: inVar, value: param.defaultValue});

		return {expr: finalExpr, inVars: [], outVars:[output], externVars: [inVar, output], inits: []};
	}

	public var variable : TVar;

	override public function computeOutputs() {
		if (variable != null)
			addOutput("output", variable.type);
		else
			removeOutput("output");
	}

	override public function getOutput(key : String) : TVar {
		return variable;
	}

	override public function loadProperties(props : Dynamic) {
		parameterId = Reflect.field(props, "parameterId");
		perInstance = Reflect.field(props, "perInstance");
	}

	override public function saveProperties() : Dynamic {
		var parameters = {
			parameterId: parameterId,
			perInstance: perInstance
		};

		return parameters;
	}

	override public function build(key : String) : TExpr {
		if (variable != null){
			if (variable.qualifiers == null)
				variable.qualifiers = [];
			if (perInstance)
				if (!variable.qualifiers.contains(PerInstance(1)))
					variable.qualifiers.push(PerInstance(1));
			else
				if (variable.qualifiers.contains(PerInstance(1)))
					variable.qualifiers.remove(PerInstance(1));
		}
		return null;
	}

	#if editor
	private var parameterName : String;
	private var eltName : hide.Element;

	private var parameterDisplay : String;
	private var displayDiv : hide.Element;
	public function setName(s : String) {
		parameterName = s;
		if (eltName != null)
			eltName.html(s);
	}
	public function setDisplayValue(value : String) {
		parameterDisplay = value;
		switch (this.variable.type) {
			case TFloat:
				if (displayDiv != null)
					displayDiv.html(value);
			case TSampler2D:
				if (displayDiv != null)
					displayDiv.css("background-image", 'url(${value})');
			case TVec(4, VFloat):
				if (displayDiv != null)
					displayDiv.css("background-color", value);
			default:
		}
	}
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		var height = 25;
		switch (this.variable.type) {
			case TFloat:
				displayDiv = new hide.Element('<div class="float-preview" ></div>');
				height += 20;
			case TSampler2D:
				displayDiv = new hide.Element('<div class="texture-preview" ></div>');
				height += 50;
			case TVec(4, VFloat):
				displayDiv = new hide.Element('<div class="color-preview" ></div>');
				height += 25;
			default:
				displayDiv = null;
		}
		var element = new hide.Element('<div style="width: 110px; height: ${height}px"></div>');
		if (displayDiv != null) {
			setDisplayValue(parameterDisplay);
			displayDiv.appendTo(element);
		}
		eltName = new hide.Element('<div class="paramVisible" >${parameterName}</div>').appendTo(element);

		elements.push(element);

		return elements;
	}
	#end

}