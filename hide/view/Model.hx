package hide.view;

class Model extends FileView {

	var tools : hide.comp.Toolbar;
	var obj : h3d.scene.Object;
	var sceneEditor : hide.comp.SceneEditor;
	var tree : hide.comp.SceneTree;
	var tabs : hide.comp.Tabs;
	var overlay : Element;
	var eventList : Element;

	var plight : hrt.prefab.Prefab;
	var light : h3d.scene.Object;
	var lightDirection : h3d.Vector;

	var aspeed : hide.comp.Range;
	var aloop : { function toggle( v : Bool ) : Void; var element : Element; }
	var apause : { function toggle( v : Bool ) : Void; var element : Element; };
	var aretarget : { var element : Element; };
	var timeline : h2d.Graphics;
	var timecursor : h2d.Bitmap;
	var frameIndex : h2d.Text;
	var currentAnimation : { file : String, name : String };
	var cameraMove : Void -> Void;
	var scene(get,never) : hide.comp.Scene;
	var rootPath : String;
	var root : hrt.prefab.Prefab;
	var selectedAxes : h3d.scene.Object;


	override function save() {
		if(!modified) return;
		// Save current Anim data
		if( currentAnimation != null ) {
			var hideData = loadProps();

			var events : Array<{ frame : Int, data : String }> = [];
			for(i in 0 ... obj.currentAnimation.events.length){
				if( obj.currentAnimation.events[i] == null) continue;
				for( e in obj.currentAnimation.events[i])
					events.push({frame:i, data:e});
			}
			hideData.animations.set(currentAnimation.file.split("/").pop(), {events : events} );

			var bytes = new haxe.io.BytesOutput();
			bytes.writeString(haxe.Json.stringify(hideData, "\t"));
			hxd.File.saveBytes(getPropsPath(), bytes.getBytes());
		}
		super.save();
	}

	override function onFileChanged( wasDeleted : Bool, rebuildView = true ) {
		if (wasDeleted ) {
			super.onFileChanged(wasDeleted);
		} else if (element.find(".heaps-scene").length == 0) {
			super.onFileChanged(wasDeleted);
		} else {
			super.onFileChanged(wasDeleted, false);
			onRefresh();
		}
	}

	function loadProps() {
		var propsPath = getPropsPath();
		var hideData : h3d.prim.ModelCache.HideProps;
		if( sys.FileSystem.exists(propsPath) )
			hideData = haxe.Json.parse(sys.io.File.getContent(propsPath));
		else
			hideData = { animations : {} };
		return hideData;
	}

	function getPropsPath() {
		var path = config.get("hmd.savePropsByAnimation") ? currentAnimation.file : getPath();
		var parts = path.split(".");
		parts.pop();
		parts.push("props");
		return ide.getPath(parts.join("."));
	}

