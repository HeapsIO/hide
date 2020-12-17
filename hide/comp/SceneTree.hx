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
		var prop = path[0];
		switch( prop.split(":").shift() ) {
		case "mat":
			return root.toMesh().getMaterials()[Std.parseInt(prop.substr(4))];
		case "joint":
			return root.getObjectByName(path.pop().substr(6));
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

		var obj = Std.downcast(v, h3d.scene.Object);
		if( obj == null || Std.is(obj,h3d.scene.Skin.Joint) ) return;

		if (el.find(".fa-eye").length == 0) {
			var visibilityToggle = new Element('<i class="fa fa-eye visibility-large-toggle"/>').appendTo(el.find(".jstree-anchor").first());
			visibilityToggle.click(function (e) {
				obj.visible = !obj.visible;
				el.toggleClass("hidden", !obj.visible);
			});
		}
		el.toggleClass("hidden", !obj.visible);
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
			var parts = [for(p in id.split("/")) { id : p, index : Std.parseInt(p) }];
			for( p in parts ) {
				if( StringTools.startsWith(p.id,"joint:") ) {
					root = root.getObjectByName(parts.pop().id.substr(6)); // last joint only
					break;
				} else {
					root = root.getChildAt(p.index);
				}
			}
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
			var sk = Std.downcast(root,h3d.scene.Skin);
			if( sk != null ) {
				for( j in sk.getSkinData().rootJoints )
					elements.push({
						value: path+"joint:"+j.name,
						text : j.name,
						icon : "fa fa-gg",
						children : j.subs.length > 0,
					});
			}
		}
		var joint = Std.downcast(root,h3d.scene.Skin.Joint);
		if( joint != null ) {
			var j = joint.skin.getSkinData().allJoints[joint.index];
			for( j in j.subs )
				elements.push({
					value: path+"joint:"+j.name,
					text : j.name,
					icon : "fa fa-gg",
					children : j.subs.length > 0,
				});
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