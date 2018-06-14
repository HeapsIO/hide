package hide.prefab;

class Light extends Object3D {

	public var color : Int = 0xffffff;
	public var range : Float = 10;
	public var size : Float = 1.0;

	override function save() {
		var obj : Dynamic = super.save();
		obj.color = color;
		obj.range = range;
		obj.size = size;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		color = obj.color;
		range = obj.range;
		size = obj.size;
	}


	override function applyPos( o : h3d.scene.Object ) {
		super.applyPos(o);
		o.setScale(1.0);
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		var obj = new h3d.scene.Object(ctx.local3d);
		ctx.local3d = obj;
		ctx.local3d.name = name;

		applyPos(ctx.local3d);
		applyProps(ctx);
		return ctx;
	}

	function applyProps(ctx: Context) {
		if(ctx.custom != null) {
			var l : h3d.scene.Light = cast ctx.custom;
			l.remove();
		}
		var light = new h3d.scene.pbr.PointLight(ctx.local3d);
		light.color.setColor(color);
		light.range = range;
		light.size = size;
		ctx.custom = light;

		#if editor
		var color = color | 0xff000000;

		var debugObj = ctx.local3d.find(c -> if(c.name == "_debug") c else null);
		var mesh : h3d.scene.Mesh = null;
		var sizeSphere : h3d.scene.Sphere = null;
		var rangeSphere : h3d.scene.Sphere = null;
		if(debugObj == null) {
			debugObj = new h3d.scene.Object(ctx.local3d);
			debugObj.name = "_debug";

			mesh = new h3d.scene.Mesh(h3d.prim.Sphere.defaultUnitSphere(), debugObj);

			var highlight = new h3d.scene.Object(debugObj);
			highlight.name = "_highlight";
			highlight.visible = false;
			sizeSphere = new h3d.scene.Sphere(0xffffff, size, true, highlight);
			sizeSphere.ignoreCollide = true;
			sizeSphere.material.mainPass.setPassName("overlay");

			rangeSphere = new h3d.scene.Sphere(0xffffff, range, true, highlight);
			rangeSphere.ignoreCollide = true;
			rangeSphere.material.mainPass.setPassName("overlay");
		}
		else {
			mesh = cast debugObj.getChildAt(0);
			sizeSphere = cast debugObj.getChildAt(1).getChildAt(0);
			rangeSphere = cast debugObj.getChildAt(1).getChildAt(1);
		}

		mesh.setScale(hxd.Math.min(0.25, size));
		var mat = mesh.material;
		mat.mainPass.setPassName("overlay");
		mat.color.setColor(color);

		sizeSphere.radius = size;
		rangeSphere.radius = range;
		#end
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		#if editor

		var props = ctx.properties.add(new hide.Element('
			<div class="group" name="Light">
				<dl>
					<dt>Color</dt><dd><input name="colorVal"/></dd>
				</dl>
			</div>
		'),this, function(pname) {
			applyProps(ctx.getContext(this));
			ctx.onChange(this, pname);
		});
		var colorInput = props.find('input[name="colorVal"]');
		var picker = new hide.comp.ColorPicker(false,null,colorInput);
		picker.value = color;
		picker.onChange = function(move) {
			if(!move) {
				var prevVal = color;
				var newVal = picker.value;
				color = picker.value;
				ctx.properties.undo.change(Custom(function(undo) {
					if(undo)
						color = prevVal;
					else
						color = newVal;
					picker.value = color;
					applyProps(ctx.getContext(this));
					ctx.onChange(this, "color");
				}));
			}
			color = picker.value;
			applyProps(ctx.getContext(this));
			ctx.onChange(this, "color");
		}

		var group = new Element('<div class="group" name="Point Light"></div>');
		group.append(hide.comp.PropsEditor.makePropsList([
			{
				name: "size",
				t: PFloat(0, 5),
				def: 0
			},
			{
				name: "range",
				t: PFloat(1, 20),
				def: 10
			},
		]));
		var props = ctx.properties.add(group, this, function(pname) {
			applyProps(ctx.getContext(this));
			ctx.onChange(this, pname);
		});
		#end
	}

	override function getHideProps() {
		return { icon : "sun", name : "Light", fileSource : null };
	}

	static var _ = Library.register("light", Light);
}