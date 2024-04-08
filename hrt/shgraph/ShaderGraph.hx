package hrt.shgraph;

import hxsl.SharedShader;
using hxsl.Ast;
using haxe.EnumTools.EnumValueTools;
using Lambda;
import hrt.shgraph.AstTools.*;
import hrt.shgraph.SgHxslVar.ShaderDefInput;

enum abstract AngleUnit(String) {
	var Radian;
	var Degree;
}

final angleUnits = [Radian, Degree];

#if editor
function getAngleUnitDropdown(self: Dynamic, width: Float) : hide.Element {
	var element = new hide.Element('<div style="width: ${width * 0.8}px; height: 40px"></div>');
	element.append('<span>Unit</span>');
	element.append(new hide.Element('<select id="unit"></select>'));
	if (self.unit == null) {
		self.unit = angleUnits[0];
	}

	var input = element.children("#unit");
	var indexOption = 0;
	for (i => curAngle in angleUnits) {
		input.append(new hide.Element('<option value="${i}">${curAngle}</option>'));
		if (self.unit == curAngle) {
			input.val(i);
		}
		indexOption++;
	}

	input.on("change", function(e) {
		var value = input.val();
		self.unit = angleUnits[value];
	});

	return element;
}
#end

enum SgType {
	SgFloat(dimension: Int);
	SgSampler;
	SgInt;
	SgBool;

	/**
		All the generics in the same shader node with the same id unify to the
		same type.

		Constraint :
			newType : the type we are trying to constraint. If null the function should return previousType
			previousType : the type previously constraint to this generic.
			if both newType and previousType are null, the function should return the most generic type for the constraint
			return : null if the newType can't be constrained, or a type that can fit both new and previous types
	**/
	SgGeneric(id: Int, constraint: (newType: Type, previousType: Type) -> Null<Type>);
}

function typeToSgType(t: Type) : SgType {
	return switch(t) {
		case TFloat:
			SgFloat(1);
		case TVec(n, VFloat):
			SgFloat(n);
		case TSampler(T2D, false):
			SgSampler;
		case TInt:
			SgInt;
		case TBool:
			SgBool;
		default:
			throw "Unsuported type";
	}
}

function sgTypeToType(t: SgType) : Type {
	return switch(t) {
		case SgBool:
			return TBool;
		case SgFloat(1):
			return TFloat;
		case SgFloat(n):
			return TVec(n, VFloat);
		case SgSampler:
			return TSampler(T2D, false);
		case SgInt:
			return TInt;
		case SgGeneric(id, consDtraint):
			throw "Can't resolve generic without context";
	}
}

function ConstraintFloat(newType: Type, previousType: Type) : Null<Type> {
	function getN(type:Type) {
		return switch(type) {
			case TFloat:
				1;
			case TVec(n, VFloat):
				n;
			case null, _:
				null;
		};
	}

	var newN = getN(newType) ?? return (previousType ?? TFloat);
	var oldN = getN(previousType) ?? newN;

	var maxN = hxd.Math.imax(newN, oldN);
	switch (maxN) {
		case 1:
			return TFloat;
		case 2,3,4:
			return TVec(maxN, VFloat);
		default:
			throw "invalid float size " + maxN;
	}
}



typedef ShaderNodeDefInVar = {v: TVar, internal: Bool, ?defVal: ShaderDefInput, isDynamic: Bool};
typedef ShaderNodeDefOutVar = {v: TVar, internal: Bool, isDynamic: Bool};
typedef ShaderNodeDef = {
	expr: TExpr,
	inVars: Array<ShaderNodeDefInVar>, // If internal = true, don't show input in ui
	outVars: Array<ShaderNodeDefOutVar>,
	externVars: Array<TVar>, // other external variables like globals and stuff
	inits: Array<{variable: TVar, value: Dynamic}>, // Default values for some variables
	?__inits__: Array<{name: String, e:TExpr}>,
	?functions: Array<TFunction>,
};

typedef Node = {
	x : Float,
	y : Float,
	id : Int,
	type : String,
	?properties : Dynamic,
	?instance : ShaderNode,
	?outputs: Array<Node>,
	?indegree : Int,
	?generateId : Int, // Id used to index the node in the generate function
};

typedef Edge = {
	?outputNodeId : Int,
	nameOutput : String, // Fallback if name has changed
	?outputId : Int,
	?inputNodeId : Int,
	nameInput : String, // Fallback if name has changed
	?inputId : Int,
};

