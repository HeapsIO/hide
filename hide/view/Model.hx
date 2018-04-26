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

	var aspeed : hide.comp.Range;
	var aloop : { function toggle( v : Bool ) : Void; var element : Element; }
	var apause : { function toggle( v : Bool ) : Void; var element : Element; };
	var timeline : h2d.Graphics;
	var timecursor : h2d.Bitmap;
	var currentAnimation : String;

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

	function selectObject( obj : h3d.scene.Object ) {
		properties.clear();

		var objectCount = 1 + obj.getObjectsCount();
		var meshes = obj.getMeshes();
		var vertexCount = 0, triangleCount = 0, materialDraws = 0, materialCount = 0;
		var uniqueMats = new Map();
		for( m in obj.getMaterials() ) {
			if( uniqueMats.exists(m.name) ) continue;
			uniqueMats.set(m.name, true);
			materialCount++;
		}
		for( m in meshes ) {
			var p = m.primitive;
			triangleCount += p.triCount();
			vertexCount += p.vertexCount();
			var multi = Std.instance(m, h3d.scene.MultiMaterial);
			materialDraws += if( multi != null ) multi.materials.length else 1;
		}

		var e = properties.add(new Element('
			<div class="group" name="Properties">
				<dl>
					<dt>X</dt><dd><input field="x"/></dd>
					<dt>Y</dt><dd><input field="y"/></dd>
					<dt>Z</dt><dd><input field="z"/></dd>
					<dt>Visible</dt><dd><input type="checkbox" field="visible"/></dd>
					<dt>Attach</dt><dd><select class="follow"><option value="">--- None ---</option></select></dd>
				</dl>
			</div>
			<div class="group" name="Info">
				<dl>
					<dt>Objects</dt><dd>$objectCount</dd>
					<dt>Meshes</dt><dd>${meshes.length}</dd>
					<dt>Materials</dt><dd>$materialCount</dd>
					<dt>Draws</dt><dd>$materialDraws</dd>
					<dt>Vertexes</dt><dd>$vertexCount</dd>
					<dt>Triangles</dt><dd>$triangleCount</dd>
				</dl>
			</div>
			<br/>
		'),obj);

		var select = e.find(".follow");
		for( path in getNamedObjects(obj) ) {
			var parts = path.split(".");
			var opt = new Element("<option>").attr("value", path).html([for( p in 1...parts.length ) "&nbsp; "].join("") + parts.pop());
			select.append(opt);
		}
		select.change(function(_) {
			var name = select.val().split(".").pop();
			obj.follow = this.obj.getObjectByName(name);
		});
	}

	function getNamedObjects( ?exclude : h3d.scene.Object ) {
		var out = [];

		function getJoint(path:Array<String>,j:h3d.anim.Skin.Joint) {
			path.push(j.name);
			out.push(path.join("."));
			for( j in j.subs )
				getJoint(path, j);
			path.pop();
		}

		function getRec(path:Array<String>,o:h3d.scene.Object) {
			if( o == exclude || o.name == null ) return;
			path.push(o.name);
			out.push(path.join("."));
			for( c in o )
				getRec(path, c);
			var sk = Std.instance(o, h3d.scene.Skin);
			if( sk != null ) {
				var j = sk.getSkinData();
				for( j in j.rootJoints )
					getJoint(path, j);
			}
			path.pop();
		}

		if( obj.name == null )
			for( o in obj )
				getRec([], o);
		else
			getRec([], obj);

		return out;
	}

	function init() {

		undo.onChange = function() {};

		obj = scene.loadModel(state.path, true);
		new h3d.scene.Object(scene.s3d).addChild(obj);

		light = obj.find(function(o) return Std.instance(o, h3d.scene.DirLight));
		if( light == null ) {
			light = new h3d.scene.DirLight(new h3d.Vector(), scene.s3d);
			light.enableSpecular = true;
		}

		control = new h3d.scene.CameraController(scene.s3d);
		tree = new hide.comp.SceneTree(obj, overlay, obj.name != null);
		tree.onSelectMaterial = selectMaterial;
		tree.onSelectObject = selectObject;

		this.saveDisplayKey = "Model:" + state.path;
		tree.saveDisplayKey = this.saveDisplayKey;

		var cam = getDisplayState("Camera");
		scene.s3d.camera.zNear = scene.s3d.camera.zFar = 0;
		scene.resetCamera(obj, 1.5);
		control.lockZPlanes = scene.s3d.camera.zNear != 0;
		if( cam != null ) {
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
			sel.onSelect = setAnimation;
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

		var axis = new h3d.scene.Graphics(scene.s3d);
		axis.lineStyle(1,0xFF0000);
		axis.lineTo(1,0,0);
		axis.lineStyle(1,0x00FF00);
		axis.moveTo(0,0,0);
		axis.lineTo(0,1,0);
		axis.lineStyle(1,0x0000FF);
		axis.moveTo(0,0,0);
		axis.lineTo(0,0,1);
		axis.visible = false;

		tools.addToggle("", "Toggle Axis", function(v) {
			axis.visible = v;
		});

		tools.addColor("Background color", function(v) {
			scene.engine.backgroundColor = v;
		}, scene.engine.backgroundColor);

		aloop = tools.addToggle("refresh", "Loop animation", function(v) {
			if( obj.currentAnimation != null ) {
				obj.currentAnimation.loop = v;
				obj.currentAnimation.onAnimEnd = function() {
					if( !v ) haxe.Timer.delay(function() obj.currentAnimation.setFrame(0), 500);
				}
			}
		});

		apause = tools.addToggle("pause", "Pause animation", function(v) {
			if( obj.currentAnimation != null ) obj.currentAnimation.pause = v;
		});

		aspeed = tools.addRange("Animation speed", function(v) {
			if( obj.currentAnimation != null ) obj.currentAnimation.speed = v;
		}, 1, 0, 2);

		scene.onResize = buildTimeline;
		setAnimation(null);
	}

	override function buildTabMenu() {
		var menu = super.buildTabMenu();
		var arr : Array<hide.comp.ContextMenu.ContextMenuItem> = [
			{ label : null, isSeparator : true },
			{ label : "Export", enabled : this.extension != "hsd", click : function() {
				ide.chooseFileSave(this.getPath().substr(0,-4)+"_dump.txt", function(file) {
					var lib = @:privateAccess scene.loadHMD(this.getPath(),false);
					var hmd = lib.header;
					hmd.data = lib.getData();
					sys.io.File.saveContent(ide.getPath(file), new hxd.fmt.hmd.Dump().dump(hmd));
				});
			} },
			{ label : "Export Animation", enabled : this.extension != "hsd" && currentAnimation != null, click : function() {
				ide.chooseFileSave(this.getPath().substr(0,-4)+"_"+obj.currentAnimation.name+"_dump.txt", function(file) {
					var lib = @:privateAccess scene.loadHMD(ide.getPath(currentAnimation),true);
					var hmd = lib.header;
					hmd.data = lib.getData();
					sys.io.File.saveContent(ide.getPath(file), new hxd.fmt.hmd.Dump().dump(hmd));
				});
			} },
		];
		return menu.concat(arr);
	}

	function setAnimation( file : String ) {
		if( timeline != null ) {
			timeline.remove();
			timeline = null;
		}
		apause.toggle(false);
		aloop.toggle(true);
		aspeed.value = 1;
		aloop.element.toggle(file != null);
		aspeed.root.toggle(file != null);
		apause.element.toggle(file != null);
		if( file == null ) {
			obj.stopAnimation();
			currentAnimation = null;
			return;
		}
		var anim = scene.loadAnimation(file);
		currentAnimation = file;
		obj.playAnimation(anim);
		buildTimeline();
	}

	function buildTimeline() {
		if( timeline != null ) {
			timeline.remove();
			timeline = null;
		}
		if( obj.currentAnimation == null )
			return;

		var H = 15;
		var W = scene.s2d.width;
		timeline = new h2d.Graphics(scene.s2d);
		timeline.y = scene.s2d.height - H;
		timeline.beginFill(0, 0.8);
		timeline.drawRect(0, 0, W, H);

		if( W / obj.currentAnimation.frameCount > 3 ) {
			timeline.beginFill(0x333333);
			for( i in 0...obj.currentAnimation.frameCount+1 ) {
				var p = Std.int(i * W / obj.currentAnimation.frameCount);
				if( p == W ) p--;
				timeline.drawRect(p, 0, 1, H>>1);
			}
		}

		var int = new h2d.Interactive(W, H, timeline);
		timecursor = new h2d.Bitmap(h2d.Tile.fromColor(0x808080, 8, H), timeline);
		timecursor.x = -100;
		int.onPush = function(e) {
			var prevPause = obj.currentAnimation.pause;
			obj.currentAnimation.pause = true;
			obj.currentAnimation.setFrame( (e.relX / W) * obj.currentAnimation.frameCount );
			int.startDrag(function(e) {
				switch(e.kind ) {
				case ERelease:
					obj.currentAnimation.pause = prevPause;
					int.stopDrag();
				case EMove:
					obj.currentAnimation.setFrame( (e.relX / W) * obj.currentAnimation.frameCount );
				default:
				}
			});
		};

		var events = @:privateAccess obj.currentAnimation.events;
		for( i in 0...events.length ) {
			var el = events[i];
			if( el == null || el.length == 0 ) continue;
			var px = Std.int((i / obj.currentAnimation.frameCount) * W);
			timeline.beginFill(0xC0C0C0);
			timeline.drawRect(px, 0, 1, H);
			var py = -14;
			for( e in el ) {
				var tf = new h2d.Text(hxd.res.DefaultFont.get(), timeline);
				tf.text = e;
				tf.x = px - Std.int(tf.textWidth * 0.5);
				tf.y = py;
				tf.alpha = 0.5;
				py -= 15;
			}
		}

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
		if( timeline != null ) {
			timecursor.x = Std.int((obj.currentAnimation.frame / obj.currentAnimation.frameCount) * (scene.s2d.width - timecursor.tile.width));
		}
	}

	static var _ = FileTree.registerExtension(Model,["hmd","hsd","fbx"],{ icon : "cube" });

}