package hide;

// ----- Default Rendering --------------------------------
class MaterialSetup extends h3d.mat.MaterialSetup {
    override public function createRenderer() {
	    return new Renderer();
	}

	override function getDefaults( ?type : String ) : Any {
		if(type == "ui") return {
			kind : "Alpha",
			shadows : false,
			culled : false,
			lighted : false
		};
		return super.getDefaults(type);
	}
}

class Renderer extends h3d.scene.fwd.Renderer {

	public function new() {
		super();
	}

	override function render() {
		var output = allocTarget("output");
		setTarget(output);
		clear(h3d.Engine.getCurrent().backgroundColor, 1, 0);

		if( has("shadow") )
			renderPass(shadow,get("shadow"));

		if( has("depth") )
			renderPass(depth,get("depth"));

		if( has("normal") )
			renderPass(normal,get("normal"));

		renderPass(defaultPass, get("default"), frontToBack);
		renderPass(defaultPass, get("alpha"), backToFront);
		renderPass(defaultPass, get("additive") );
		#if editor_hl
		if(showEditorGuides) {
			renderPass(defaultPass, get("debuggeom"), backToFront);
			renderPass(defaultPass, get("debuggeom_alpha"), backToFront);
		}
		#end
		renderPass(defaultPass, get("overlay"), backToFront );
		renderPass(defaultPass, get("ui"), backToFront);
		resetTarget();
	}
}

// ----- PBR Rendering --------------------------------

#if editor
class PbrSetup extends h3d.mat.PbrMaterialSetup {

	function getEnvMap() {
		var ide = hide.Ide.inst;
		var scene = hide.comp.Scene.getCurrent();
		var path : String = "";
		if (scene != null) {
			path = ide.getPath(scene.config.get("scene.environment"));
		}
		else {
			var scene2 = hide.comp.Scene.getCurrent();
			path = ide.getPath(scene2.config.get("scene.environment"));
		}
		var data = sys.io.File.getBytes(path);
		var pix = hxd.res.Any.fromBytes(path, data).toImage().getPixels();
		var t = h3d.mat.Texture.fromPixels(pix, h3d.mat.Texture.nativeFormat); // sync
		t.setName(ide.makeRelative(path));
		return t;
	}

    override function createRenderer() {
		var env = new h3d.scene.pbr.Environment(getEnvMap());
		env.compute();
		return new PbrRenderer(env);
	}

	override function getDefaults( ?type : String ) : Any {
		if(type == "ui") return {
			mode : "Overlay",
			blend : "Alpha",
			shadows : false,
			culled : false,
			lighted : false
		};
		return super.getDefaults(type);
	}
}
#end

class ScreenOutline extends h3d.shader.ScreenShader {
	static var SRC = {
		@param var texture: Sampler2D;
		@param var outlineColor: Vec3 = vec3(1, 1, 1);

		function fragment() {
			var outval = texture.get(calculatedUV).rgb;
			pixelColor.a = outval.r > 0.1 && outval.r < 0.5 ? 1.0 : 0.0;
			pixelColor.rgb = outlineColor;
		}
	};
}

class PbrRenderer extends h3d.scene.pbr.Renderer {
	public function new(env) {
		super(env);
		#if editor
		outline.pass.setBlendMode(Alpha);
		#end
	}

	override function getPassByName(name:String):h3d.pass.Output {
		switch( name ) {
		case "highlight", "highlightBack":
			return defaultPass;
		}
		return super.getPassByName(name);
	}

	override function getDefaultProps( ?kind : String ) : Any {
		var props : h3d.scene.pbr.Renderer.RenderProps = super.getDefaultProps(kind);
		props.sky = Background;
		return props;
	}

	override function end() {
		switch( currentStep ) {
		case Overlay:
			renderPass(defaultPass, get("ui"), backToFront);
		default:
		}
		super.end();
	}

}
