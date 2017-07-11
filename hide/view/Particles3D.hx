package hide.view;

@:access(hide.view.Particles3D)
class GpuParticles extends h3d.parts.GpuParticles {

	var parts : Particles3D;

	public function new(parts, parent) {
		super(parent);
		this.parts = parts;
	}

	override function loadTexture( path : String ) {
		return parts.scene.loadTextureFile(parts.state.path, path);
	}

}

class Particles3D extends FileView {

	var scene : hide.comp.Scene;
	var parts : GpuParticles;

	override function getDefaultContent() {
		var p = new h3d.parts.GpuParticles();
		return haxe.io.Bytes.ofString(haxe.Json.stringify(p.save(),"\t"));
	}

	override function onDisplay( e : Element ) {
		scene = new hide.comp.Scene(e);
		scene.onReady = init;
	}

	function init() {
		new h3d.scene.CameraController(scene.s3d).loadFromCamera();
		parts = new GpuParticles(this,scene.s3d);
		parts.load(haxe.Json.parse(sys.io.File.getContent(getPath())));
	}

	static var _ = FileTree.registerExtension(Particles3D, ["json.particles3D"], { icon : "snowflake-o", createNew: "Particle 3D" });

}