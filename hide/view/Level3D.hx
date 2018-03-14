package hide.view;
import hxd.Math;

import hide.prefab.Prefab in PrefabElement;

class LevelEditContext extends hide.prefab.EditContext {

	public var elt : PrefabElement;

	public function new(ctx, elt) {
		super(ctx);
		this.elt = elt;
	}

	override function rebuild() {
		properties.clear();
		cleanup();
		elt.edit(this);
	}

	public function cleanup() {
		for( c in cleanups.copy() )
			c();
		cleanups = [];
	}

}

typedef AxesOptions = {
	?x: Bool,
	?y: Bool,
	?z: Bool
}

enum TransformMode {
	MoveX;
	MoveY;
	MoveZ;
	MoveXY;
	MoveYZ;
	MoveZX;
	RotateX;
	RotateY;
	RotateZ;
}

class Gizmo3D extends h3d.scene.Object {

	var gizmo: h3d.scene.Object;
	var scene : hide.comp.Scene;

	var updateFunc: Float -> Void;

	public var startMove: Void -> Void;
	public var onMove: h3d.Vector -> h3d.Quat -> Void;
	public var finishMove: Void -> Void;

	// var dragAxes: AxesOptions;
	// var startPos: h3d.Vector;
	// var startDragPt: h3d.col.Point;
	// var dragPlane: h3d.col.Plane;
	var debug: h3d.scene.Graphics;

	

	public function new(scene: hide.comp.Scene) {
		super(scene.s3d);
		this.scene = scene;
		gizmo = hxd.Res.gizmo.toHmd().makeObject();
		addChild(gizmo);
		debug = new h3d.scene.Graphics(scene.s3d);

		function setup(objname, color, mode: TransformMode) {
			var o = gizmo.getObjectByName(objname);
			var mat = o.getMaterials()[0];
			mat.mainPass.setPassName("alpha");
			mat.mainPass.depth(false, Always);
			var m = o.getMeshes()[0];
			var int = new h3d.scene.Interactive(m.getCollider(), scene.s3d);
			var highlight = hxd.Math.colorLerp(color, 0xffffff, 0.5);
			color = hxd.Math.colorLerp(color, 0, 0.2);
			mat.color.setColor(color);
			int.onOver = function(e : hxd.Event) {
				mat.color.setColor(highlight);
			}
			int.onOut = function(e : hxd.Event) {
				mat.color.setColor(color);
			}

			int.onPush = function(e) {
				if(startMove != null) startMove();
				var startPos = getAbsPos().pos().toPoint();
				var startRot = getRotationQuat();
				var dragPlane = null;
				var cam = scene.s3d.camera;
				var norm = startPos.sub(cam.pos.toPoint());
				switch(mode) {
					case MoveX: norm.x = 0;
					case MoveY: norm.y = 0;
					case MoveZ: norm.z = 0;
					case MoveXY: norm.set(0, 0, 1);
					case MoveYZ: norm.set(1, 0, 0);
					case MoveZX: norm.set(0, 1, 0);
					case RotateX: norm.set(1, 0, 0);
					case RotateY: norm.set(0, 1, 0);
					case RotateZ: norm.set(0, 0, 1);
				}
				norm.normalize();
				dragPlane = h3d.col.Plane.fromNormalPoint(norm, startPos);
				var startDragPt = getDragPoint(dragPlane);
				updateFunc = function(dt) {
					var curPt = getDragPoint(dragPlane);
					var delta = curPt.sub(startDragPt);
					if(mode == MoveX || mode == MoveXY || mode == MoveZX) x = startPos.x + delta.x;
					if(mode == MoveY || mode == MoveYZ || mode == MoveXY) y = startPos.y + delta.y;
					if(mode == MoveZ || mode == MoveZX || mode == MoveYZ) z = startPos.z + delta.z;

					if(mode == RotateX || mode == RotateY || mode == RotateZ) {
						// debug.clear();
						// debug.lineStyle(2, 0x00ff00, 1.0);
						// debug.moveTo(startDragPt.x, startDragPt.y, startDragPt.z);
						// debug.lineTo(startPos.x, startPos.y, startPos.z);
						// debug.lineTo(curPt.x, curPt.y, curPt.z);
						var v1 = startDragPt.sub(startPos);
						v1.normalize();
						var v2 = curPt.sub(startPos);
						v2.normalize();

						var rot = startRot.clone();
						var angle = Math.atan2(v1.cross(v2).dot(norm), v1.dot(v2));
						var delta = new h3d.Quat(norm.x, norm.y, norm.z, angle);
						// rot.multiply(rot, delta);
						// rot.normalize();
						rot.initRotateAxis(norm.x, norm.y, norm.z, angle);
						setRotationQuat(rot);
					}

					if(onMove != null) onMove(null, null);
				}
			}
			int.onRelease = function(e) {
				updateFunc = null;
				if(finishMove != null) finishMove();
			}
		}

		setup("xAxis", 0xff0000, MoveX);
		setup("yAxis", 0x00ff00, MoveY);
		setup("zAxis", 0x0000ff, MoveZ);
		setup("xy", 0xffff00, MoveXY);
		setup("xz", 0xffff00, MoveZX);
		setup("yz", 0xffff00, MoveYZ);
		setup("xRotate", 0xff0000, RotateX);
		setup("yRotate", 0x00ff00, RotateY);
		setup("zRotate", 0x0000ff, RotateZ);
	}


