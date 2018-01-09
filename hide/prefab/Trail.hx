package hide.prefab;

class Trail extends Object3D {

	var data : Dynamic;

	function new(?parent) {
		super(parent);
		data = new h3d.scene.Trail().save();
	}

	override function load(obj:Dynamic) {
		super.load(obj);
		data = obj.data;
	}

	override function save() : {} {
		var obj : Dynamic = super.save();
		obj.data = data;
		return obj;
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		var tr = new h3d.scene.Trail(ctx.local3d);
		tr.load(data);
		applyPos(tr);
		tr.name = name;
		ctx.local3d = tr;
		return ctx;
	}

	override function getHideProps():HideProps {
		return { icon : "toggle-on", name : "Trail" };
	}


	override public function edit(ctx:EditContext) {
		#if editor
		super.edit(ctx);

		var trail = Std.instance(ctx.getContext(this).local3d, h3d.scene.Trail);
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
		#end
	}



	static var _ = Library.register("trail", Trail);

}