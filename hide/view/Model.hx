package hide.view;

class Model extends FileView {

	var tools : hide.comp.Toolbar;
	var obj : h3d.scene.Object;
	var scene : hide.comp.Scene;
	var control : h3d.scene.CameraController;
	var tree : hide.comp.IconTree;

	override function onDisplay( e : Element ) {
		tools = new hide.comp.Toolbar(e);
		var cont = new Element('<div class="hide-scene-layer">').appendTo(tools.content);
		var scroll = new hide.comp.ScrollZone(cont);
		tree = new hide.comp.IconTree(scroll.content);
		tree.get = getSceneElements;
		scene = new hide.comp.Scene(tools.content);
		scene.onReady = init;
	}
	
	function init() {
		obj = scene.loadModel(state.path);
		scene.s3d.addChild(obj);
		control = new h3d.scene.CameraController(scene.s3d);
		resetCamera();
		tree.init();

		var anims = listAnims();
		if( anims.length > 0 ) {
			var sel = tools.addSelect("bicycle");
			var content = [for( a in anims ) {
				var label = a.split("/").pop().substr(5).substr(0,-4);
				if( StringTools.endsWith(label,"_loop") ) label = label.substr(0,-5);
				{ label : label, value : a }
			}];
			content.unshift({ label : "-- no anim --", value : null });
			sel.setContent(content);
			sel.onSelect = function(a) {
				if( a == null ) {
					obj.stopAnimation();
					return;
				}
				var anim = scene.loadAnimation(a);
				obj.playAnimation(anim);
			};
		}
	
		tools.addButton("cube","Test");
		tools.addToggle("bank","Test toggle");
	}

	function listAnims() {
		var dirs : Array<String> = props.get("hmd.animPaths");
		if( dirs == null ) {
			var parts = getPath().split("/");
			parts.pop();
			dirs = [parts.join("/")];
		} else
			dirs = [for( d in dirs ) ide.resourceDir + d];
		var anims = [];
		for( dir in dirs )
			for( f in sys.FileSystem.readDirectory(dir) )
				if( StringTools.startsWith(f,"Anim_") )
					anims.push(dir+"/"+f);
		return anims;
	}

	function getSceneElements( id : String ) {
		var root = obj; 
		var path = id == null ? "" : id+"/";
		if( id != null ) {
			var parts = [for(p in id.split("/")) Std.parseInt(p)];
			for( p in parts )
				root = root.getChildAt(p);
		}
		var elements : Array<hide.comp.IconTree.IconTreeItem> = [
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
			function makeMaterial( m : h3d.mat.Material, index : Int ) : hide.comp.IconTree.IconTreeItem {
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

	function resetCamera() {
		var b = obj.getBounds();
		var dx = Math.max(Math.abs(b.xMax),Math.abs(b.xMin));
		var dy = Math.max(Math.abs(b.yMax),Math.abs(b.yMin));
		var dz = Math.max(Math.abs(b.zMax),Math.abs(b.zMin));
		var dist = Math.max(Math.max(dx * 6, dy * 6), dz * 4);
		var ang = Math.PI / 4;
		var zang = Math.PI * 0.4;
		scene.s3d.camera.pos.set(Math.sin(zang) * Math.cos(ang) * dist, Math.sin(zang) * Math.sin(ang) * dist, Math.cos(zang) * dist);
		scene.s3d.camera.target.set(0, 0, (b.zMax + b.zMin) * 0.5);
		control.loadFromCamera();		
	}

	static var _ = FileTree.registerExtension(Model,["hmd","fbx"],{ icon : "cube" });

}