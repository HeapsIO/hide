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

		var prim = h3d.prim.Sphere.defaultUnitSphere();
		var mesh = new h3d.scene.Mesh(prim, obj);
		mesh.setScale(0.33);

		// var path = hide.Ide.inst.appPath + "/res/pointLightSmall.png";
		// var data = sys.io.File.getBytes(path);
		// var tile = hxd.res.Any.fromBytes(path, data).toTile().center();
		// var objFollow = new h2d.ObjectFollower(ctx.local3d, ctx.shared.root2d);
		// var bmp = new h2d.Bitmap(tile, objFollow);
		// ctx.local2d = objFollow;

		applyPos(ctx.local3d);
		applyProps(ctx);
		return ctx;
	}

	function applyProps(ctx: Context) {
		if(ctx.custom != null) {
			var l : h3d.scene.Light = cast ctx.custom;
			l.remove();
		}

		var mesh = Std.instance(ctx.local3d.getChildAt(0), h3d.scene.Mesh);
		if(mesh != null) {
			var mat = mesh.material;
			mat.mainPass.setPassName("overlay");
			mat.color.setColor(color | 0xff000000);
		}

		var light = new h3d.scene.pbr.PointLight(ctx.local3d);
		light.color.setColor(color);
		ctx.custom = light;
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
		#end
	}

	override function getHideProps() {
		return { icon : "sun", name : "Light", fileSource : null };
	}

	static var _ = Library.register("light", Light);
}