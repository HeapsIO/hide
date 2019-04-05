package hide.comp;

class SceneTree extends IconTree<String> {

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

	override function onClick(id:String, evt: Dynamic) {
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

	override function applyStyle(id: String, el: Element) {
		var v : Dynamic = resolvePath(id);

		var obj = Std.instance(v, h3d.scene.Object);

		if (obj != null) {
			if (el.find(".fa-eye").length == 0) {
				var visibilityToggle = new Element('<i class="fa fa-eye visibility-large-toggle"/>').appendTo(el.find(".jstree-wholerow").first());
				visibilityToggle.click(function (e) {
					obj.visible = !obj.visible;
					el.toggleClass("hidden", !obj.visible);
				});
			}
			el.toggleClass("hidden", !obj.visible);
		}
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
		var elements : Array<IconTree.IconTreeItem<String>> = [
			for( i in 0...root.numChildren ) {
				var c = root.getChildAt(i);
				{
					value :path+i,
					text : getObjectName(c),
					icon : "fa fa-" + getIcon(c),
					children : c.isMesh() || c.numChildren > 0,
					state : { opened : c.numChildren > 0 && c.numChildren < 10 }
				}
			}
		];
		if( root.isMesh() ) {
			var materials = root.toMesh().getMeshMaterials();
			for( i in 0...materials.length ) {
				var m = materials[i];
				elements.push({
					value :path+"mat:"+i,
					text : m.name == null ? "Material@"+i : m.name,
					icon : "fa fa-photo",
				});
			}
		}
		return elements;
	}

	public function getObjectName( o : h3d.scene.Object ) {
		if( o.name != null )
			return o.name;
		if( o.parent == null )
			return o.toString();
		return o.toString() + "@" + @:privateAccess o.parent.children.indexOf(o);
	}

}