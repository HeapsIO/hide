package hrt.shgraph;

import hxsl.SharedShader;
using hxsl.Ast;
using hide.tools.Extensions.ArrayExtensions;
using haxe.EnumTools.EnumValueTools;
using Lambda;

typedef ShaderNodeDef = {
	expr: TExpr,
	inVars: Array<TVar>, // Variables that shows up as input of a node
	outVars: Array<TVar>, // Variables that shows up as outputs of a node
	externVars: Array<TVar>, // All the external variables of a shader, including sginput/sgoutputs
	inits: Array<{variable: TVar, value: Dynamic}>, // Default values for some variables
};

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

typedef Connection = {
	from : Node,
	fromName : String,
};

typedef Parameter = {
	name : String,
	type : Type,
	defaultValue : Dynamic,
	?id : Int,
	?variable : TVar,
	index : Int
};

class ShaderGraph {

	var allParameters = [];
	var allParamDefaultValue = [];
	var current_node_id = 0;
	var current_param_id = 0;
	var filepath : String;
	var nodes : Map<Int, Node> = [];

	public var parametersAvailable : Map<Int, Parameter> = [];
	public var parametersKeys : Array<Int> = [];

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
		parametersKeys = [];
		generate(Reflect.getProperty(json, "nodes"), Reflect.getProperty(json, "edges"), Reflect.getProperty(json, "parameters"));
	}
	public function checkParameterOrder() {
		parametersKeys.sort((x,y) -> Reflect.compare(parametersAvailable.get(x).index, parametersAvailable.get(y).index));
	}

	public function generate(nodes : Array<Node>, edges : Array<Edge>, parameters : Array<Parameter>) {

		for (p in parameters) {
			var typeString : Array<Dynamic> = Reflect.field(p, "type");
			if (Std.isOfType(typeString, Array)) {
				if (typeString[1] == null || typeString[1].length == 0)
					p.type = std.Type.createEnum(Type, typeString[0]);
				else {
					var paramsEnum = typeString[1].split(",");
					p.type = std.Type.createEnum(Type, typeString[0], [Std.parseInt(paramsEnum[0]), std.Type.createEnum(VecType, paramsEnum[1])]);
				}
			}
			p.variable = generateParameter(p.name, p.type);
			this.parametersAvailable.set(p.id, p);
			parametersKeys.push(p.id);
			current_param_id = p.id + 1;
		}
		checkParameterOrder();

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
		if (!output.instance.getOutputs2().exists(edge.nameOutput)) {
			return false;
		}
		node.instance.setInput(edge.nameInput, new NodeVar(output.instance, edge.nameOutput));
		output.outputs.push(node);

		// pas du tout envie de mourrir

		var toGen = node.instance.getShaderDef();
		var toName = toGen.inVars[node.instance.getInputInfoKeys().indexOf(edge.nameInput)].name;

		var connection : Connection = {from: output, fromName: edge.nameOutput};
		node.instance.inputs2.set(toName, connection);

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

		var toGen = node.instance.getShaderDef();
		var toName = toGen.inVars[node.instance.getInputInfoKeys().indexOf(nameInput)].name;

		node.instance.inputs2.remove(toName);
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

	public function generate2(?getNewVarId: () -> Int) : ShaderNodeDef {
		if (getNewVarId == null) {
			var varIdCount = 0;
			getNewVarId = function()
				{
					return varIdCount++;
				};
		}

		inline function getNewVarName(node: Node, id: Int) : String {
			return '_sg_${(node.type).split(".").pop()}_var_$id';
		}

		var nodeOutputs : Map<Node, Map<String, TVar>> = [];
		function getOutputs(node: Node) : Map<String, TVar> {
			if (!nodeOutputs.exists(node)) {
				var outputs : Map<String, TVar> = [];

				var def = node.instance.getShaderDef();
				for (output in def.outVars) {
					var type = output.type;
					if (type == null) throw "no type";
					var id = getNewVarId();
					var outVar = {id: id, name: getNewVarName(node, id), type: type, kind : Local};
					outputs.set(output.name, outVar);
				}

				nodeOutputs.set(node, outputs);
			}
			return nodeOutputs.get(node);
		}

		// Recursively replace the to tvar with from tvar in the given expression
		function replaceVar(expr: TExpr, what: TVar, with: TExpr) : TExpr {
			if(!what.type.equals(with.t))
				throw "type missmatch " + what.type + " != " + with.t;
			function repRec(f: TExpr) {
				if (f.e.equals(TVar(what))) {
					return with;
				} else {
					return f.map(repRec);
				}
			}
			return repRec(expr);
		}

		// Shader generation starts here

		var pos : Position = {file: "", min: 0, max: 0};
		var outputNodes : Array<Node> = [];
		var inits : Array<{ variable : hxsl.Ast.TVar, value : Dynamic }> = [];

		var allConnections : Array<Connection> = [for (node in nodes) for (connection in node.instance.inputs2) connection];


		// find all node with no output
		var nodeHasOutputs : Map<Node, Bool> = [];
		for (node in nodes) {
			nodeHasOutputs.set(node, false);
		}
		for (connection in allConnections) {
			nodeHasOutputs.set(connection.from, true);
		}

		var graphInputVars : Array<TVar> = [];
		var graphOutputVars : Array<TVar> = [];
		var externs : Array<TVar> = [];

		var nodeToExplore : Array<Node> = [];

		for (node => hasOutputs in nodeHasOutputs) {
			if (!hasOutputs)
				nodeToExplore.push(node);
		}

		var sortedNodes : Array<Node> = [];

		// Topological sort the nodes with Kahn's algorithm
		// https://en.wikipedia.org/wiki/Topological_sorting#Kahn's_algorithm
		{
			while (nodeToExplore.length > 0) {
				var currentNode = nodeToExplore.pop();
				sortedNodes.push(currentNode);
				for (connection in currentNode.instance.inputs2) {
					var targetNode = connection.from;
					if (!allConnections.remove(connection)) throw "connection not in graph";
					if (allConnections.find((n:Connection) -> n.from == targetNode) == null) {
						nodeToExplore.push(targetNode);
					}
				}
			}
		}

		function convertToType(targetType: hxsl.Ast.Type, sourceExpr: TExpr) : TExpr {
			var sourceType = sourceExpr.t;

			var sourceSize = switch (sourceType) {
				case TFloat: 1;
				case TVec(size, VFloat): size;
				default:
					throw "Unsupported source type " + sourceType;
			}

			var targetSize = switch (targetType) {
				case TFloat: 1;
				case TVec(size, VFloat): size;
				default:
					throw "Unsupported target type " + targetType;
			}

			var delta = targetSize - sourceSize;
			if (delta == 0)
				return sourceExpr;
			if (delta > 0) {
				var args = [];
				if (sourceSize == 1) {
					for (_ in 0...targetSize) {
						args.push(sourceExpr);
					}
				}
				else {
					args.push(sourceExpr);
					for (i in 0...delta) {
						args.push({e : TConst(CFloat(0.0)), p: sourceExpr.p, t: TFloat});
					}
				}
				var global : TGlobal = switch (targetSize) {
					case 2: Vec2;
					case 3: Vec3;
					case 4: Vec4;
					default: throw "unreachable";
				}
				return {e: TCall({e: TGlobal(global), p: sourceExpr.p, t:targetType}, args), p: sourceExpr.p, t: targetType};
			}
			if (delta < 0) {
				var swizz : Array<hxsl.Ast.Component> = [X,Y,Z,W];
				swizz.resize(targetSize);
				return {e: TSwiz(sourceExpr, swizz), p: sourceExpr.p, t: targetType};
			}
			throw "unreachable";
		}

		// Actually build the final shader expression
		var exprsReverse : Array<TExpr> = [];
		for (currentNode in sortedNodes) {
			// Skip nodes with no outputs that arent a final node
			if (Std.downcast(currentNode.instance, ShaderOutput)==null) {
				if (!nodeHasOutputs.get(currentNode))
					continue;
			}


			var outputs = getOutputs(currentNode);

			{
				var def = currentNode.instance.getShaderDef();
				var expr = def.expr;

				var outputDecls : Array<TVar> = [];
				for (nodeVar in def.externVars) {
					if (nodeVar.qualifiers != null) {
						if (nodeVar.qualifiers.has(SgInput)) {
							var connection = currentNode.instance.inputs2.get(nodeVar.name);

							var replacement : TExpr = null;

							if (connection != null) {
								var outputs = getOutputs(connection.from);
								var outputVar = outputs[connection.fromName];
								if (outputVar == null) throw "null tvar";
								replacement = convertToType(nodeVar.type,  {e: TVar(outputVar), p:pos, t: outputVar.type});
							}
							else {
								var shParam = Std.downcast(currentNode.instance, ShaderParam);
								if (shParam != null) {
									var id = getNewVarId();
									var outVar = {id: id, name: nodeVar.name, type: nodeVar.type, kind : Param, qualifiers: [SgInput]};
									replacement = {e: TVar(outVar), p:pos, t: nodeVar.type};
									graphInputVars.push(outVar);
									externs.push(outVar);
									var param = getParameter(shParam.parameterId);
									inits.push({variable: outVar, value: param.defaultValue});
								}
								else {
									replacement = convertToType(nodeVar.type, {e: TConst(CFloat(0.5)), p: pos, t:TFloat});
								}
							}

							expr = replaceVar(expr, nodeVar, replacement);

						}
						else if (nodeVar.qualifiers.has(SgOutput)) {
							var outputVar : TVar = outputs.get(nodeVar.name);
							if (outputVar == null) {
								externs.push(nodeVar);
							} else {
								expr = replaceVar(expr, nodeVar, {e: TVar(outputVar), p:pos, t: nodeVar.type});
								outputDecls.push(outputVar);
							}
						}
						else {
							externs.push(nodeVar);
						}
					}
					else {
						externs.push(nodeVar);
					}
				}

				exprsReverse.push(expr);

				for (output in outputDecls) {
					var finalExpr : TExpr = {e: TVarDecl(output), p: pos, t: output.type};
					exprsReverse.push(finalExpr);
				}
			}
		}

		exprsReverse.reverse();

		return {
			expr: {e: TBlock(exprsReverse), t:TVoid, p:pos},
			inVars: graphInputVars,
			outVars: graphOutputVars,
			externVars: externs,
			inits: inits,
		};
	}

	public function compile2() : hrt.prefab.ContextShared.ShaderDef {
		var start = haxe.Timer.stamp();

		var gen = generate2();

		var shaderData : ShaderData = {
			name: "",
			vars: [],
			funs: [],
		};

		shaderData.vars.append(gen.externVars);

		shaderData.funs.push({
			ret : TVoid, kind : Fragment,
			ref : {
				name : "fragment",
				id : 0,
				kind : Function,
				type : TFun([{ ret : TVoid, args : [] }])
			},
			expr : gen.expr,
			args : []
		});


		var shared = new SharedShader("");
		@:privateAccess shared.data = shaderData;
		@:privateAccess shared.initialize();

		var time = haxe.Timer.stamp() - start;
		trace("Shader compile2 in " + time * 1000 + " ms");

		return {shader : shared, inits: gen.inits};
	}

	public function getParameter(id : Int) {
		return parametersAvailable.get(id);
	}

	public function makeInstance(ctx: hrt.prefab.ContextShared) : hxsl.DynamicShader {
		var def = compile2();
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
		parametersAvailable.set(current_param_id, {id: current_param_id, name : name, type : type, defaultValue : null, variable : generateParameter(name, type), index : parametersKeys.length});
		parametersKeys.push(current_param_id);
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
		parametersKeys.remove(id);
		checkParameterIndex();
	}

	public function checkParameterIndex() {
		for (k in parametersKeys) {
			var oldParam = parametersAvailable.get(k);
			oldParam.index = parametersKeys.indexOf(k);
			parametersAvailable.set(k, oldParam);
		}
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
				for (p in parametersAvailable) { id : p.id, name : p.name, type : [p.type.getName(), p.type.getParameters().toString()], defaultValue : p.defaultValue, index : p.index }
			]
		}, "\t");

		return json;
	}
	#end
}