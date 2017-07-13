package hide.view;

class Model extends FileView {

	var tools : hide.comp.Toolbar;
	var obj : h3d.scene.Object;
	var scene : hide.comp.Scene;
	var control : h3d.scene.CameraController;
	var tree : hide.comp.IconTree;
	var overlay : Element;

	override function onDisplay( e : Element ) {
		e.html('
			<div class="flex vertical">
				<div class="toolbar"></div>
				<div class="scene">
					<div class="hide-scene-layer hide-scroll"></div>
				</div>
			</div>
		');
		tools = new hide.comp.Toolbar(e.find(".toolbar"));
		overlay = e.find(".hide-scene-layer");
		scene = new hide.comp.Scene(e.find(".scene"));
		scene.onReady = init;
	}

	function initRec( obj : h3d.scene.Object ) {
		if( obj.name == "Selection" || obj.name == "Collide" )
			obj.visible = false;
		for( o in obj )
			initRec(o);
	}

	function init() {
		obj = scene.loadModel(state.path);

		initRec(obj);

		new h3d.scene.Object(scene.s3d).addChild(obj);
		control = new h3d.scene.CameraController(scene.s3d);
		tree = new hide.comp.SceneTree(obj,overlay, obj.name != null);
		resetCamera();

		var anims = listAnims();
		if( anims.length > 0 ) {
			var sel = tools.addSelect("play-circle");
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

		//tools.addButton("cube","Test");
		//tools.addToggle("bank","Test toggle");
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

	static var _ = FileTree.registerExtension(Model,["hmd","fbx","scn"],{ icon : "cube" });

}