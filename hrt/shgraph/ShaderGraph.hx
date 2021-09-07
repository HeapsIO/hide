package hrt.shgraph;

import hxsl.SharedShader;
using hxsl.Ast;

typedef Node = {
	x : Float,
	y : Float,
	id : Int,
	type : String,
	?properties : Dynamic,
	?instance : ShaderNode,
	?outputs: Array<Node>,
	?indegree : Int
};

private typedef Edge = {
	idOutput : Int,
	nameOutput : String,
	idInput : Int,
	nameInput : String
};

typedef Parameter = {
	name : String,
	type : Type,
	defaultValue : Dynamic,
	?id : Int,
	?variable : TVar
};

class ShaderGraph {

	var allVariables : Array<TVar> = [];
	var allParameters = [];
	var allParamDefaultValue = [];
	var current_node_id = 0;
	var current_param_id = 0;
	var filepath : String;
	var nodes : Map<Int, Node> = [];
	public var parametersAvailable : Map<Int, Parameter> = [];

	// subgraph variable
	var variableNamesAlreadyUpdated = false;

	public function new(filepath : String) {
		if (filepath == null) return;
		this.filepath = filepath;

		var json : Dynamic;
		try {
			var content : String = null;
			#if editor
			content = sys.io.File.getContent(hide.Ide.inst.resourceDir + "/" + this.filepath);
			#else
			content = hxd.res.Loader.currentInstance.load(this.filepath).toText();
			//content = hxd.Res.load(this.filepath).toText();
			#end
			if (content.length == 0) return;
			json = haxe.Json.parse(content);
		} catch( e : Dynamic ) {
			throw "Invalid shader graph parsing ("+e+")";
		}

		load(json);

	}

	public function load(json : Dynamic) {
		nodes = [];
		parametersAvailable = [];
		generate(Reflect.getProperty(json, "nodes"), Reflect.getProperty(json, "edges"), Reflect.getProperty(json, "parameters"));
	}

	public function generate(nodes : Array<Node>, edges : Array<Edge>, parameters : Array<Parameter>) {

		for (p in parameters) {
			var typeString : Array<Dynamic> = Reflect.field(p, "type");
			if (Std.is(typeString, Array)) {
				if (typeString[1] == null || typeString[1].length == 0)
					p.type = std.Type.createEnum(Type, typeString[0]);
				else {
					var paramsEnum = typeString[1].split(",");
					p.type = std.Type.createEnum(Type, typeString[0], [Std.parseInt(paramsEnum[0]), std.Type.createEnum(VecType, paramsEnum[1])]);
				}
			}
			p.variable = generateParameter(p.name, p.type);
			this.parametersAvailable.set(p.id, p);
			current_param_id = p.id + 1;
		}

		for (n in nodes) {
			n.outputs = [];
			var cl = std.Type.resolveClass(n.type);
			if( cl == null ) throw "Missing shader node "+n.type;
			n.instance = std.Type.createInstance(cl, []);
			n.instance.setId(n.id);
			n.instance.loadProperties(n.properties);
			this.nodes.set(n.id, n);

			var shaderParam = Std.downcast(n.instance, ShaderParam);
			if (shaderParam != null) {
				var paramShader = getParameter(shaderParam.parameterId);
				shaderParam.variable = paramShader.variable;
				shaderParam.computeOutputs();
			}
		}
		if (nodes[nodes.length-1] != null)
			this.current_node_id = nodes[nodes.length-1].id+1;

		for (e in edges) {
			addEdge(e);
		}
	}

	public function addEdge(edge : Edge) {
		var node = this.nodes.get(edge.idInput);
		var output = this.nodes.get(edge.idOutput);
		node.instance.setInput(edge.nameInput, new NodeVar(output.instance, edge.nameOutput));
		output.outputs.push(node);

		var subShaderIn = Std.downcast(node.instance, hrt.shgraph.nodes.SubGraph);
		var subShaderOut = Std.downcast(output.instance, hrt.shgraph.nodes.SubGraph);
		if( @:privateAccess ((subShaderIn != null) && !subShaderIn.inputInfoKeys.contains(edge.nameInput))
			|| @:privateAccess ((subShaderOut != null) && !subShaderOut.outputInfoKeys.contains(edge.nameOutput))
		) {
			removeEdge(edge.idInput, edge.nameInput, false);
		}

		#if editor
		if (hasCycle()){
			removeEdge(edge.idInput, edge.nameInput, false);
			return false;
		}
		try {
			updateOutputs(output);
		} catch (e : Dynamic) {
			removeEdge(edge.idInput, edge.nameInput);
			throw e;
		}
		#end
		return true;
	}

