package hide.view;

import hide.prefab.Prefab in PrefabElement;

class Prefab extends FileView {

	var data : hide.prefab.Library;
	var context : hide.prefab.Context;
	var tabs : hide.comp.Tabs;

	var tools : hide.comp.Toolbar;
	var scene : hide.comp.Scene;
	var control : h3d.scene.CameraController;
	var properties : hide.comp.PropsEditor;
	var light : h3d.scene.DirLight;
	var lightDirection = new h3d.Vector( 1, 2, -4 );
	var tree : hide.comp.IconTree<PrefabElement>;

	override function getDefaultContent() {
		return haxe.io.Bytes.ofString(ide.toJSON(new hide.prefab.Library().save()));
	}

	override function save() {
		sys.io.File.saveContent(getPath(), ide.toJSON(data.save()));
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
		var sh = context.shared;
		sh.root2d.remove();
		sh.root3d.remove();
		sh.root2d = new h2d.Sprite();
		sh.root3d = new h3d.scene.Object();
		context.init();
		data.makeInstance(context);
		scene.s2d.addChild(sh.root2d);
		scene.s3d.addChild(sh.root3d);
		scene.init(props);
		tree.refresh(callb);
	}

	function allocName( prefix : String ) {
		var id = 0;
		while( data.getPrefabByName(prefix + id) != null )
			id++;
		return prefix + id;
	}

	function selectObject( elt : PrefabElement ) {
		properties.clear();
		var edit = new hide.prefab.EditContext(context);
		edit.prefabPath = state.path;
		edit.properties = properties;
		edit.scene = scene;
		elt.edit(edit);
	}

	function resetCamera() {
		var bounds = context.shared.root2d.getBounds();
		context.shared.root2d.x = Std.int(bounds.width) >> 1;
		context.shared.root2d.y = Std.int(bounds.height) >> 1;
		scene.resetCamera(context.shared.root3d, 1.5);
		control.loadFromCamera();
	}

	function addObject( e : PrefabElement ) {
		var roots = e.parent.children;
		undo.change(Custom(function(undo) {
			if( undo )
				roots.remove(e);
			else
				roots.push(e);
			refresh();
		}));
		refresh(function() {
			tree.setSelection([e]);
			selectObject(e);
		});
		if( e.parent == data && data.children.length == 1 )
			resetCamera();
	}

	function init() {
		data = new hide.prefab.Library();
		data.load(haxe.Json.parse(sys.io.File.getContent(getPath())));

		context = new hide.prefab.Context();
		context.onError = function(e) {
			ide.error(e);
		};
		context.init();
		scene.s2d.addChild(context.shared.root2d);
		scene.s3d.addChild(context.shared.root3d);

		data.makeInstance(context);

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
			resetCamera();
		else {
			scene.s3d.camera.pos.set(cam.x, cam.y, cam.z);
			scene.s3d.camera.target.set(cam.tx, cam.ty, cam.tz);
		}
		control.loadFromCamera();

		scene.onUpdate = update;
		scene.init(props);
		tools.saveDisplayKey = "SceneTools";

		tools.addButton("video-camera", "Reset Camera", resetCamera);
		tools.addToggle("sun-o", "Enable Lights/Shadows", function(v) {
			if( !v ) {
				for( m in context.shared.root3d.getMaterials() ) {
					m.mainPass.enableLights = false;
					m.shadows = false;
				}
			} else {
				for( m in context.shared.root3d.getMaterials() )
					h3d.mat.MaterialSetup.current.initModelMaterial(m);
			}
		},true);

		tools.addColor("Background color", function(v) {
			scene.engine.backgroundColor = v;
		}, scene.engine.backgroundColor);

		tools.addRange("Speed", function(v) {
			scene.speed = v;
		}, scene.speed);

		// BUILD scene tree

		function makeItem(o:PrefabElement) : hide.comp.IconTree.IconTreeItem<PrefabElement> {
			var p = o.getHideProps();
			return {
				data : o,
				text : o.name,
				icon : "fa fa-"+p.icon,
				children : o.iterator().hasNext(),
				state : { opened : true },
			};
		}
		tree.get = function(o:PrefabElement) {
			var objs = o == null ? data.children : Lambda.array(o);
			return [for( o in objs ) makeItem(o)];
		};
		tree.root.parent().contextmenu(function(e) {
			e.preventDefault();
			var current = tree.getCurrentOver();
			tree.setSelection(current == null ? [] : [current]);

			var registered = new Array<hide.comp.ContextMenu.ContextMenuItem>();
			var allRegs = @:privateAccess hide.prefab.Library.registeredElements;
			for( ptype in allRegs.keys() ) {
				if( ptype == "prefab" ) continue;
				var pcl = allRegs.get(ptype);
				var props = Type.createEmptyInstance(pcl).getHideProps();
				registered.push({
					label : props.name,
					click : function() {

						function make() {
							var p = Type.createInstance(pcl, [current == null ? data : current]);
							@:privateAccess p.type = ptype;
							p.name = allocName(ptype);
							return p;
						}

						if( props.fileSource != null )
							ide.chooseFile(props.fileSource, function(path) {
								if( path == null ) return;
								var p = make();
								p.source = path;
								addObject(p);
							});
						else
							addObject(make());
					}
				});
			}


			new hide.comp.ContextMenu([
				{ label : "New...", menu : registered },
				{ label : "Delete", enabled : current != null, click : function() {
					function deleteRec(roots:Array<PrefabElement>) {
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
							@:privateAccess deleteRec(o.children);
						}
					}
					deleteRec(data.children);
				} },
			]);
		});
		tree.init();
		tree.onClick = selectObject;
		scene.onResize = function() {
			scene.s2d.x = scene.s2d.width >> 1;
			scene.s2d.y = scene.s2d.height >> 1;
		};
		scene.onResize();
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

	static var _ = FileTree.registerExtension(Prefab,["pref"],{ icon : "sitemap", createNew : "Prefab" });

}