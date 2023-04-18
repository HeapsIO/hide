package hrt.prefab2;

class ShaderGraph extends DynamicShader {

	public function new(?parent, shared: ContextShared) {
		super(parent, shared);
	}

	override public function loadShaderDef() {
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
	override function getHideProps() : hide.prefab2.HideProps {
		return { icon : "scribd", name : "Shader Graph", fileSource : ["shgraph"], allowParent : function(p) return p.to(Object2D) != null || p.to(Object3D) != null };
	}

	override function edit( ctx : hide.prefab2.EditContext ) {
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

	static var _ = hrt.prefab2.Prefab.register("shgraph", ShaderGraph);
}