package hide.view.l3d;
import hxd.Math;
import hxd.Key as K;

import hide.prefab.Prefab as PrefabElement;
import hide.prefab.Object3D;
import h3d.scene.Object;

class CamController extends h3d.scene.CameraController {
	public function new(?distance, ?parent) {
		super(distance, parent);
		friction = 0.9;
		panSpeed = 0.6;
		zoomAmount = 1.05;
		smooth = 0.2;
	}
}

class Level3D extends FileView {

	var data : hide.prefab.Library;
	var context : hide.prefab.Context;
	var tabs : hide.comp.Tabs;

	var tools : hide.comp.Toolbar;
	var scene : hide.comp.Scene;
	var cameraController : CamController;
	var properties : hide.comp.PropsEditor;
	var light : h3d.scene.DirLight;
	var lightDirection = new h3d.Vector( 1, 2, -4 );
	var tree : hide.comp.IconTree<PrefabElement>;
	var layerButtons : Map<PrefabElement, hide.comp.Toolbar.ToolToggle>;
	var interactives : Map<PrefabElement, h3d.scene.Interactive>;

	var searchBox : Element;
	var curEdit : LevelEditContext;
	var gizmo : Gizmo;

	// autoSync
	var autoSync : Bool;
	var currentVersion : Int = 0;
	var lastSyncChange : Float = 0.;
	var currentSign : String;

	override function setContainer(cont) {
		super.setContainer(cont);
		keys.register("copy", onCopy);
		keys.register("paste", onPaste);
		keys.register("cancel", deselect);
		keys.register("selectAll", selectAll);
		keys.register("duplicate", duplicate);
		keys.register("group", groupSelection);
		keys.register("delete", () -> deleteElements(curEdit.rootElements));
		keys.register("search", showSearch);
	}

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
								<div class="hide-list hide-scene-tree">
									<div class="tree small"></div>
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
		tree.async = false;
		currentVersion = undo.currentID;

