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

	function resolvePath(id:String) : Dynamic {
		var path = id.split("/");
		var root = showRoot ? obj.parent : obj;
		while( path.length > 0 ) {
			var idx = Std.parseInt(path[0]);
			if( idx == null ) break;
			path.shift();
			root = root.getChildAt(idx);
		}
		if( path.length == 0 )
			return root;
		var prop = path.shift();
		switch( prop.split(":").shift() ) {
		case "mat":
			return root.toMesh().getMaterials()[Std.parseInt(prop.substr(4))];
		default:
		}
		return null;
	}

	override function onClick(id:String) {
		var v : Dynamic = resolvePath(id);
		if( Std.is(v, h3d.scene.Object) )
			onSelectObject(v);
		else if( Std.is(v, h3d.mat.Material) )
			onSelectMaterial(v);
	}

	public dynamic function onSelectObject( obj : h3d.scene.Object ) {
	}

	public dynamic function onSelectMaterial( m : h3d.mat.Material ) {
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
			var materials = root.toMesh().getMeshMaterials();
			for( i in 0...materials.length ) {
				var m = materials[i];
				elements.push({
					id : path+"mat:"+i,
					text : m.name == null ? "Material@"+i : m.name,
					icon : "fa fa-photo",
				});
			}
		}
		return elements;
	}

}