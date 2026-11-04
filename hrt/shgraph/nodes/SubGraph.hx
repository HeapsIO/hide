package hrt.shgraph.nodes;

using hxsl.Ast;
import hrt.shgraph.ShaderGraph.SgType;

@name("SubGraph")
@description("Include a subgraph")
@width(160)
@icon("icon/file/shader_graph.svg")
@alwaysshowinputs()
@:access(hrt.shgraph.NodeGenContext)
@:access(hrt.shgraph.NodeGenContextSubGraph)
class SubGraph extends ShaderNode {

	@prop() public var pathShaderGraph : String;

	// Paths of the subgraphs being generated, to detect subgraphs including themselves
	static var generating : Array<String> = [];

	override function new(path: String) {
		pathShaderGraph = path;
	}

	override public function generate(ctx: NodeGenContext) {
		if (generating.contains(pathShaderGraph))
			throw 'Subgraph $pathShaderGraph includes itself';

		var graph = loadSubGraph().getGraph(ctx.domain);

		// Generic outputs without generic inputs
		ctx.genericTypes[0] ??= TFloat;

		generating.push(pathShaderGraph);
		try {
			var genCtx = new ShaderGraphGenContext(graph, false);
			genCtx.generate(new NodeGenContext.NodeGenContextSubGraph(graph, ctx));
		} catch (e) {
			generating.pop();
			throw e;
		}
		generating.pop();

		// Outputs not written by the subgraph default to zero
		for (id => output in ctx.nodeOutputInfo) {
			if (ctx.outputs[id] != null)
				continue;
			var zero = switch (ctx.getType(output.type)) {
				case TBool: AstTools.makeExpr(TConst(CBool(false)), TBool);
				case TInt: AstTools.makeInt(0);
				case t: NodeGenContext.convertToType(t, AstTools.makeFloat(0.0));
			}
			ctx.setOutput(id, zero);
		}
	}

	override public function getInputs() : Array<ShaderNode.InputInfo> {
		var inputs: Array<ShaderNode.InputInfo> = [];

		for (p in loadSubGraph().getSortedParameters()) {
			var def : hrt.shgraph.SgHxslVar.ShaderDefInput = NoDefault;
			var inlineEditable = false;
			if (p.defaultValue != null) {
				switch (p.type) {
					case TFloat:
						def = Const(p.defaultValue);
						inlineEditable = true;
					case TVec(_, VFloat):
						def = ConstVec(p.defaultValue);
						inlineEditable = false; // no editor for vectors atm
					default:
				}
			}

			var type = p.generic ? SgGeneric(0, ShaderGraph.ConstraintFloat) : ShaderGraph.typeToSgType(p.type);
			inputs.push({name: p.name, type: type, def: def, inlineEditable: inlineEditable});
		}

		return inputs;
	}

	override public function getOutputs() : Array<ShaderNode.OutputInfo> {
		return [for (o in loadSubGraph().getSortedOutputs()) {name: o.name, type: o.type}];
	}

	#if editor
	override public function getInfo() {
		var info = super.getInfo();
		var nodeName = pathShaderGraph.split("/").pop().split(".")[0];
		nodeName = StringTools.replace(nodeName, "_", " ");
		nodeName = hide.kit.Macros.camelToSpaceCase(nodeName);
		info.name = nodeName;

		info.contextMenu = () -> [
			{label: "Open Subgraph", click: () -> hide.Ide.inst.openFile(pathShaderGraph)},
		];
		info.doubleClick = () -> hide.Ide.inst.openFile(pathShaderGraph);
		return info;
	}

	#end
	function loadSubGraph() : hrt.shgraph.ShaderSubGraph {
		#if !editor
		var prefab = hxd.res.Loader.currentInstance.load(pathShaderGraph).toPrefab().load();
		#else
		var prefab = hide.Ide.inst.loadPrefab(pathShaderGraph);
		#end
		var subGraph = Std.downcast(prefab, hrt.shgraph.ShaderSubGraph);
		if (subGraph == null)
			throw '$pathShaderGraph is not a subgraph';
		return subGraph;
	}

}