typedef Connection = {
	from : Node,
	outputId : Int,
};

typedef Parameter = {
	name : String,
	type : Type,
	defaultValue : Dynamic,
	?id : Int,
	?variable : TVar,
	?internal: Bool,
	index : Int
};

enum Domain {
	Vertex;
	Fragment;
}


typedef GenNodeInfo = {
	outputToInputMap: Map<String, Array<{node: Node, inputName: String}>>,
	inputTypes: Array<Type>,
	?outputs: Map<String, TVar>,
	?def: ShaderGraph.ShaderNodeDef,
}

@:structInit @:publicFields
class
ExternVarDef {
	var v: TVar;
	var defValue: Dynamic;
	var __init__: TExpr;
	@:optional var paramIndex: Int;
}

@:access(hrt.shgraph.Graph)
class ShaderGraphGenContext2 {
	var graph : Graph;
	var includePreviews : Bool;

	public function new(graph: Graph, includePreviews: Bool = false) {
		this.graph = graph;
		this.includePreviews = includePreviews;
	}

	var nodes : Array<{
		var outputs: Array<Array<{to: Int, input: Int}>>;
		var inputs : Array<TExpr>;
		var node : Node;
	}>;

	var inputNodes : Array<Int> = [];

	public function initNodes() {
		nodes = [];
		for (id => node in graph.nodes) {
			nodes[id] = {node: node, inputs : [], outputs : []};
		}
	}

	public function generate(?genContext: NodeGenContext) : TExpr {
		initNodes();
		var sortedNodes = sortGraph();

		genContext = genContext ?? new NodeGenContext(graph.domain);
		var expressions : Array<TExpr> = [];
		genContext.expressions = expressions;

		for (nodeId in sortedNodes) {
			var node = nodes[nodeId];
			genContext.initForNode(node.node, node.inputs);

			node.node.instance.generate(genContext);

			for (outputId => expr in genContext.outputs) {
				if (expr == null) throw "null expr for output " + outputId;
				var targets = node.outputs[outputId];
				if (targets == null) continue;
				for (target in targets) {
					nodes[target.to].inputs[target.input] = expr;
				}
			}

			genContext.finishNode();
		}

		// Assign preview color to pixel color as last operation
		var previewColor = genContext.globalVars.get(Variables.Globals[Variables.Global.PreviewColor].name);
		if (previewColor != null) {
			var previewSelect = genContext.getOrAllocateGlobal(PreviewSelect);
			var pixelColor = genContext.getOrAllocateGlobal(PixelColor);
			var assign = makeAssign(makeVar(pixelColor), makeVar(previewColor.v));
			var ifExpr = makeIf(makeBinop(makeVar(previewSelect), OpNotEq, makeInt(0)), assign);
			expressions.push(ifExpr);
		}

		for (id => p in graph.parent.parametersAvailable) {
			var global = genContext.globalVars.get(p.name);
			if (global == null)
				continue;
			global.defValue = p.defaultValue;
			global.paramIndex = p.index;
		}

		return AstTools.makeExpr(TBlock(expressions), TVoid);
	}

	// returns null if the graph couldn't be sorted (i.e. contains cycles)
	function sortGraph() : Array<Int>
	{
		// Topological sort all the nodes from input to ouputs

		var nodeToExplore : Array<Int> = [];
		var nodeTopology : Array<{to: Array<Int>, incoming: Int}> = [];
		nodeTopology.resize(nodes.length);

		for (id => node in nodes) {
			if (node == null) continue;
			nodeTopology[id] = {to: [], incoming: 0};
		}

		var totalEdges = 0;

		for (id => node in nodes) {
			if (node == null) continue;
			var inst = node.node.instance;
			var empty = true;
			var inputs = inst.getInputs();


			// Todo : store ID of input in connections instead of relying on the "name" at runtime
			for (inputId => connection in inst.connections) {
				if (connection == null)
					continue;
				empty = false;
				var nodeOutputs = connection.from.instance.getOutputs();
				var outputs = nodes[connection.from.id].outputs;
				if (outputs == null) {
					outputs = [];
					nodes[connection.from.id].outputs = [];
				}

				var outputId = connection.outputId;

				var output = outputs[outputId];
				if (output == null) {
					output = [];
					outputs[outputId] = output;
				}

				output.push({to: id, input: inputId});

				nodeTopology[connection.from.id].to.push(id);
				nodeTopology[id].incoming ++;
				totalEdges++;
			}
			for (inputId => input in inputs) {
			}
			if (empty) {
				nodeToExplore.push(id);
			}
		}

		var sortedNodes : Array<Int> = [];

		// Perform the sort
		while (nodeToExplore.length > 0) {
			var currentNodeId = nodeToExplore.pop();
			sortedNodes.push(currentNodeId);
			var currentTopology = nodeTopology[currentNodeId];
			for (to in currentTopology.to) {
				var remaining = --nodeTopology[to].incoming;
				totalEdges --;
				if (remaining == 0) {
					nodeToExplore.push(to);
				}
			}
		}

		if (totalEdges > 0) {
			return null;
		}
		return sortedNodes;
	}
}

