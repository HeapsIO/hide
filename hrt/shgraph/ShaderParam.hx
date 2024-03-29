package hrt.shgraph;

using hxsl.Ast;

@noheader()
@width(120)
@color("#d6d6d6")
class ShaderParam extends ShaderNode {


	@prop() public var parameterId : Int;
	@prop() public var perInstance : Bool;

	override function getOutputs() {
		return [{name: "output", type: null}];
	}

	override function generate(inputs: Array<TExpr>, ctx: ShaderNode.NodeGenContext) {
		var ret : Array<{e: TExpr, ?outputId: Int}> = [];
		var v = ctx.getGlobalParam(variable.name, variable.type, 0.0);
		ret.push({e: AstTools.makeVar(v), outputId: 0});
		ctx.addPreview(AstTools.makeVar(v), ret);
		return ret;
	}


	override function getShaderDef(domain: ShaderGraph.Domain, getNewIdFn : () -> Int, ?inputTypes: Array<Type>):hrt.shgraph.ShaderGraph.ShaderNodeDef {
		var pos : Position = {file: "", min: 0, max: 0};

		var qual = [];
		if (this.variable.type.isTexture()) {
			qual.push(Sampler(this.variable.name));
		}

		//if (this.variable.type != TSampler2D) {
			var inVar : TVar = {name: this.variable.name, id: getNewIdFn(), type: this.variable.type, kind: Param, qualifiers: qual};
			var output : TVar = {name: "output", id: getNewIdFn(), type: this.variable.type, kind: Local, qualifiers: []};
			var finalExpr : TExpr = {e: TBinop(OpAssign, {e:TVar(output), p:pos, t:output.type}, {e: TVar(inVar), p: pos, t: output.type}), p: pos, t: output.type};

			return {expr: finalExpr, inVars: [{v:inVar, internal: true, isDynamic: false}], outVars:[{v:output, internal: false, isDynamic: false}], externVars: [], inits: []};
		//}
		//else {
			//var samplerVar : TVar = {name: this.variable.name, id: getNewIdFn(), type: this.variable.type, kind: Param, qualifiers: qual};
			//var cuv = ShaderInput.availableInputs.get("calculatedUV");
			//var uv : TVar = {name: cuv.v.name, id: getNewIdFn(), type: cuv.v.type, kind: cuv.v.kind, qualifiers: []};
			//var output : TVar = {name: "output", id: getNewIdFn(), type: this.variable.type, kind: Local, qualifiers: []};
		//	return
		//}
	}

	public var variable : TVar;

	override public function computeOutputs() {
		if (variable != null)
			addOutput("output", variable.type);
		else
			removeOutput("output");
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


	// override public function canHavePreview() {
	// 	return this.variable.type != TSampler2D;
	// }

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
			case TSampler(_):
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
			case TSampler(_):
				displayDiv = null;
			case TVec(4, VFloat):
				displayDiv = null;
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