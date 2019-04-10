package hrt.shgraph;

using hxsl.Ast;

private typedef Node = {
	x : Float,
	y : Float,
	comment : String,
	id : Int,
	type : String,
	?parameters : Dynamic,
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

class ShaderGraph {

	var current_node_id = 0;
	var filepath : String;
	var nodes : Map<Int, Node> = [];
	var allVariables : Array<TVar> = [];

	public function new(filepath : String) {
		if (filepath == null) return;
		this.filepath = filepath;

		var json;
		try {
			json = haxe.Json.parse(sys.io.File.getContent(this.filepath));
		} catch( e : Dynamic ) {
			throw "Invalid shader graph parsing ("+e+")";
		}

		generate(Reflect.getProperty(json, "nodes"), Reflect.getProperty(json, "edges"));

	}

	public function generate(nodes : Array<Node>, edges : Array<Edge>) {

		for (n in nodes) {
			n.outputs = [];
			n.instance = std.Type.createInstance(std.Type.resolveClass(n.type), []);
			n.instance.loadProperties(n.parameters);
			n.instance.setId(n.id);
			this.nodes.set(n.id, n);
		}
		if (nodes[nodes.length-1] != null)
			this.current_node_id = nodes[nodes.length-1].id+1;

		for (e in edges) {
			addEdge(e);
		}
	}

	public function addNode(x : Float, y : Float, nameClass : Class<ShaderNode>) {
		var node : Node = { x : x, y : y, comment: "", id : current_node_id, type: std.Type.getClassName(nameClass) };

		node.instance = std.Type.createInstance(nameClass, []);
		node.instance.setId(current_node_id);
		node.instance.computeOutputs();
		node.outputs = [];

		this.nodes.set(node.id, node);
		current_node_id++;

		return node.instance;
	}

	public function removeNode(idNode : Int) {
		this.nodes.remove(idNode);
	}

	public function addEdge(edge : Edge) {
		var node = this.nodes.get(edge.idInput);
		var output = this.nodes.get(edge.idOutput);
		node.instance.setInput(edge.nameInput, new NodeVar(output.instance, edge.nameOutput));
		output.outputs.push(node);
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

	function buildNodeVar(nodeVar : NodeVar) : Array<TExpr>{
		var node = nodeVar.node;
		if (node == null)
			return [];
		var res = [];
		var keys = node.getInputInfoKeys();
		for (key in keys) {
			var input = node.getInput(key);
			if (input != null) {
				res = res.concat(buildNodeVar(input));
			} else if (node.getInputInfo(key).hasProperty) {
			} else {
				throw ShaderException.t("This box has inputs not connected", node.id);
			}
		}
		var build = nodeVar.getExpr();
		res = res.concat(build);
		return res;
	}

	static function alreadyAddVariable(array : Array<TVar>, variable : TVar) {
		for (v in array) {
			if (v.name == variable.name && v.type == variable.type) {
				return true;
			}
		}
		return false;
	}

	public function buildFragment() : ShaderData {

		allVariables = [];
		var content = [];

		for (n in nodes) {
			n.instance.outputCompiled = [];
		}

		for (n in nodes) {
			if (Std.is(n.instance, ShaderInput)) {
				var variable = Std.instance(n.instance, ShaderInput).variable;
				if ((variable.kind == Param || variable.kind == Global || variable.kind == Input) && !alreadyAddVariable(allVariables, variable)) {
					allVariables.push(variable);
				}
			}
			if (Std.is(n.instance, ShaderOutput)) {
				var variable = Std.instance(n.instance, ShaderOutput).variable;
				if ( !alreadyAddVariable(allVariables, variable) ) {
					allVariables.push(variable);
				}
				var nodeVar = new NodeVar(n.instance, "input");
				content = content.concat(buildNodeVar(nodeVar));
			}
		}

		return {
			funs : [{
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
						e : TBlock(content)
					},
					args : []
				}],
			name: "MON_FRAGMENT",
			vars: allVariables
		};
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
				for (n in nodes) { x : n.x, y : n.y, comment: n.comment, id: n.id, type: n.type, parameters : n.instance.savePropertiesNode() }
			],
			edges: edgesJson
		});

		return json;
	}
}