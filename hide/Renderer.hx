package hide;

// ----- Default Rendering --------------------------------

class MaterialSetup extends h3d.mat.MaterialSetup {
    override public function createRenderer() {
	    return new Renderer();
	}
}

class Renderer extends h3d.scene.DefaultRenderer {

	override function render() {

		renderPass(defaultPass, getSort("debuggeom", true) );
		clear(null, 1.0);

		if( has("shadow") )
			renderPass(shadow,get("shadow"));

		if( has("depth") )
			renderPass(depth,get("depth"));

		if( has("normal") )
			renderPass(normal,get("normal"));

		renderPass(defaultPass, getSort("default", true) );
        renderPass(defaultPass, get("outline"));
		renderPass(defaultPass, get("outlined"));
		renderPass(defaultPass, getSort("debuggeom_alpha"));
		renderPass(defaultPass, getSort("alpha") );
		renderPass(defaultPass, get("additive") );
		renderPass(defaultPass, getSort("ui", true));
	}
}

// ----- PBR Rendering --------------------------------

class PbrSetup extends h3d.mat.PbrMaterialSetup {

	function getEnvMap() {
		var ide = hide.Ide.inst;
		var scene = hide.comp.Scene.getCurrent();
		var path = ide.getPath(scene.props.get("scene.environment"));
		var data = sys.io.File.getBytes(path);
		var pix = hxd.res.Any.fromBytes(path, data).toImage().getPixels();
		var t = h3d.mat.Texture.fromPixels(pix); // sync
		t.name = ide.makeRelative(path);
		return t;
	}

    override function createRenderer() {
		var env = new h3d.scene.pbr.Environment(getEnvMap());
		env.compute();
		return new PbrRenderer(env);
	}
}

class PbrRenderer extends h3d.scene.pbr.Renderer {

	override function mainDraw() {
		output.draw(getSort("default", true));
		output.draw(get("outlined"));
		output.draw(getSort("alpha"));
		output.draw(get("additive"));
	}

	override function postDraw() {
		draw("debuggeom");
		draw("debuggeom_alpha");
		draw("outline");
		draw("overlay");
	}
}