	function getDragPoint(plane: h3d.col.Plane) {
		var cam = scene.s3d.camera;
		var ray = cam.rayFromScreen(scene.s2d.mouseX, scene.s2d.mouseY);
		// debug.clear();
		// debug.lineStyle(3, 0xff0000, 1.0);
		// debug.moveTo(ray.px, ray.py, ray.pz);
		// debug.lineTo(ray.px+ray.lx*500, ray.py+ray.ly*500, ray.pz+ray.lz*500);
		return ray.intersect(plane);
	}

	// function startDrag() {
	// 	startPos = getAbsPos().pos();
	// 	dragPlane = h3d.col.Plane.Z(0);
	// 	startDragPt = getDragPoint();
	// }

	// function stopDrag() {
	// 	dragPlane = null;
	// 	startPos = null;
	// 	startDragPt = null;
	// }
	
	public function update(dt) {
		var cam = this.getScene().camera;
		var gpos = gizmo.getAbsPos().pos();
		var distToCam = cam.pos.sub(gpos).length();
		gizmo.setScale(distToCam / 30 );

		if(updateFunc != null) {
			updateFunc(dt);
		}

		// if(startDragPt != null) {
		// 	var curPt = getDragPoint();
		// 	if(curPt != null) {
		// 		// debug.clear();
		// 		// debug.lineStyle(3, 0xff0000, 1.0);
		// 		// debug.moveTo(startPos.x, startPos.y, startPos.z);
		// 		// debug.lineTo(curPt.x, curPt.y, curPt.z);
		// 		// var delta = curPt.sub(startDragPt);
		// 		x = startPos.x + curPt.x - startDragPt.x;
		// 	}
		// }
	}
}

class Level3D extends FileView {

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

	var curEdit : LevelEditContext;
	var gizmo : Gizmo3D;

	// autoSync
	var autoSync : Bool;
	var currentVersion : Int = 0;
	var lastSyncChange : Float = 0.;
	var currentSign : String;

	override function getDefaultContent() {
		return haxe.io.Bytes.ofString(ide.toJSON(new hide.prefab.Library().save()));
	}

	override function onFileChanged(wasDeleted:Bool) {
		if( !wasDeleted ) {
			// double check if content has changed
			var content = sys.io.File.getContent(getPath());
			var sign = haxe.crypto.Md5.encode(content);
			if( sign == currentSign )
				return;
		}
		super.onFileChanged(wasDeleted);
	}

	override function save() {
		var content = ide.toJSON(data.save());
		currentSign = haxe.crypto.Md5.encode(content);
		sys.io.File.saveContent(getPath(), content);
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
		currentVersion = undo.currentID;
	}

