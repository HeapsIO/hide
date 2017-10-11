package hide.view;
import hxd.fmt.s3d.Data;

class SceneEditor extends FileView {

	var content : hxd.fmt.s3d.Library;
	var objRoot : h3d.scene.Object;
	var tabs : hide.comp.Tabs;

	var tools : hide.comp.Toolbar;
	var scene : hide.comp.Scene;
	var control : h3d.scene.CameraController;
	var properties : hide.comp.PropsEditor;
	var light : h3d.scene.DirLight;
	var lightDirection = new h3d.Vector( 1, 2, -4 );
	var tree : hide.comp.IconTree<BaseObject>;

	override function getDefaultContent() {
		return haxe.io.Bytes.ofString(ide.toJSON(new hxd.fmt.s3d.Library().save()));
	}

	override function save() {
		sys.io.File.saveContent(getPath(), ide.toJSON(content.save()));
	}

	override function onDisplay() {

		root.html('
			<div class="flex vertical">
				<div class="toolbar"></div>
				<div class="flex">
					<div class="scene">
					</div>
					<div class="tabs">
						<div class="tab" name="Scene" icon="sitemap">
							<div class="hide-block">
								<div class="hide-list">
									<div class="tree"></div>
								</div>
							</div>
							<div class="props"></div>
						</div>
						<div class="tab" name="Properties" icon="gears">
						</div>
					</div>
				</div>
			</div>
		');
		tools = new hide.comp.Toolbar(root.find(".toolbar"));
		tabs = new hide.comp.Tabs(root.find(".tabs"));
		properties = new hide.comp.PropsEditor(root.find(".props"), undo);
		scene = new hide.comp.Scene(root.find(".scene"));
		scene.onReady = init;
		tree = new hide.comp.IconTree(root.find(".tree"));
	}

	function refresh( ?callb ) {
		objRoot.remove();
		objRoot = content.makeInstance();
		scene.s3d.addChild(objRoot);
		scene.init(props);
		tree.refresh(callb);
	}

	function allocName( prefix : String ) {
		var id = 0;
		while( objRoot.getObjectByName(prefix + id) != null )
			id++;
		return prefix + id;
	}

	function selectObject( elt : BaseObject ) {
		var obj = objRoot.getObjectByName(elt.name);

		properties.clear();

		if( obj != null )
			properties.add(new Element('
			<div class="group" name="Position">
				<dl>
					<dt>Name</dt><dd><input field="name"></dd>
					<dt>X</dt><dd><input type="range" min="-10" max="10" field="x"/></dd>
					<dt>Y</dt><dd><input type="range" min="-10" max="10" field="y"/></dd>
					<dt>Z</dt><dd><input type="range" min="-10" max="10" field="z"/></dd>
					<dt>ScaleX</dt><dd><input type="range" min="0" max="5" field="scaleX"/></dd>
					<dt>ScaleY</dt><dd><input type="range" min="0" max="5" field="scaleY"/></dd>
					<dt>ScaleZ</dt><dd><input type="range" min="0" max="5" field="scaleZ"/></dd>
					<dt>Visible</dt><dd><input type="checkbox" field="visible"/></dd>
				</dl>
			</div>
			'),obj, function(name) {
				elt.x = obj.x;
				elt.y = obj.y;
				elt.z = obj.z;
				elt.name = obj.name;
				elt.scaleX = obj.scaleX;
				elt.scaleY = obj.scaleY;
				elt.scaleZ = obj.scaleZ;
				if( elt.x == 0 ) Reflect.deleteField(elt,"x");
				if( elt.y == 0 ) Reflect.deleteField(elt,"y");
				if( elt.z == 0 ) Reflect.deleteField(elt,"z");
				if( elt.scaleX == 1 ) Reflect.deleteField(elt, "scaleX");
				if( elt.scaleY == 1 ) Reflect.deleteField(elt, "scaleY");
				if( elt.scaleZ == 1 ) Reflect.deleteField(elt, "scaleZ");
				if( name == "name" )
					tree.refresh();
			});

		switch( elt.type ) {
		case Object:
			var elt : ObjectProperties = cast elt;
			var props = properties.add(new Element('
				<dl>
					<dt>Animation</dt><dd><select><option value="">-- Choose --</option></select>
					<dt title="Don\'t save animation changes">Lock</dt><dd><input type="checkbox" field="lock"></select>
				</dl>
			'),elt);

			var select = props.find("select");
			var anims = scene.listAnims(elt.modelPath);
			for( a in anims )
				new Element('<option>').attr("value", a).text(scene.animationName(a)).appendTo(select);
			if( elt.animationPath != null ) select.val(ide.getPath(elt.animationPath));
			select.change(function(_) {
				var v = select.val();
				var prev = elt.animationPath;
				if( v == "" ) {
					elt.animationPath = null;
					obj.stopAnimation();
				} else {
					obj.playAnimation(scene.loadAnimation(v)).loop = true;
					if( elt.lock ) return;
					elt.animationPath = ide.makeRelative(v);
				}
				var newValue = elt.animationPath;
				undo.change(Custom(function(undo) {
					elt.animationPath = undo ? prev : newValue;
					if( elt.animationPath == null ) {
						obj.stopAnimation();
						select.val("");
					} else {
						obj.playAnimation(scene.loadAnimation(v)).loop = true;
						select.val(v);
					}
				}));
			});

		case Constraint:
			var elt : ConstraintProperties = cast elt;
			var props = properties.add(new Element('
				<dl>
					<dt>Name</dt><dd><input field="name"/></dd>
					<dt>Source</dt><dd><select field="source"><option value="">-- Choose --</option></select>
					<dt>Target</dt><dd><select field="attach"><option value="">-- Choose --</option></select>
				</dl>
			'),elt, function(field) if( field == "name" ) tree.refresh() else refresh());

			for( select in [props.find("[field=source]"), props.find("[field=attach]")] ) {
				for( path in getNamedObjects() ) {
					var parts = path.split(".");
					var opt = new Element("<option>").attr("value", path).html([for( p in 1...parts.length ) "&nbsp; "].join("") + parts.pop());
					select.append(opt);
				}
				select.val(Reflect.field(elt, select.attr("field")));
			}

		case Trail:

			var elt : ExtraProperties = cast elt;
			var obj : h3d.scene.Trail = cast obj;
			var props = properties.add(new Element('
			<div class="group" name="Trail Properties">
				<dl>
					<dt>Angle</dt><dd><input type="range" field="angle" scale="${180/Math.PI}" min="0" max="${Math.PI*2}"/></dd>
					<dt>Duration</dt><dd><input type="range" field="duration" min="0" max="10"/></dd>
					<dt>Size Start</dt><dd><input type="range" field="sizeStart" min="0" max="10"/></dd>
					<dt>Size End</dt><dd><input type="range" field="sizeEnd" min="0" max="10"/></dd>
					<dt>Movement Min.</dt><dd><input type="range" field="movementMin" min="0" max="1"/></dd>
					<dt>Movement Max.</dt><dd><input type="range" field="movementMax" min="0" max="1"/></dd>
					<dt>Texture</dt><dd><input type="texture" field="texture"/></dd>
				</dl>
			</div>
			'),obj, function(_) {
				elt.data = obj.save();
			});

		default:
		}
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

		function getRec(path:Array<String>, o:h3d.scene.Object) {
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

		for( o in objRoot )
			getRec([], o);

		return out;
	}

	function init() {
		content = new hxd.fmt.s3d.Library();
		content.load(haxe.Json.parse(sys.io.File.getContent(getPath())));
		objRoot = content.makeInstance();
		scene.s3d.addChild(objRoot);

		light = scene.s3d.find(function(o) return Std.instance(o, h3d.scene.DirLight));
		if( light == null ) {
			light = new h3d.scene.DirLight(new h3d.Vector(), scene.s3d);
			light.enableSpecular = true;
		} else
			light = null;

		control = new h3d.scene.CameraController(scene.s3d);

		this.saveDisplayKey = "Scene:" + state.path;

		var cam = getDisplayState("Camera");
		if( cam == null )
			scene.resetCamera(scene.s3d, 1.5);
		else {
			scene.s3d.camera.pos.set(cam.x, cam.y, cam.z);
			scene.s3d.camera.target.set(cam.tx, cam.ty, cam.tz);
		}
		control.loadFromCamera();

		scene.onUpdate = update;
		scene.init(props);
		tools.saveDisplayKey = "SceneTools";

		tools.addButton("video-camera", "Reset Camera", function() {
			scene.resetCamera(objRoot,1.5);
			control.loadFromCamera();
		});

		tools.addToggle("sun-o", "Enable Lights/Shadows", function(v) {
			if( !v ) {
				for( m in objRoot.getMaterials() ) {
					m.mainPass.enableLights = false;
					m.shadows = false;
				}
			} else {
				for( m in objRoot.getMaterials() )
					h3d.mat.MaterialSetup.current.initModelMaterial(m);
			}
		},true);

		tools.addColor("Background color", function(v) {
			scene.engine.backgroundColor = v;
		}, scene.engine.backgroundColor);

		// BUILD scene tree

		function makeItem(o:BaseObject) : hide.comp.IconTree.IconTreeItem<BaseObject> {
			return {
				data : o,
				text : o.name,
				icon : "fa fa-"+switch( o.type ) {
				case Object: "cube";
				case Constraint: "lock";
				case Particles: "snowflake-o";
				case Trail: "toggle-on";
				},
				children : o.children != null && o.children.length > 0,
				state : { opened : true },
			};
		}
		tree.get = function(o:BaseObject) {
			var objs = o == null ? content.data.content : o.children;
			return [for( o in objs ) makeItem(o)];
		};
		tree.root.parent().contextmenu(function(e) {
			e.preventDefault();
			var current = tree.getCurrentOver();
			tree.setSelection(current == null ? [] : [current]);

			new hide.comp.ContextMenu([
				{ label : "New...", menu : [
					{ label : "Model", click : function() {
						ide.chooseFile(["fbx", "hmd"], function(path) {
							if( path == null ) return;
							var props : ObjectProperties = {
								type : Object,
								name : allocName("Object"),
								modelPath : path,
							};
							addObject(props, current);
						});
					} },
					{ label : "Particles", click : function() {
						var parts = new h3d.parts.GpuParticles();
						parts.addGroup();
						var props : ExtraProperties = {
							type : Particles,
							name : allocName("Particles"),
							data : parts.save(),
						};
						addObject(props, current);
					} },
					{ label : "Trail", click : function() {
						var props : ExtraProperties = {
							type : Trail,
							name : allocName("Trail"),
							data : new h3d.scene.Trail().save(),
						};
						addObject(props, current);
					} },
					{ label : "Constraint", click : function() {
						var props : ConstraintProperties = {
							type : Constraint,
							name : allocName("Constraint"),
							source : "",
							attach : "",
						};
						addObject(props, current);
					} },
				] },
				{ label : "Delete", enabled : current != null, click : function() {
					function deleteRec(roots:Array<BaseObject>) {
						for( o in roots ) {
							if( o == current ) {
								properties.clear();
								var index = roots.indexOf(o);
								roots.remove(o);
								undo.change(Custom(function(undo) {
									if( undo ) roots.insert(index, o) else roots.remove(o);
									refresh();
								}));
								refresh();
								return;
							}
							if( o.children != null ) deleteRec(o.children);
						}
					}
					deleteRec(content.data.content);
				} },
			]);
		});
		tree.init();
		tree.onClick = selectObject;
	}

	function addObject( props : BaseObject, parent : BaseObject ) {
		var roots = content.data.content;
		if( parent != null ) {
			roots = parent.children;
			if( roots == null ) parent.children = roots = [];
		}
		roots.push(props);
		undo.change(Custom(function(undo) {
			if( undo ) {
				roots.remove(props);
				if( roots.length == 0 && parent != null ) Reflect.deleteField(parent, "children");
			} else {
				roots.push(props);
				if( parent != null ) parent.children = roots;
			}
			refresh();
		}));
		refresh(function() {
			tree.setSelection([props]);
			selectObject(props);
		});
		if( parent == null && roots.length == 1 ) {
			scene.resetCamera(objRoot, 1.5);
			control.loadFromCamera();
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
	}

	static var _ = FileTree.registerExtension(SceneEditor,["s3d"],{ icon : "sitemap", createNew : "Scene 3D" });

}