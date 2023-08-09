package hrt.shgraph;

@:autoBuild(hrt.shgraph.Macros.buildNode())
class ShaderNodeHxsl extends ShaderNode {

	static var nodeCache : Map<String, ShaderGraph.ShaderNodeDef> = [];

	override public function getShaderDef() : ShaderGraph.ShaderNodeDef {
		var cl = Type.getClass(this);
		var className = Type.getClassName(cl);
		var def = nodeCache.get(className);
		if (def == null) {

			var unser = new hxsl.Serializer();
			var toUnser = (cl:Dynamic).SRC;
			if (toUnser == null) throw "Node " + className + " has no SRC";
			var data = @:privateAccess unser.unserialize(toUnser);
			var expr = data.funs[0].expr;
			var inVars = [];
			var outVars = [];
			var externVars = [];

			for (tvar in data.vars) {
				if (tvar.qualifiers != null) {
					var input = false;
					var output = false;
					if (tvar.qualifiers.contains(SgInput)) {
						inVars.push(tvar);
						// TODO : handle default values
						input = true;
					}
					if (tvar.qualifiers.contains(SgOutput)) {
						outVars.push(tvar);
						output = true;
					}
					if (input && output) {
						throw "Variable is both sginput and sgoutput";
					}
					externVars.push(tvar);
				}
			}

			def = {expr: expr, inVars: inVars, outVars: outVars, externVars: externVars, inits: []};
			nodeCache.set(className, def);
		}

		return def;
	}
}