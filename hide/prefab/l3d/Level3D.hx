package hide.prefab.l3d;

class Level3D extends Library {

	public var width : Int = 0;
	public var height : Int = 0;

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

	override function edit( ctx : EditContext ) {
		#if editor
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
		#end
	}

	override function getHideProps() {
		return { icon : "cube", name : "Level3D", fileSource : ["l3d"] };
	}

	static var _ = Library.register("level3d", Level3D);
}