class ShaderGraph extends hrt.prefab.Prefab {

	var graphs : Array<Graph> = [];

	var cachedDef : hrt.prefab.Cache.ShaderDef = null;

	static var _ = hrt.prefab.Prefab.register("shgraph", hrt.shgraph.ShaderGraph, "shgraph");

	override public function load(json : Dynamic) : Void {
		super.load(json);
		graphs = [];
		parametersAvailable = [];
		parametersKeys = [];

		loadParameters(json.parameters ?? []);
		for (domain in haxe.EnumTools.getConstructors(Domain)) {
			var graph = new Graph(this, haxe.EnumTools.createByName(Domain, domain));
			var graphJson = Reflect.getProperty(json, domain);
			if (graphJson != null) {
				graph.load(graphJson);
			}

			graphs.push(graph);
		}
	}

	override public function copy(other: hrt.prefab.Prefab) : Void {
		throw "Shadergraph is not meant to be put in a prefab tree. Use a dynamic shader that references this shadergraph instead";
	}


	override function save() {
		var json = super.save();
		json.parameters = [
			for (p in parametersAvailable) { id : p.id, name : p.name, type : [p.type.getName(), p.type.getParameters().toString()], defaultValue : p.defaultValue, index : p.index, internal : p.internal }
		];

		for (graph in graphs) {
			var serName = EnumValueTools.getName(graph.domain);
			Reflect.setField(json, serName, graph.saveToDynamic());
		}

		return json;
	}

	public function saveToText() : String {
		return haxe.Json.stringify(save(), "\t");
	}

	static public function resolveDynamicType(inputTypes: Array<Type>, inVars: Array<ShaderNodeDefInVar>) : Type {
		var dynamicType : Type = TFloat;
		for (i => t in inputTypes) {
			var targetInput = inVars[i];
			if (targetInput == null)
				throw "More input types than inputs";
			if (!targetInput.isDynamic)
				continue; // Skip variables not marked as dynamic
			switch (t) {
				case null:
				case TFloat:
					if (dynamicType == null)
						dynamicType = TFloat;
				case TVec(size, t1): // Vec2 always convert to it because it's the smallest vec type
					switch(dynamicType) {
						case TFloat, null:
							dynamicType = t;
						case TVec(size2, t2):
							if (t1 != t2)
								throw "Incompatible vectors types";
							dynamicType = TVec(size < size2 ? size : size2, t1);
						default:
					}
				default:
					throw "Type " + t + " is incompatible with Dynamic";
			}
		}
		return dynamicType;
	}

