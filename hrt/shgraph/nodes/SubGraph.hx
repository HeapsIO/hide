package hrt.shgraph.nodes;

using hxsl.Ast;

@name("SubGraph")
@description("Include a subgraph")
@group("Other")
@width(250)
@alwaysshowinputs()
class SubGraph extends ShaderNode {

	@prop() var pathShaderGraph : String;

	var inputsInfo : Map<String, ShaderNode.InputInfo>;
	var inputInfoKeys : Array<String> = [];
	var outputsInfo : Map<String, ShaderNode.OutputInfo>;
	var outputInfoKeys : Array<String> = [];
	var parameters : Array<ShaderGraph.Parameter> = [];
	var propertiesSubGraph : Map<Int, Dynamic>;

	public var subShaderGraph : ShaderGraph;

	public var varsSubGraph : Array<TVar> = [];

	public function loadGraphShader() {
		if (this.pathShaderGraph != null) {
			try {
				subShaderGraph = new ShaderGraph("E:/Projects/arena/trunk/res/" + pathShaderGraph);
			} catch (e : Dynamic) {
				trace("The shader doesn't not exist.");
				return;
			}
			inputsInfo = new Map<String, ShaderNode.InputInfo>();
			inputInfoKeys = [];
			outputsInfo = new Map<String, ShaderNode.OutputInfo>();
			outputInfoKeys = [];
			parameters = [];
			propertiesSubGraph = new Map<Int, Dynamic>();
			var prefixSubGraph = "shgraph_" + id + "_";

			for (node in subShaderGraph.getNodes()) {
				switch (node.type.split(".").pop()) {
					case "ShaderParam": // params become inputs
						var shaderParam = Std.instance(node.instance, ShaderParam);
						var paramName = subShaderGraph.getParameter(shaderParam.parameterId).name;

						inputsInfo.set(prefixSubGraph+node.id, { name : paramName , type: ShaderType.getSType(shaderParam.variable.type), hasProperty: false, id : node.id });
						inputInfoKeys.push(prefixSubGraph+node.id);
					case "ShaderInput":
						var shaderInput = Std.instance(node.instance, ShaderInput);

						inputsInfo.set(prefixSubGraph+node.id, { name : "*" + shaderInput.variable.name , type: ShaderType.getSType(shaderInput.variable.type), hasProperty: false, id : node.id });
						inputInfoKeys.push(prefixSubGraph+node.id);
					case "ShaderOutput":
						var shaderOutput = Std.instance(node.instance, ShaderOutput);

						outputsInfo.set(prefixSubGraph+node.id, { name : shaderOutput.variable.name , type: ShaderType.getSType(shaderOutput.variable.type), id : node.id });
						outputInfoKeys.push(prefixSubGraph+node.id);

						addOutput(prefixSubGraph+node.id, shaderOutput.variable.type);
					default:
						var shaderConst = Std.instance(node.instance, ShaderConst);
						if (shaderConst != null) { // input static become properties
							if (Std.is(shaderConst, BoolConst)) {
								parameters.push({ name : "Bool", type : TBool, defaultValue : null, id : shaderConst.id });
							} else if (Std.is(shaderConst, FloatConst)) {
								parameters.push({ name : "Number", type : TFloat, defaultValue : null, id : shaderConst.id });
							} else if (Std.is(shaderConst, Color)) {
								parameters.push({ name : "Color", type : TVec(4, VFloat), defaultValue : null, id : shaderConst.id });
							}
						}
				}
			}

		}
	}

	override public function build(key : String) : TExpr {

		for (inputKey in inputInfoKeys) {
			var inputInfo = inputsInfo.get(inputKey);
			var inputTVar = getInput(inputKey);

			if (inputTVar != null) {
				var nodeToReplace = subShaderGraph.getNodes().get(inputInfo.id);
				for (i in 0...nodeToReplace.outputs.length) {
					var inputNode = nodeToReplace.outputs[i];

					for (inputKey in inputNode.instance.getInputsKey()) {
						var input = inputNode.instance.getInput(inputKey);
						if (input.node == nodeToReplace.instance) {
							inputNode.instance.setInput(inputKey, inputTVar);
						}
					}
				}
			}
		}

		var shaderDef;
		try {
			shaderDef = subShaderGraph.generateShader(null, id);
		} catch (e : Dynamic) {
			throw ShaderException.t(e.msg, id);
		}
		if (shaderDef.funs.length > 1) {
			throw ShaderException.t("The sub shader is vertex and fragment.", id);
		}
		varsSubGraph = shaderDef.vars;
		var arrayExpr : Array<TExpr> = [];
		switch (shaderDef.funs[0].expr.e) {
			case TBlock(block):
				arrayExpr = block;
			default:

		}

		for (outputKey in outputInfoKeys) {
			var outputInfo = outputsInfo.get(outputKey);
			var outputTVar = getOutput(outputKey);
			if (outputTVar != null) {
				arrayExpr.push({
					p : null,
					t : outputTVar.type,
					e : TBinop(OpAssign, {
							e: TVar(outputTVar),
							p: null,
							t: outputTVar.type
						}, subShaderGraph.getNodes().get(outputInfo.id).instance.getInput("input").getVar(outputTVar.type))
				});
			}
		}

		return {
				p : null,
				t : TVoid,
				e : TBlock(arrayExpr)
			};
	}

	override public function getInputInfo(key : String) : ShaderNode.InputInfo {
		return inputsInfo.get(key);
	}

	override public function getInputInfoKeys() : Array<String> {
		return inputInfoKeys;
	}

	override public function getOutputInfo(key : String) : ShaderNode.OutputInfo {
		return outputsInfo.get(key);
	}

	override public function getOutputInfoKeys() : Array<String> {
		return outputInfoKeys;
	}

	override public function loadProperties(props : Dynamic) {
		this.pathShaderGraph = Reflect.field(props, "pathShaderGraph");
		loadGraphShader();
	}

	override public function saveProperties() : Dynamic {
		var properties = {
			pathShaderGraph: this.pathShaderGraph
		};

		return properties;
	}

	#if editor
	override public function getPropertiesHTML(width : Float) : Array<hide.Element> {
		var elements = super.getPropertiesHTML(width);
		var element = new hide.Element('<div style="width: ${width * 0.8}px; height: 25px"></div>');
		var fileInput = new hide.Element('<input type="text" field="filesubgraph" />').appendTo(element);

		fileInput.on("mousedown", function(e) {
			e.stopPropagation();
		});

		var tfile = new hide.comp.FileSelect(["hlshader"], null, fileInput);
		if (this.pathShaderGraph != null && this.pathShaderGraph.length > 0) tfile.path = this.pathShaderGraph;
		tfile.onChange = function() {
			this.pathShaderGraph = tfile.path;
			loadGraphShader();
			fileInput.trigger("change");
		}
		elements.push(element);
		elements.push(new hide.Element('<div style="background: #202020; height: 1px; margin-bottom: 5px;"></div>'));

		for (p in parameters) {
			var element = new hide.Element('<div style="width: 100px; height: 25px"></div>');
			element.on("mousedown", function(e) {
				e.stopPropagation();
			});
			switch (p.type) {
				case TBool:
					element.append(new hide.Element('<input type="checkbox" id="value" />'));
				case TFloat:
					element.append(new hide.Element('<input type="text" id="value" style="width: ${width*0.65}px" value="" />'));
				case TVec(4, VFloat):
					new hide.comp.ColorPicker(true, element);
				default:

			}
			elements.push(element);
		}


		return elements;
	}
	#end

}