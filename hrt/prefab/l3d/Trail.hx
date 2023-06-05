package hrt.prefab.l3d;

class Trail extends Object3D {

	@:s var data : Dynamic;

	function new(?parent, shared: ContextShared) {
		super(parent, shared);
		data = new h3d.scene.Trail().save();
	}

	override public function makeObject(parent3d:h3d.scene.Object):h3d.scene.Object {
		var tr = new h3d.scene.Trail(parent3d);
		tr.load(data);
		applyTransform();
		return tr;
	}

	#if editor

	override function getHideProps():hide.prefab.HideProps {
		return { icon : "toggle-on", name : "Trail" };
	}

	override public function edit(ctx:hide.prefab.EditContext) {
		super.edit(ctx);

		var trail = Std.downcast(local3d, h3d.scene.Trail);
		var props = ctx.properties.add(new hide.Element('
		<div class="group" name="Material">
		</div>
		<div class="group" name="Trail Properties">
			<dl>
				<dt>Angle</dt><dd><input type="range" field="angle" scale="${180/Math.PI}" min="0" max="${Math.PI*2}"/></dd>
				<dt>Duration</dt><dd><input type="range" field="duration" min="0" max="1"/></dd>
				<dt>Size Start</dt><dd><input type="range" field="sizeStart" min="0" max="10"/></dd>
				<dt>Size End</dt><dd><input type="range" field="sizeEnd" min="0" max="10"/></dd>
				<dt>Movement Min.</dt><dd><input type="range" field="movementMin" min="0" max="1"/></dd>
				<dt>Movement Max.</dt><dd><input type="range" field="movementMax" min="0" max="1"/></dd>
				<dt>Smoothness</dt><dd><input type="range" field="smoothness" min="0" max="1"/></dd>
				<dt>Texture</dt><dd><input type="texture" field="texture"/></dd>
			</dl>
		</div>
		'),trail, function(_) {
			data = trail.save();
		});
		ctx.properties.addMaterial( trail.material, props.find("[name=Material] > .content"), function(_) data = trail.save());
	}

	#end

	static var _ = Prefab.register("trail", Trail);

}