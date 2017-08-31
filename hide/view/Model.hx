package hide.view;

class Model extends FileView {

	var tools : hide.comp.Toolbar;
	var obj : h3d.scene.Object;
	var scene : hide.comp.Scene;
	var control : h3d.scene.CameraController;
	var tree : hide.comp.SceneTree;
	var overlay : Element;
	var properties : hide.comp.PropsEditor;
	var light : h3d.scene.DirLight;
	var lightDirection = new h3d.Vector( 1, 2, -4 );

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
		properties = new hide.comp.PropsEditor(root.find(".props"), undo);
		properties.saveDisplayKey = "Model";
		scene = new hide.comp.Scene(root.find(".scene"));
		scene.onReady = init;
	}

	function selectMaterial( m : h3d.mat.Material ) {
		properties.clear();

		properties.add(new Element('
			<div class="group" name="Textures">
				<dl>
					<dt>Base</dt><dd><input type="texture" field="texture"/></dd>
				</dl>
			</div>
			<br/>
		'),m);


		var e = properties.add(new Element('
			<div class="group" name="Material ${m.name}">
			</div>
			<dl>
				<dt></dt><dd><input type="button" value="Reset Defaults" class="reset"/></dd>
			</dl>
			<br/>
		'));

		properties.addMaterial(m, e.find(".group > .content"));
		e.find(".reset").click(function(_) {
			var cur = h3d.mat.MaterialSetup.current;
			var old = m.props;
			m.props = null;
			cur.saveModelMaterial(m);
			cur.initModelMaterial(m);
			selectMaterial(m);
			undo.change(Field(m, "props", old), selectMaterial.bind(m));
		});
	}

	function init() {

		undo.onChange = function() {};

		obj = scene.loadModel(state.path);
		new h3d.scene.Object(scene.s3d).addChild(obj);

		light = obj.find(function(o) return Std.instance(o, h3d.scene.DirLight));
		if( light == null ) {
			light = new h3d.scene.DirLight(new h3d.Vector(), scene.s3d);
			light.enableSpecular = true;
		}

		control = new h3d.scene.CameraController(scene.s3d);
		tree = new hide.comp.SceneTree(obj, overlay, obj.name != null);
		tree.onSelectMaterial = selectMaterial;

		this.saveDisplayKey = "Model:" + state.path;
		tree.saveDisplayKey = this.saveDisplayKey;

		var cam = getDisplayState("Camera");
		if( cam == null )
			scene.resetCamera(obj, 1.5);
		else {
			scene.s3d.camera.pos.set(cam.x, cam.y, cam.z);
			scene.s3d.camera.target.set(cam.tx, cam.ty, cam.tz);
		}
		control.loadFromCamera();

		var anims = scene.listAnims(getPath());
		if( anims.length > 0 ) {
			var sel = tools.addSelect("play-circle");
			var content = [for( a in anims ) {
				var label = scene.animationName(a);
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

		tools.saveDisplayKey = "ModelTools";

		tools.addButton("video-camera", "Reset Camera", function() {
			scene.resetCamera(obj,1.5);
			control.loadFromCamera();
		});

		tools.addToggle("sun-o", "Enable Lights/Shadows", function(v) {
			if( !v ) {
				for( m in obj.getMaterials() ) {
					m.mainPass.enableLights = false;
					m.shadows = false;
				}
			} else {
				for( m in obj.getMaterials() )
					h3d.mat.MaterialSetup.current.initModelMaterial(m);
			}
		},true);

		tools.addColor("Background color", function(v) {
			scene.engine.backgroundColor = v;
		}, scene.engine.backgroundColor);
	}

	function update(dt:Float) {
		var cam = scene.s3d.camera;
		saveDisplayState("Camera", { x : cam.pos.x, y : cam.pos.y, z : cam.pos.z, tx : cam.target.x, ty : cam.target.y, tz : cam.target.z });
		if( light != null ) {
			var angle = Math.atan2(cam.target.y - cam.pos.y, cam.target.x - cam.pos.x);
			light.direction.set(
				Math.cos(angle) * lightDirection.x - Math.sin(angle) * lightDirection.y,
				Math.sin(angle) * lightDirection.x + Math.cos(angle) * lightDirection.y,
				lightDirection.z
			);
		}
	}

	static var _ = FileTree.registerExtension(Model,["hmd","fbx","scn"],{ icon : "cube" });

}