	public function nodeUpdated(idNode : Int) {
		var node = this.nodes.get(idNode);
		if (node != null) {
			updateOutputs(node);
		}
	}

	function updateOutputs(node : Node) {
		node.instance.computeOutputs();
		for (o in node.outputs) {
			updateOutputs(o);
		}
	}

	public function removeEdge(idNode, nameInput, update = true) {
		var node = this.nodes.get(idNode);
		this.nodes.get(node.instance.getInput(nameInput).node.id).outputs.remove(node);
		node.instance.setInput(nameInput, null);
		if (update) {
			updateOutputs(node);
		}
	}

	public function setPosition(idNode : Int, x : Float, y : Float) {
		var node = this.nodes.get(idNode);
		node.x = x;
		node.y = y;
	}

	public function getNodes() {
		return this.nodes;
	}

	public function getNode(id : Int) {
		return this.nodes.get(id);
	}

	function generateParameter(name : String, type : Type) : TVar {
		return {
				parent: null,
				id: 0,
				kind:Param,
				name: name,
				type: type
			};
	}

	public function getParameter(id : Int) {
		return parametersAvailable.get(id);
	}

	function buildNodeVar(nodeVar : NodeVar) : Array<TExpr>{
		var node = nodeVar.node;
		var isSubGraph = Std.is(node, hrt.shgraph.nodes.SubGraph);
		if (node == null)
			return [];
		var res = [];
		var keys = node.getInputInfoKeys();
		for (key in keys) {
			var input = node.getInput(key);
			if (input != null) {
				res = res.concat(buildNodeVar(input));
			} else if (node.getInputInfo(key).hasProperty) {
			} else if (!node.getInputInfo(key).isRequired) {
			} else {
				throw ShaderException.t("This box has inputs not connected", node.id);
			}
		}
		var build = nodeVar.getExpr();

		var shaderInput = Std.downcast(node, ShaderInput);
		if (shaderInput != null) {
			var variable = shaderInput.variable;
			if ((variable.kind == Param || variable.kind == Global || variable.kind == Input || variable.kind == Local) && !alreadyAddVariable(variable)) {
				allVariables.push(variable);
			}
		}
		var shaderParam = Std.downcast(node, ShaderParam);
		if (shaderParam != null && !alreadyAddVariable(shaderParam.variable)) {
			if (shaderParam.variable == null) {
				shaderParam.variable = generateParameter(shaderParam.variable.name, shaderParam.variable.type);
			}
			allVariables.push(shaderParam.variable);
			allParameters.push(shaderParam.variable);
			if (parametersAvailable.exists(shaderParam.parameterId))
				allParamDefaultValue.push(getParameter(shaderParam.parameterId).defaultValue);
		}
		if (isSubGraph) {
			var subGraph = Std.downcast(node, hrt.shgraph.nodes.SubGraph);
			var params = subGraph.subShaderGraph.parametersAvailable;
			for (subVar in subGraph.varsSubGraph) {
				if (subVar.kind == Param) {
					if (!alreadyAddVariable(subVar)) {
						allVariables.push(subVar);
						allParameters.push(subVar);
						var defaultValueFound = false;
						for (param in params) {
							if (param.variable.name == subVar.name) {
								allParamDefaultValue.push(param.defaultValue);
								defaultValueFound = true;
								break;
							}
						}
						if (!defaultValueFound) {
							throw ShaderException.t("Default value of '" + subVar.name + "' parameter not found", node.id);
						}
					}
				} else {
					if (!alreadyAddVariable(subVar)) {
						allVariables.push(subVar);
					}
				}
			}
			var buildWithoutTBlock = [];
			for (i in 0...build.length) {
				switch (build[i].e) {
					case TBlock(block):
						for (b in block) {
							buildWithoutTBlock.push(b);
						}
					default:
						buildWithoutTBlock.push(build[i]);
				}
			}
			build = buildWithoutTBlock;
		}
		res = res.concat(build);
		return res;
	}

	function alreadyAddVariable(variable : TVar) {
		for (v in allVariables) {
			if (v.name == variable.name && v.type == variable.type) {
				return true;
			}
		}
		return false;
	}

	var variableNameAvailableOnlyInVertex = [];

