package hide.comp;

class SceneTree extends IconTree {

	var showRoot : Bool;
	public var obj : h3d.scene.Object;

	public function new(obj, root, showRoot : Bool) {
		super(root);
		this.showRoot = showRoot;
		this.obj = obj;
		init();
	}

	function getIcon( c : h3d.scene.Object ) {
		if( c.isMesh() ) {
			if( Std.is(c, h3d.scene.Skin) )
				return "male";
			if( Std.is(c, h3d.parts.GpuParticles) || Std.is(c, h3d.parts.Particles) )
				return "snowflake-o";
			return "cube";
		}
		if( Std.is(c, h3d.scene.Light) )
			return "sun-o";
		return "circle-o";
	}

	override function get( id : String ) {
		var root = showRoot ? obj.parent : obj;
		var path = id == null ? "" : id+"/";
		if( id != null ) {
			var parts = [for(p in id.split("/")) Std.parseInt(p)];
			for( p in parts )
				root = root.getChildAt(p);
		}
		var elements : Array<IconTree.IconTreeItem> = [
			for( i in 0...root.numChildren ) {
				var c = root.getChildAt(i);
				{
					id : path+i,
					text : c.name == null ? c.toString()+"@"+i : c.name,
					icon : "fa fa-" + getIcon(c),
					children : c.isMesh() || c.numChildren > 0,
				}
			}
		];
		if( root.isMesh() ) {
			function makeMaterial( m : h3d.mat.Material, index : Int ) : IconTree.IconTreeItem {
				return {
					id : path+"mat"+index,
					text : m.name == null ? "Material@"+index : m.name,
					icon : "fa fa-photo",
				};
			}
			var multi = Std.instance(root,h3d.scene.MultiMaterial);
			if( multi != null )
				for( m in multi.materials )
					elements.push(makeMaterial(m,multi.materials.indexOf(m)));
			else
				elements.push(makeMaterial(root.toMesh().material,0));
		}
		return elements;
	}

}