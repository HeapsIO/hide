package hide.prefab2.terrain;

class CustomRenderer extends h3d.scene.Renderer {

	var passName : String;

	public function new(passName) {
		super();
		this.passName = passName;
		defaultPass = new h3d.pass.Default("default");
		allPasses.push(defaultPass);
	}

	override function start() {

	}

	override function render() {
		defaultPass.draw(get(passName));
	}
}