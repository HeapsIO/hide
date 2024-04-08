package hrt.shgraph.nodes;

using hxsl.Ast;

@name("SubGraph")
@description("Include a subgraph")
@width(200)
@alwaysshowinputs()
@:access(hrt.shgraph.NodeGenContext)
@:access(hrt.shgraph.NodeGenContextSubGraph)
class SubGraph extends ShaderNode {

	@prop() public var pathShaderGraph : String;

	override function new(path: String) {
		pathShaderGraph = path;
	}

	override public function generate(ctx: NodeGenContext) {
		#if !editor
		var shader = cast hxd.res.Loader.currentInstance.load(pathShaderGraph).toPrefab().load();
		#else
		var shader = cast hide.Ide.inst.loadPrefab(pathShaderGraph);
		#end
		var graph = shader.getGraph(ctx.domain);

		var genCtx = new ShaderGraphGenContext(graph, false);
		genCtx.generate(new NodeGenContext.NodeGenContextSubGraph(ctx));
	}

	override public function getInputs() : Array<ShaderNode.InputInfo> {
		#if !editor
		var shader = cast hxd.res.Loader.currentInstance.load(pathShaderGraph).toPrefab().load();
		#else
		var shader = cast hide.Ide.inst.loadPrefab(pathShaderGraph);
		#end
		var graph = shader.getGraph(hrt.shgraph.Domain.Fragment);

		var genCtx = new ShaderGraphGenContext(graph, false);
		var nodeGenCtx = new NodeGenContext.NodeGenContextSubGraph(null);
		genCtx.generate(nodeGenCtx);
		var inputs: Array<ShaderNode.InputInfo> = [];

		for (name => info in nodeGenCtx.globalInVars) {
			var global = nodeGenCtx.globalVars.get(name);
			var t = typeToSgType(global.v.type);
			inputs[info.id] = {name: name, type: hrt.shgraph.ShaderGraph.typeToSgType(info.type)};
		}

		return inputs;
	}

	override public function getOutputs() : Array<ShaderNode.InputInfo> {
		#if !editor
		var shader = cast hxd.res.Loader.currentInstance.load(pathShaderGraph).toPrefab().load();
		#else
		var shader = cast hide.Ide.inst.loadPrefab(pathShaderGraph);
		#end
		var graph = shader.getGraph(hrt.shgraph.Domain.Fragment);

		var genCtx = new ShaderGraphGenContext(graph, false);
		var nodeGenCtx = new NodeGenContext.NodeGenContextSubGraph(null);
		genCtx.generate(nodeGenCtx);
		var outputs: Array<ShaderNode.InputInfo> = [];

		for (name => info in nodeGenCtx.globalOutVars) {
			outputs[info.id] = {name: name, type: hrt.shgraph.ShaderGraph.typeToSgType(info.type)};
		}

		return outputs;
	}

}