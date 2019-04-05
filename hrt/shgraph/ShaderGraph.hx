package hrt.shgraph;

using hxsl.Ast;

private typedef Node = {
	x : Float,
	y : Float,
	comment : String,
	id : Int,
	type : String,
	?parameters : Dynamic,
	?instance : ShaderNode
};

private typedef Edge = {
	idOutput : Int,
	nameOutput : String,
	idInput : Int,
	nameInput : String
};

class ShaderGraph {

	var id = 0;
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
			n.instance = std.Type.createInstance(std.Type.resolveClass(n.type), []);
			n.instance.loadProperties(n.parameters);
			n.instance.setId(n.id);
			this.nodes.set(n.id, n);
		}
		if (nodes[nodes.length-1] != null)
			this.id = nodes[nodes.length-1].id+1;

		for (e in edges) {
			addEdge(e);
		}
	}

	public function addNode(x : Float, y : Float, nameClass : Class<ShaderNode>) {
		var node : Node = { x : x, y : y, comment: "", id : id, type: std.Type.getClassName(nameClass) };
		id++;

		node.instance = std.Type.createInstance(nameClass, []);
		node.instance.createOutputs();

		this.nodes.set(node.id, node);

		return node.instance;
	}

	public function removeNode(idNode : Int) {
		this.nodes.remove(idNode);
	}

	public function addEdge(edge : Edge) {
		this.nodes.get(edge.idInput).instance.setInput(edge.nameInput, new NodeVar(this.nodes.get(edge.idOutput).instance, edge.nameOutput));
		this.nodes.get(edge.idInput).instance.createOutputs();
	}

	public function removeEdge(idNode, nameInput) {
		this.nodes.get(idNode).instance.setInput(nameInput, null);
	}

	public function setPosition(idNode : Int, x : Float, y : Float) {
		var node = this.nodes.get(idNode);
		node.x = x;
		node.y = y;
	}

	public function getNodes() {
		return this.nodes;
	}

	function buildNodeVar(nodeVar : NodeVar) : Array<TExpr>{
		var node = nodeVar.node;
		if (node == null)
			return [];
		var res = [];
		var inputs = node.getInputs();
		for (k in inputs) {
			res = res.concat(buildNodeVar(k));
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
				for (n in nodes) { x : n.x, y : n.y, comment: n.comment, id: n.id, type: n.type, parameters : n.instance.saveProperties() }
			],
			edges: edgesJson
		});

		sys.io.File.saveContent(this.filepath, json);
	}
}