package hide.view;

class Model extends FileView {

	var tools : hide.comp.Toolbar;
	var obj : h3d.scene.Object;
	var scene : hide.comp.Scene;
	var control : h3d.scene.CameraController;
	var tree : hide.comp.SceneTree;
	var overlay : Element;
	var properties : hide.comp.PropsEditor;

	override function onDisplay() {
		root.html('
			<div class="flex vertical">
				<div class="toolbar"></div>
				<div class="flex">
					<div class="scene">
						<div class="hide-scroll hide-scene-layer">
							<div class="tree"></div>
						</div>
					</div>
					<div class="props">
					</div>
				</div>
			</div>
		');
		tools = new hide.comp.Toolbar(root.find(".toolbar"));
		overlay = root.find(".hide-scene-layer .tree");
		properties = new hide.comp.PropsEditor(root.find(".props"));
		properties.saveDisplayKey = "Model";
		scene = new hide.comp.Scene(root.find(".scene"));
		scene.onReady = init;
	}

	function init() {
		obj = scene.loadModel(state.path);

		new h3d.scene.Object(scene.s3d).addChild(obj);
		control = new h3d.scene.CameraController(scene.s3d);
		tree = new hide.comp.SceneTree(obj, overlay, obj.name != null);
		tree.onSelectMaterial = function(m) {
			properties.clear();
			properties.addMaterial(m);
		}

		this.saveDisplayKey = "Model:"+state.path;
		var cam = getDisplayState("Camera");
		if( cam == null )
			scene.resetCamera(obj, 1.5);
		else {
			scene.s3d.camera.pos.set(cam.x, cam.y, cam.z);
			scene.s3d.camera.target.set(cam.tx, cam.ty, cam.tz);
		}
		control.loadFromCamera();

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

		scene.init(props);
		scene.onUpdate = update;
		tools.addButton("video-camera", "Reset Camera", function() {
			scene.resetCamera(obj,1.5);
			control.loadFromCamera();
		});
		//tools.addButton("cube","Test");
		//tools.addToggle("bank","Test toggle");
	}

	function update(dt:Float) {
		var cam = scene.s3d.camera;
		saveDisplayState("Camera", { x : cam.pos.x, y : cam.pos.y, z : cam.pos.z, tx : cam.target.x, ty : cam.target.y, tz : cam.target.z });
	}

	function listAnims() {
		var dirs : Array<String> = props.get("hmd.animPaths");
		if( dirs == null ) dirs = [];
		dirs = [for( d in dirs ) ide.resourceDir + d];

		var parts = getPath().split("/");
		parts.pop();
		dirs.unshift(parts.join("/"));

		var anims = [];
		for( dir in dirs )
			for( f in sys.FileSystem.readDirectory(dir) )
				if( StringTools.startsWith(f,"Anim_") )
					anims.push(dir+"/"+f);
		return anims;
	}

	static var _ = FileTree.registerExtension(Model,["hmd","fbx","scn"],{ icon : "cube" });

}