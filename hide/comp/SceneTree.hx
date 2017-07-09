package hide.comp;

class SceneTree extends IconTree {

	public var obj : h3d.scene.Object;

	public function new(obj, root) {
		super(root);
		this.obj = obj;
		init();
	}

	override function get( id : String ) {
		var root = obj.parent;
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
					text : c.name,
					icon : "fa fa-" + (c.isMesh() ? (Std.is(c,h3d.scene.Skin) ? "male" : "cube") : "circle-o"),
					children : c.isMesh() || c.numChildren > 0,
				}
			}
		];
		if( root.isMesh() ) {
			function makeMaterial( m : h3d.mat.Material, index : Int ) : IconTree.IconTreeItem {
				return {
					id : path+"mat"+index,
					text : m.name,
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