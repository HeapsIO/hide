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

class PbrSetup extends h3d.mat.MaterialSetup {

	override public function createRenderer() : h3d.scene.Renderer {
		var envMap = new h3d.mat.Texture(16,16,[Cube]);
		envMap.clear(0x808080);
		var irrad = new h3d.scene.pbr.Irradiance(envMap);
		irrad.compute();
		return new h3d.scene.pbr.Renderer(irrad);
	}

	override function createLightSystem() {
		return new h3d.scene.pbr.LightSystem();
	}

	override function applyProps( m : h3d.mat.Material ) {
		m.shadows = false;
		// default values (if no texture)
		if( m.mainPass.getShader(h3d.shader.pbr.PropsValues) == null )
			m.mainPass.addShader(new h3d.shader.pbr.PropsValues());
		// get values from specular texture
		var spec = m.mainPass.getShader(h3d.shader.pbr.PropsTexture);
		if( m.specularTexture != null ) {
			if( spec == null ) {
				spec = new h3d.shader.pbr.PropsTexture();
				m.mainPass.addShader(spec);
			}
			spec.texture = m.specularTexture;
		} else
			m.mainPass.removeShader(spec);
		m.castShadows = true;
	}

}

