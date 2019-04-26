package hrt.prefab;

class ShaderGraph extends Shader {

	public function new(?parent) {
		super(parent);
		type = "shadergraph";
	}

	override function fixSourcePath() {
		#if editor
		var ide = hide.Ide.inst;
		var shadersPath = ide.projectDir + "/res";

		var path = source.split("\\").join("/");
		if( StringTools.startsWith(path.toLowerCase(), shadersPath.toLowerCase()+"/") ) {
			path = path.substr(shadersPath.length + 1);
		}
		source = shadersPath + "/" + path;
		#end
	}

	override public function loadShaderDef(ctx: Context) {
		if(shaderDef == null) {
			fixSourcePath();
			var shaderGraph = new hrt.shgraph.ShaderGraph(source);
			shaderDef = shaderGraph.compile();
		}
		if(shaderDef == null)
			return;

		#if editor
		for( v in shaderDef.inits ) {
			if(!Reflect.hasField(props, v.variable.name)) {
				Reflect.setField(props, v.variable.name, v.value);
			}
		}
		#end
	}

	#if editor
	override function getHideProps() : HideProps {
		return { icon : "cog", name : "Shader Graph", fileSource : ["hlshader"], allowParent : function(p) return p.to(Object3D) != null };
	}
	#end

	static var _ = Library.register("hlshader", ShaderGraph);
}