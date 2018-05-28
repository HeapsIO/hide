package hide.prefab;

class Shader extends Prefab {

	var shaderDef : Context.ShaderDef;

	public function new(?parent) {
		super(parent);
		props = {};
	}
	
	override function load(o:Dynamic) {

	}

	override function save() {
		return {
		};
	}

	override function makeInstance(ctx:Context):Context {
		if(source == null)
			return ctx;
		if(ctx.local3d == null)
			return ctx;
		ctx = ctx.clone(this);
		if(shaderDef == null)
			shaderDef = ctx.loadShader("shaders/TestShader");
		if(shaderDef == null)
			return ctx;
		var shader = new hxsl.DynamicShader(shaderDef.shader);
		for( v in shaderDef.inits )
			shader.hscriptSet(v.v.name, hxsl.Ast.Tools.evalConst(v.e));
		ctx.custom = shader;
		if(shader != null) {
			for(m in ctx.local3d.getMaterials()) {
				m.mainPass.addShader(shader);
			}
		}
		return ctx;
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		var shader = shctx.shader;
		for(v in shaderDef.shader.data.vars) {
			// TODO
		}
	}

	override function getHideProps() {
		return { icon : "cog", name : "Shader", fileSource : ["hx"] };
	}

	static var _ = Library.register("shader", Shader);
}