	public function generateShader(specificOutput : ShaderNode = null, subShaderId : Int = null) : ShaderData {
		allVariables = [];
		allParameters = [];
		allParamDefaultValue = [];
		var contentVertex = [];
		var contentFragment = [];

		for (n in nodes) {
			if (!variableNamesAlreadyUpdated && subShaderId != null && !Std.is(n.instance, ShaderInput)) {
				for (outputKey in n.instance.getOutputInfoKeys()) {
					var output = n.instance.getOutput(outputKey);
					if (output != null)
						output.name = "sub_" + subShaderId + "_" + output.name;
				}
			}
			n.instance.outputCompiled = [];
			#if !editor
			if (!n.instance.hasInputs()) {
				updateOutputs(n);
			}
			#end
		}
		variableNamesAlreadyUpdated = true;

		var outputs : Array<String> = [];

		for (g in ShaderGlobalInput.globalInputs) {
			allVariables.push(g);
		}

		for (n in nodes) {
			var outNode;
			var outVar;
			if (specificOutput != null) {
				if (n.instance != specificOutput) continue;
				outNode = specificOutput;
				outVar = Std.downcast(specificOutput, hrt.shgraph.nodes.Preview).variable;
			} else {
				var shaderOutput = Std.downcast(n.instance, ShaderOutput);

				if (shaderOutput != null) {
					outVar = shaderOutput.variable;
					outNode = n.instance;
				} else {
					continue;
				}
			}
			if (outNode != null) {
				if (outputs.indexOf(outVar.name) != -1) {
					throw ShaderException.t("This output already exists", n.id);
				}
				outputs.push(outVar.name);
				if ( !alreadyAddVariable(outVar) ) {
					allVariables.push(outVar);
				}
				var nodeVar = new NodeVar(outNode, "input");
				var isVertex = (variableNameAvailableOnlyInVertex.indexOf(outVar.name) != -1);
				if (isVertex) {
					contentVertex = contentVertex.concat(buildNodeVar(nodeVar));
				} else {
					contentFragment = contentFragment.concat(buildNodeVar(nodeVar));
				}
				if (specificOutput != null) break;
			}
		}

		var shvars = [];
		var inputVar : TVar = null, inputVars = [], inputMap = new Map();
		for( v in allVariables ) {
			if( v.id == 0 )
				v.id = hxsl.Tools.allocVarId();
			if( v.kind != Input ) {
				shvars.push(v);
				continue;
			}
			if( inputVar == null ) {
				inputVar = {
					id : hxsl.Tools.allocVarId(),
					name : "input",
					kind : Input,
					type : TStruct(inputVars),
				};
				shvars.push(inputVar);
			}
			var prevId = v.id;
			v = Reflect.copy(v);
			v.id = hxsl.Tools.allocVarId();
			v.parent = inputVar;
			inputVars.push(v);
			inputMap.set(prevId, v);
		}

		if( inputVars.length > 0 ) {
			function remap(e:TExpr) {
				return switch( e.e ) {
				case TVar(v):
					var i = inputMap.get(v.id);
					if( i == null ) e else { e : TVar(i), p : e.p, t : e.t };
				default:
					hxsl.Tools.map(e, remap);
				}
			}
			contentVertex = [for( e in contentVertex ) remap(e)];
			contentFragment = [for( e in contentFragment ) remap(e)];
		}

		var shaderData = {
			funs : [],
			name: "SHADER_GRAPH",
			vars: shvars
		};

		if (contentVertex.length > 0) {
			shaderData.funs.push({
					ret : TVoid, kind : Vertex,
					ref : {
						name : "vertex",
						id : 0,
						kind : Function,
						type : TFun([{ ret : TVoid, args : [] }])
					},
					expr : {
						p : null,
						t : TVoid,
						e : TBlock(contentVertex)
					},
					args : []
				});
		}

		if (contentFragment.length > 0) {
			shaderData.funs.push({
					ret : TVoid, kind : Fragment,
					ref : {
						name : "fragment",
						id : 0,
						kind : Function,
						type : TFun([{ ret : TVoid, args : [] }])
					},
					expr : {
						p : null,
						t : TVoid,
						e : TBlock(contentFragment)
					},
					args : []
				});
		}

		return shaderData;
	}

