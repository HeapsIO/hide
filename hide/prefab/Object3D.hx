package hide.prefab;
using Lambda;

class Object3D extends Prefab {

	public var x : Float = 0.;
	public var y : Float = 0.;
	public var z : Float = 0.;
	public var scaleX : Float = 1.;
	public var scaleY : Float = 1.;
	public var scaleZ : Float = 1.;
	public var rotationX : Float = 0.;
	public var rotationY : Float = 0.;
	public var rotationZ : Float = 0.;
	public var visible : Bool = true;

	override function load( obj : Dynamic ) {
		x = obj.x == null ? 0. : obj.x;
		y = obj.y == null ? 0. : obj.y;
		z = obj.z == null ? 0. : obj.z;

		scaleX = obj.scaleX == null ? 1. : obj.scaleX;
		scaleY = obj.scaleY == null ? 1. : obj.scaleY;
		scaleZ = obj.scaleZ == null ? 1. : obj.scaleZ;

		rotationX = obj.rotationX == null ? 0. : obj.rotationX;
		rotationY = obj.rotationY == null ? 0. : obj.rotationY;
		rotationZ = obj.rotationZ == null ? 0. : obj.rotationZ;

		visible = obj.visible == null ? true : obj.visible;
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		ctx.local3d = new h3d.scene.Object(ctx.local3d);
		ctx.local3d.name = name;
		applyPos(ctx.local3d);
		return ctx;
	}
	
	override function save() {
		var o : Dynamic = {};
		if( x != 0 ) o.x = x;
		if( y != 0 ) o.y = y;
		if( z != 0 ) o.z = z;
		if( scaleX != 1 ) o.scaleX = scaleX;
		if( scaleY != 1 ) o.scaleY = scaleY;
		if( scaleZ != 1 ) o.scaleZ = scaleZ;
		if( rotationX != 0 ) o.rotationX = rotationX;
		if( rotationY != 0 ) o.rotationY = rotationY;
		if( rotationZ != 0 ) o.rotationZ = rotationZ;
		if( !visible ) o.visible = visible;
		return o;
	}

	public function setTransform(mat : h3d.Matrix) {
		var rot = mat.getEulerAngles();
		x = mat.tx;
		y = mat.ty;
		z = mat.tz;
		var s = mat.getScale();
		scaleX = s.x;
		scaleY = s.y;
		scaleZ = s.z;
		rotationX = rot.x;
		rotationY = rot.y;
		rotationZ = rot.z;
	}

	public function getTransform() {
		var m = new h3d.Matrix();
		m.initScale(scaleX, scaleY, scaleZ);
		m.rotate(rotationX, rotationY, rotationZ);
		m.translate(x, y, z);
		return m;
	}

	public function applyPos( o : h3d.scene.Object ) {
		o.x = x;
		o.y = y;
		o.z = z;
		o.scaleX = scaleX;
		o.scaleY = scaleY;
		o.scaleZ = scaleZ;
		o.setRotate(rotationX, rotationY, rotationZ);
		o.visible = visible;
	}

	override function edit( ctx : EditContext ) {
		#if editor
		var props = new hide.Element('
			<div class="group" name="Position">
				<dl>
					<dt><input type="button" value="X" xfield="x" class="reset"/></dt><dd><input type="range" min="-10" max="10" value="0" field="x"/></dd>
					<dt><input type="button" value="Y" xfield="y" class="reset"/></dt><dd><input type="range" min="-10" max="10" value="0" field="y"/></dd>
					<dt><input type="button" value="Z" xfield="z" class="reset"/></dt><dd><input type="range" min="-10" max="10" value="0" field="z"/></dd>
					<dt><input type="button" value="Scale X" xfield="scaleX" class="reset"/></dt><dd><input type="range" min="0" max="5" value="1" field="scaleX"/></dd>
					<dt><input type="button" value="Scale Y" xfield="scaleY" class="reset"/></dt><dd><input type="range" min="0" max="5" value="1" field="scaleY"/></dd>
					<dt><input type="button" value="Scale Z" xfield="scaleZ" class="reset"/></dt><dd><input type="range" min="0" max="5" value="1" field="scaleZ"/></dd>
					<dt><input type="button" value="Rotation X" xfield="rotationX" class="reset"/></dt><dd><input type="range" min="-180" max="180" value="0" field="rotationX" scale="${Math.PI/180}"/></dd>
					<dt><input type="button" value="Rotation Y" xfield="rotationY" class="reset"/></dt><dd><input type="range" min="-180" max="180" value="0" field="rotationY" scale="${Math.PI/180}"/></dd>
					<dt><input type="button" value="Rotation Z" xfield="rotationZ" class="reset"/></dt><dd><input type="range" min="-180" max="180" value="0" field="rotationZ" scale="${Math.PI/180}"/></dd>
					<dt>Visible</dt><dd><input type="checkbox" field="visible"/></dd>
				</dl>
			</div>
		');

		ctx.properties.add(props, this, function(_) {
			applyPos(ctx.getContext(this).local3d);
			ctx.onChange(this);
		});

		for(fname in "x y z rotationX rotationY rotationZ scaleX scaleY scaleZ".split(" ")) {
			var resets = props.find('input.reset[xfield="$fname"]');
			resets.click(function(e) {
				var field = ctx.properties.fields.find(f -> f.fname == fname);
				if(field != null) {
					var range = @:privateAccess field.range;
					if(range != null) range.reset();
				}
			});
		}
		#end
	}

	override function getHideProps() {
		return { icon : "folder-open", name : "Group", fileSource : null };
	}

	static var _ = Library.register("object", Object3D);

}