		var sceneTree = root.find(".hide-scene-tree");
		searchBox = new Element("<div>").addClass("searchBox").appendTo(sceneTree);
		new Element("<input type='text'>").appendTo(searchBox).keydown(function(e) {
			if( e.keyCode == 27 ) {
				searchBox.find("i").click();
				return;
			}
		}).keyup(function(e) {
			tree.searchFilter(e.getThis().val());
		});
		new Element("<i>").addClass("fa fa-times-circle").appendTo(searchBox).click(function(_) {
			tree.searchFilter(null);
			searchBox.toggle();
		});
	}

	function refresh( ?callb ) {
		var sh = context.shared;
		sh.root3d.remove();
		for( f in sh.cleanups )
			f();
		sh.root3d = new h3d.scene.Object();
		sh.cleanups = [];
		context.init();
		data.makeInstance(context);
		scene.s3d.addChild(sh.root3d);
		scene.init(props);
		refreshInteractives();
		refreshLayerIcons();
		tree.refresh(function() {
			for(elt in sh.contexts.keys()) {
				onPrefabChange(elt);
			}
			if(callb != null) callb();
		});
	}

	function autoName(p : PrefabElement) {
		var id = 0;
		var prefix = p.type;
		if(prefix == "object")
			prefix = "group";

		var model = Std.instance(p, hide.prefab.Model);
		if(model != null && model.source != null) {
			var path = new haxe.io.Path(model.source);
			prefix = path.file;
		}
		while( data.getPrefabByName(prefix + id) != null )
			id++;
		
		p.name = prefix + id;

		for(c in p.children) {
			autoName(c);
		}
	}

	function selectObjects( elts : Array<PrefabElement>, ?includeTree=true) {
		if( curEdit != null )
			curEdit.cleanup();
		var edit = new LevelEditContext(context, elts);
		edit.prefabPath = state.path;
		edit.properties = properties;
		edit.scene = scene;
		edit.view = this;
		edit.cleanups = [];
		edit.rebuild();

		if(includeTree) {
			tree.setSelection(elts);
		}

		var objects = edit.rootObjects;
		addOutline(objects);
		edit.cleanups.push(function() {
			cleanOutline(objects);
		});

		curEdit = edit;
		setupGizmo();
	}

	function refreshProps() {
		properties.clear();
		if(curEdit != null && curEdit.elements != null && curEdit.elements.length > 0) {
			curEdit.elements[0].edit(curEdit);
		}
	}

	function setupGizmo() {
		if(curEdit == null) return;
		gizmo.onStartMove = function() {
			var objects = curEdit.rootObjects;
			var pivotPt = getPivot(objects);
			var pivot = new h3d.Matrix();
			pivot.initTranslate(pivotPt.x, pivotPt.y, pivotPt.z);
			var invPivot = pivot.clone();
			invPivot.invert();

			var localMats = [for(o in objects) {
				var m = worldMat(o);
				m.multiply(m, invPivot);
				m;
			}];

			var objects3d = [for(e in curEdit.elements) Std.instance(e, Object3D)];
			var prevState = [for(o in objects3d) o.save()];			
			
			gizmo.onMove = function(translate: h3d.Vector, rot: h3d.Quat, scale: h3d.Vector) {
				var transf = new h3d.Matrix();
				transf.identity();
				if(rot != null)
					rot.saveToMatrix(transf);
				if(translate != null)
					transf.translate(translate.x, translate.y, translate.z);
				for(i in 0...objects.length) {
					var newMat = localMats[i].clone();
					newMat.multiply(newMat, transf);
					newMat.multiply(newMat, pivot);
					var invParent = objects[i].parent.getAbsPos().clone();
					invParent.invert();
					newMat.multiply(newMat, invParent);
					if(scale != null) {
						newMat.prependScale(scale.x, scale.y, scale.z);
					}
					var obj3d = objects3d[i];
					obj3d.setTransform(newMat);
					obj3d.applyPos(objects[i]);
				}
			}

			gizmo.onFinishMove = function() {
				var newState = [for(o in objects3d) o.save()];
				refreshProps();
				undo.change(Custom(function(undo) {
					if( undo ) {
						for(i in 0...objects3d.length) {
							objects3d[i].load(prevState[i]);
							objects3d[i].applyPos(objects[i]);
						}
						refreshProps();
					}
					else {
						for(i in 0...objects3d.length) {
							objects3d[i].load(newState[i]);
							objects3d[i].applyPos(objects[i]);
						}
						refreshProps();
					}
				}));
			}
		}
	}

	function moveGizmoToSelection() {
		// Snap Gizmo at center of objects
		gizmo.getRotationQuat().identity();
		if(curEdit != null && curEdit.rootObjects.length > 0) {
			var pos = getPivot(curEdit.rootObjects);
			gizmo.visible = true;
			gizmo.setPos(pos.x, pos.y, pos.z);

			if(curEdit.rootObjects.length == 1 && K.isDown(K.ALT)) {
				var obj = curEdit.rootObjects[0];
				var mat = worldMat(obj);
				var s = mat.getScale();
				mat.prependScale(1.0 / s.x, 1.0 / s.y, 1.0 / s.z);
				gizmo.getRotationQuat().initRotateMatrix(mat);
			}
		}
		else {
			gizmo.visible = false;
		}
	}

	function resetCamera(?top = false) {
		var targetPt = new h3d.col.Point(0, 0, 0);
		if(curEdit != null && curEdit.rootObjects.length > 0) {
			targetPt = curEdit.rootObjects[0].getAbsPos().pos().toPoint();
		}
		if(top) 
			cameraController.set(50, Math.PI/2, 0.001, targetPt);
		else
			cameraController.set(50, -4.7, 0.8, targetPt);
		cameraController.toTarget();
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
			selectObjects([e]);
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


		gizmo = new Gizmo(scene);
		
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

		cameraController = new CamController(scene.s3d);

		this.saveDisplayKey = "Scene:" + state.path;

		resetCamera();
		var cam = getDisplayState("Camera");
		if( cam != null ) {
			scene.s3d.camera.pos.set(cam.x, cam.y, cam.z);
			scene.s3d.camera.target.set(cam.tx, cam.ty, cam.tz);
		}
		cameraController.loadFromCamera();

		scene.onUpdate = update;
		scene.init(props);
		tools.saveDisplayKey = "SceneTools";

		tools.addButton("video-camera", "Perspective camera", () -> resetCamera(false));
		tools.addButton("arrow-down", "Top camera", () -> resetCamera(true));
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
			var r : hide.comp.IconTree.IconTreeItem<PrefabElement> = {
				value : o,
				text : o.name,
				icon : "fa fa-"+p.icon,
				children : o.children.length > 0,
				state : { opened : true },
			};
			return r;
		}
		tree.get = function(o:PrefabElement) {
			var objs = o == null ? data.children : Lambda.array(o);
			var out = [for( o in objs ) makeItem(o)];
			return out;
		};
		tree.root.parent().contextmenu(function(e) {
			e.preventDefault();
			var current = tree.getCurrentOver();
			if(current != null && (curEdit == null || curEdit.elements.indexOf(current) < 0)) {
				selectObjects([current]);
			}

			var registered = new Array<hide.comp.ContextMenu.ContextMenuItem>();
			var allRegs = @:privateAccess hide.prefab.Library.registeredElements;
			var allowed = ["model", "object", "layer", "box"];
			for( ptype in allowed ) {
				var pcl = allRegs.get(ptype);
				var props = Type.createEmptyInstance(pcl).getHideProps();
				registered.push({
					label : props.name,
					click : function() {

						function make(?path) {
							var p = Type.createInstance(pcl, [current == null ? data : current]);
							@:privateAccess p.type = ptype;
							if(path != null)
								p.source = path;
							autoName(p);
							return p;
						}

						if( props.fileSource != null )
							ide.chooseFile(props.fileSource, function(path) {
								if( path == null ) return;
								var p = make(path);
								addObject(p);
							});
						else
							addObject(make());
					}
				});
			}

			var menuItems : Array<hide.comp.ContextMenu.ContextMenuItem> = [
				{ label : "New...", menu : registered },
				{ label : "Rename", enabled : current != null, click : function() tree.editNode(current) },
				{ label : "Delete", enabled : current != null, click : function() deleteElements(curEdit.rootElements) },
				{ label : "Select all", click : selectAll },
				{ label : "Select children", enabled : current != null, click : function() selectObjects(current.getAll(PrefabElement)) },
				{ label : "Show", enabled : curEdit != null && curEdit.elements.length > 0, click : function() setVisible(curEdit.elements, true) },
				{ label : "Hide", enabled : curEdit != null && curEdit.elements.length > 0, click : function() setVisible(curEdit.elements, false) },
				{ label : "Isolate", enabled : curEdit != null && curEdit.elements.length > 0, click : function() isolate(curEdit.elements) },
				{ label : "Group", enabled : curEdit != null && canGroupSelection(), click : groupSelection },
			];

			new hide.comp.ContextMenu(menuItems);
		});
		tree.allowRename = true;
		tree.init();
		tree.onClick = function(e) {
			selectObjects(tree.getSelection(), false);
			if(curEdit.rootObjects.length > 0) {
				cameraController.set(curEdit.rootObjects[0].getAbsPos().pos().toPoint());
			}
		}
		tree.onRename = function(e, name) {
			var oldName = e.name;
			e.name = name;
			undo.change(Field(e, "name", oldName), function() tree.refresh());
			return true;
		};
		tree.onAllowMove = function(_, _) {
			return true;
		};
		tree.onMove = reparentElement;

		refresh();
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
			if(!gizmo.moving) {
				moveGizmoToSelection();
			}
			gizmo.update(dt);
		}
		if( autoSync && (currentVersion != undo.currentID || lastSyncChange != properties.lastChange) ) {
			save();
			lastSyncChange = properties.lastChange;
			currentVersion = undo.currentID;
		}
	}

	function onCopy() {
		if(curEdit == null) return;
		if(curEdit.rootElements.length == 1) {
			setClipboard(curEdit.rootElements[0].saveRec(), "prefab");
		}
		else {
			var lib = new hide.prefab.Library();
			for(e in curEdit.rootElements) {
				lib.children.push(e);
			}
			setClipboard(lib.saveRec(), "library");
		}
	}

	function onPaste() {
		var parent : PrefabElement = data;
		if(curEdit != null && curEdit.elements.length > 0) {
			parent = curEdit.elements[0];
		}
		var obj: PrefabElement = getClipboard("prefab");
		if(obj != null) {
			var p = hide.prefab.Prefab.loadRec(obj, parent);
			autoName(p);
			refresh();
		}
		else {
			obj = getClipboard("library");
			if(obj != null) {
				var lib = hide.prefab.Prefab.loadRec(obj);
				for(c in lib.children) {
					autoName(c);
					c.parent = parent;
				}
				refresh();
			}
		}
	}

	function selectAll() {
		selectObjects([for(e in context.shared.contexts.keys()) e]);
	}

	function deselect() {
		selectObjects([]);
	}

	function isolate(elts : Array<PrefabElement>) {
		var all = context.shared.contexts.keys();
		var toShow = elts.copy();
		var toHide = [];
		function hideSiblings(elt: PrefabElement) {
			var p = elt.parent;
			for(c in p.children) {
				var needsVisible = c == elt
					|| toShow.indexOf(c) >= 0
					|| hasChild(c, toShow);
				if(!needsVisible) {
					toHide.push(c);
				}
			}
			if(p != data) {
				hideSiblings(p);
			}
		}
		for(e in toShow) {
			hideSiblings(e);
		}
		setVisible(toHide, false);
	}

	function duplicate() {
		if(curEdit == null) return;
		var elements = curEdit.rootElements;
		var newElements = [for(elt in elements) {
			var clone = hide.prefab.Prefab.loadRec(elt.saveRec());
			autoName(clone);
			clone.parent = elt.parent;
			clone;
		}];
		refresh(function() {
			selectObjects(newElements);
			tree.setSelection(newElements);
			gizmo.startMove(MoveXY, true);
			gizmo.onFinishMove = function() {
				undo.change(Custom(function(undo) {
					for(elt in newElements) {
						if(undo) {
							elt.parent.children.remove(elt);
						}
						else {
							elt.parent.children.push(elt);
						}
					}
					refresh();
				}));
			}
		});
	}

	function deleteElements(elts : Array<PrefabElement>) {
		var contexts = context.shared.contexts;
		var list = [for(e in elts) {
			elt: e,
			parent: e.parent,
			index: e.parent.children.indexOf(e)
		}];
		var oldContexts = contexts.copy();
		for(e in elts) {
			for(c in e.getAll(PrefabElement))
				contexts.remove(c);
		}
		var newContexts = contexts.copy();
		function action(undo) {
			if( undo ) {
				for(o in list)
					o.parent.children.insert(o.index, o.elt);
				context.shared.contexts = oldContexts;
			}
			else {
				for(o in list)
					o.parent.children.remove(o.elt);
				context.shared.contexts = newContexts;				
			}
			refresh();
		}
		action(false);
		undo.change(Custom(action));
	}

	function reparentElement(e : PrefabElement, to : PrefabElement, index : Int) {
		if( to == null )
			to = data;

		var undoFunc = reparentImpl(e, to, index);
		undo.change(Custom(function(undo) {
			undoFunc(undo);
			refresh();
		}));
		refresh();
	}

	function reparentImpl(e : PrefabElement, to: PrefabElement, index: Int) {
		var prev = e.parent;
		var prevIndex = prev.children.indexOf(e);
		e.parent = to;
		to.children.remove(e);
		to.children.insert(index, e);

		var obj3d = Std.instance(e, Object3D);
		var obj = getObject(e);
		var toObj = getObject(to);
		var mat = worldMat(obj);
		var parentMat = worldMat(toObj);
		parentMat.invert();
		mat.multiply(mat, parentMat);
		var prevState = obj3d.save();
		obj3d.setTransform(mat);
		var newState = obj3d.save();

		return function(undo) {
			if( undo ) {
				e.parent = prev;
				prev.children.remove(e);
				prev.children.insert(prevIndex, e);
				obj3d.load(prevState);
			} else {
				e.parent = to;
				to.children.remove(e);
				to.children.insert(index, e);
				obj3d.load(newState);
			};
		}
	}

	function groupSelection() {
		if(!canGroupSelection())
			return;

		var elts = curEdit.rootElements;
		var parent = elts[0].parent;
		var parentMat = getContext(parent).local3d.getAbsPos();
		var invParentMat = parentMat.clone();
		invParentMat.invert();

		var pivot = getPivot(curEdit.rootObjects);
		var local = new h3d.Matrix();
		local.initTranslate(pivot.x, pivot.y, pivot.z);
		local.multiply(local, invParentMat);
		var group = new hide.prefab.Object3D(parent);
		@:privateAccess group.type = "object";
		autoName(group);
		group.x = local.tx;
		group.y = local.ty;
		group.z = local.tz;
		group.makeInstance(getContext(parent));
		var groupCtx = getContext(group);

		var undoes = [for(e in elts) reparentImpl(e, group, 0)];
		undo.change(Custom(function(undo) {
			if(undo) {
				group.parent = null;
				context.shared.contexts.remove(group);
				for(u in undoes)
					u(true);
			}
			else {
				group.parent = parent;
				context.shared.contexts.set(group, groupCtx);
				for(u in undoes)
					u(false);
			}
			if(undo)
				refresh(deselect);
			else
				refresh(()->selectObjects([group]));
		}));
		refresh(() -> selectObjects([group]));
	}

	function getContext(elt : PrefabElement) {
		if(elt != null) {
			return context.shared.contexts.get(elt);
		}
		return null;
	}

	function getObject(elt: PrefabElement) {
		var ctx = getContext(elt);
		if(ctx != null)
			return ctx.local3d;
		return context.shared.root3d;
	}

	function setVisible(elements : Array<PrefabElement>, visible: Bool) {
		var cache = [];
		for(e in elements) {
			var o = Std.instance(e, Object3D);
			if(o != null) {
				cache.push({o: o, vis: o.visible});
			}
		}

		function apply(b) {
			for(c in cache) {
				c.o.visible = b ? visible : c.vis;
				var obj = getContext(c.o).local3d;
				if(obj != null) {
					c.o.applyPos(obj);
				}
				onPrefabChange(c.o);
			}
		}

		apply(true);
		undo.change(Custom(function(undo) {
			if(undo)
				apply(false);
			else
				apply(true);
		}));
	}

	function showSearch() {
		searchBox.show();
		searchBox.find("input").focus().select();
	}

	function refreshLayerIcons() {
		if(layerButtons != null) {
			for(b in layerButtons)
				b.element.remove();
		}
		layerButtons = new Map<PrefabElement, hide.comp.Toolbar.ToolToggle>();
		var all = context.shared.contexts.keys();
		for(elt in all) {
			var layer = Std.instance(elt, hide.prefab.l3d.Layer);
			if(layer == null) continue;
			layerButtons[elt] = tools.addToggle("file", layer.name, layer.name, function(on) {
				setVisible([layer], on);
			}, layer.visible);
		}
	}

	function getSelfMeshes(p : PrefabElement) {
		var childObjs = [for(c in p.children) getContext(c).local3d];
		var ret = [];
		function rec(o : Object) {
			var m = Std.instance(o, h3d.scene.Mesh);
			if(m != null) ret.push(m);
			for(i in 0...o.numChildren) {
				var child = o.getChildAt(i);
				if(childObjs.indexOf(child) < 0) {
					rec(child);
				}
			}
		}
		rec(getContext(p).local3d);
		return ret;
	}

	function refreshInteractives() {
		var contexts = context.shared.contexts;
		interactives = new Map();
		var all = contexts.keys();
		for(elt in all) {
			var ctx = contexts[elt];
			var cls = Type.getClass(elt);
			if(!(cls == hide.prefab.Model || cls == hide.prefab.Box))
				continue;
			if(ctx.local3d != null) {
				var o = ctx.local3d;
				var meshes = getSelfMeshes(elt);
				var invRootMat = o.getAbsPos().clone();
				invRootMat.invert();
				var bounds = new h3d.col.Bounds();
				for(mesh in meshes) {
					var localMat = mesh.getAbsPos().clone();
					localMat.multiply(localMat, invRootMat);
					var lb = mesh.primitive.getBounds().clone();
					lb.transform(localMat);
					bounds.add(lb);
				}
				var meshCollider = new h3d.col.Collider.GroupCollider([for(m in meshes) m.getGlobalCollider()]);
				var boundsCollider = new h3d.col.ObjectCollider(o, bounds);
				var int = new h3d.scene.Interactive(boundsCollider, o);
				interactives.set(elt, int);
				int.ignoreParentTransform = true;
				int.preciseShape = meshCollider;
				int.propagateEvents = true;
				var startDrag = null;			
				int.onPush = function(e) {
					startDrag = [scene.s2d.mouseX, scene.s2d.mouseY];
					e.propagate = false;
					if(K.isDown(K.CTRL) && curEdit != null) {
						var list = curEdit.elements.copy();
						if(list.indexOf(elt) < 0) {
								list.push(elt);
							selectObjects(list);
						}
					}
					else {
						selectObjects([elt]);
					}
				}
				int.onRelease = function(e) {
					startDrag = null;
				}
				int.onMove = function(e) {
					if(startDrag != null) {
						if((hxd.Math.abs(startDrag[0] - scene.s2d.mouseX) + hxd.Math.abs(startDrag[1] - scene.s2d.mouseY)) > 5) {
							startDrag = null;
							moveGizmoToSelection();
							gizmo.startMove(MoveXY);
						}
					}
				}
			}
		}
	}

	public function onPrefabChange(p: PrefabElement) {
		var el = tree.getElement(p);
		var obj3d  = Std.instance(p, Object3D);
		if(obj3d != null) {
			if(obj3d.visible) {
				el.removeClass("jstree-invisible");
			}
			else {
				el.addClass("jstree-invisible");
			}
		}

		var layer = Std.instance(p, hide.prefab.l3d.Layer);
		if(layer != null) {
			var color = "#" + StringTools.hex(layer.color, 6);
			el.find("i.jstree-themeicon").first().css("color", color);
			if(layer.locked) 
				el.find("a").first().addClass("jstree-locked");
			else
				el.find("a").first().removeClass("jstree-locked");

			var lb = layerButtons[p];
			if(lb != null) {
				if(layer.visible != lb.isDown())
					lb.toggle(layer.visible);
				lb.element.find(".icon").css("color", color);
				var label = lb.element.find("label");
				if(layer.locked) 
					label.addClass("locked");
				else 
					label.removeClass("locked");
			}

			var boxes = layer.getAll(hide.prefab.Box);
			for(box in boxes) {
				box.setColor(layer.color);
				interactives.get(box).visible = !layer.locked;				
			}

			var models = layer.getAll(hide.prefab.Model);
			for(m in models) {
				interactives.get(m).visible = !layer.locked;
			}
		}
	}

	static function worldMat(obj: Object) {
		if(obj.defaultTransform != null) {
			var m = obj.defaultTransform.clone();
			m.invert();
			m.multiply(m, obj.getAbsPos());
			return m;
		}
		else {
			return obj.getAbsPos().clone();
		}
	}

	static function getPivot(objects: Array<Object>) {
		var pos = new h3d.Vector();
		for(o in objects) {
			pos = pos.add(o.getAbsPos().pos());
		}
		pos.scale3(1.0 / objects.length);
		return pos;
	}

	static function addOutline(objects: Array<Object>) {
		var outlineShader = new h3d.shader.Outline();
		outlineShader.size = 0.12;
		outlineShader.distance = 0;
		outlineShader.color.setColor(0xffffff);
		for(obj in objects) {
			for( m in obj.getMaterials() ) {
				var p = m.allocPass("outline");
				p.culling = None;
				p.depthWrite = false;
				p.addShader(outlineShader);
				if( m.mainPass.name == "default" )
					m.mainPass.setPassName("outlined");
			}
		}
	}

	static function cleanOutline(objects: Array<Object>) {
		for(obj in objects) {
			for( m in obj.getMaterials() ) {
				if( m.mainPass != null && m.mainPass.name == "outlined" )
					m.mainPass.setPassName("default");
				m.removePass(m.getPass("outline"));
			}
		}
	}

	function canGroupSelection() {
		var elts = curEdit.rootElements;
		if(elts.length == 0)
			return false;

		if(elts.length == 1)
			return true;

		// Only allow grouping of sibling elements
		var parent = elts[0].parent;
		for(e in elts)
			if(e.parent != parent)
				return false;
		
		return true;
	}

	public static function hasParent(elt: PrefabElement, list: Array<PrefabElement>) {
		for(p in list) {
			if(isParent(elt, p))
				return true;
		}
		return false;
	}

	public static function hasChild(elt: PrefabElement, list: Array<PrefabElement>) {
		for(p in list) {
			if(isParent(p, elt))
				return true;
		}
		return false;
	}

	public static function isParent(elt: PrefabElement, parent: PrefabElement) {
		var p = elt.parent;
		while(p != null) {
			if(p == parent) return true;
			p = p.parent;
		}
		return false;
	}

	static var _ = FileTree.registerExtension(Level3D,["l3d"],{ icon : "sitemap", createNew : "Level3D" });

}