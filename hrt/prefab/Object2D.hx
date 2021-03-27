package hrt.prefab;
import hxd.Math;
using Lambda;

class Object2D extends Prefab {

	@:s public var x : Float = 0.;
	@:s public var y : Float = 0.;
	@:s public var scaleX : Float = 1.;
	@:s public var scaleY : Float = 1.;
	@:s public var rotation : Float = 0.;

	@:s public var visible : Bool = true;
	public var blendMode : h2d.BlendMode = None;

	public function loadTransform(t) {
		x = t.x;
		y = t.y;
		scaleX = t.scaleX;
		scaleY = t.scaleY;
		rotation = t.rotation;
	}

	public function saveTransform() {
		return { x : x, y : y, scaleX : scaleX, scaleY : scaleY, rotation : rotation };
	}

	public function setTransform(t) {
		x = t.x;
		y = t.y;
		scaleX = t.scaleX;
		scaleY = t.scaleY;
		rotation = t.rotation;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		if( obj.blendMode != null )
			blendMode = std.Type.createEnum(h2d.BlendMode, obj.blendMode);
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		ctx.local2d = new h2d.Object(ctx.local2d);
		ctx.local2d.name = name;
		updateInstance(ctx);
		return ctx;
	}

	override function save() {
		var o : Dynamic = super.save();
		if( blendMode != None ) o.blendMode = blendMode.getName();
		return o;
	}

	public function getTransform() {
		var m = new h2d.col.Matrix();
		m.initScale(scaleX, scaleY);
		m.rotate(Math.degToRad(rotation));
		m.translate(x, y);
		return m;
	}

	public function applyTransform( o : h2d.Object ) {
		o.x = x;
		o.y = y;
		o.scaleX = scaleX;
		o.scaleY = scaleY;
		o.rotation = Math.degToRad(rotation);
	}

	override function updateInstance( ctx: Context, ?propName : String ) {
		var o = ctx.local2d;
		o.x = x;
		o.y = y;
		if(propName == null || propName.indexOf("scale") == 0) {
			o.scaleX = scaleX;
			o.scaleY = scaleY;
		}
		if(propName == null || propName.indexOf("rotation") == 0)
			o.rotation = Math.degToRad(rotation);
		if(propName == null || propName == "visible")
			o.visible = visible;

		if(propName == null || propName == "blendMode")
			if (blendMode != null) o.blendMode = blendMode;
	}

	override function removeInstance(ctx: Context):Bool {
		if(ctx.local2d != null)
			ctx.local2d.remove();
		return true;
	}

	#if editor

	override function edit( ctx : EditContext ) {
		var props = new hide.Element('
			<div class="group" name="Position">
				<dl>
					<dt>X</dt><dd><input type="range" min="-100" max="100" value="0" field="x"/></dd>
					<dt>Y</dt><dd><input type="range" min="-100" max="100" value="0" field="y"/></dd>
					<dt>Scale X</dt><dd><input type="range" min="0" max="5" value="1" field="scaleX"/></dd>
					<dt>Scale Y</dt><dd><input type="range" min="0" max="5" value="1" field="scaleY"/></dd>
					<dt>Rotation</dt><dd><input type="range" min="-180" max="180" value="0" field="rotation" /></dd>
				</dl>
			</div>
			<div class="group" name="Display">
				<dl>
					<dt>Visible</dt><dd><input type="checkbox" field="visible"/></dd>
					<dt>Blend Mode</dt><dd><select field="blendMode"/></dd></dd>
				</dl>
			</div>
		');
		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : HideProps {
		// Check children
		return {
			icon : children == null || children.length > 0 ? "folder-open" : "genderless",
			name : "Group 2D"
		};
	}
	#end

	override function getDefaultName() {
		return type == "object2D" ? "group2D" : super.getDefaultName();
	}

	static var _ = Library.register("object2D", Object2D);

}