package hide.prefab;

@:enum abstract LightKind(Int) {
	var Point = 0;
	var Directional = 1;

	inline function new(v) {
		this = v;
	}

	public inline function toInt() {
		return this;
	}

	public static inline function fromInt( v : Int ) : LightKind {
		return new LightKind(v);
	}
}


class Light extends Object3D {

	public var kind : LightKind = Point;
	public var color : Int = 0xffffff;
	public var range : Float = 10;
	public var size : Float = 1.0;
	public var power : Float = 1.0;
	public var isSun : Bool = false;

	public function new(?parent) {
		super(parent);
		type = "light";
	}

	override function save() {
		var obj : Dynamic = super.save();
		obj.kind = kind.toInt();
		obj.color = color;
		obj.range = range;
		obj.size = size;
		obj.power = power;
		obj.isSun = isSun;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		kind = LightKind.fromInt(obj.kind);
		color = obj.color;
		range = obj.range;
		size = obj.size;
		power = obj.power;
		if(obj.isSun)
			isSun = obj.isSun;
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

		var isPbr = Std.is(h3d.mat.MaterialSetup.current, h3d.mat.PbrMaterialSetup);
		if(!isPbr)
			return; // TODO

		var color = color | 0xff000000;

		if(kind == Point) {
			var light = new h3d.scene.pbr.PointLight(ctx.local3d);
			light.color.setColor(color);
			light.range = range;
			light.size = size;
			light.power = power;
			ctx.custom = light;
		}
		else {
			var light = new h3d.scene.pbr.DirLight(ctx.local3d);
			light.color.setColor(color);
			light.power = power;
			ctx.custom = light;
		}
		
		#if editor
		var debugPoint = ctx.local3d.find(c -> if(c.name == "_debugPoint") c else null);
		var debugDir = ctx.local3d.find(c -> if(c.name == "_debugDir") c else null);
		var mesh : h3d.scene.Mesh = null;

		if(kind == Point) {
			if(debugDir != null)
				debugDir.remove();

			var sizeSphere : h3d.scene.Sphere = null;
			var rangeSphere : h3d.scene.Sphere = null;
			if(debugPoint == null) {
				debugPoint = new h3d.scene.Object(ctx.local3d);
				debugPoint.name = "_debugPoint";

				mesh = new h3d.scene.Mesh(h3d.prim.Sphere.defaultUnitSphere(), debugPoint);

				var highlight = new h3d.scene.Object(debugPoint);
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
				mesh = cast debugPoint.getChildAt(0);
				sizeSphere = cast debugPoint.getChildAt(1).getChildAt(0);
				rangeSphere = cast debugPoint.getChildAt(1).getChildAt(1);
			}
			mesh.setScale(hxd.Math.clamp(size, 0.1, 0.5));
			sizeSphere.radius = size;
			rangeSphere.radius = range;
		}
		else {
			if(debugPoint != null)
				debugPoint.remove();
			
			if(debugDir == null) {
				debugDir = new h3d.scene.Object(ctx.local3d);
				debugDir.name = "_debugDir";

				mesh = new h3d.scene.Mesh(h3d.prim.Sphere.defaultUnitSphere(), debugDir);
				mesh.scale(0.5);

				var g = new h3d.scene.Graphics(debugDir);
				g.lineStyle(1, 0xffffff);
				g.moveTo(0,0,0);
				g.lineTo(10,0,0);
				g.ignoreCollide = true;
				g.material.mainPass.setPassName("overlay");
			}
			else {
				mesh = cast debugDir.getChildAt(0);
			}
		}

		var mat = mesh.material;
		mat.mainPass.setPassName("overlay");
		mat.color.setColor(color);
		mat.shadows = false;

		#end
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		#if editor

		var group = new hide.Element('<div class="group" name="Light">
				<dl>
					<dt>Kind</dt><dd>
						<select field="kind">
							<option value="0">Point</option>
							<option value="1">Directional</option>
						</select></dd>
					<dt>Color</dt><dd><input name="colorVal"/></dd>
					<dt>Power</dt><dd><input type="range" min="0" max="10" field="power"/></dd>
				</dl>
			</div>
		');

		var pointProps = hide.comp.PropsEditor.makePropsList([
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
		]);

		var dirProps = hide.comp.PropsEditor.makePropsList([
			{
				name: "isSun",
				t: PBool,
				def: false
			},
		]);
		
		group.append(pointProps);
		group.append(dirProps);
		function updateProps() {
			if(kind == Point) {
				pointProps.show();
				dirProps.hide();
			}
			else {
				pointProps.hide();
				dirProps.show();
			}
		}
		updateProps();
		
		var props = ctx.properties.add(group,this, function(pname) {
			applyProps(ctx.getContext(this));
			ctx.onChange(this, pname);
			updateProps();
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
		return { icon : "sun-o", name : "Light", fileSource : null };
	}

	static var _ = Library.register("light", Light);
}