	public function compile3(?previewDomain: Domain) : hrt.prefab.Cache.ShaderDef {
		var inits : Array<{variable: TVar, value: Dynamic}>= [];

		var shaderData : ShaderData = {
			name: "",
			vars: [],
			funs: [],
		};


		var nodeGen = new NodeGenContext(Vertex);
		nodeGen.previewDomain = previewDomain;

		for (i => graph in graphs) {
			if (previewDomain != null && previewDomain != graph.domain)
				continue;
			nodeGen.domain = graph.domain;
			var ctx = new ShaderGraphGenContext2(graph);
			var gen = ctx.generate(nodeGen);

			var fnKind : FunctionKind = switch(previewDomain != null ? Fragment : graph.domain) {
				case Fragment: Fragment;
				case Vertex: Vertex;
			};

			var functionName : String = EnumValueTools.getName(fnKind).toLowerCase();

			var funcVar : TVar = {
				name : functionName,
				id : hxsl.Tools.allocVarId(),
				kind : Function,
				type : TFun([{ ret : TVoid, args : [] }])
			};

			var fn : TFunction = {
				ret: TVoid, kind: fnKind,
				ref: funcVar,
				expr: gen,
				args: [],
			};

			shaderData.funs.push(fn);
			shaderData.vars.push(funcVar);
		}

		var externs = [for (v in nodeGen.globalVars) v];

		var __init__exprs : Array<TExpr>= [];

		externs.sort((a,b) -> Reflect.compare(a.paramIndex ?? -1, b.paramIndex ?? -1));

		for (v in externs) {
			if (v.v.parent == null) {
				shaderData.vars.push(v.v);
			}
			if (v.defValue != null) {
				inits.push({variable:v.v, value:v.defValue});
			}
			if (v.__init__ != null) {
				__init__exprs.push(v.__init__);
			}
		}

		if (__init__exprs.length != 0) {
			var funcVar : TVar = {
				name : "__init__",
				id : hxsl.Tools.allocVarId(),
				kind : Function,
				type : TFun([{ ret : TVoid, args : [] }])
			};

			var fn : TFunction = {
				ret : TVoid, kind : Init,
				ref : funcVar,
				expr : makeExpr(TBlock(__init__exprs), TVoid),
				args : []
			};

			shaderData.funs.push(fn);
			shaderData.vars.push(funcVar);
		}

		var shared = new SharedShader("");
		@:privateAccess shared.data = shaderData;
		@:privateAccess shared.initialize();

		return {shader : shared, inits: inits};
	}

	public function makeShaderInstance() : hxsl.DynamicShader {
		var def = compile3(null);
		var s = new hxsl.DynamicShader(def.shader);
		for (init in def.inits)
			setParamValue(s, init.variable, init.value);
		return s;
	}

