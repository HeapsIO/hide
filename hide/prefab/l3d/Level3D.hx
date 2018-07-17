package hide.prefab.l3d;

class Level3D extends hxd.prefab.Library {

	public var width : Int = 100;
	public var height : Int = 100;

	public function new() {
		super();
		type = "level3d";
	}

	override function save() {
		var obj : Dynamic = super.save();
		obj.width = width;
		obj.height = height;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		width = obj.width == null ? 100 : obj.width;
		height = obj.height == null ? 100 : obj.height;
	}

	#if editor

	override function edit( ctx : EditContext ) {
		var props = new hide.Element('
			<div class="group" name="Level">
					<dl>
					<dt>Width</dt><dd><input type="number" value="0" field="width"/></dd>
					<dt>Height</dt><dd><input type="number" value="0" field="height"/></dd>
				</dl>
			</div>
		');
		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : HideProps {
		return { icon : "cube", name : "Level3D", fileSource : ["l3d"], allowChildren : function(t) return hxd.prefab.Library.isOfType(t,Object3D) };
	}

	#end

	static var _ = hxd.prefab.Library.register("level3d", Level3D);
}