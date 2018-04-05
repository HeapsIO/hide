package hide;

class MaterialSetup extends h3d.mat.MaterialSetup {
    override public function createRenderer() {
	    return new Renderer();
	}
}

class Renderer extends h3d.scene.DefaultRenderer {

	override function render() {
		renderPass(defaultPass, getSort("ground", true) );
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
		renderPass(defaultPass, getSort("ground_alpha"));
		renderPass(defaultPass, getSort("alpha") );
		renderPass(defaultPass, get("additive") );
		renderPass(defaultPass, getSort("ui", true));
	}
}