	static function setParamValue(shader : hxsl.DynamicShader, variable : hxsl.Ast.TVar, value : Dynamic) {
		try {
			switch (variable.type) {
				case TSampler(_):
					var t = hrt.impl.TextureType.Utils.getTextureFromValue(value, Repeat);
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

	var allParameters = [];
	var current_param_id = 0;
	public var parametersAvailable : Map<Int, Parameter> = [];
	public var parametersKeys : Array<Int> = [];

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

	public function addParameter(type : Type) {
		var name = "Param_" + current_param_id;
		parametersAvailable.set(current_param_id, {id: current_param_id, name : name, type : type, defaultValue : null, variable : generateParameter(name, type), index : parametersKeys.length});
		parametersKeys.push(current_param_id);
		current_param_id++;
		return current_param_id-1;
	}

	function loadParameters(parameters: Array<Dynamic>) {
		for (p in parameters) {
			var typeString : Array<Dynamic> = Reflect.field(p, "type");
			if (Std.isOfType(typeString, Array)) {
				typeString[1] = typeString[1] ?? "";
				var enumParamsString = typeString[1].split(",");

				switch(typeString[0]) {
					case "TSampler2D": // Legacy parameters conversion
						p.type = Type.TSampler(T2D, false);
					case "TSampler":
						var params : Array<Dynamic> = [std.Type.createEnum(TexDimension, enumParamsString[0] ?? "T2D"), enumParamsString[1] == "true"];
						p.type = std.Type.createEnum(Type, typeString[0], params);
					case "TVec":
						var params : Array<Dynamic> = [Std.parseInt(enumParamsString[0]), std.Type.createEnum(VecType, enumParamsString[1])];
						p.type = std.Type.createEnum(Type, typeString[0], params);
					case "TFloat":
						p.type = TFloat;
					default:
						throw "Couldn't unserialize type " + typeString[0];
				}
			}
			p.variable = generateParameter(p.name, p.type);
			this.parametersAvailable.set(p.id, p);
			parametersKeys.push(p.id);
			current_param_id = p.id + 1;
		}
		checkParameterOrder();
	}

	public function checkParameterOrder() {
		parametersKeys.sort((x,y) -> Reflect.compare(parametersAvailable.get(x).index, parametersAvailable.get(y).index));
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

	public function getGraph(domain: Domain) {
		return graphs[domain.getIndex()];
	}
}

class Graph {

	var cachedGen : ShaderNodeDef = null;
	var allParamDefaultValue = [];
	var current_node_id = 0;
	var nodes : Map<Int, Node> = [];

	public var parent : ShaderGraph = null;

	public var domain : Domain = Fragment;


	public function new(parent: ShaderGraph, domain: Domain) {
		this.parent = parent;
		this.domain = domain;
	}

	public function load(json : Dynamic) {
		nodes = [];
		generate(Reflect.getProperty(json, "nodes"), Reflect.getProperty(json, "edges"));
	}

	public function generate(nodes : Array<Node>, edges : Array<Edge>) {
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
			}
		}
		if (nodes[nodes.length-1] != null)
			this.current_node_id = nodes[nodes.length-1].id+1;

		// Migration patch
		for (e in edges) {
			if (e.inputNodeId == null)
				e.inputNodeId = (e:Dynamic).idInput;
			if (e.outputNodeId == null)
				e.outputNodeId = (e:Dynamic).idOutput;
		}

		for (e in edges) {
			addEdge(e);
		}
	}

	public function addEdge(edge : Edge) {
		var node = this.nodes.get(edge.inputNodeId);
		var output = this.nodes.get(edge.outputNodeId);

		var inputs = node.instance.getInputs();
		var outputs = output.instance.getOutputs();


		var outputId = edge.outputId;
		var inputId = edge.inputId;

		{
			// Check if there is an output with that id and if it has the same name
			// else try to find the id of another output with the same name
			var output = outputs[outputId];
			if (output == null || output.name != edge.nameOutput) {
				for (id => o in outputs) {
					if (o.name == edge.nameOutput) {
						outputId = id;
						break;
					}
				}
			};
		}

		{
			var input = inputs[inputId];
			if (input == null || input.name != edge.nameInput) {
				for (id => i in inputs) {
					if (i.name == edge.nameInput) {
						inputId = id;
						break;
					}
				}
			}
		}

		node.instance.connections[inputId] = {from: output, outputId: outputId};

		#if editor
		if (hasCycle()){
			removeEdge(edge.inputNodeId, inputId, false);
			return false;
		}

		var inputType = inputs[inputId].type;
		var outputType = outputs[outputId].type;

		if (!areTypesCompatible(inputType, outputType)) {
			removeEdge(edge.inputNodeId, inputId);
		}
		try {
		} catch (e : Dynamic) {
			removeEdge(edge.inputNodeId, inputId);
			throw e;
		}
		#end
		return true;
	}

	public function areTypesCompatible(input: SgType, output: SgType) : Bool {
		return switch (input) {
			case SgFloat(_):
				switch (output) {
					case SgFloat(_), SgGeneric(_,_): true;
					default: false;
				};
			case SgGeneric(_, fn):
				switch (output) {
					case SgFloat(_), SgGeneric(_,_): true;
					default: false;
				};
			default: haxe.EnumTools.EnumValueTools.equals(input, output);
		}
	}

	public function removeEdge(idNode, inputId, update = true) {
		var node = this.nodes.get(idNode);
		if (node.instance.connections[inputId] == null) return;
		this.nodes.get(node.instance.connections[inputId].from.id).outputs.remove(node);

		node.instance.connections[inputId] = null;
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

	public function getParameter(id : Int) {
		return parent.getParameter(id);
	}


	public function addNode(x : Float, y : Float, nameClass : Class<ShaderNode>, args: Array<Dynamic>) {
		var node : Node = { x : x, y : y, id : current_node_id, type: std.Type.getClassName(nameClass) };

		node.instance = std.Type.createInstance(nameClass, args);
		node.instance.setId(current_node_id);
		node.outputs = [];

		this.nodes.set(node.id, node);
		current_node_id++;

		return node.instance;
	}

	public function hasCycle() : Bool {
		var ctx = new ShaderGraphGenContext2(this, false);
		@:privateAccess ctx.initNodes();
		var res = @:privateAccess ctx.sortGraph();
		return res == null;
	}

	public function removeNode(idNode : Int) {
		this.nodes.remove(idNode);
	}

	public function saveToDynamic() : Dynamic {
		var edgesJson : Array<Edge> = [];
		for (n in nodes) {
			for (inputId => connection in n.instance.connections) {
				if (connection == null) continue;
				var outputId = connection.outputId;
				edgesJson.push({ outputNodeId: connection.from.id, nameOutput: connection.from.instance.getOutputs()[outputId].name, inputNodeId: n.id, nameInput: n.instance.getInputs()[inputId].name, inputId: inputId, outputId: outputId });
			}
		}
		var json = {
			nodes: [
				for (n in nodes) { x : Std.int(n.x), y : Std.int(n.y), id: n.id, type: n.type, properties : n.instance.saveProperties() }
			],
			edges: edgesJson
		};

		return json;
	}

}