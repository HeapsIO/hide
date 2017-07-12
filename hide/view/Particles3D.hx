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
	var properties : hide.comp.Properties;

	override function getDefaultContent() {
		var p = new h3d.parts.GpuParticles();
		p.addGroup().name = "Default";
		return haxe.io.Bytes.ofString(haxe.Json.stringify(p.save(),"\t"));
	}

	override function onDisplay( e : Element ) {
		properties = new hide.comp.Properties(e);
		scene = new hide.comp.Scene(properties.content);
		scene.onReady = init;
	}

	function init() {
		new h3d.scene.CameraController(scene.s3d).loadFromCamera();
		parts = new GpuParticles(this,scene.s3d);
		parts.load(haxe.Json.parse(sys.io.File.getContent(getPath())));

		for( g in parts.getGroups() ) {
			var e = new Element('
				<div class="section open">
					<h1><span>${g.name}</span> &nbsp;<input type="checkbox" field="enable"/></h1>
					<dl class="content">
						<dt>Name</dt><dd><input field="name" onchange="$(this).closest(\'.section\').find(\'>h1 span\').text($(this).val())"/></dd>
						<dt>Mode</dt><dd><select field="emitMode"/></dd>
						<dt>Count</dt><dd><input type="range" field="nparts" min="0" max="1000" step="1"/></dd>
						<dt>Distance</dt><dd><input type="range" field="emitDist" min="0" max="10"/></dd>
						<dt>Angle</dt><dd><input type="range" field="emitAngle" min="${-Math.PI/2}" max="${Math.PI}"/></dd>
						<dt>Loop</dt><dd><input type="checkbox" field="emitLoop"/></dd>
						<dt>Sync</dt><dd><input type="range" field="emitSync" min="0" max="1"/></dd>
						<dt>Delay</dt><dd><input type="range" field="emitDelay" min="0" max="10"/></dd>
						<dt>Transform3D</dt><dd><input type="checkbox" field="transform3D"/></dd>
					</dl>
				</div>
			');
			e.find("[field=emitLoop]").change(function(_) parts.currentTime = 0);
			properties.add(e,g);
		}
	}

	static var _ = FileTree.registerExtension(Particles3D, ["json.particles3D"], { icon : "snowflake-o", createNew: "Particle 3D" });

}