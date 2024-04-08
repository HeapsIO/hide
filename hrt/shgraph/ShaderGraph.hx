package hrt.shgraph;

import hxsl.SharedShader;
using hxsl.Ast;
using haxe.EnumTools.EnumValueTools;
using Lambda;
import hrt.shgraph.AstTools.*;

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

enum ShaderDefInput {
	Var(name: String);
	Const(intialValue: Float);
	ConstBool(initialValue: Bool);
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

private typedef Edge = {
	?outputNodeId : Int,
	nameOutput : String,
	?outputId : Int, // Fallback if name has changed
	?inputNodeId : Int,
	nameInput : String,
	?inputId : Int, // Fallback if name has changed
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

typedef ExternVarDef = {v: TVar, isInput: Bool, isOutput: Bool, defValue: Dynamic};

@:access(hrt.shgraph.Graph)
class ShaderGraphGenContext2 {
	var graph : Graph;
	var includePreviews : Bool;

	public function new(graph: Graph, includePreviews: Bool = false) {
		this.graph = graph;
		this.includePreviews = includePreviews;
	}

	var nodes : Array<{
		var outputs: Array<Array<{to: Node, input: Node}>>;
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

	public function generate() : {e: TExpr, externs: ExternVarDef} {
		initNodes();
		var sortedNodes = sortGraph();

		for (nodeId in sortedNodes) {
			var node = nodes[nodeId];
			trace(node.node.type + ":" + nodeId);
		}

		return null;
	}

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

		for (id => node in nodes) {
			if (node == null) continue;
			var inst = node.node.instance;
			var empty = true;//false;!inst.connections.iterator().hasNext();
			var inputs = inst.getInputs();
			for (input in inst.connections) {
				empty = false;
				nodeTopology[input.from.id].to.push(id);
				nodeTopology[id].incoming ++;
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
				if (remaining == 0) {
					nodeToExplore.push(to);
				}
			}
		}

		return sortedNodes;
	}
}


@:access(hrt.shgraph.Graph)
class ShaderGraphGenContext {
	/** Generation inputs **/
	var graph : Graph;
	var includePreviews : Bool;

	/** Generation data **/
	var nodeData : Array<GenNodeInfo> = [];
	var inits : Array<{ variable : hxsl.Ast.TVar, value : Dynamic }> = [];
	var allConnections : Array<Connection>;
	var graphInputVars : Array<ShaderNodeDefInVar> = [];
	var graphOutputVars : Array<ShaderNodeDefOutVar> = [];
	var externs : Array<TVar> = [];
	var outputSelectVar : TVar = null;
	var outputPreviewPixelColor : TVar = null;
	var pixelColor : TVar;
	var outsideVars : Map<String, TVar> = [];
	var sortedNodes : Array<Node>;
	var functions : Array<TFunction> = [];

	var exprsReverse : Array<TExpr> = [];


	static var pos : Position = {file: "", min: 0, max: 0};

	public function new(graph: Graph, includePreviews: Bool = false) {
		this.graph = graph;
		this.includePreviews = includePreviews;
	}

	static inline function getNewVarName(node: Node, id: Int) : String {
		return '_sg_${(node.type).split(".").pop()}_var_$id';
	}

	static inline function getNewVarId() : Int {
		return hxsl.Tools.allocVarId();
	}

	static function replaceVar(expr: TExpr, what: TVar, with: TExpr) : TExpr {
		if(!what.type.equals(with.t))
			throw "type missmatch " + what.type + " != " + with.t;
		function repRec(f: TExpr) {
			if (f.e.equals(TVar(what))) {
				return with;
			} else {
				return f.map(repRec);
			}
		}
		var expr = repRec(expr);
		//trace("replaced " + what.getName() + " with " + switch(with.e) {case TVar(v): v.getName(); default: "err";});
		//trace(hxsl.Printer.toString(expr));
		return expr;
	}


	static function convertToType(targetType: hxsl.Ast.Type, sourceExpr: TExpr) : TExpr {
		var sourceType = sourceExpr.t;

		if (sourceType.equals(targetType))
			return sourceExpr;

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
					// Set alpha to 1.0 by default on upcasts casts
					var value = i == delta - 1 ? 1.0 : 0.0;
					args.push({e : TConst(CFloat(value)), p: sourceExpr.p, t: TFloat});
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

	function getDef(node: Node) : ShaderGraph.ShaderNodeDef {
		var data = nodeData[node.generateId];
		if (data.def != null)
			return data.def;

		var def = node.instance.getShaderDef(graph.domain, getNewVarId, data.inputTypes);

		var type = ShaderGraph.resolveDynamicType(data.inputTypes, def.inVars);

		// Don't cache vars while there still are dynamics inputs
		if (type == null)
			return def;

		for (v in def.inVars) {
			if (v.isDynamic) {
				v.v.type = type;
				v.isDynamic = false;
			}
		}

		for (v in def.outVars) {
			if (v.isDynamic) {
				v.v.type = type;
				v.isDynamic = false;
			}
		}

		return def;
	}

	function getOutputs(node: Node) : Map<String, TVar> {
		var data = nodeData[node.generateId];
		if (data.outputs != null)
			return data.outputs;
		data.outputs = [];


		var def = getDef(node);
		for (output in def.outVars) {
			if (output.internal)
				continue;
			var type = output.v.type;
			if (type == null) throw "no type";
			var id = getNewVarId();
			var outVar = {id: id, name: getNewVarName(node, id), type: type, kind : Local};
			data.outputs.set(output.v.name, outVar);
		}
		return data.outputs;
	}

	function getOutsideVar(name: String, original: TVar, isInput: Bool, internal: Bool) : TVar {
		var v : TVar = outsideVars.get(name);
		if (v == null) {
			v = Reflect.copy(original);
			v.id = getNewVarId();
			v.name = name;
			outsideVars.set(name, v);
		}
		if (isInput) {
			if (graphInputVars.find((o) -> o.v == v) == null) {
				graphInputVars.push({v: v, internal: internal, defVal: null, isDynamic: false});
			}
		}
		else {
			if (graphOutputVars.find((o) -> o.v == v) == null) {
				if (v == null)
					throw "null var";
				graphOutputVars.push({v: v, internal: false, isDynamic: false});
			}
		}

		return v;
	}

	function getOrCreateExtern(name: String, type: Type) : TVar {
		var tvar = externs.find((v) -> v.name == name);
		if (tvar == null) {
			tvar = {
				id: getNewVarId(),
				name: name,
				type: type,
				kind: Local
			};
			externs.push(tvar);
		}
		else if (!EnumValueTools.equals(tvar.type, type)) {
			throw 'Extern was declared with 2 different types (original : ${tvar.type}, new : ${type}';
		}
		return tvar;
	}




	public function generate() : ShaderNodeDef {
		initNodeData();

		allConnections = [for (node in graph.nodes) for (connection in node.instance.connections) connection];
		pixelColor = {name: "pixelColor", id: getNewVarId(), type: TVec(4, VFloat), kind: Local, qualifiers: []};

		if (includePreviews) {
			outputPreviewPixelColor = pixelColor;
			outputSelectVar = {name: "__sg_PREVIEW_output_select", id: getNewVarId(), type: TInt, kind: Param, qualifiers: []};
			graphInputVars.push({v: outputSelectVar, internal: true, isDynamic: false});
			inits.push({variable: outputSelectVar, value: 0});
		}

		sortedNodes = sortGraph();
		typeGraph(sortedNodes);

		var exprsReverse : Array<TExpr> = [];
		for (currentNode in sortedNodes) {
			generateNodeExpression(currentNode, exprsReverse);
		}

		graphOutputVars.push({v: pixelColor, internal: true, isDynamic: false});

		exprsReverse.reverse();

		//trace(haxe.Json.stringify(exprsReverse, "\t"));

		return {
			expr: {e: TBlock(exprsReverse), t:TVoid, p:pos},
			inVars: graphInputVars,
			outVars: graphOutputVars,
			externVars: externs,
			inits: inits,
			functions: functions,
		};
	}

	public function sortGraph() : Array<Node> {
		var nodeToExplore : Array<Node> = [];

		var nodeHasOutputs : Map<Node, Bool> = [];
		for (node in graph.nodes) {
			nodeHasOutputs.set(node, true);
		}

		for (connection in allConnections) {
			nodeHasOutputs.remove(connection.from);
		}

		for (node in nodeHasOutputs.keys()) {
			nodeToExplore.push(node);
		}

		var sortedNodes : Array<Node> = [];

		// Topological sort the nodes with Kahn's algorithm
		// https://en.wikipedia.org/wiki/Topological_sorting#Kahn's_algorithm
		{
			while (nodeToExplore.length > 0) {
				var currentNode = nodeToExplore.pop();
				sortedNodes.push(currentNode);
				for (connection in currentNode.instance.connections) {
					var targetNode = connection.from;
					if (!allConnections.remove(connection)) throw "connection not in graph";
					if (allConnections.find((n:Connection) -> n.from == targetNode) == null) {
						nodeToExplore.push(targetNode);
					}
				}
			}
		}

		return sortedNodes;
	}

	public function typeGraph(sortedNodes: Array<Node>) {
		for (node in sortedNodes) {
			for (inputName => co in node.instance.connections) {
				var targetNodeMap = nodeData[co.from.generateId].outputToInputMap;
				var arr = targetNodeMap.get(co.fromName);
				if (arr == null) {
					arr = [];
					targetNodeMap.set(co.fromName, arr);
				}
				arr.push({node: node, inputName: inputName});
			}
		}

		for (i => _ in sortedNodes) {
			var node = sortedNodes[sortedNodes.length - i - 1];

			var def = getDef(node);
			var data = nodeData[node.generateId];

			for (i => inputVar in def.inVars) {
				var from = node.instance.connections.get(inputVar.v.name);
				if (from == null) {
					var init = def.inits.find((v) -> v.variable == inputVar.v);
					if (init != null) {
						data.inputTypes[i] = init.variable.type;
					}
				}
			}

			for (outputVar in def.outVars) {
				if (outputVar.internal)
					continue;
				var inputs = data.outputToInputMap.get(outputVar.v.name);

				if (inputs == null)
					continue;

				for (input in inputs) {
					var def = getDef(input.node);

					var inputVarId = -1;
					for (i => v in def.inVars) {
						if (v.v.name == input.inputName) {
							inputVarId = i;
							break;
						}
					}
					if (inputVarId < 0)
						throw "Missing var " + input.inputName;

					nodeData[input.node.generateId].inputTypes[inputVarId] = outputVar.v.type;
				}
			}

			data.def = def;
		}
	}

	public function initNodeData() {
		var currIndex = 0;
		var previewIndex = 1;
		for (node in graph.nodes) {
			node.generateId = currIndex;
			var preview = Std.downcast(node.instance, hrt.shgraph.nodes.Preview);
			if (preview != null) {
				preview.previewID = previewIndex;
				previewIndex++;
			}

			var output = Std.downcast(node.instance, hrt.shgraph.ShaderOutput);
			if (output != null) {
				output.generatePreview = includePreviews;
			}

			nodeData[node.generateId] = {
				outputToInputMap: [],
				inputTypes: []
			};
			currIndex++;
		}
	}

	public function generateNodeExpression(currentNode: Node, exprsReverse: Array<TExpr>) {
		// Skip nodes with no outputs that arent a final node
		if ((currentNode.outputs?.length ?? 0) > 0)
		{
			if (Std.downcast(currentNode.instance, ShaderOutput) != null && (Std.downcast(currentNode.instance, hrt.shgraph.nodes.Preview) != null && !includePreviews))
				return;
		}

		var outputs = getOutputs(currentNode);

		var def = getDef(currentNode);
		var expr = def.expr;

		{

			if (def.functions != null) {
				for (func in def.functions) {
					var prev = functions.find((f) -> f.ref.name == func.ref.name);
					// Patch new functions declarations with this one
					if (prev != null) {
						func.ref = prev.ref;
					}
					else {
						functions.push(func);
					}
				}
			}

			var outputDecls : Array<TVar> = [];

			// Used to capture input for output node preview
			//var firstInputVar = null;

			var allInputsVarsBound = true;

			for (nodeVar in def.inVars) {
				var connection = currentNode.instance.connections.get(nodeVar.v.name);

				var replacement : TExpr = null;

				if (connection != null) {
					var outputs = getOutputs(connection.from);
					var outputVar = outputs[connection.fromName];
					if (outputVar == null) throw "null tvar";
					//if (firstInputVar == null) firstInputVar = outputVar;
					replacement = convertToType(nodeVar.v.type,  {e: TVar(outputVar), p:pos, t: outputVar.type});
				}
				else {
					if (nodeVar.internal) {
						if (nodeVar.v.type.isTexture()) {
							// Rewrite output var to be the sampler directly because we can't assign
							// a sampler to a temporary variable
							var outVar = outputs["output"];
							outVar.id = nodeVar.v.id;
							outVar.name = nodeVar.v.name;
							outVar.type = nodeVar.v.type;
							outVar.qualifiers = nodeVar.v.qualifiers;
							outVar.parent = nodeVar.v.parent;
							outVar.kind = nodeVar.v.kind;

							expr = null;
							if (graphInputVars.find((v) -> v.v == outVar) == null) {
								graphInputVars.push({v: outVar, internal: false, defVal: null, isDynamic: false});
								var shParam = Std.downcast(currentNode.instance, ShaderParam);
								var param = graph.getParameter(shParam.parameterId);
								inits.push({variable: outVar, value: param.defaultValue});
							}

							if (includePreviews) {
								var calulatedUV = getOrCreateExtern("calculatedUV", TVec(2, VFloat));
								var sample = makeExpr(
									TCall(makeExpr(TGlobal(Texture),TVoid), [
										makeVar(outVar),
										makeVar(calulatedUV),
									]), TVec(4, VFloat));

								var previewExpr = makeAssign(makeVar(outputPreviewPixelColor), sample);

								var expr = makeIf(makeEq(makeVar(outputSelectVar), makeInt(currentNode.id + 1)),
									previewExpr,
								);

								exprsReverse.push(expr);
							}

							return;
						}

						var inVar = getOutsideVar(nodeVar.v.name, nodeVar.v, true, false);
						if (inVar.name == "input.normal" && includePreviews) {
							inVar.name = "fakeNormal";
						}

						var shParam = Std.downcast(currentNode.instance, ShaderParam);
						if (shParam != null) {
							var param = graph.getParameter(shParam.parameterId);
							var v = graphInputVars.find((v) -> v.v == inVar);
							v.internal = param.internal ?? false;
							if (v.internal) {
								if (inVar.qualifiers == null)
									inVar.qualifiers = [];
								inVar.qualifiers.push(Ignore);
							}
							inits.push({variable: inVar, value: param.defaultValue});
						}
						replacement = {e: TVar(inVar), p: pos, t:nodeVar.v.type};
					}
					else {
						if (nodeVar.v.type.match(TSampler(_)) ) {
							allInputsVarsBound = false;
							continue;
						}
							// default parameter if no connection
						switch(nodeVar.defVal) {
							case Const(def):
								var defVal = def;
								var defaultValue = Reflect.getProperty(currentNode.instance.defaults, nodeVar.v.name);
								if (defaultValue != null) {
									defVal = Std.parseFloat(defaultValue) ?? defVal;
								}
								replacement = convertToType(nodeVar.v.type, {e: TConst(CFloat(defVal)), p: pos, t:TFloat});
							case ConstBool(def):
								var defVal = def;
								var defaultValue = Reflect.getProperty(currentNode.instance.defaults, nodeVar.v.name);
								if (defaultValue != null) {
									defVal = defaultValue == "true";
								}
								replacement = makeExpr(TConst(CBool(defVal)), TBool);
							case Var(name):
								var tvar = getOrCreateExtern(name, nodeVar.v.type);
								replacement = {e: TVar(tvar), p: pos, t:nodeVar.v.type};
							default:
								replacement = convertToType(nodeVar.v.type, {e: TConst(CFloat(0.0)), p: pos, t:TFloat});
						}
					}
				}

				expr = replaceVar(expr, nodeVar.v, replacement);
			}

			if (expr != null) {
				for (i => nodeVar in def.outVars) {
					var outputVar : TVar = outputs.get(nodeVar.v.name);
					// Kinda of a hack : skip decl writing for shaderParams
					// var shParam = Std.downcast(currentNode.instance, ShaderParam);
					// if (shParam != null) {
					// 	continue;
					// }

					if (Std.downcast(currentNode.instance, hrt.shgraph.nodes.Sampler) != null ||
						Std.downcast(currentNode.instance, hrt.shgraph.nodes.Dissolve) != null) {
						if (!allInputsVarsBound) {
							expr = makeAssign(makeVar(nodeVar.v), makeVec([0.0,0.0,0.0,0.0]));
						}
					}

					if (outputVar == null) {
						var v = getOutsideVar(nodeVar.v.name, nodeVar.v, false, false);
						var outputVar = {e: TVar(v), p:pos, t: nodeVar.v.type};

						expr = replaceVar(expr, nodeVar.v, outputVar);

						if (includePreviews) {

							if (expr == null)
								throw "break";

							//if (firstInputVar == null)
							//	throw "impossible";

							// switch (outputVar.t) {
							// 	switch ()
							// }

							var previewExpr = makeAssign(makeVar(outputPreviewPixelColor), convertToType(outputPreviewPixelColor.type, makeVar(v)));

							expr = makeExpr(TBlock(
								[
									expr,
									makeIf(makeEq(makeVar(outputSelectVar), makeInt(currentNode.id + 1)),
										previewExpr,
									)
								]),
								TVoid
							);

						}

						//graphOutputVars.push({v: nodeVar.v, internal: false});
					} else {
						expr = replaceVar(expr, nodeVar.v, {e: TVar(outputVar), p:pos, t: nodeVar.v.type});
						outputDecls.push(outputVar);
					}

					if (i == 0 && includePreviews && outputVar != null && currentNode.instance.canHavePreview()) {


						var finalExpr = makeAssign(makeVar(outputPreviewPixelColor), convertToType(outputPreviewPixelColor.type, makeVar(outputVar)));
						//var finalExpr : TExpr = {e: TBinop(OpAssign, {e:TVar(outputPreviewPixelColor), p:pos, t:outputPreviewPixelColor.type}, convertToType(outputPreviewPixelColor.type, {e: TVar(outputVar), p: pos, t: outputVar.type})), p: pos, t: outputPreviewPixelColor.type};

						var ifExpr = makeIf(
							makeEq(makeInt(currentNode.id + 1), makeVar(outputSelectVar)),
							finalExpr
						);

						expr = makeExpr(
							TBlock([expr,ifExpr]),
							TVoid,
						);
					}
				}
			}


			for (nodeVar in def.externVars) {
				var prev = externs.find((v) -> v.name == nodeVar.name);
				if (prev != null) {
					expr = replaceVar(expr, nodeVar, {e: TVar(prev), p:pos, t: prev.type});
				}
				else {
					externs.push(nodeVar);
				}
			}

			if (expr != null)
				exprsReverse.push(expr);

			for (output in outputDecls) {
				var finalExpr : TExpr = {e: TVarDecl(output), p: pos, t: output.type};
				exprsReverse.push(finalExpr);
			}
		}
	}

	var allInputsVarsBound : Bool; // tmp hack

	public function patchExprVar(expr: TExpr, nodeVar: ShaderNodeDefInVar, currentNode: Node) : TExpr {
		var connection = currentNode.instance.connections.get(nodeVar.v.name);

		var replacement : TExpr = null;

		if (connection != null) {
			var outputs = getOutputs(connection.from);
			var outputVar = outputs[connection.fromName];
			if (outputVar == null) throw "null tvar";
			//if (firstInputVar == null) firstInputVar = outputVar;
			replacement = convertToType(nodeVar.v.type,  {e: TVar(outputVar), p:pos, t: outputVar.type});
		}
		else {
			if (nodeVar.internal) {
				if (nodeVar.v.type.isTexture()) {
					// Rewrite output var to be the sampler directly because we can't assign
					// a sampler to a temporary variable
					var outVar = getOutputs(currentNode)["output"];
					outVar.id = nodeVar.v.id;
					outVar.name = nodeVar.v.name;
					outVar.type = nodeVar.v.type;
					outVar.qualifiers = nodeVar.v.qualifiers;
					outVar.parent = nodeVar.v.parent;
					outVar.kind = nodeVar.v.kind;

					if (graphInputVars.find((v) -> v.v == outVar) == null) {
						graphInputVars.push({v: outVar, internal: false, defVal: null, isDynamic: false});
						var shParam = Std.downcast(currentNode.instance, ShaderParam);
						var param = graph.getParameter(shParam.parameterId);
						inits.push({variable: outVar, value: param.defaultValue});
					}

					if (!includePreviews)
						return null;

					var calulatedUV = getOrCreateExtern("calculatedUV", TVec(2, VFloat));
					var sample = makeExpr(
						TCall(makeExpr(TGlobal(Texture),TVoid), [
							makeVar(outVar),
							makeVar(calulatedUV),
						]), TVec(4, VFloat));

					var previewExpr = makeAssign(makeVar(outputPreviewPixelColor), sample);

					var expr = makeIf(makeEq(makeVar(outputSelectVar), makeInt(currentNode.id + 1)),
						previewExpr,
					);

					return expr;

				}

				var inVar = getOutsideVar(nodeVar.v.name, nodeVar.v, true, false);
				if (inVar.name == "input.normal" && includePreviews) {
					inVar.name = "fakeNormal";
				}

				var shParam = Std.downcast(currentNode.instance, ShaderParam);
				if (shParam != null) {
					var param = graph.getParameter(shParam.parameterId);
					var v = graphInputVars.find((v) -> v.v == inVar);
					v.internal = param.internal ?? false;
					if (v.internal) {
						if (inVar.qualifiers == null)
							inVar.qualifiers = [];
						inVar.qualifiers.push(Ignore);
					}
					inits.push({variable: inVar, value: param.defaultValue});
				}
				replacement = {e: TVar(inVar), p: pos, t:nodeVar.v.type};
			}
			else {
				if (nodeVar.v.type.match(TSampler(_)) ) {
					allInputsVarsBound = false;
					return null;
				}
				replacement = getDefaultValue(nodeVar, currentNode);
			}
		}

		return replaceVar(expr, nodeVar.v, replacement);
	}

	function getDefaultValue(nodeVar: ShaderNodeDefInVar, currentNode: Node) : TExpr {
		switch(nodeVar.defVal) {
			case Const(def):
				var defVal = def;
				var defaultValue = Reflect.getProperty(currentNode.instance.defaults, nodeVar.v.name);
				if (defaultValue != null) {
					defVal = Std.parseFloat(defaultValue) ?? defVal;
				}
				return convertToType(nodeVar.v.type, {e: TConst(CFloat(defVal)), p: pos, t:TFloat});
			case ConstBool(def):
				var defVal = def;
				var defaultValue = Reflect.getProperty(currentNode.instance.defaults, nodeVar.v.name);
				if (defaultValue != null) {
					defVal = defaultValue == "true";
				}
				return makeExpr(TConst(CBool(defVal)), TBool);
			case Var(name):
				var tvar = getOrCreateExtern(name, nodeVar.v.type);
				return {e: TVar(tvar), p: pos, t:nodeVar.v.type};
			default:
				return convertToType(nodeVar.v.type, {e: TConst(CFloat(0.0)), p: pos, t:TFloat});
		}
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

	public function compile3() {
		var ctx = new ShaderGraphGenContext2(graphs[1], false);
		ctx.generate();
	}


	public function compile2(?previewDomain: Domain) : hrt.prefab.Cache.ShaderDef {
		#if !editor
		if (cachedDef != null)
			return cachedDef;
		#end


		var start = haxe.Timer.stamp();

		var gens : Array<ShaderNodeDef> = [];
		var inits : Array<{variable: TVar, value: Dynamic}>= [];

		var shaderData : ShaderData = {
			name: "",
			vars: [],
			funs: [],
		};

		for (i => graph in graphs) {
			if (previewDomain != null && graph.domain != previewDomain)
				continue;
			// Temp fix for code generation
			//if (graph.domain == Vertex)
			//	continue;

			var ctx = new ShaderGraphGenContext(graph, previewDomain != null);
			var gen = ctx.generate();

			gens.push(gen);

			//shaderData.vars.append(gen.externVars);

			var inputInputVars : Array<TVar> = [];
			var globalInputVars : Array<TVar> = [];

			#if editor
			var names : Map<String, Parameter> = [];
			for (p in parametersAvailable) {
				names.set(p.name, p);
			}

			gen.inVars.sort((a,b) -> {
				// if the name is not a parameter, sort it at the start of the list
				var aIndex = names.get(a.v.name)?.index ?? -1;
				var bIndex = names.get(b.v.name)?.index ?? -1;
				return Reflect.compare(aIndex, bIndex);
			});
			#end

			for (arr in [[for (v in gen.inVars) v.v], gen.externVars]) {
				for (v in arr) {
					var split = v.name.split(".");
					switch(split[0]) {
						case "input": {
							v.name = split[1] ?? throw "Invalid variable name";
							if (inputInputVars.find((a) -> a.id == v.id) == null)
								inputInputVars.push(v);
						}
						case "global": {
							v.name = split[1] ?? throw "Invalid variable name";
							if (globalInputVars.find((a) -> a.id == v.id) == null)
								globalInputVars.push(v);
						}
						default: {
							if (split.length > 1)
								throw "Var has a dot in its name without being input or global var";
							if (shaderData.vars.find((a) -> a.id == v.id) == null)
								shaderData.vars.push(v);
						}
					}
				}
			}



			var cuv = shaderData.vars.find((v) -> v.name == "calculatedUV");
			if (cuv != null) {
				var inputUv : TVar = inputInputVars.find(v -> v.name == "uv");
				if (inputUv == null) {
					inputUv = { parent: null, id: hxsl.Tools.allocVarId(), kind: Input, name: "uv", type: TVec(2, VFloat) };
					inputInputVars.push(inputUv);
				}

				var pos : Position = {file: "", min: 0, max: 0};
				var finalExpr : TExpr = {e: TBinop(OpAssign, {e:TVar(cuv), p:pos, t:cuv.type}, {e: TVar(inputUv), p: pos, t: inputUv.type}), p: pos, t: inputUv.type};

				var block: TExpr = {e: TBlock([finalExpr]), p:pos, t:null};
				var funcVar : TVar = {
					name : "__init__",
					id : hxsl.Tools.allocVarId(),
					kind : Function,
					type : TFun([{ ret : TVoid, args : [] }])
				};

				var fn : TFunction = {
					ret : TVoid, kind : Init,
					ref : funcVar,
					expr : block,
					args : []
				};

				shaderData.funs.push(fn);
				shaderData.vars.push(funcVar);
			}

			function makeVarStruct(elems: Array<TVar>, name: String, kind: VarKind) {
				if (elems.length > 0) {
					var v : TVar = {
						id: hxsl.Tools.allocVarId(),
						type: TStruct(elems),
						kind: kind,
						name: name,
					};

					for (iv in elems) {
						iv.parent = v;
					}

					shaderData.vars.push(v);
				}
			}

			makeVarStruct(inputInputVars, "input", Input);
			makeVarStruct(globalInputVars, "global", Global);

			// if (inputInputVars.length > 0) {
			// 	var v : TVar = {
			// 		id: hxsl.Tools.allocVarId(),
			// 		type: TStruct(inputInputVars),
			// 		kind: Input,
			// 		name: "input",
			// 	};

			// 	for (iv in inputInputVars) {
			// 		iv.parent = v;
			// 	}

			// 	shaderData.vars.pushUnique(v);
			// }

			for (v in gen.outVars) {
				if (shaderData.vars.find((a) -> a.id == v.v.id) == null) {
					shaderData.vars.push(v.v);
				}
			}

			var fnKind : FunctionKind = switch(graph.domain) {
				case Fragment: Fragment;
				case Vertex: Vertex;
			};

			if (previewDomain != null)
				fnKind = Fragment;

			var functionName : String = EnumValueTools.getName(fnKind).toLowerCase();

			var funcVar : TVar = {
				name : functionName,
				id : hxsl.Tools.allocVarId(),
				kind : Function,
				type : TFun([{ ret : TVoid, args : [] }])
			};

			var finalExpr = gen.expr;

			// Patch Color
			if (fnKind == Fragment) {
				var includePreviews = previewDomain != null;
				var finalBlock = [finalExpr];

				var pos : Position = {file: "", min: 0, max: 0};
				var pixelColor = gen.outVars.find((v) -> v.v.name == "pixelColor")?.v;
				var outputPreviewPixelColor = pixelColor;
				var outputSelectVar = gen.inVars.find((v) -> v.v.name == "__sg_PREVIEW_output_select")?.v;


				var color = gen.outVars.find((v) -> v.v.name == "_sg_out_color");
				if (color != null) {
					var vec3 = TVec(3, VFloat);

					var finalExpr = makeAssign(makeExpr(TSwiz(makeVar(pixelColor), [X,Y,Z]), TVec(3, VFloat)), makeVar(color.v));

					if (includePreviews) {
						if (outputSelectVar == null)
							throw "WTF";

						finalExpr = makeIf(makeEq(makeVar(outputSelectVar), makeInt(0)), finalExpr);
					}


					finalBlock.push(finalExpr);
				}

				var alpha = gen.outVars.find((v) -> v.v.name == "_sg_out_alpha");
				if (alpha != null) {
					var flt = TFloat;

					var finalExpr = makeAssign(makeExpr(TSwiz(makeVar(pixelColor), [W]), TFloat), makeVar(alpha.v));

					if (includePreviews) {
						finalExpr = makeIf(makeEq(makeVar(outputSelectVar), makeInt(0)), finalExpr);
					}

					finalBlock.push(finalExpr);
				}

				finalExpr = {e: TBlock(finalBlock), t: TVoid, p: pos};
			}


			var fn : TFunction = {
				ret : TVoid, kind : fnKind,
				ref : funcVar,
				expr : finalExpr,
				args : []
			};
			shaderData.funs.push(fn);
			shaderData.vars.push(funcVar);

			for (func in gen.functions) {
				shaderData.funs.push(func);
				shaderData.vars.push(func.ref);
			}

			for (init in gen.inits) {
				inits.push(init);
			}
		}

		var shared = new SharedShader("");
		@:privateAccess shared.data = shaderData;
		@:privateAccess shared.initialize();

		var time = haxe.Timer.stamp() - start;
		//trace("Shader compile2 in " + time * 1000 + " ms");

		cachedDef = {shader : shared, inits: inits};

		return cachedDef;
	}

	public function makeShaderInstance() : hxsl.DynamicShader {
		var def = compile2(null);
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
						p.type = TSampler(T2D, false);
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
				shaderParam.computeOutputs();
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

		var inputs = node.instance.getInputs2(domain);
		var outputs = output.instance.getOutputs2(domain);

		var inputName = edge.nameInput;
		var outputName = edge.nameOutput;

		// Patch I/O if name have changed
		if (!outputs.exists(outputName)) {
			outputName = null;
			for (k => v in outputs) {
				if (v.index == edge.outputId)
					outputName = k;
			}
			if (outputName == null)
				return false;
		}

		if (!inputs.exists(inputName)) {
			inputName = null;
			for (k => v in inputs) {
				if (v.index == edge.inputId)
					inputName = k;
			}
			if (inputName == null)
				return false;
		}

		var connection : Connection = {from: output, fromName: outputName};
		node.instance.connections.set(inputName, connection);

		#if editor
		if (hasCycle()){
			removeEdge(edge.inputNodeId, inputName, false);
			return false;
		}

		var inputType = inputs[inputName].v.type;
		var outputType = outputs[outputName].v.type;

		if (!areTypesCompatible(inputType, outputType)) {
			removeEdge(edge.inputNodeId, inputName);
		}
		try {
		} catch (e : Dynamic) {
			removeEdge(edge.inputNodeId, inputName);
			throw e;
		}
		#end
		return true;
	}

	public function areTypesCompatible(input: hxsl.Ast.Type, output: hxsl.Ast.Type) : Bool {
		return switch (input) {
			case TFloat, TVec(_, VFloat), null:
				switch (output) {
					case TFloat, TVec(_, VFloat), null: true;
					default: false;
				}
			default: haxe.EnumTools.EnumValueTools.equals(input, output);
		}
	}

	public function removeEdge(idNode, nameInput, update = true) {
		var node = this.nodes.get(idNode);
		this.nodes.get(node.instance.connections[nameInput].from.id).outputs.remove(node);

		node.instance.connections.remove(nameInput);
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

			for (connection in node.instance.connections) {
				var nodeInput = connection.from;
				nodeInput.indegree -= 1;
				if (nodeInput.indegree == 0) {
					queue.push(nodeInput);
				}
			}
			counter++;
		}

		return counter != nbNodes;
	}

	public function removeNode(idNode : Int) {
		this.nodes.remove(idNode);
	}

	public function saveToDynamic() : Dynamic {
		var edgesJson : Array<Edge> = [];
		for (n in nodes) {
			for (inputName => connection in n.instance.connections) {
				var def = n.instance.getShaderDef(domain, () -> 0);
				var inputId = null;
				for (i => inVar in def.inVars) {
					if (inVar.v.name == inputName) {
						inputId = i;
						break;
					}
				}

				var def = connection.from.instance.getShaderDef(domain, () -> 0);
				var outputId = null;
				for (i => outVar in def.outVars) {
					if (outVar.v.name == connection.fromName) {
						outputId = i;
						break;
					}
				}

				edgesJson.push({ outputNodeId: connection.from.id, nameOutput: connection.fromName, inputNodeId: n.id, nameInput: inputName, inputId: inputId, outputId: outputId });
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