	override function onDisplay() {
		element.html('
			<div class="flex vertical">
				<div class="toolbar"></div>
				<div class="flex-elt">
					<div class="heaps-scene">
						<div class="hide-scroll hide-scene-layer">
							<div class="tree"></div>
						</div>
					</div>
					<div class="tabs">
						<div class="tab expand" name="Model" icon="sitemap">
							<div class="hide-block">
								<table>
								<tr>
								<td><input type="button" style="width:145px" value="Export"/>
								<td><input type="button" style="width:145px" value="Import"/>
								</tr>
								</table>
								<div class="hide-scene-tree hide-list">
								</div>
							</div>
							<div class="props hide-scroll">
							</div>
						</div>
						<div class="tab expand" name="Animation" icon="cog">
							<div class="event-editor"> </div>
						</div>
					</div>

				</div>
			</div>
		');
		tools = new hide.comp.Toolbar(null,element.find(".toolbar"));
		overlay = element.find(".hide-scene-layer .tree");
		tabs = new hide.comp.Tabs(null,element.find(".tabs"));
		eventList = element.find(".event-editor");

		if( rootPath == null )
			rootPath = config.getLocal("scene.renderProps");

		if( rootPath != null )
			root = ide.loadPrefab(rootPath, hrt.prefab.Library);

		if( root == null ) {
			var def = new hrt.prefab.Library();
			new hrt.prefab.RenderProps(def).name = "renderer";
			var l = new hrt.prefab.Light(def);
			l.name = "sunLight";
			l.kind = Directional;
			l.power = 1.5;
			var q = new h3d.Quat();
			q.initDirection(new h3d.Vector(-0.28,0.83,-0.47));
			var a = q.toEuler();
			l.rotationX = Math.round(a.x * 180 / Math.PI);
			l.rotationY = Math.round(a.y * 180 / Math.PI);
			l.rotationZ = Math.round(a.z * 180 / Math.PI);
			l.shadows.mode = Dynamic;
			l.shadows.size = 1024;
			root = def;
		}

		sceneEditor = new hide.comp.SceneEditor(this, root);
		sceneEditor.editorDisplay = false;
		sceneEditor.onRefresh = onRefresh;
		sceneEditor.onUpdate = update;
		sceneEditor.view.keys = new hide.ui.Keys(null); // Remove SceneEditor Shortcuts
		sceneEditor.view.keys.register("save", function() {
			save();
			skipNextChange = true;
			modified = false;
		});

		element.find(".hide-scene-tree").first().append(sceneEditor.tree.element);
		element.find(".props").first().append(sceneEditor.properties.element);
		element.find(".heaps-scene").first().append(sceneEditor.scene.element);
		sceneEditor.tree.element.addClass("small");

		element.find("input[value=Export]").click(function(_) {
			ide.chooseFileSave("renderer.prefab", function(sel) if( sel != null ) ide.savePrefab(sel, root));
		});
		element.find("input[value=Import]").click(function(_) {
			ide.chooseFile(["prefab"], function(f) {
				if( ide.loadPrefab(f, hrt.prefab.RenderProps) == null ) {
					ide.error("This prefab does not have renderer properties");
					return;
				}
				rootPath = f;
				rebuild();
			});
		});
	}

	inline function get_scene() return sceneEditor.scene;

	function selectMaterial( m : h3d.mat.Material ) {
		var properties = sceneEditor.properties;
		properties.clear();

		properties.add(new Element('
			<div class="group" name="Textures">
				<dl>
					<dt>Base</dt><dd><input type="texture" field="texture"/></dd>
					<dt>Spec</dt><dd><input type="texture" field="specularTexture"/></dd>
					<dt>Normal</dt><dd><input type="texture" field="normalMap"/></dd>
				</dl>
			</div>
			<br/>
		'),m);


		var e = properties.add(new Element('
			<div class="group" name="Material ${m.name}">
			</div>
			<dl>
				<dt></dt><dd><input type="button" value="Reset Defaults" class="reset"/></dd>
				<dt></dt><dd><input type="button" value="Save" class="save"/></dd>
			</dl>
			<br/>
		'));

		properties.addMaterial(m, e.find(".group > .content"));
		e.find(".reset").click(function(_) {
			var old = m.props;
			m.props = m.getDefaultModelProps();
			selectMaterial(m);
			undo.change(Field(m, "props", old), selectMaterial.bind(m));
		});
		e.find(".save").click(function(_) {
			h3d.mat.MaterialSetup.current.saveMaterialProps(m);
		});
	}

	function selectObject( obj : h3d.scene.Object ) {
		selectedAxes.follow = obj;

		var properties = sceneEditor.properties;
		properties.clear();

		var objectCount = 1 + obj.getObjectsCount();
		var meshes = obj.getMeshes();
		var vertexCount = 0, triangleCount = 0, materialDraws = 0, materialCount = 0, bonesCount = 0;
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
			var multi = Std.downcast(m, h3d.scene.MultiMaterial);
			var skin = Std.downcast(m, h3d.scene.Skin);
			if( skin != null )
				bonesCount += skin.getSkinData().allJoints.length;
			var count = if( skin != null && skin.getSkinData().splitJoints != null )
				skin.getSkinData().splitJoints.length;
			else if( multi != null )
				multi.materials.length
			else
				1;
			materialDraws += count;
		}

		var e = properties.add(new Element('
			<div class="group" name="Properties">
				<dl>
					<dt>X</dt><dd><input field="x"/></dd>
					<dt>Y</dt><dd><input field="y"/></dd>
					<dt>Z</dt><dd><input field="z"/></dd>
					<dt>Attach</dt><dd><select class="follow"><option value="">--- None ---</option></select></dd>
				</dl>
			</div>
			<div class="group" name="Info">
				<dl>
					<dt>Objects</dt><dd>$objectCount</dd>
					<dt>Meshes</dt><dd>${meshes.length}</dd>
					<dt>Materials</dt><dd>$materialCount</dd>
					<dt>Draws</dt><dd>$materialDraws</dd>
					<dt>Bones</dt><dd>$bonesCount</dd>
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
			var sk = Std.downcast(o, h3d.scene.Skin);
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

	function makeAxes() {
		var g = new h3d.scene.Graphics(scene.s3d);
		g.lineStyle(1,0xFF0000);
		g.lineTo(1,0,0);
		g.lineStyle(1,0x00FF00);
		g.moveTo(0,0,0);
		g.lineTo(0,1,0);
		g.lineStyle(1,0x0000FF);
		g.moveTo(0,0,0);
		g.lineTo(0,0,1);
		g.lineStyle();

		for(m in g.getMaterials()) {
			m.mainPass.setPassName("overlay");
			m.mainPass.depth(false, Always);
		}

		return g;
	}

	function onRefresh() {
		var r = root.get(hrt.prefab.RenderProps);
		if( r != null ) r.applyProps(scene.s3d.renderer);

		plight = root.getAll(hrt.prefab.Light)[0];
		if( plight != null ) {
			this.light = sceneEditor.context.shared.contexts.get(plight).local3d;
			lightDirection = this.light.getLocalDirection();
		}

		undo.onChange = function() {};

		if (obj != null)
			obj.remove();
		obj = scene.loadModel(state.path, true, true);
		new h3d.scene.Object(scene.s3d).addChild(obj);

		var autoHide : Array<String> = config.get("scene.autoHide");

		function hidePropsRec( obj : h3d.scene.Object ) {
			for(n in autoHide)
				if(obj.name != null && obj.name.indexOf(n) == 0)
					obj.visible = false;
			for( o in obj )
				hidePropsRec(o);
		}
		hidePropsRec(obj);

		if( tree != null ) tree.remove();
		tree = new hide.comp.SceneTree(obj, overlay, obj.name != null);
		tree.onSelectMaterial = selectMaterial;
		tree.onSelectObject = selectObject;

		this.saveDisplayKey = "Model:" + state.path;
		tree.saveDisplayKey = this.saveDisplayKey;

		tools.element.empty();
		var anims = scene.listAnims(getPath());

		if( anims.length > 0 ) {
			var sel = tools.addSelect("play-circle");
			var content = [for( a in anims ) {
				var label = scene.animationName(a);
				{ label : label, value : a }
			}];
			content.unshift({ label : "-- no anim --", value : null });
			sel.setContent(content);
			sel.onSelect = setAnimation;
		}

		tools.saveDisplayKey = "ModelTools";

		tools.addButton("video-camera", "Reset Camera", function() {
			sceneEditor.resetCamera();
		});

		var axes = makeAxes();
		axes.visible = false;

		selectedAxes = makeAxes();
		selectedAxes.visible = false;

		tools.addToggle("location-arrow", "Toggle Axis", function(v) {
			axes.visible = v;
			selectedAxes.visible = v;
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

		aretarget = tools.addToggle("share-square-o", "Retarget Animation", function(b) {
			setRetargetAnim(b);
		});

		aspeed = tools.addRange("Animation speed", function(v) {
			if( obj.currentAnimation != null ) obj.currentAnimation.speed = v;
		}, 1, 0, 2);

		initConsole();

		sceneEditor.onResize = buildTimeline;
		setAnimation(null);
	}

	function setRetargetAnim(b:Bool) {
		for( m in obj.getMeshes() ) {
			var sk = Std.downcast(m, h3d.scene.Skin);
			if( sk == null ) continue;
			for( j in sk.getSkinData().allJoints ) {
				if( j.parent == null ) continue; // skip root join (might contain feet translation)
				j.retargetAnim = b;
			}
		}
	}

	function initConsole() {
		var c = new h2d.Console(hxd.res.DefaultFont.get(), scene.s2d);
		c.addCommand("rotate",[{ name : "speed", t : AFloat }], function(r) {
			cameraMove = function() {
				var cam = scene.s3d.camera;
				var dir = cam.pos.sub(cam.target);
				dir.z = 0;
				var angle = Math.atan2(dir.y, dir.x);
				angle += r * hxd.Timer.tmod * 0.01;
				var ray = dir.length();
				cam.pos.set(
					Math.cos(angle) * ray + cam.target.x,
					Math.sin(angle) * ray + cam.target.y,
					cam.pos.z);
				sceneEditor.cameraController.loadFromCamera();
			};
		});
		c.addCommand("stop", [], function() {
			cameraMove = null;
		});
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
				ide.chooseFileSave(this.getPath().substr(0,-4)+"_"+currentAnimation.name+"_dump.txt", function(file) {
					var lib = @:privateAccess scene.loadHMD(ide.getPath(currentAnimation.file),true);
					var hmd = lib.header;
					hmd.data = lib.getData();
					sys.io.File.saveContent(ide.getPath(file), new hxd.fmt.hmd.Dump().dump(hmd));
				});
			} },
		];
		return menu.concat(arr);
	}

	function setAnimation( file : String ) {
		scene.setCurrent();
		if( timeline != null ) {
			timeline.remove();
			timeline = null;
		}
		apause.toggle(false);
		aloop.toggle(true);
		aspeed.value = 1;
		aloop.element.toggle(file != null);
		aspeed.element.toggle(file != null);
		apause.element.toggle(file != null);
		aretarget.element.toggle(file != null);
		if( file == null ) {
			obj.stopAnimation();
			currentAnimation = null;
			return;
		}
		var anim = scene.loadAnimation(file);
		currentAnimation = { file : file, name : scene.animationName(file) };

		var hideData = loadProps();
		var animData = hideData.animations.get(currentAnimation.file.split("/").pop());
		if( animData != null && animData.events != null )
			anim.setEvents(animData.events);

		obj.playAnimation(anim);
		buildTimeline();
		buildEventPanel();
		modified = false;
	}

	function buildEventPanel(){
		eventList.empty();
		var events = @:privateAccess obj.currentAnimation.events;
		var fbxEventList = new Element('<div></div>');
		fbxEventList.append(new Element('<div class="title"><label>Events</label></div>'));
		function addEvent( n : String, f : Float, root : Element ){
			var e = new Element('<div class="event"><span class="label">"$n"</span><span class="label">$f</span></div>');
			root.append(e);
		}
		if(events != null) {
			for( i in 0...events.length ) {
				var el = events[i];
				if( el == null || el.length == 0 ) continue;
				for( e in el )
					addEvent(e, i, fbxEventList);
			}
		}
		eventList.append(fbxEventList);
	}

	function buildTimeline() {
		scene.setCurrent();
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
		timeline.beginFill(0x101010, 0.8);
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
		int.enableRightButton = true;
		timecursor = new h2d.Bitmap(h2d.Tile.fromColor(0x808080, 8, H), timeline);
		timecursor.x = -100;
		int.onPush = function(e) {
			if( hxd.Key.isDown( hxd.Key.MOUSE_LEFT) ){
				var prevPause = obj.currentAnimation.pause;
				obj.currentAnimation.pause = true;
				obj.currentAnimation.setFrame( (e.relX / W) * obj.currentAnimation.frameCount );
				int.startCapture(function(e) {
					switch(e.kind ) {
					case ERelease:
						obj.currentAnimation.pause = prevPause;
						int.stopCapture();
					case EMove:
						obj.currentAnimation.setFrame( (e.relX / W) * obj.currentAnimation.frameCount );
					default:
					}
				});
			}
			else if( hxd.Key.isDown( hxd.Key.MOUSE_RIGHT) ){
				var deleteEvent = function(s:String, f:Int){
					obj.currentAnimation.events[f].remove(s);
					if(obj.currentAnimation.events[f].length == 0)
						obj.currentAnimation.events[f] = null;
					buildTimeline();
					buildEventPanel();
					modified = true;
				}
				var addEvent = function(s:String, f:Int){
					obj.currentAnimation.addEvent(f, s);
					buildTimeline();
					buildEventPanel();
					modified = true;
				}
				var frame = Math.round((e.relX / W) * obj.currentAnimation.frameCount);
				var menuItems : Array<hide.comp.ContextMenu.ContextMenuItem> = [
					{ label : "New", click: function(){ addEvent("NewEvent", frame); }},
				];
				if(obj.currentAnimation.events != null && obj.currentAnimation.events[frame] != null){
					for(e in obj.currentAnimation.events[frame])
						menuItems.push({ label : "Delete " + e, click: function(){ deleteEvent(e, frame); }});
				}
				new hide.comp.ContextMenu(menuItems);
			}
		}

		frameIndex = new h2d.Text(hxd.res.DefaultFont.get(), timecursor);
		frameIndex.y = -30.0;
		frameIndex.textAlign = Center;
		frameIndex.text = "0";
		frameIndex.alpha = 0.5;

		var events = @:privateAccess obj.currentAnimation.events;
		if( events != null ) {
			for( i in 0...events.length ) {
				var el = events[i];
				if( el == null || el.length == 0 ) continue;
				var px = Std.int((i / obj.currentAnimation.frameCount) * W);
				timeline.beginFill(0xC0C0C0);
				timeline.drawRect(px, 0, 1, H);
				var py = -20;
				for(j in 0 ... el.length ) {
					var event = events[i][j];
					var tf = new h2d.TextInput(hxd.res.DefaultFont.get(), timeline);
					tf.backgroundColor = 0xFF0000;
					tf.onFocusLost = function(e){
						events[i][j] = tf.text;
						buildTimeline();
						buildEventPanel();
						modified = true;
					}
					tf.text = event;
					tf.x = px - Std.int(tf.textWidth * 0.5);
					tf.y = py;
					tf.alpha = 0.5;
					py -= 15;
					var dragIcon = new h2d.Bitmap(null, timeline);
					dragIcon.scaleX = 5.0;
					dragIcon.scaleY = 2.0;
					dragIcon.color.set(0.34, 0.43, 0, 1);
					dragIcon.x = px - (dragIcon.scaleX * 0.5 * 5);
					dragIcon.y = py;
					py -= Std.int(dragIcon.scaleY * 5 * 2);
					var dragInter = new h2d.Interactive(5, 5, dragIcon, null );
					dragInter.x = 0;
					dragInter.y = 0;
					var curFrame = i;
					var curPos = (curFrame / obj.currentAnimation.frameCount) * W;
					dragInter.onPush = function(e) {
						if( hxd.Key.isDown( hxd.Key.MOUSE_LEFT) ){
							var startFrame = curFrame;
							dragInter.startCapture(function(e) {
								switch( e.kind ) {
								case ERelease:
									dragInter.stopCapture();
									buildTimeline();
									buildEventPanel();
									if( curFrame != startFrame )
										modified = true;
								case EMove:
									var newFrame = Math.round(( (curPos + (e.relX - 2.5) * dragIcon.scaleX ) / W ) * obj.currentAnimation.frameCount);
									if( newFrame >= 0 && newFrame <= obj.currentAnimation.frameCount ) {
										events[curFrame].remove(event);
										if(events[newFrame] == null)
											events[newFrame] = [];
										events[newFrame].insert(0, event);
										curFrame = newFrame;
										buildTimeline();
										buildEventPanel();
										@:privateAccess dragInter.scene = scene.s2d;
									}
								default:
								}
							});
						}
					};
				}
			}
		}
	}

	function update(dt:Float) {
		var cam = scene.s3d.camera;
		saveDisplayState("Camera", { x : cam.pos.x, y : cam.pos.y, z : cam.pos.z, tx : cam.target.x, ty : cam.target.y, tz : cam.target.z });
		if( light != null ) {
			if( sceneEditor.isSelected(plight) )
				lightDirection = light.getLocalDirection();
			else {
				var angle = Math.atan2(cam.target.y - cam.pos.y, cam.target.x - cam.pos.x);
				light.setDirection(new h3d.Vector(
					Math.cos(angle) * lightDirection.x - Math.sin(angle) * lightDirection.y,
					Math.sin(angle) * lightDirection.x + Math.cos(angle) * lightDirection.y,
					lightDirection.z
				));
			}
		}
		if( timeline != null ) {
			timecursor.x = Std.int((obj.currentAnimation.frame / obj.currentAnimation.frameCount) * (scene.s2d.width - timecursor.tile.width));
			frameIndex.text = untyped obj.currentAnimation.frame.toFixed(2);
		}
		if( cameraMove != null )
			cameraMove();
	}

	static var _ = FileTree.registerExtension(Model,["hmd","hsd","fbx"],{ icon : "cube" });

}