	function refresh( ?callb ) {
		var sh = context.shared;
		sh.root2d.remove();
		sh.root3d.remove();
		for( f in sh.cleanups )
			f();
		sh.root2d = new h2d.Sprite();
		sh.root3d = new h3d.scene.Object();
		sh.cleanups = [];
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
		if( curEdit != null )
			curEdit.cleanup();
		var edit = new LevelEditContext(context, elt);
		edit.prefabPath = state.path;
		edit.properties = properties;
		edit.scene = scene;
		edit.view = this;
		edit.cleanups = [];
		edit.rebuild();
		curEdit = edit;
	}

	function resetCamera() {
		var bounds = context.shared.root2d.getBounds();
		context.shared.root2d.x = -Std.int(bounds.xMin + bounds.width * 0.5);
		context.shared.root2d.y = -Std.int(bounds.yMin + bounds.height * 0.5);
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
		var content = sys.io.File.getContent(getPath());
		data.load(haxe.Json.parse(content));
		currentSign = haxe.crypto.Md5.encode(content);

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


		{
			gizmo = new Gizmo3D(scene);
			// material.mainPass.setPassName("")
			// var pass = material.allocPass("ui");
		}

		{
			var grid = new h3d.scene.Graphics(scene.s3d);
			grid.lineStyle(1, 0x404040, 1.0);
			var size = 40;
			grid.scale(10);
			var offset = size/2;
			for(ix in 0...size+1) {
				grid.moveTo(ix - offset, -offset, 0);
				grid.lineTo(ix - offset, offset, 0);
			}
			for(iy in 0...size+1) {
				grid.moveTo(-offset, iy - offset, 0);
				grid.lineTo(offset, iy - offset, 0);
			}
			grid.lineStyle(0);
		}

		control = new h3d.scene.CameraController(scene.s3d);

		this.saveDisplayKey = "Scene:" + state.path;

		resetCamera();
		var cam = getDisplayState("Camera");
		if( cam != null ) {
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

		tools.addToggle("refresh", "Auto synchronize", function(b) {
			autoSync = b;
		});

		// BUILD scene tree

		function makeItem(o:PrefabElement) : hide.comp.IconTree.IconTreeItem<PrefabElement> {
			var p = o.getHideProps();
			return {
				data : o,
				text : o.name,
				icon : "fa fa-"+p.icon,
				children : o.children.length > 0,
				state : { opened : true },
			};
		}
		tree.get = function(o:PrefabElement) {
			var objs = o == null ? data.children : Lambda.array(o);
			var out = [for( o in objs ) makeItem(o)];
			return out;
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
				{ label : "Rename", enabled : current != null, click : function() tree.editNode(current) },
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
		tree.allowRename = true;
		tree.init();
		tree.onClick = selectObject;
		tree.onRename = function(e, name) {
			var oldName = e.name;
			e.name = name;
			undo.change(Field(e, "name", oldName), function() tree.refresh());
			return true;
		};
		tree.onAllowMove = function(_, _) {
			return true;
		};
		tree.onMove = function(e, to, index) {
			if( to == null ) to = data;
			var prev = e.parent;
			var prevIndex = prev.children.indexOf(e);
			e.parent = to;
			to.children.remove(e);
			to.children.insert(index, e);
			undo.change(Custom(function(undo) {
				if( undo ) {
					e.parent = prev;
					prev.children.remove(e);
					prev.children.insert(prevIndex, e);
				} else {
					e.parent = to;
					to.children.remove(e);
					to.children.insert(index, e);
				}
				refresh();
			}));
			refresh();
			return true;
		};


		if( curEdit != null ) {
			curEdit.cleanup();
			var e = curEdit.elt.name;
			var elt = data.getPrefabByName(e);
			if( elt != null ) selectObject(elt);
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
		if(gizmo != null) {
			gizmo.update(dt);
			var model = scene.s3d.getObjectByName("model0");
			model.setPos(gizmo.x, gizmo.y, gizmo.z);
			model.setRotationQuat(gizmo.getRotationQuat());
		}
		if( autoSync && (currentVersion != undo.currentID || lastSyncChange != properties.lastChange) ) {
			save();
			lastSyncChange = properties.lastChange;
			currentVersion = undo.currentID;
		}
	}

	static var _ = FileTree.registerExtension(Level3D,["l3d"],{ icon : "sitemap", createNew : "Level3D" });

}