	public function compile(?specificOutput : ShaderNode, ?subShaderId : Int) : hrt.prefab.ContextShared.ShaderDef {

		var shaderData = generateShader(specificOutput, subShaderId);

		var s = new SharedShader("");
		s.data = shaderData;
		@:privateAccess s.initialize();
		var inits : Array<{ variable : hxsl.Ast.TVar, value : Dynamic }> = [];

		for (i in 0...allParameters.length) {
			inits.push({ variable : allParameters[i], value : allParamDefaultValue[i] });
		}

		var shaderDef = { shader : s, inits : inits };
		return shaderDef;
	}

	public function makeInstance(ctx: hrt.prefab.ContextShared) : hxsl.DynamicShader {
		var def = compile();
		var s = new hxsl.DynamicShader(def.shader);
		for (init in def.inits)
			setParamValue(ctx, s, init.variable, init.value);
		return s;
	}

	static function setParamValue(ctx: hrt.prefab.ContextShared, shader : hxsl.DynamicShader, variable : hxsl.Ast.TVar, value : Dynamic) {
		try {
			switch (variable.type) {
				case TSampler2D:
					var t = ctx.loadTexture(value);
					t.wrap = Repeat;
					shader.setParamValue(variable, t);
				case TVec(size, _):
					shader.setParamValue(variable, h3d.Vector.fromArray(value));
				default:
					shader.setParamValue(variable, value);
			}
		} catch (e : Dynamic) {
			// The parameter is not used
		}
	}


	#if editor
	public function addNode(x : Float, y : Float, nameClass : Class<ShaderNode>) {
		var node : Node = { x : x, y : y, id : current_node_id, type: std.Type.getClassName(nameClass) };

		node.instance = std.Type.createInstance(nameClass, []);
		node.instance.setId(current_node_id);
		node.instance.computeOutputs();
		node.outputs = [];

		this.nodes.set(node.id, node);
		current_node_id++;

		return node.instance;
	}

	public function hasCycle() : Bool {
		var queue : Array<Node> = [];

		var counter = 0;
		var nbNodes = 0;
		for (n in nodes) {
			n.indegree = n.outputs.length;
			if (n.indegree == 0) {
				queue.push(n);
			}
			nbNodes++;
		}

		var currentIndex = 0;
		while (currentIndex < queue.length) {
			var node = queue[currentIndex];
			currentIndex++;

			for (input in node.instance.getInputs()) {
				var nodeInput = nodes.get(input.node.id);
				nodeInput.indegree -= 1;
				if (nodeInput.indegree == 0) {
					queue.push(nodeInput);
				}
			}
			counter++;
		}

		return counter != nbNodes;
	}

	public function addParameter(type : Type) {
		var name = "Param_" + current_param_id;
		parametersAvailable.set(current_param_id, {id: current_param_id, name : name, type : type, defaultValue : null, variable : generateParameter(name, type)});
		current_param_id++;
		return current_param_id-1;
	}

	public function setParameterTitle(id : Int, newName : String) {
		var p = parametersAvailable.get(id);
		if (p != null) {
			if (newName != null) {
				for (p in parametersAvailable) {
					if (p.name == newName) {
						return false;
					}
				}
				p.name = newName;
				p.variable = generateParameter(newName, p.type);
				return true;
			}
		}
		return false;
	}

	public function setParameterDefaultValue(id : Int, newDefaultValue : Dynamic) : Bool {
		var p = parametersAvailable.get(id);
		if (p != null) {
			if (newDefaultValue != null) {
				p.defaultValue = newDefaultValue;
				return true;
			}
		}
		return false;
	}

	public function removeParameter(id : Int) {
		parametersAvailable.remove(id);
	}

	public function removeNode(idNode : Int) {
		this.nodes.remove(idNode);
	}

	public function save() {
		var edgesJson : Array<Edge> = [];
		for (n in nodes) {
			for (k in n.instance.getInputsKey()) {
				var output =  n.instance.getInput(k);
				edgesJson.push({ idOutput: output.node.id, nameOutput: output.keyOutput, idInput: n.id, nameInput: k });
			}
		}
		var json = haxe.Json.stringify({
			nodes: [
				for (n in nodes) { x : Std.int(n.x), y : Std.int(n.y), id: n.id, type: n.type, properties : n.instance.savePropertiesNode() }
			],
			edges: edgesJson,
			parameters: [
				for (p in parametersAvailable) { id : p.id, name : p.name, type : [p.type.getName(), p.type.getParameters().toString()], defaultValue : p.defaultValue }
			]
		}, "\t");

		return json;
	}
	#end
}