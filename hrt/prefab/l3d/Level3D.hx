package hrt.prefab.l3d;

class Level3D extends hrt.prefab.Library {

	@:s public var width : Int;
	@:s public var height : Int;
	@:s public var gridSize : Int = 1;

	public function new() {
		super();
		type = "level3d";
		width = height = 100;
	}

	#if editor

	override function edit( ctx : EditContext ) {
		var props = new hide.Element('
			<div class="group" name="Level">
					<dl>
					<dt>Width</dt><dd><input type="number" value="0" field="width"/></dd>
					<dt>Height</dt><dd><input type="number" value="0" field="height"/></dd>
					<dt>Grid Size</dt><dd><input type="number" value="0" field="gridSize"/></dd>
				</dl>
			</div>
		');
		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	override function getHideProps() : HideProps {
		return { icon : "cube", name : "Level3D", allowParent: _ -> false};
	}

	#end

	static var _ = Library.register("level3d", Level3D, "l3d");
}