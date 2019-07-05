package hrt.prefab;

class ShaderGraph extends Shader {

	public function new(?parent) {
		super(parent);
		type = "shadergraph";
	}

	override public function loadShaderDef(ctx: Context) {
		if(shaderDef == null) {
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
		return { icon : "cog", name : "Shader Graph", fileSource : ["hlshader"], allowParent : function(p) return p.to(Object2D) != null || p.to(Object3D) != null };
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		var btn = new hide.Element("<input type='submit' style='width: 100%; margin-top: 10px;' value='Open Shader Graph' />");
		btn.on("click", function() {
 			ctx.ide.openFile(source);
		});

		ctx.properties.add(btn,this.props, function(pname) {
			ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Library.register("hlshader", ShaderGraph);
}