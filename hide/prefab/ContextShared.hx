package hide.prefab;

class ContextShared extends hxd.prefab.ContextShared {

	var scene : hide.comp.Scene;

	public function new(scene) {
		super();
		this.scene = scene;
	}

	function getScene() {
		return scene;
	}

	override function loadShader( path : String ) {
		return hide.Ide.inst.shaderLoader.loadSharedShader(path);
	}

	override function loadModel( path : String ) {
		return getScene().loadModel(path);
	}

	override function loadAnimation( path : String ) {
		return getScene().loadAnimation(path);
	}

	override function loadTexture( path : String ) {
		return getScene().loadTexture("",path);
	}

}