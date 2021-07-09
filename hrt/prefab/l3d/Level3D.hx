package hrt.prefab.l3d;

class Level3D extends hrt.prefab.Library {

	public function new() {
		super();
		type = "level3d";
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