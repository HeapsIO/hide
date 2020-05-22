package hrt.prefab.l3d;

class Level3D extends hrt.prefab.Library {

	public var width : Int = 100;
	public var height : Int = 100;
	public var gridSize : Int = 1;

	public function new() {
		super();
		type = "level3d";
	}

	override function save() {
		var obj : Dynamic = super.save();
		obj.width = width;
		obj.height = height;
		obj.gridSize = gridSize;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		width = obj.width == null ? 100 : obj.width;
		height = obj.height == null ? 100 : obj.height;
		gridSize = obj.gridSize == null ? 1 : obj.gridSize;
	}

	#if editor

	override function getCdbModel(?p:hrt.prefab.Prefab) : cdb.Sheet {
		if( p == null ) p = this;
		return @:privateAccess hide.view.l3d.Level3D.getCdbModel(p);
	}

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
		return { icon : "cube", name : "Level3D", allowChildren : function(t) return Library.isOfType(t,Object3D) || t == "renderProps", allowParent: _ -> false};
	}

	#end

	static var _ = Library.register("level3d", Level3D, "l3d");
}