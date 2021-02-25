package hide.comp;

import hrt.prefab.Reference;
import h3d.col.Sphere;
import h3d.scene.Mesh;
import h3d.col.FPoint;
import h3d.col.Ray;
import h3d.col.PolygonBuffer;
import h3d.prim.HMDModel;
import h3d.col.Collider.OptimizedCollider;
import h3d.Vector;
import hxd.Key as K;
import hxd.Math as M;

import hrt.prefab.Prefab as PrefabElement;
import hrt.prefab.Object2D;
import hrt.prefab.Object3D;
import h3d.scene.Object;

import hide.comp.cdb.DataFiles;

enum SelectMode {
	/**
		Update tree, add undo command
	**/
	Default;
	/**
		Update tree only
	**/
	NoHistory;
	/**
		Add undo but don't update tree
	**/
	NoTree;
	/**
		Don't refresh tree and don't undo command
	**/
	Nothing;
}

@:access(hide.comp.SceneEditor)
class SceneEditorContext extends hide.prefab.EditContext {

	public var editor(default, null) : SceneEditor;
	public var elements : Array<PrefabElement>;
	public var rootObjects(default, null): Array<Object>;
	public var rootObjects2D(default, null): Array<h2d.Object>;
	public var rootElements(default, null): Array<PrefabElement>;

	public function new(ctx, elts, editor) {
		super(ctx);
		this.editor = editor;
		this.updates = editor.updates;
		this.elements = elts;
		rootObjects = [];
		rootObjects2D = [];
		rootElements = [];
		cleanups = [];
		for(elt in elements) {
			// var obj3d = elt.to(Object3D);
			// if(obj3d == null) continue;
			if(!SceneEditor.hasParent(elt, elements)) {
				rootElements.push(elt);
				var ctx = getContext(elt);
				if(ctx != null) {
					var pobj = elt.parent == editor.sceneData ? ctx.shared.root3d : getContextRec(elt.parent).local3d;
					var pobj2d = elt.parent == editor.sceneData ? ctx.shared.root2d : getContextRec(elt.parent).local2d;
					if( ctx.local3d != pobj )
						rootObjects.push(ctx.local3d);
					if( ctx.local2d != pobj2d )
						rootObjects2D.push(ctx.local2d);
				}
			}
		}
	}

	override function screenToGround(x:Float, y:Float, ?forPrefab:hrt.prefab.Prefab) {
		return editor.screenToGround(x, y, forPrefab);
	}

	override function positionToGroundZ(x:Float, y:Float, ?forPrefab:hrt.prefab.Prefab):Float {
		return editor.getZ(x, y, forPrefab);
	}

	override function getCurrentProps( p : hrt.prefab.Prefab ) {
		var cur = editor.curEdit;
		return cur != null && cur.elements[0] == p ? editor.properties.element : new Element();
	}

	function getContextRec( p : hrt.prefab.Prefab ) {
		if( p == null )
			return editor.context;
		var c = editor.context.shared.contexts.get(p);
		if( c == null )
			return getContextRec(p.parent);
		return c;
	}

	override function rebuildProperties() {
		editor.scene.setCurrent();
		editor.selectObjects(elements, NoHistory);
	}

	override function rebuildPrefab( p : hrt.prefab.Prefab ) {
		// refresh all for now
		editor.refresh();
	}

	public function cleanup() {
		for( c in cleanups.copy() )
			c();
		cleanups = [];
	}

	override function onChange(p : PrefabElement, pname: String) {
		super.onChange(p, pname);
		editor.onPrefabChange(p, pname);
	}
}

enum RefreshMode {
	Partial;
	Full;
}

typedef CustomPivot = { elt : PrefabElement, mesh : Mesh, locPos : Vector };

class SceneEditor {

	public var tree : hide.comp.IconTree<PrefabElement>;
	public var favTree : hide.comp.IconTree<PrefabElement>;
	public var scene : hide.comp.Scene;
	public var properties : hide.comp.PropsEditor;
	public var context(default,null) : hrt.prefab.Context;
	public var curEdit(default, null) : SceneEditorContext;
	public var snapToGround = false;
	public var localTransform = true;
	public var cameraController : h3d.scene.CameraController;
	public var cameraController2D : hide.view.l3d.CameraController2D;
	public var editorDisplay(default,set) : Bool;
	public var camera2D(default,set) : Bool = false;

	var updates : Array<Float -> Void> = [];

	var showGizmo = true;
	var gizmo : hide.view.l3d.Gizmo;
	var gizmo2d : hide.view.l3d.Gizmo2D;
	static var customPivot : CustomPivot;
	var interactives : Map<PrefabElement, hxd.SceneEvents.Interactive>;
	var ide : hide.Ide;
	public var event(default, null) : hxd.WaitEvent;
	var hideList : Map<PrefabElement, Bool> = new Map();
	var lockList : Map<PrefabElement, Bool> = new Map();
	var favorites : Array<PrefabElement> = [];

	var undo(get, null):hide.ui.UndoHistory;
	function get_undo() { return view.undo; }

	public var view(default, null) : hide.view.FileView;
	var sceneData : PrefabElement;
	var lastRenderProps : hrt.prefab.RenderProps;

	public function new(view, data, ?chunkifyS3D : Bool = false) {
		ide = hide.Ide.inst;
		this.view = view;
		this.sceneData = data;

		event = new hxd.WaitEvent();

		var propsEl = new Element('<div class="props"></div>');
		properties = new hide.comp.PropsEditor(undo,null,propsEl);
		properties.saveDisplayKey = view.saveDisplayKey + "/properties";

		tree = new hide.comp.IconTree();
		tree.async = false;
		tree.autoOpenNodes = false;

		favTree = new hide.comp.IconTree();
		favTree.async = false;
		favTree.autoOpenNodes = false;

		var sceneEl = new Element('<div class="heaps-scene"></div>');
		scene = new hide.comp.Scene(chunkifyS3D, view.config, null, sceneEl);
		scene.editor = this;
		scene.onReady = onSceneReady;
		scene.onResize = function() {
			if( cameraController2D != null ) cameraController2D.toTarget();
			onResize();
		};

		context = new hrt.prefab.Context();
		context.shared = new hide.prefab.ContextShared(scene);
		context.shared.currentPath = view.state.path;
		context.init();
		editorDisplay = true;

		view.keys.register("copy", onCopy);
		view.keys.register("paste", onPaste);
		view.keys.register("cancel", deselect);
		view.keys.register("selectAll", selectAll);
		view.keys.register("duplicate", duplicate.bind(true));
		view.keys.register("duplicateInPlace", duplicate.bind(false));
		view.keys.register("group", groupSelection);
		view.keys.register("delete", () -> deleteElements(curEdit.rootElements));
		view.keys.register("search", function() tree.openFilter());
		view.keys.register("rename", function () {
			if(curEdit.rootElements.length > 0)
				tree.editNode(curEdit.rootElements[0]);
		});

		view.keys.register("sceneeditor.focus", focusSelection);
		view.keys.register("sceneeditor.lasso", startLassoSelect);
		view.keys.register("sceneeditor.hide", function() {
			var isHidden = isHidden(curEdit.rootElements[0]);
			setVisible(curEdit.elements, isHidden);
		});
		view.keys.register("sceneeditor.isolate", function() {	isolate(curEdit.elements); });
		view.keys.register("sceneeditor.showAll", function() {	setVisible(context.shared.elements(), true); });
		view.keys.register("sceneeditor.selectParent", function() {
			if(curEdit.rootElements.length > 0) {
				var p = curEdit.rootElements[0].parent;
				if( p != null && p != sceneData ) selectObjects([p]);
			}
		});
		view.keys.register("sceneeditor.reparent", function() {
			if(curEdit.rootElements.length > 1) {
				var children = curEdit.rootElements.copy();
				var parent = children.pop();
				reparentElement(children, parent, 0);
			}
		});
		view.keys.register("sceneeditor.editPivot", editPivot);

		// Load display state
		{
			var all = sceneData.flatten(hrt.prefab.Prefab);
			var list = @:privateAccess view.getDisplayState("hideList");
			if(list != null) {
				var m = [for(i in (list:Array<Dynamic>)) i => true];
				for(p in all) {
					if(m.exists(p.getAbsPath()))
						hideList.set(p, true);
				}
			}
			var list = @:privateAccess view.getDisplayState("lockList");
			if(list != null) {
				var m = [for(i in (list:Array<Dynamic>)) i => true];
				for(p in all) {
					if(m.exists(p.getAbsPath()))
						lockList.set(p, true);
				}
			}
			var favList = @:privateAccess view.getDisplayState("favorites");
			if(favList != null) {
				for(p in all) {
					if(favList.indexOf(p.getAbsPath()) >= 0)
						favorites.push(p);
				}
			}
		}
	}

	public function dispose() {
		scene.dispose();
		tree.dispose();
		favTree.dispose();
	}

	function set_camera2D(b) {
		if( cameraController != null ) cameraController.visible = !b;
		if( cameraController2D != null ) cameraController2D.visible = b;
		return camera2D = b;
	}

	public function onResourceChanged(lib : hxd.fmt.hmd.Library) {

		var models = sceneData.findAll(p -> Std.downcast(p, PrefabElement));
		var toRebuild : Array<PrefabElement> = [];
		for(m in models) {
			@:privateAccess if(m.source == lib.resource.entry.path) {
				if (toRebuild.indexOf(m) < 0) {
					toRebuild.push(m);
				}
			}
		}

		for(m in toRebuild) {
			removeInstance(m);
			makeInstance(m);
		}
	}

	public dynamic function onResize() {
	}

	function set_editorDisplay(v) {
		context.shared.editorDisplay = v;
		return editorDisplay = v;
	}

	public function getSelection() {
		return curEdit != null ? curEdit.elements : [];
	}

	function makeCamController() {
		var c = new h3d.scene.CameraController(scene.s3d);
		c.friction = 0.9;
		c.panSpeed = 0.6;
		c.zoomAmount = 1.05;
		c.smooth = 0.7;
		return c;
	}

	public function setFullScreen( b : Bool ) {
		view.fullScreen = b;
		if( b ) {
			view.element.find(".tabs").hide();
		} else {
			view.element.find(".tabs").show();
		}
	}

	function makeCamController2D() {
		return new hide.view.l3d.CameraController2D(context.shared.root2d);
	}

	function focusSelection() {
		if(curEdit.rootObjects.length > 0) {
			var bnds = new h3d.col.Bounds();
			var centroid = new h3d.Vector();
			for(obj in curEdit.rootObjects) {
				centroid = centroid.add(obj.getAbsPos().getPosition());
				bnds.add(obj.getBounds());
			}
			if(!bnds.isEmpty()) {
				var s = bnds.toSphere();
				cameraController.set(s.r * 4.0, null, null, s.getCenter());
			}
			else {
				centroid.scale3(1.0 / curEdit.rootObjects.length);
				cameraController.set(centroid.toPoint());
			}
		}
		for(obj in curEdit.rootElements)
			tree.revealNode(obj);
	}

	function getAvailableTags(p: PrefabElement) : Array<{id: String, color: String}>{
		return null;
	}

	public function getTag(p: PrefabElement) {
		if(p.props != null) {
			var tagId = Reflect.field(p.props, "tag");
			if(tagId != null) {
				var tags = getAvailableTags(p);
				if(tags != null)
					return Lambda.find(tags, t -> t.id == tagId);
			}
		}
		return null;
	}

	public function setTag(p: PrefabElement, tag: String) {
		if(p.props == null)
			p.props = {};
		var prevVal = getTag(p);
		Reflect.setField(p.props, "tag", tag);
		onPrefabChange(p, "tag");
		undo.change(Field(p.props, "tag", prevVal), function() {
			onPrefabChange(p, "tag");
		});
	}

	function getTagMenu(p: PrefabElement) : Array<hide.comp.ContextMenu.ContextMenuItem> {
		var tags = getAvailableTags(p);
		if(tags == null) return null;
		var cur = getTag(p);
		return [for(tag in tags) {
			label: tag.id,
			click: function () {
				if(cur == tag)
					setTag(p, null);
				else
					setTag(p, tag.id);
			},
			checked: cur == tag
		}];
	}

	function onSceneReady() {

		tree.saveDisplayKey = view.saveDisplayKey + '/tree';

		scene.s2d.addChild(context.shared.root2d);
		scene.s3d.addChild(context.shared.root3d);

		gizmo = new hide.view.l3d.Gizmo(scene);
		gizmo.moveStep = view.config.get("sceneeditor.gridSnapStep");

		gizmo2d = new hide.view.l3d.Gizmo2D();
		scene.s2d.add(gizmo2d, 1); // over local3d

		cameraController = makeCamController();
		cameraController.onClick = function(e) {
			switch( e.button ) {
			case K.MOUSE_RIGHT:
				selectNewObject();
			case K.MOUSE_LEFT:
				selectObjects([]);
			}
		};
		if (!camera2D)
			resetCamera();


		var cam = @:privateAccess view.getDisplayState("Camera");
		if( cam != null ) {
			scene.s3d.camera.pos.set(cam.x, cam.y, cam.z);
			scene.s3d.camera.target.set(cam.tx, cam.ty, cam.tz);
		}
		cameraController.loadFromCamera();

		scene.s2d.defaultSmooth = true;
		context.shared.root2d.x = scene.s2d.width >> 1;
		context.shared.root2d.y = scene.s2d.height >> 1;
		cameraController2D = makeCamController2D();
		cameraController2D.onClick = cameraController.onClick;
		var cam2d = @:privateAccess view.getDisplayState("Camera2D");
		if( cam2d != null ) {
			context.shared.root2d.x = scene.s2d.width*0.5 + cam2d.x;
			context.shared.root2d.y = scene.s2d.height*0.5 + cam2d.y;
			context.shared.root2d.setScale(cam2d.z);
		}
		cameraController2D.loadFromScene();
		if (camera2D)
			resetCamera();

		scene.onUpdate = update;

		// BUILD scene tree

		var icons = new Map();
		var iconsConfig = view.config.get("sceneeditor.icons");
		for( f in Reflect.fields(iconsConfig) )
			icons.set(f, Reflect.field(iconsConfig,f));

		function makeItem(o:PrefabElement, ?state) : hide.comp.IconTree.IconTreeItem<PrefabElement> {
			var p = o.getHideProps();
			var ref = o.to(Reference);
			var icon = p.icon;
			var ct = o.getCdbType();
			if( ct != null && icons.exists(ct) )
				icon = icons.get(ct);
			var r : hide.comp.IconTree.IconTreeItem<PrefabElement> = {
				value : o,
				text : o.name,
				icon : "fa fa-"+icon,
				children : (o.children.length > 0 && !p.hideChildren) || (ref != null && @:privateAccess ref.editMode),
				state: state
			};
			return r;
		}
		favTree.get = function (o:PrefabElement) {
			if(o == null) {
				return [for(f in favorites) makeItem(f, {
					disabled: true
				})];
			}
			return [];
		}
		favTree.allowRename = false;
		favTree.init();
		favTree.onAllowMove = function(_, _) {
			return false;
		};
		favTree.onClick = function(e, evt) {
			if(evt.ctrlKey) {
				var sel = tree.getSelection();
				sel.push(e);
				selectObjects(sel);
				tree.revealNode(e);
			}
			else
				selectObjects([e]);
		}
		favTree.onDblClick = function(e) {
			selectObjects([e]);
			tree.revealNode(e);
			return true;
		}
		tree.get = function(o:PrefabElement) {
			var objs = o == null ? sceneData.children : Lambda.array(o);
			var ref = o == null ? null : o.to(Reference);
			@:privateAccess if( ref != null && ref.editMode && ref.ref != null ) {
				for( c in ref.ref )
					objs.push(c);
			}
			var out = [for( o in objs ) makeItem(o)];
			return out;
		};
		function ctxMenu(tree, e) {
			e.preventDefault();
			var current = tree.getCurrentOver();
			if(current != null && (curEdit == null || curEdit.elements.indexOf(current) < 0)) {
				selectObjects([current]);
			}

			var newItems = getNewContextMenu(current);
			var menuItems : Array<hide.comp.ContextMenu.ContextMenuItem> = [
				{ label : "New...", menu : newItems },
			];
			var actionItems : Array<hide.comp.ContextMenu.ContextMenuItem> = [
				{ label : "Favorite", checked : current != null && isFavorite(current), click : function() setFavorite(current, !isFavorite(current)) },
				{ label : "Rename", enabled : current != null, click : function() tree.editNode(current) },
				{ label : "Delete", enabled : current != null, click : function() deleteElements(curEdit.rootElements) },
				{ label : "Duplicate", enabled : current != null, click : duplicate.bind(false) },
				{ label : "Reference", enabled : current != null, click : function() createRef(current, current.parent) },
			];

			var isObj = current != null && (current.to(Object3D) != null || current.to(Object2D) != null);
			var isRef = current != null && current.to(hrt.prefab.Reference) != null;

			if( isObj ) {
				var visible = !isHidden(current);
				var locked = isLocked(current);
				menuItems = menuItems.concat([
					{ label : "Visible", checked : visible, click : function() setVisible(curEdit.elements, !visible) },
					{ label : "Locked", checked : locked, click : function() {
						locked = !locked;
						setLock(curEdit.elements, locked);
					} },
					{ label : "Select all", click : selectAll },
					{ label : "Select children", enabled : current != null, click : function() selectObjects(current.flatten()) },
				]);
				if( !isRef )
					actionItems = actionItems.concat([
						{ label : "Isolate", click : function() isolate(curEdit.elements) },
						{ label : "Group", enabled : curEdit != null && canGroupSelection(), click : groupSelection }
					]);
			}
			if( current != null && (!isObj || isRef) ) {
				var enabled = current.enabled;
				menuItems.push({ label : "Enable", checked : enabled, click : function() setEnabled(curEdit.elements, !enabled) });
			}

			if( current != null ) {
				var menu = getTagMenu(current);
				if(menu != null)
					menuItems.push({ label : "Tag", menu: menu });
			}

			menuItems.push({ isSeparator : true, label : "" });
			new hide.comp.ContextMenu(menuItems.concat(actionItems));
		};
		tree.element.parent().contextmenu(ctxMenu.bind(tree));
		favTree.element.parent().contextmenu(ctxMenu.bind(favTree));
		tree.allowRename = true;
		tree.init();
		tree.onClick = function(e, _) {
			selectObjects(tree.getSelection(), NoTree);
		}
		tree.onDblClick = function(e) {
			focusSelection();
			return true;
		}
		tree.onRename = function(e, name) {
			var oldName = e.name;
			e.name = name;
			undo.change(Field(e, "name", oldName), function() {
				tree.refresh();
				refreshScene();
			});
			refreshScene();
			return true;
		};
		tree.onAllowMove = function(_, _) {
			return true;
		};

		// Batch tree.onMove, which is called for every node moved, causing problems with undo and refresh
		{
			var movetimer : haxe.Timer = null;
			var moved = [];
			tree.onMove = function(e, to, idx) {
				if(movetimer != null) {
					movetimer.stop();
				}
				moved.push(e);
				movetimer = haxe.Timer.delay(function() {
					reparentElement(moved, to, idx);
					movetimer = null;
					moved = [];
				}, 50);
			}
		}
		tree.applyStyle = function(p, el) applyTreeStyle(p, el);
		selectObjects([]);
		refresh();
		this.camera2D = camera2D;
	}

	public function refresh( ?mode: RefreshMode, ?callb: Void->Void) {
		if(mode == null || mode == Full) refreshScene();
		refreshFavs();
		refreshTree(callb);
	}

	public function collapseTree() {
		tree.collapseAll();
	}

	function refreshTree( ?callb ) {
		tree.refresh(function() {
			var all = sceneData.flatten(hrt.prefab.Prefab);
			for(elt in all) {
				var el = tree.getElement(elt);
				if(el == null) continue;
				applyTreeStyle(elt, el);
			}
			if(callb != null) callb();
		});
	}

	function refreshFavs() {
		favTree.refresh();
	}

	function refreshProps() {
		selectObjects(curEdit.elements, Nothing);
	}

	public function refreshScene() {
		var sh = context.shared;
		sh.root3d.remove();
		sh.root2d.remove();

		// Prevent leaks
		var chunkiFiedScene = Std.downcast(scene.s3d, hide.tools.ChunkedScene);
		if( chunkiFiedScene != null )
			chunkiFiedScene.reset();

		for( c in sh.contexts )
			if( c != null && c.cleanup != null )
				c.cleanup();
		context.shared = sh = new hide.prefab.ContextShared(scene);
		sh.editorDisplay = editorDisplay;
		sh.currentPath = view.state.path;
		scene.s3d.addChild(sh.root3d);
		scene.s2d.addChild(sh.root2d);
		sh.root2d.addChild(cameraController2D);
		scene.setCurrent();
		scene.onResize();
		context.init();
		sceneData.make(context);
		var bgcol = scene.engine.backgroundColor;
		scene.init();
		scene.engine.backgroundColor = bgcol;
		refreshInteractives();

		var all = sceneData.flatten(hrt.prefab.Prefab);
		for(elt in all)
			applySceneStyle(elt);

		if( lastRenderProps == null ) {
			var renderProps = getAllWithRefs(sceneData,hrt.prefab.RenderProps);
			for( r in renderProps )
				if( @:privateAccess r.isDefault ) {
					lastRenderProps = r;
					break;
				}
			if( lastRenderProps == null )
				lastRenderProps = renderProps[0];
		}

		if( lastRenderProps != null )
			lastRenderProps.applyProps(scene.s3d.renderer);
		else {
			var refPrefab = new Reference();
			refPrefab.refpath = view.config.getLocal("scene.renderProps");
			refPrefab.makeInstance(context);
			if( @:privateAccess refPrefab.ref != null ) {
				var renderProps = @:privateAccess refPrefab.ref.get(hrt.prefab.RenderProps);
				if( renderProps != null )
					renderProps.applyProps(scene.s3d.renderer);
			}
		}

		onRefresh();
	}

	function getAllWithRefs<T:hrt.prefab.Prefab>( p : hrt.prefab.Prefab, cl : Class<T>, ?arr : Array<T> ) : Array<T> {
		if( arr == null ) arr = [];
		var v = p.to(cl);
		if( v != null ) arr.push(v);
		for( c in p.children )
			getAllWithRefs(c, cl, arr);
		var ref = p.to(Reference);
		@:privateAccess if( ref != null && ref.ref != null ) getAllWithRefs(ref.ref, cl, arr);
		return arr;
	}

	public dynamic function onRefresh() {
	}

	function makeInteractive( elt : PrefabElement ) {
		var contexts = context.shared.contexts;
		var ctx = contexts[elt];
		if( ctx == null )
			return;
		var int = elt.makeInteractive(ctx);
		if( int == null ) return;
		initInteractive(elt,cast int);
		if( isLocked(elt) ) toggleInteractive(elt, false);
	}

	function toggleInteractive( e : PrefabElement, visible : Bool ) {
		var int = getInteractive(e);
		if( int == null ) return;
		var i2d = Std.downcast(int,h2d.Interactive);
		var i3d = Std.downcast(int,h3d.scene.Interactive);
		if( i2d != null ) i2d.visible = visible;
		if( i3d != null ) i3d.visible = visible;
	}

	function initInteractive( elt : PrefabElement, int : {
		dynamic function onPush(e:hxd.Event) : Void;
		dynamic function onMove(e:hxd.Event) : Void;
		dynamic function onRelease(e:hxd.Event) : Void;
		dynamic function onClick(e:hxd.Event) : Void;
		function handleEvent(e:hxd.Event) : Void;
		function preventClick() : Void;
	} ) {
		if( int == null ) return;
		var startDrag = null;
		var curDrag = null;
		var dragBtn = -1;
		var lastPush : Array<Float> = null;
		var i3d = Std.downcast(int, h3d.scene.Interactive);
		var i2d = Std.downcast(int, h2d.Interactive);
		int.onClick = function(e) {
			if(e.button == K.MOUSE_RIGHT) {
				var dist = hxd.Math.distance(scene.s2d.mouseX - lastPush[0], scene.s2d.mouseY - lastPush[1]);
				if( dist > 5 ) return;
				selectNewObject();
				e.propagate = false;
				return;
			}
		}
		int.onPush = function(e) {
			if( e.button == K.MOUSE_MIDDLE ) return;
			startDrag = [scene.s2d.mouseX, scene.s2d.mouseY];
			if( e.button == K.MOUSE_RIGHT )
				lastPush = startDrag;
			dragBtn = e.button;
			if( e.button == K.MOUSE_LEFT ) {
				var elts = null;
				if(K.isDown(K.SHIFT)) {
					if(Type.getClass(elt.parent) == hrt.prefab.Object3D)
						elts = [elt.parent];
					else
						elts = elt.parent.children;
				}
				else
					elts = [elt];

				if(K.isDown(K.CTRL)) {
					var current = curEdit.elements.copy();
					if(current.indexOf(elt) < 0) {
						for(e in elts) {
							if(current.indexOf(e) < 0)
								current.push(e);
						}
					}
					else {
						for(e in elts)
							current.remove(e);
					}
					selectObjects(current);
				}
				else
					selectObjects(elts);
			}
			// ensure we get onMove even if outside our interactive, allow fast click'n'drag
			if( e.button == K.MOUSE_LEFT ) {
				scene.sevents.startDrag(int.handleEvent);
				e.propagate = false;
			}
		};
		int.onRelease = function(e) {
			if( e.button == K.MOUSE_MIDDLE ) return;
			startDrag = null;
			curDrag = null;
			dragBtn = -1;
			if( e.button == K.MOUSE_LEFT ) {
				scene.sevents.stopDrag();
				e.propagate = false;
			}
		}
		int.onMove = function(e) {
			if(startDrag != null && hxd.Math.distance(startDrag[0] - scene.s2d.mouseX, startDrag[1] - scene.s2d.mouseY) > 5 ) {
				if(dragBtn == K.MOUSE_LEFT ) {
					if( i3d != null ) {
						moveGizmoToSelection();
						gizmo.startMove(MoveXY);
					}
					if( i2d != null ) {
						moveGizmoToSelection();
						gizmo2d.startMove(Pan);
					}
				}
				int.preventClick();
				startDrag = null;
			}
		}
		interactives.set(elt,cast int);
	}

	function selectNewObject() {
		var parentEl = sceneData;
		 // for now always create at scene root, not `curEdit.rootElements[0];`
		var group = getParentGroup(parentEl);
		if( group != null )
			parentEl = group;
		var originPt = getPickTransform(parentEl).getPosition();
		var newItems = getNewContextMenu(parentEl, function(newElt) {
			var newObj3d = Std.downcast(newElt, Object3D);
			if(newObj3d != null) {
				var newPos = new h3d.Matrix();
				newPos.identity();
				newPos.setPosition(originPt);
				var invParent = getObject(parentEl).getAbsPos().clone();
				invParent.invert();
				newPos.multiply(newPos, invParent);
				newObj3d.setTransform(newPos);
			}
			var newObj2d = Std.downcast(newElt, Object2D);
			if( newObj2d != null ) {
				var pt = new h2d.col.Point(scene.s2d.mouseX, scene.s2d.mouseY);
				var l2d = getContext(parentEl).local2d;
				l2d.globalToLocal(pt);
				newObj2d.x = pt.x;
				newObj2d.y = pt.y;
			}
		});
		var menuItems : Array<hide.comp.ContextMenu.ContextMenuItem> = [
			{ label : "New...", menu : newItems },
		];
		new hide.comp.ContextMenu(menuItems);
	}

	public function refreshInteractive(elt : PrefabElement) {
		var int = interactives.get(elt);
		if(int != null) {
			var i3d = Std.downcast(int, h3d.scene.Interactive);
			if( i3d != null ) i3d.remove() else cast(int,h2d.Interactive).remove();
			interactives.remove(elt);
		}
		makeInteractive(elt);
	}

	function refreshInteractives() {
		var contexts = context.shared.contexts;
		interactives = new Map();
		var all = contexts.keys();
		for(elt in all) {
			makeInteractive(elt);
		}
	}

	function setupGizmo() {
		if(curEdit == null) return;

		var posQuant = view.config.get("sceneeditor.xyzPrecision");
		var scaleQuant = view.config.get("sceneeditor.scalePrecision");
		var rotQuant = view.config.get("sceneeditor.rotatePrecision");
		inline function quantize(x: Float, step: Float) {
			if(step > 0) {
				x = Math.round(x / step) * step;
				x = untyped parseFloat(x.toFixed(5)); // Snap to closest nicely displayed float :cold_sweat:
			}
			return x;
		}

		gizmo.onStartMove = function(mode) {
			var objects3d = [for(o in curEdit.rootElements) {
				var obj3d = o.to(hrt.prefab.Object3D);
				if(obj3d != null)
					obj3d;
			}];
			var sceneObjs = [for(o in objects3d) getContext(o).local3d];
			var pivotPt = getPivot(sceneObjs);
			var pivot = new h3d.Matrix();
			pivot.initTranslation(pivotPt.x, pivotPt.y, pivotPt.z);
			var invPivot = pivot.clone();
			invPivot.invert();

			var localMats = [for(o in sceneObjs) {
				var m = worldMat(o);
				m.multiply(m, invPivot);
				m;
			}];

			var prevState = [for(o in objects3d) o.saveTransform()];
			gizmo.onMove = function(translate: h3d.Vector, rot: h3d.Quat, scale: h3d.Vector) {
				var transf = new h3d.Matrix();
				transf.identity();
				if(rot != null)
					rot.toMatrix(transf);
				if(translate != null)
					transf.translate(translate.x, translate.y, translate.z);
				for(i in 0...sceneObjs.length) {
					var newMat = localMats[i].clone();
					newMat.multiply(newMat, transf);
					newMat.multiply(newMat, pivot);
					if(snapToGround && mode == MoveXY) {
						newMat.tz = getZ(newMat.tx, newMat.ty);
					}
					var invParent = sceneObjs[i].parent.getAbsPos().clone();
					invParent.invert();
					newMat.multiply(newMat, invParent);
					if(scale != null) {
						newMat.prependScale(scale.x, scale.y, scale.z);
					}
					var obj3d = objects3d[i];
					var rot = newMat.getEulerAngles();
					obj3d.x = quantize(newMat.tx, posQuant);
					obj3d.y = quantize(newMat.ty, posQuant);
					obj3d.z = quantize(newMat.tz, posQuant);
					obj3d.rotationX = quantize(M.radToDeg(rot.x), rotQuant);
					obj3d.rotationY = quantize(M.radToDeg(rot.y), rotQuant);
					obj3d.rotationZ = quantize(M.radToDeg(rot.z), rotQuant);
					if(scale != null) {
						inline function scaleSnap(x: Float) {
							if(K.isDown(K.CTRL)) {
								var step = K.isDown(K.SHIFT) ? 0.5 : 1.0;
								x = Math.round(x / step) * step;
							}
							return x;
						}
						var s = newMat.getScale();
						obj3d.scaleX = quantize(scaleSnap(s.x), scaleQuant);
						obj3d.scaleY = quantize(scaleSnap(s.y), scaleQuant);
						obj3d.scaleZ = quantize(scaleSnap(s.z), scaleQuant);
					}
					obj3d.applyTransform(sceneObjs[i]);
				}
			}

			gizmo.onFinishMove = function() {
				var newState = [for(o in objects3d) o.saveTransform()];
				refreshProps();
				undo.change(Custom(function(undo) {
					if( undo ) {
						for(i in 0...objects3d.length) {
							objects3d[i].loadTransform(prevState[i]);
							objects3d[i].applyTransform(sceneObjs[i]);
						}
						refreshProps();
					}
					else {
						for(i in 0...objects3d.length) {
							objects3d[i].loadTransform(newState[i]);
							objects3d[i].applyTransform(sceneObjs[i]);
						}
						refreshProps();
					}

					for(o in objects3d)
						o.updateInstance(getContext(o));
				}));

				for(o in objects3d)
					o.updateInstance(getContext(o));
			}
		}
		gizmo2d.onStartMove = function(mode) {
			var objects2d = [for(o in curEdit.rootElements) {
				var obj = o.to(hrt.prefab.Object2D);
				if(obj != null) obj;
			}];
			var sceneObjs = [for(o in objects2d) getContext(o).local2d];
			var pivot = getPivot2D(sceneObjs);
			var center = pivot.getCenter();
			var prevState = [for(o in objects2d) o.saveTransform()];
			var startPos = [for(o in sceneObjs) o.getAbsPos()];

			gizmo2d.onMove = function(t) {
				t.x = Math.round(t.x);
				t.y = Math.round(t.y);
				for(i in 0...sceneObjs.length) {
					var pos = startPos[i].clone();
					var obj = objects2d[i];
					switch( mode ) {
					case Pan:
						pos.x += t.x;
						pos.y += t.y;
					case ScaleX, ScaleY, Scale:
						// no inherited rotation
						if( pos.b == 0 && pos.c == 0 ) {
							pos.x -= center.x;
							pos.y -= center.y;
							pos.x *= t.scaleX;
							pos.y *= t.scaleY;
							pos.x += center.x;
							pos.y += center.y;
							obj.scaleX = quantize(t.scaleX * prevState[i].scaleX, scaleQuant);
							obj.scaleY = quantize(t.scaleY * prevState[i].scaleY, scaleQuant);
						} else {
							var m2 = new h2d.col.Matrix();
							m2.initScale(t.scaleX, t.scaleY);
							pos.x -= center.x;
							pos.y -= center.y;
							pos.multiply(pos,m2);
							pos.x += center.x;
							pos.y += center.y;
							var s = pos.getScale();
							obj.scaleX = quantize(s.x, scaleQuant);
							obj.scaleY = quantize(s.y, scaleQuant);
						}
					case Rotation:
						pos.x -= center.x;
						pos.y -= center.y;
						var ca = Math.cos(t.rotation);
						var sa = Math.sin(t.rotation);
						var px = pos.x * ca - pos.y * sa;
						var py = pos.x * sa + pos.y * ca;
						pos.x = px + center.x;
						pos.y = py + center.y;
						var r = M.degToRad(prevState[i].rotation) + t.rotation;
						r = quantize(M.radToDeg(r), rotQuant);
						obj.rotation = r;
					}
					var pt = pos.getPosition();
					sceneObjs[i].parent.globalToLocal(pt);
					obj.x = quantize(pt.x, posQuant);
					obj.y = quantize(pt.y, posQuant);
					obj.applyTransform(sceneObjs[i]);
				}
			};
			gizmo2d.onFinishMove = function() {
				var newState = [for(o in objects2d) o.saveTransform()];
				refreshProps();
				undo.change(Custom(function(undo) {
					if( undo ) {
						for(i in 0...objects2d.length) {
							objects2d[i].loadTransform(prevState[i]);
							objects2d[i].applyTransform(sceneObjs[i]);
						}
						refreshProps();
					}
					else {
						for(i in 0...objects2d.length) {
							objects2d[i].loadTransform(newState[i]);
							objects2d[i].applyTransform(sceneObjs[i]);
						}
						refreshProps();
					}
					for(o in objects2d)
						o.updateInstance(getContext(o));
				}));
				for(o in objects2d)
					o.updateInstance(getContext(o));
			};
		};
	}

	function moveGizmoToSelection() {
		// Snap Gizmo at center of objects
		gizmo.getRotationQuat().identity();
		if(curEdit != null && curEdit.rootObjects.length > 0) {
			var pos = getPivot(curEdit.rootObjects);
			gizmo.visible = showGizmo;
			gizmo.setPosition(pos.x, pos.y, pos.z);

			if(curEdit.rootObjects.length == 1 && (localTransform || K.isDown(K.ALT))) {
				var obj = curEdit.rootObjects[0];
				var mat = worldMat(obj);
				var s = mat.getScale();
				if(s.x != 0 && s.y != 0 && s.z != 0) {
					mat.prependScale(1.0 / s.x, 1.0 / s.y, 1.0 / s.z);
					gizmo.getRotationQuat().initRotateMatrix(mat);
				}
			}
		}
		else {
			gizmo.visible = false;
		}
		if( curEdit != null && curEdit.rootObjects2D.length > 0 && !gizmo.visible ) {
			var pos = getPivot2D(curEdit.rootObjects2D);
			gizmo2d.visible = showGizmo;
			gizmo2d.setPosition(pos.getCenter().x, pos.getCenter().y);
			gizmo2d.setSize(pos.width, pos.height);
		} else {
			gizmo2d.visible = false;
		}
	}

	var inLassoMode = false;
	function startLassoSelect() {
		if(inLassoMode) {
			inLassoMode = false;
			return;
		}
		scene.setCurrent();
		inLassoMode = true;
		var g = new h2d.Object(scene.s2d);
		var overlay = new h2d.Bitmap(h2d.Tile.fromColor(0xffffff, 10000, 10000, 0.1), g);
		var intOverlay = new h2d.Interactive(10000, 10000, scene.s2d);
		var lastPt = new h2d.col.Point(scene.s2d.mouseX, scene.s2d.mouseY);
		var points : h2d.col.Polygon = [lastPt];
		var polyG = new h2d.Graphics(g);
		event.waitUntil(function(dt) {
			var curPt = new h2d.col.Point(scene.s2d.mouseX, scene.s2d.mouseY);
			if(curPt.distance(lastPt) > 3.0) {
				points.push(curPt);
				polyG.clear();
				polyG.beginFill(0xff0000, 0.5);
				polyG.lineStyle(1.0, 0, 1.0);
				polyG.moveTo(points[0].x, points[0].y);
				for(i in 1...points.length) {
					polyG.lineTo(points[i].x, points[i].y);
				}
				polyG.endFill();
				lastPt = curPt;
			}

			var finish = false;
			if(!inLassoMode || K.isDown(K.ESCAPE) || K.isDown(K.MOUSE_RIGHT)) {
				finish = true;
			}

			if(K.isDown(K.MOUSE_LEFT)) {
				var contexts = context.shared.contexts;
				var all = getAllSelectable3D();
				var inside = [];
				for(elt in all) {
					if(elt.to(Object3D) == null)
						continue;
					var ctx = contexts[elt];
					var o = ctx.local3d;
					if(o == null || !o.visible)
						continue;
					var absPos = o.getAbsPos();
					var screenPos = worldToScreen(absPos.tx, absPos.ty, absPos.tz);
					if(points.contains(screenPos, false)) {
						inside.push(elt);
					}
				}
				selectObjects(inside);
				finish = true;
			}

			if(finish) {
				intOverlay.remove();
				g.remove();
				inLassoMode = false;
				return true;
			}
			return false;
		});
	}

	public function onPrefabChange(p: PrefabElement, ?pname: String) {
		var model = p.to(hrt.prefab.Model);
		if(model != null && pname == "source") {
			refreshScene();
			return;
		}

		if(p != sceneData) {
			var el = tree.getElement(p);
			applyTreeStyle(p, el, pname);
		}

		applySceneStyle(p);
	}

	public function applyTreeStyle(p: PrefabElement, el: Element, ?pname: String) {
		var obj3d  = p.to(Object3D);
		el.toggleClass("disabled", !p.enabled);
		var aEl = el.find("a").first();
		aEl.toggleClass("favorite", isFavorite(p));

		var tag = getTag(p);

		if(tag != null) {
			aEl.css("background", tag.color);
			el.find("ul").first().css("background", tag.color + "80");
		}
		else if(pname == "tag") {
			aEl.css("background", "none");
			el.find("ul").first().css("background", "none");
		}

		if(obj3d != null) {
			el.toggleClass("disabled", !obj3d.visible);
			el.toggleClass("hidden", isHidden(obj3d));
			el.toggleClass("locked", isLocked(obj3d));
			var visTog = el.find(".visibility-toggle").first();
			if(visTog.length == 0) {
				visTog = new Element('<i class="fa fa-eye visibility-toggle"/>').insertAfter(el.find("a.jstree-anchor").first());
				visTog.click(function(e) {
					if(curEdit.elements.indexOf(obj3d) >= 0)
						setVisible(curEdit.elements, isHidden(obj3d));
					else
						setVisible([obj3d], isHidden(obj3d));

					e.preventDefault();
					e.stopPropagation();
				});
				visTog.dblclick(function(e) {
					e.preventDefault();
					e.stopPropagation();
				});
			}
			var lockTog = el.find(".lock-toggle").first();
			if(lockTog.length == 0) {
				lockTog = new Element('<i class="fa fa-lock lock-toggle"/>').insertAfter(el.find("a.jstree-anchor").first());
				lockTog.click(function(e) {
					if(curEdit.elements.indexOf(obj3d) >= 0)
						setLock(curEdit.elements, !isLocked(obj3d));
					else
						setLock([obj3d], !isLocked(obj3d));

					e.preventDefault();
					e.stopPropagation();
				});
				lockTog.dblclick(function(e) {
					e.preventDefault();
					e.stopPropagation();
				});
			}
			lockTog.css({visibility: (isLocked(obj3d) ? "visible" : "hidden")});
		}
	}

	public function applySceneStyle(p: PrefabElement) {
		var obj3d = p.to(Object3D);
		if(obj3d != null) {
			var visible = obj3d.visible && !isHidden(obj3d);
			for(ctx in getContexts(obj3d)) {
				ctx.local3d.visible = visible;
			}
		}
	}

	public function getInteractives(elt : PrefabElement) {
		var r = [getInteractive(elt)];
		for(c in elt.children) {
			r = r.concat(getInteractives(c));
		}
		return r;
	}

	public function getInteractive(elt: PrefabElement) {
		return interactives.get(elt);
	}

	public function getContext(elt : PrefabElement, ?shared : hrt.prefab.ContextShared) {
		if(elt == null) return null;
		if( shared == null ) shared = context.shared;
		var ctx = shared.contexts.get(elt);
		if( ctx == null ) {
			for( r in @:privateAccess shared.refsContexts ) {
				ctx = getContext(elt, r);
				if( ctx != null ) break;
			}
		}
		if( ctx == null && elt == sceneData )
			ctx = context;
		return ctx;
	}

	public function getContexts(elt: PrefabElement) {
		if(elt == null)
			return null;
		return context.shared.getContexts(elt);
	}

	public function getObject(elt: PrefabElement) {
		var ctx = getContext(elt);
		if(ctx != null)
			return ctx.local3d;
		return context.shared.root3d;
	}

	public function getSelfObject(elt: PrefabElement) {
		var ctx = getContext(elt);
		var parentCtx = getContext(elt.parent);
		if(ctx == null || parentCtx == null) return null;
		if(ctx.local3d != parentCtx.local3d)
			return ctx.local3d;
		return null;
	}

	function removeInstance(elt : PrefabElement) {
		var result = true;
		var contexts = context.shared.contexts;
		function recRemove(e: PrefabElement) {
			for(c in e.children)
				recRemove(c);

			var int = interactives.get(e);
			if(int != null) {
				var i3d = Std.downcast(int, h3d.scene.Interactive);
				if( i3d != null ) i3d.remove() else cast(int,h2d.Interactive).remove();
				interactives.remove(e);
			}
			for(ctx in getContexts(e)) {
				if(!e.removeInstance(ctx))
					result = false;
				contexts.remove(e);
			}
		}
		recRemove(elt);
		return result;
	}

	function makeInstance(elt: PrefabElement) {
		scene.setCurrent();
		var p = elt.parent;
		var parentCtx = null;
		while( p != null ) {
			parentCtx = getContext(p);
			if( parentCtx != null ) break;
			p = p.parent;
		}
		var ctx = elt.make(parentCtx);
		for( p in elt.flatten() )
			makeInteractive(p);
		scene.init(ctx.local3d);
	}

	function refreshParents( elts : Array<PrefabElement> ) {
		var parents = new Map();
		for( e in elts ) {
			if( e.parent == null ) throw e+" is missing parent";
			parents.set(e.parent, true);
		}
		for( p in parents.keys() ) {
			var h = p.getHideProps();
			if( h.onChildListChanged != null ) h.onChildListChanged();
		}
		if( lastRenderProps != null && parents.exists(lastRenderProps) )
			lastRenderProps.applyProps(scene.s3d.renderer);
	}

	public function addObject(elts : Array<PrefabElement>, selectObj : Bool = true, doRefresh : Bool = true, isTemporary = false) {
		for (e in elts) {
			makeInstance(e);
		}
		if (doRefresh) {
			refresh(Partial, if (selectObj) () -> selectObjects(elts, NoHistory) else null);
			refreshParents(elts);
		}
		if( isTemporary )
			return;

		undo.change(Custom(function(undo) {
			var fullRefresh = false;
			if(undo) {
				selectObjects([], NoHistory);
				for (e in elts) {
					if(!removeInstance(e))
						fullRefresh = true;
					e.parent.children.remove(e);
				}
				refresh(fullRefresh ? Full : Partial);
			}
			else {
				for (e in elts) {
					e.parent.children.push(e);
					makeInstance(e);
				}
				refresh(Partial, () -> selectObjects(elts,NoHistory));
				refreshParents(elts);
			}
		}));
	}

	function makeCdbProps( e : PrefabElement, type : cdb.Sheet ) {
		var props = type.getDefaults();
		Reflect.setField(props, "$cdbtype", DataFiles.getTypeName(type));
		if( type.idCol != null && !type.idCol.opt ) {
			var id = new haxe.io.Path(view.state.path).file;
			id = id.charAt(0).toUpperCase() + id.substr(1);
			id += "_"+e.name;
			Reflect.setField(props, type.idCol.name, id);
		}
		return props;
	}

	function fillProps( edit, e : PrefabElement ) {
		e.edit(edit);

		var typeName = e.getCdbType();
		if( typeName == null && e.props != null )
			return; // don't allow CDB data with props already used !

		var types = DataFiles.getAvailableTypes();
		if( types.length == 0 )
			return;

		var group = new hide.Element('
			<div class="group" name="CDB">
				<dl>
				<dt>
					<div class="btn-cdb-large fa fa-file-text"></div>
					Type
				</dt>
				<dd><select><option value="">- No props -</option></select></dd>
			</div>
		');

		var cdbLarge = @:privateAccess view.getDisplayState("cdbLarge");
		group.find(".btn-cdb-large").click((_) -> {
			cdbLarge = !cdbLarge;
			@:privateAccess view.saveDisplayState("cdbLarge", cdbLarge);
			group.toggleClass("cdb-large", cdbLarge);
		});
		group.toggleClass("cdb-large", cdbLarge == true);

		var select = group.find("select");
		for(t in types) {
			var id = DataFiles.getTypeName(t);
			new hide.Element("<option>").attr("value", id).text(id).appendTo(select);
		}

		var curType = DataFiles.resolveType(typeName);
		if(curType != null) select.val(DataFiles.getTypeName(curType));

		function changeProps(props: Dynamic) {
			properties.undo.change(Field(e, "props", e.props), ()->edit.rebuildProperties());
			e.props = props;
			edit.onChange(e, "props");
			edit.rebuildProperties();
		}

		select.change(function(v) {
			var typeId = select.val();
			if(typeId == null || typeId == "") {
				changeProps(null);
				return;
			}
			var props = makeCdbProps(e, DataFiles.resolveType(typeId));
			changeProps(props);
		});

		edit.properties.add(group);

		if(curType != null) {
			var props = new hide.Element('<div></div>').appendTo(group.find(".content"));
			var editor = new hide.comp.cdb.ObjEditor(curType, view.config, e.props, props);
			editor.undo = properties.undo;
			editor.fileView = view;
			editor.onChange = function(pname) {
				edit.onChange(e, 'props.$pname');
				var e = Std.instance(e, Object3D);
				if( e != null ) e.addEditorUI(context.shared.contexts.get(e));
			}
		}
	}

	public function showProps(e: PrefabElement) {
		scene.setCurrent();
		var edit = makeEditContext([e]);
		properties.clear();
		fillProps(edit, e);
	}

	function setObjectSelected( p : PrefabElement, ctx : hrt.prefab.Context, b : Bool ) {
		return p.setSelected(ctx, b);
	}

	public function selectObjects( elts : Array<PrefabElement>, ?mode : SelectMode = Default ) {
		function impl(elts,mode:SelectMode) {
			scene.setCurrent();
			if( curEdit != null )
				curEdit.cleanup();
			var edit = makeEditContext(elts);
			if (elts.length == 0 || (customPivot != null && customPivot.elt != edit.rootElements[0])) {
				customPivot = null;
			}
			properties.clear();
			if( elts.length > 0 ) fillProps(edit, elts[0]);

			switch( mode ) {
			case Default, NoHistory:
				tree.setSelection(elts);
			case Nothing, NoTree:
			}

			function getSelContext( e : PrefabElement ) {
				var ectx = context.shared.contexts.get(e);
				if( ectx == null ) ectx = context.shared.getContexts(e)[0];
				if( ectx == null ) ectx = context;
				return ectx;
			}

			var map = new Map<PrefabElement,Bool>();
			function selectRec(e : PrefabElement, b:Bool) {
				if( map.exists(e) )
					return;
				map.set(e, true);
				if(setObjectSelected(e, getSelContext(e), b))
					for( e in e.children )
						selectRec(e,b);
			}

			for( e in elts )
				selectRec(e, true);

			edit.cleanups.push(function() {
				for( e in map.keys() ) {
					if( hasBeenRemoved(e) ) continue;
					setObjectSelected(e, getSelContext(e), false);
				}
			});

			curEdit = edit;
			showGizmo = false;
			for( e in elts )
				if( !isLocked(e) ) {
					showGizmo = true;
					break;
				}
			setupGizmo();
		}

		if( curEdit != null && mode.match(Default|NoTree) ) {
			var prev = curEdit.rootElements.copy();
			undo.change(Custom(function(u) {
				if(u) impl(prev,NoHistory);
				else impl(elts,NoHistory);
			}),true);
		}

		impl(elts,mode);
	}

	function hasBeenRemoved( e : hrt.prefab.Prefab ) {
		var root = sceneData;
		var eltCtx = context.shared.getContexts(e)[0];
		if( eltCtx != null && eltCtx.shared.parent != null ) {
			if( hasBeenRemoved(eltCtx.shared.parent.prefab) )
				return true;
			root = null;
		}
		while( e != null && e != root ) {
			if( e.parent != null && e.parent.children.indexOf(e) < 0 )
				return true;
			e = e.parent;
		}
		return e != root;
	}

	public function resetCamera() {
		if( camera2D ) {
			cameraController2D.initFromScene();
		} else {
			scene.s3d.camera.zNear = scene.s3d.camera.zFar = 0;
			scene.s3d.camera.fovY = 25; // reset to default fov
			scene.resetCamera(1.5);
			cameraController.lockZPlanes = scene.s3d.camera.zNear != 0;
			cameraController.loadFromCamera();
		}
	}

	public function getPickTransform(parent: PrefabElement) {
		var proj = screenToGround(scene.s2d.mouseX, scene.s2d.mouseY);
		if(proj == null) return null;

		var localMat = new h3d.Matrix();
		localMat.initTranslation(proj.x, proj.y, proj.z);

		if(parent == null)
			return localMat;

		var parentMat = worldMat(getObject(parent));
		parentMat.invert();

		localMat.multiply(localMat, parentMat);
		return localMat;
	}

	public function onDragDrop( items : Array<String>, isDrop : Bool ) {
		var supported = @:privateAccess hrt.prefab.Library.registeredExtensions;
		var paths = [];
		for(path in items) {
			var ext = haxe.io.Path.extension(path).toLowerCase();
			if( supported.exists(ext) || ext == "fbx" || ext == "hmd" )
				paths.push(path);
		}
		if( paths.length == 0 )
			return false;
		if(isDrop)
			dropObjects(paths, sceneData);
		return true;
	}

	function dropObjects(paths: Array<String>, parent: PrefabElement) {
		scene.setCurrent();
		var localMat = getPickTransform(parent);
		if(localMat == null) return;

		localMat.tx = hxd.Math.round(localMat.tx * 10) / 10;
		localMat.ty = hxd.Math.round(localMat.ty * 10) / 10;
		localMat.tz = hxd.Math.floor(localMat.tz * 10) / 10;

		var elts: Array<PrefabElement> = [];
		for(path in paths) {
			var obj3d : Object3D;
			var relative = ide.makeRelative(path);

			if(hrt.prefab.Library.getPrefabType(path) != null) {
				var ref = new hrt.prefab.Reference(parent);
				ref.refpath = "/" + relative;
				obj3d = ref;
				obj3d.name = new haxe.io.Path(relative).file;
			}
			else {
				obj3d = new hrt.prefab.Model(parent);
				obj3d.source = relative;
			}
			obj3d.setTransform(localMat);
			autoName(obj3d);
			elts.push(obj3d);

		}

		for(e in elts)
			makeInstance(e);
		refresh(Partial, () -> selectObjects(elts));

		undo.change(Custom(function(undo) {
			if( undo ) {
				var fullRefresh = false;
				for(e in elts) {
					if(!removeInstance(e))
						fullRefresh = true;
					parent.children.remove(e);
				}
				refresh(fullRefresh ? Full : Partial);
			}
			else {
				for(e in elts) {
					parent.children.push(e);
					makeInstance(e);
				}
				refresh(Partial);
			}
		}));
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

	function groupSelection() {
		if(!canGroupSelection())
			return;

		var elts = curEdit.rootElements;
		var parent = elts[0].parent;
		var parentMat = worldMat(parent);
		var invParentMat = parentMat.clone();
		invParentMat.invert();


		var pivot = new h3d.Vector();
		{
			var count = 0;
			for(elt in curEdit.rootElements) {
				var m = worldMat(elt);
				if(m != null) {
					pivot = pivot.add(m.getPosition());
					++count;
				}
			}
			pivot.scale3(1.0 / count);
		}
		var local = new h3d.Matrix();
		local.initTranslation(pivot.x, pivot.y, pivot.z);
		local.multiply(local, invParentMat);
		var group = new hrt.prefab.Object3D(parent);
		@:privateAccess group.type = "object";
		autoName(group);
		group.x = local.tx;
		group.y = local.ty;
		group.z = local.tz;
		var parentCtx = getContext(parent);
		if(parentCtx == null)
			parentCtx = context;
		group.make(parentCtx);
		var groupCtx = getContext(group);

		var effectFunc = reparentImpl(elts, group, 0);
		undo.change(Custom(function(undo) {
			if(undo) {
				group.parent = null;
				context.shared.contexts.remove(group);
				effectFunc(true);
			}
			else {
				group.parent = parent;
				context.shared.contexts.set(group, groupCtx);
				effectFunc(false);
			}
			if(undo)
				refresh(()->selectObjects([],NoHistory));
			else
				refresh(()->selectObjects([group],NoHistory));
		}));
		refresh(effectFunc(false) ? Full : Partial, () -> selectObjects([group],NoHistory));
	}

	function onCopy() {
		if(curEdit == null) return;
		if(curEdit.rootElements.length == 1) {
			view.setClipboard(curEdit.rootElements[0].saveData(), "prefab");
		}
		else {
			var lib = new hrt.prefab.Library();
			for(e in curEdit.rootElements) {
				lib.children.push(e);
			}
			view.setClipboard(lib.saveData(), "library");
		}
	}

	function onPaste() {
		var parent : PrefabElement = sceneData;
		if(curEdit != null && curEdit.elements.length > 0) {
			parent = curEdit.elements[0];
		}
		var obj = haxe.Json.parse(haxe.Json.stringify(view.getClipboard("prefab")));
		if(obj != null) {
			var p = hrt.prefab.Prefab.loadPrefab(obj, parent);
			autoName(p);
			refresh();
		}
		else {
			obj = view.getClipboard("library");
			if(obj != null) {
				var lib = hrt.prefab.Prefab.loadPrefab(obj);
				for(c in lib.children) {
					autoName(c);
					c.parent = parent;
				}
				refresh();
			}
		}
	}

	public function isVisible(elt: PrefabElement) {
		if(elt == sceneData)
			return true;
		var o = elt.to(Object3D);
		if(o == null)
			return true;
		return o.visible && !isHidden(o) && (elt.parent != null ? isVisible(elt.parent) : true);
	}

	public function getAllSelectable3D() : Array<PrefabElement> {
		var ret = [];
		for(elt in interactives.keys()) {
			var i = interactives.get(elt);
			var p : h3d.scene.Object = Std.downcast(i, h3d.scene.Interactive);
			if( p == null )
				continue;
			while( p != null && p.visible )
				p = p.parent;
			if( p != null ) continue;
			ret.push(elt);
		}
		return ret;
	}

	public function selectAll() {
		selectObjects(getAllSelectable3D());
	}

	public function deselect() {
		selectObjects([]);
	}

	public function isSelected( p : PrefabElement ) {
		return curEdit != null && curEdit.elements.indexOf(p) >= 0;
	}

	public function setEnabled(elements : Array<PrefabElement>, enable: Bool) {
		// Don't disable/enable Object3Ds, too confusing with visibility
		elements = [for(e in elements) if(e.to(Object3D) == null || e.to(hrt.prefab.Reference) != null) e];
		var old = [for(e in elements) e.enabled];
		function apply(on) {
			for(i in 0...elements.length) {
				elements[i].enabled = on ? enable : old[i];
				onPrefabChange(elements[i]);
			}
			refreshScene();
		}
		apply(true);
		undo.change(Custom(function(undo) {
			if(undo)
				apply(false);
			else
				apply(true);
		}));
	}

	public function isHidden(e: PrefabElement) {
		if(e == null)
			return false;
		return hideList.exists(e);
	}

	public function isLocked(e: PrefabElement) {
		if(e == null)
			return false;
		return lockList.exists(e);
	}

	function saveDisplayState() {
		var state = [for (h in hideList.keys()) h.getAbsPath()];
		@:privateAccess view.saveDisplayState("hideList", state);
		var state = [for (h in lockList.keys()) h.getAbsPath()];
		@:privateAccess view.saveDisplayState("lockList", state);
		var state = [for(f in favorites) f.getAbsPath()];
		@:privateAccess view.saveDisplayState("favorites", state);
	}

	public function isFavorite(e: PrefabElement) {
		return favorites.indexOf(e) >= 0;
	}

	public function setFavorite(e: PrefabElement, fav: Bool) {
		if(fav && !isFavorite(e))
			favorites.push(e);
		else if(!fav && isFavorite(e))
			favorites.remove(e);

		var el = tree.getElement(e);
		if(el != null)
			applyTreeStyle(e, el);

		refreshFavs();
		saveDisplayState();
	}

	public function setVisible(elements : Array<PrefabElement>, visible: Bool) {
		for(o in elements) {
			for(c in o.flatten(Object3D)) {
				if( visible )
					hideList.remove(c);
				else
					hideList.set(o, true);
				var el = tree.getElement(c);
				applyTreeStyle(c, el);
				applySceneStyle(c);
			}
		}
		saveDisplayState();
	}

	function setLock(elements : Array<PrefabElement>, locked: Bool) {
		for(o in elements) {
			for(c in o.flatten(Object3D) ) {
				if( locked )
					lockList.set(c, true);
				else
					lockList.remove(c);
				var el = tree.getElement(c);
				applyTreeStyle(c, el);
				applySceneStyle(c);
			}
		}
		saveDisplayState();
		showGizmo = !locked;
		moveGizmoToSelection();
		for( e in elements )
			toggleInteractive(e,!locked);
	}

	function isolate(elts : Array<PrefabElement>) {
		var toShow = elts.copy();
		var toHide = [];
		function hideSiblings(elt: PrefabElement) {
			var p = elt.parent;
			for(c in p.children) {
				var needsVisible = c == elt || toShow.indexOf(c) >= 0 || hasChild(c, toShow);
				if(!needsVisible) {
					toHide.push(c);
				}
			}
			if(p != sceneData) {
				hideSiblings(p);
			}
		}
		for(e in toShow) {
			hideSiblings(e);
		}
		setVisible(toHide, false);
	}

	function createRef(elt: PrefabElement, toParent: PrefabElement) {
		var ref = new hrt.prefab.Reference(toParent);
		ref.name = elt.name;
		ref.refpath = elt.getAbsPath();
		var obj3d = Std.downcast(elt, Object3D);
		if(obj3d != null) {
			ref.x = obj3d.x;
			ref.y = obj3d.y;
			ref.z = obj3d.z;
			ref.scaleX = obj3d.scaleX;
			ref.scaleY = obj3d.scaleY;
			ref.scaleZ = obj3d.scaleZ;
			ref.rotationX = obj3d.rotationX;
			ref.rotationY = obj3d.rotationY;
			ref.rotationZ = obj3d.rotationZ;
		}
		addObject([ref]);
	}

	function duplicate(thenMove: Bool) {
		if(curEdit == null) return;
		var elements = curEdit.rootElements;
		if(elements == null || elements.length == 0)
			return;
		var contexts = context.shared.contexts;

		var undoes = [];
		var newElements = [];
		for(elt in elements) {
			var clone = elt.clone();
			var index = elt.parent.children.indexOf(elt) + 1;
			clone.parent = elt.parent;
			elt.parent.children.remove(clone);
			elt.parent.children.insert(index, clone);
			autoName(clone);
			makeInstance(clone);
			newElements.push(clone);

			undoes.push(function(undo) {
				if(undo) elt.parent.children.remove(clone);
				else elt.parent.children.insert(index, clone);
			});
		}

		refreshTree(function() {
			selectObjects(newElements);
			tree.setSelection(newElements);
			if(thenMove && curEdit.rootObjects.length > 0) {
				gizmo.startMove(MoveXY, true);
				gizmo.onFinishMove = function() {
					refreshProps();
				}
			}
		});

		undo.change(Custom(function(undo) {
			selectObjects([], NoHistory);

			var fullRefresh = false;
			if(undo) {
				for(elt in newElements) {
					if(!removeInstance(elt)) {
						fullRefresh = true;
						break;
					}
				}
			}

			for(u in undoes) u(undo);

			if(!undo) {
				for(elt in newElements)
					makeInstance(elt);
			}

			refresh(fullRefresh ? Full : Partial);
		}));
	}

	function setTransform(elt: PrefabElement, ?mat: h3d.Matrix, ?position: h3d.Vector) {
		var obj3d = Std.downcast(elt, hrt.prefab.Object3D);
		if(obj3d == null)
			return;
		if(mat != null)
			obj3d.setTransform(mat);
		else {
			obj3d.x = position.x;
			obj3d.y = position.y;
			obj3d.z = position.z;
		}
		var ctx = getContext(obj3d);
		if(ctx != null)
			obj3d.updateInstance(ctx);
	}

	public function deleteElements(elts : Array<PrefabElement>, ?then: Void->Void, doRefresh : Bool = true, enableUndo : Bool = true) {
		var fullRefresh = false;
		var undoes = [];
		for(elt in elts) {
			if(!removeInstance(elt))
				fullRefresh = true;
			var index = elt.parent.children.indexOf(elt);
			elt.parent.children.remove(elt);
			undoes.push(function(undo) {
				if(undo) elt.parent.children.insert(index, elt);
				else elt.parent.children.remove(elt);
			});
		}

		function refreshFunc(then) {
			refresh(fullRefresh ? Full : Partial, then);
			if( !fullRefresh ) refreshParents(elts);
		}

		if (doRefresh)
			refreshFunc(then != null ? then : () -> selectObjects([],NoHistory));

		if (enableUndo) {
			undo.change(Custom(function(undo) {
				if(!undo && !fullRefresh)
					for(e in elts) removeInstance(e);

				for(u in undoes) u(undo);

				if(undo)
					for(e in elts) makeInstance(e);

				refreshFunc(then != null ? then : selectObjects.bind(undo ? elts : [],NoHistory));
			}));
		}
	}

	function reparentElement(e : Array<PrefabElement>, to : PrefabElement, index : Int) {
		if( to == null )
			to = sceneData;

		var effectFunc = reparentImpl(e, to, index);
		undo.change(Custom(function(undo) {
			refresh(effectFunc(undo) ? Full : Partial);
		}));
		refresh(effectFunc(false) ? Full : Partial);
	}

	function makeTransform(mat: h3d.Matrix) {
		var rot = mat.getEulerAngles();
		var x = mat.tx;
		var y = mat.ty;
		var z = mat.tz;
		var s = mat.getScale();
		var scaleX = s.x;
		var scaleY = s.y;
		var scaleZ = s.z;
		var rotationX = hxd.Math.radToDeg(rot.x);
		var rotationY = hxd.Math.radToDeg(rot.y);
		var rotationZ = hxd.Math.radToDeg(rot.z);
		return { x : x, y : y, z : z, scaleX : scaleX, scaleY : scaleY, scaleZ : scaleZ, rotationX : rotationX, rotationY : rotationY, rotationZ : rotationZ };
	}

	function reparentImpl(elts : Array<PrefabElement>, toElt: PrefabElement, index: Int) : Bool -> Bool {
		var effects = [];
		var fullRefresh = false;
		var toRefresh : Array<PrefabElement> = null;
		for(elt in elts) {
			var prev = elt.parent;
			var prevIndex = prev.children.indexOf(elt);

			var obj3d = elt.to(Object3D);
			var preserveTransform = Std.is(toElt, hrt.prefab.fx.Emitter) || Std.is(prev, hrt.prefab.fx.Emitter);
			var toObj = getObject(toElt);
			var obj = getObject(elt);
			var prevState = null, newState = null;
			if(obj3d != null && toObj != null && obj != null && !preserveTransform) {
				var mat = worldMat(elt);
				var parentMat = worldMat(toElt);
				parentMat.invert();
				mat.multiply(mat, parentMat);
				prevState = obj3d.saveTransform();
				newState = makeTransform(mat);
			}

			effects.push(function(undo) {
				var refresh = false;
				if( undo ) {
					refresh = !removeInstance(elt);
					elt.parent = prev;
					prev.children.remove(elt);
					prev.children.insert(prevIndex, elt);
					if(obj3d != null && prevState != null)
						obj3d.loadTransform(prevState);
				} else {
					var refresh = !removeInstance(elt);
					elt.parent = toElt;
					toElt.children.remove(elt);
					toElt.children.insert(index, elt);
					if(obj3d != null && newState != null)
						obj3d.loadTransform(newState);
				};
				if(toRefresh.indexOf(elt) < 0)
					toRefresh.push(elt);
				return refresh;
			});
		}
		return function(undo) {
			var refresh = false;
			toRefresh = [];
			for(f in effects) {
				if(f(undo))
					refresh = true;
			}
			if(!refresh) {
				for(elt in toRefresh) {
					removeInstance(elt);
					makeInstance(elt);
				}
			}
			return refresh;
		}
	}

	function autoName(p : PrefabElement) {

		var uniqueName = false;
		if( p.type == "volumetricLightmap" || p.type == "light" )
			uniqueName = true;

		var prefix = null;
		if(p.name != null && p.name.length > 0) {
			if(uniqueName)
				prefix = ~/_+[0-9]+$/.replace(p.name, "");
			else
				prefix = p.name;
		}
		else
			prefix = p.getDefaultName();

		if(uniqueName) {
			prefix += "_";
			var id = 0;
			while( sceneData.getPrefabByName(prefix + id) != null )
				id++;

			p.name = prefix + id;
		}
		else
			p.name = prefix;

		for(c in p.children) {
			autoName(c);
		}
	}

	function update(dt:Float) {
		var cam = scene.s3d.camera;
		@:privateAccess view.saveDisplayState("Camera", { x : cam.pos.x, y : cam.pos.y, z : cam.pos.z, tx : cam.target.x, ty : cam.target.y, tz : cam.target.z });
		@:privateAccess view.saveDisplayState("Camera2D", { x : context.shared.root2d.x - scene.s2d.width*0.5, y : context.shared.root2d.y - scene.s2d.height*0.5, z : context.shared.root2d.scaleX });
		if(gizmo != null) {
			if(!gizmo.moving) {
				moveGizmoToSelection();
			}
			gizmo.update(dt);
		}
		event.update(dt);
		for( f in updates )
			f(dt);
		onUpdate(dt);
	}

	public dynamic function onUpdate(dt:Float) {
	}

	// Override
	function makeEditContext(elts : Array<PrefabElement>) : SceneEditorContext {
		var p = elts[0];
		var rootCtx = context;
		while( p != null ) {
			var ctx = context.shared.getContexts(p)[0];
			if( ctx != null ) rootCtx = ctx;
			p = p.parent;
		}
		// rootCtx might not be == context depending on references
		var edit = new SceneEditorContext(rootCtx, elts, this);
		edit.properties = properties;
		edit.scene = scene;
		return edit;
	}

	// Override
	function getNewContextMenu(current: PrefabElement, ?onMake: PrefabElement->Void=null, ?groupByType=true ) : Array<hide.comp.ContextMenu.ContextMenuItem> {
		var newItems = new Array<hide.comp.ContextMenu.ContextMenuItem>();
		var allRegs = hrt.prefab.Library.getRegistered().copy();
		allRegs.remove("reference");
		allRegs.remove("unknown");
		var parent = current == null ? sceneData : current;
		var allowChildren = null;
		{
			var cur = parent;
			while( allowChildren == null && cur != null ) {
				allowChildren = cur.getHideProps().allowChildren;
				cur = cur.parent;
			}
		}

		var groups = [];
		var gother = [];
		for( g in (view.config.get("sceneeditor.newgroups") : Array<String>) ) {
			var parts = g.split("|");
			var cl : Dynamic = Type.resolveClass(parts[1]);
			if( cl == null ) continue;
			groups.push({
				label : parts[0],
				cl : cl,
				group : [],
			});
		}
		for( ptype in allRegs.keys() ) {
			var pinf = allRegs.get(ptype);
			if( allowChildren != null && !allowChildren(ptype) ) {
				if( pinf.inf.allowParent == null || !pinf.inf.allowParent(parent) )
					continue;
			} else {
				if( pinf.inf.allowParent != null && !pinf.inf.allowParent(parent) )
					continue;
			}
			if(ptype == "shader") {
				newItems.push(getNewShaderMenu(parent, onMake));
				continue;
			}
			var m = getNewTypeMenuItem(ptype, parent, onMake);
			if( !groupByType )
				newItems.push(m);
			else {
				var found = false;
				for( g in groups )
					if( hrt.prefab.Library.isOfType(ptype,g.cl) ) {
						g.group.push(m);
						found = true;
						break;
					}
				if( !found ) gother.push(m);
			}
		}
		function sortByLabel(arr:Array<hide.comp.ContextMenu.ContextMenuItem>) {
			arr.sort(function(l1,l2) return Reflect.compare(l1.label,l2.label));
		}
		for( g in groups )
			if( g.group.length > 0 ) {
				sortByLabel(g.group);
				newItems.push({ label : g.label, menu : g.group });
			}
		sortByLabel(gother);
		sortByLabel(newItems);
		if( gother.length > 0 ) {
			if( newItems.length == 0 )
				return gother;
			newItems.push({ label : "Other", menu : gother });
		}
		return newItems;
	}

	function getNewTypeMenuItem(ptype: String, parent: PrefabElement, onMake: PrefabElement->Void, ?label: String) : hide.comp.ContextMenu.ContextMenuItem {
		var pmodel = hrt.prefab.Library.getRegistered().get(ptype);
		return {
			label : label != null ? label : pmodel.inf.name,
			click : function() {
				function make(?path) {
					var p = Type.createInstance(pmodel.cl, [parent]);
					@:privateAccess p.type = ptype;
					if(path != null)
						p.source = path;
					autoName(p);
					if(onMake != null)
						onMake(p);
					return p;
				}

				if( pmodel.inf.fileSource != null )
					ide.chooseFile(pmodel.inf.fileSource, function(path) {
						if( path == null ) return;
						var p = make(path);
						addObject([p]);
					});
				else
					addObject([make()]);
			}
		};
	}

	function getNewShaderMenu(parentElt: PrefabElement, onMake: PrefabElement->Void) : hide.comp.ContextMenu.ContextMenuItem {
		var custom = getNewTypeMenuItem("shader", parentElt, onMake, "Custom...");

		function shaderItem(name, path) : hide.comp.ContextMenu.ContextMenuItem {
			return {
				label : name,
				click : function() {
					var s = new hrt.prefab.Shader(parentElt);
					s.source = path;
					s.name = name;
					addObject([s]);
				}
			}
		}

		var menu = [custom];

		var shaders : Array<String> = hide.Ide.inst.currentConfig.get("fx.shaders", []);
		for(path in shaders) {
			var name = path;
			if(StringTools.endsWith(name, ".hx")) {
				name = name.substr(0, -3);
				name = name.split("/").pop();
			}
			else {
				name = name.split(".").pop();
			}
			menu.push(shaderItem(name, path));
		}

		return {
			label: "Shaders",
			menu: menu
		};
	}

	public function getZ(x: Float, y: Float, ?paintOn : hrt.prefab.Prefab) {
		var offset = 1000000;
		var ray = h3d.col.Ray.fromValues(x, y, offset, 0, 0, -1);
		var dist = projectToGround(ray, paintOn);
		if(dist >= 0) {
			return offset - dist;
		}
		return 0.;
	}

	function getGroundPrefabs() : Array<PrefabElement> {
		function getAll(data:PrefabElement) {
			var all = data.findAll((p) -> p);
			for( a in all.copy() ) {
				var r = Std.downcast(a, hrt.prefab.Reference);
				if( r != null ) {
					var sub = @:privateAccess r.ref;
					if( sub != null ) all = all.concat(getAll(sub));
				}
			}
			return all;
		}
		return getAll(sceneData);
	}

	public function projectToGround(ray: h3d.col.Ray, ?paintOn : hrt.prefab.Prefab ) {
		var minDist = -1.;

		for( elt in (paintOn == null ? getGroundPrefabs() : [paintOn]) ) {
			var obj = Std.downcast(elt, Object3D);
			if( obj == null ) continue;
			var ctx = getContext(elt);
			if( ctx == null ) continue;

			var lray = ray.clone();
			lray.transform(ctx.local3d.getInvPos());
			var dist = obj.localRayIntersection(ctx, lray);
			if( dist > 0 ) {
				var pt = lray.getPoint(dist);
				pt.transform(ctx.local3d.getAbsPos());
				var dist = pt.sub(ray.getPos()).length();
				if( minDist < 0 || dist < minDist )
					minDist = dist;
			}
		}
		if( minDist >= 0 )
			return minDist;

		var zPlane = h3d.col.Plane.Z(0);
		var pt = ray.intersect(zPlane);
		if( pt != null )
			minDist = pt.sub(ray.getPos()).length();

		return minDist;
	}

	public function screenToGround(sx: Float, sy: Float, ?paintOn : hrt.prefab.Prefab ) {
		var camera = scene.s3d.camera;
		var ray = camera.rayFromScreen(sx, sy);
		var dist = projectToGround(ray, paintOn);
		if(dist >= 0) {
			return ray.getPoint(dist);
		}
		return null;
	}

	public function worldToScreen(wx: Float, wy: Float, wz: Float) {
		var camera = scene.s3d.camera;
		var pt = camera.project(wx, wy, wz, scene.s2d.width, scene.s2d.height);
		return new h2d.col.Point(pt.x, pt.y);
	}

	public function worldMat(?obj: Object, ?elt: PrefabElement) {
		if(obj != null) {
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
		else {
			var mat = new h3d.Matrix();
			mat.identity();
			var o = Std.downcast(elt, Object3D);
			while(o != null) {
				mat.multiply(mat, o.getTransform());
				o = o.parent.to(hrt.prefab.Object3D);
			}
			return mat;
		}
	}

	function editPivot() {
		if (curEdit.rootObjects.length == 1) {
			var ray = scene.s3d.camera.rayFromScreen(scene.s2d.mouseX, scene.s2d.mouseY);
			var polyColliders = new Array<PolygonBuffer>();
			var meshes = new Array<Mesh>();
			for (m in curEdit.rootObjects[0].getMeshes()) {
				var hmdModel = Std.downcast(m.primitive, HMDModel);
				if (hmdModel != null) {
					var optiCollider = Std.downcast(hmdModel.getCollider(), OptimizedCollider);
					var polyCollider = Std.downcast(optiCollider.b, PolygonBuffer);
					if (polyCollider != null) {
						polyColliders.push(polyCollider);
						meshes.push(m);
					}
				}
			}
			if (polyColliders.length > 0) {
				var pivot = getClosestVertex(polyColliders, meshes, ray);
				if (pivot != null) {
					pivot.elt = curEdit.rootElements[0];
					customPivot = pivot;
				} else {
					// mouse outside
				}
			} else {
				// no collider found
			}
		} else {
			throw "Can't edit when multiple objects are selected";
		}
	}

	function getClosestVertex( colliders : Array<PolygonBuffer>, meshes : Array<Mesh>, ray : Ray ) : CustomPivot {

		var best = -1.;
		var bestVertex : CustomPivot = null;
		for (idx in 0...colliders.length) {
			var c = colliders[idx];
			var m = meshes[idx];
			var r = ray.clone();
			r.transform(m.getInvPos());
			var rdir = new FPoint(r.lx, r.ly, r.lz);
			var r0 = new FPoint(r.px, r.py, r.pz);
			@:privateAccess var i = c.startIndex;
			@:privateAccess for( t in 0...c.triCount ) {
				var i0 = c.indexes[i++] * 3;
				var p0 = new FPoint(c.buffer[i0++], c.buffer[i0++], c.buffer[i0]);
				var i1 = c.indexes[i++] * 3;
				var p1 = new FPoint(c.buffer[i1++], c.buffer[i1++], c.buffer[i1]);
				var i2 = c.indexes[i++] * 3;
				var p2 = new FPoint(c.buffer[i2++], c.buffer[i2++], c.buffer[i2]);

				var e1 = p1.sub(p0);
				var e2 = p2.sub(p0);
				var p = rdir.cross(e2);
				var det = e1.dot(p);
				if( det < hxd.Math.EPSILON ) continue; // backface culling (negative) and near parallel (epsilon)

				var invDet = 1 / det;
				var T = r0.sub(p0);
				var u = T.dot(p) * invDet;

				if( u < 0 || u > 1 ) continue;

				var q = T.cross(e1);
				var v = rdir.dot(q) * invDet;

				if( v < 0 || u + v > 1 ) continue;

				var t = e2.dot(q) * invDet;

				if( t < hxd.Math.EPSILON ) continue;

				if( best < 0 || t < best ) {
					best = t;
					var ptIntersection = r.getPoint(t);
					var pI = new FPoint(ptIntersection.x, ptIntersection.y, ptIntersection.z);
					inline function distanceFPoints(a : FPoint, b : FPoint) : Float {
						var dx = a.x - b.x;
						var dy = a.y - b.y;
						var dz = a.z - b.z;
						return dx * dx + dy * dy + dz * dz;
					}
					var test0 = distanceFPoints(p0, pI);
					var test1 = distanceFPoints(p1, pI);
					var test2 = distanceFPoints(p2, pI);
					var locBestVertex : FPoint;
					if (test0 <= test1 && test0 <= test2) {
						locBestVertex = p0;
					} else if (test1 <= test0 && test1 <= test2) {
						locBestVertex = p1;
					} else {
						locBestVertex = p2;
					}
					bestVertex = { elt : null, mesh: m, locPos: new Vector(locBestVertex.x, locBestVertex.y, locBestVertex.z) };
				}
			}
		}
		return bestVertex;
	}

	static function getPivot(objects: Array<Object>) {
		if (customPivot != null) {
			return customPivot.mesh.localToGlobal(customPivot.locPos.toPoint());
		}
		var pos = new h3d.col.Point();
		for(o in objects) {
			pos = pos.add(o.getAbsPos().getPosition().toPoint());
		}
		pos.scale(1.0 / objects.length);
		return pos;
	}

	static function getPivot2D( objects : Array<h2d.Object> ) {
		var b = new h2d.col.Bounds();
		for( o in objects )
			b.addBounds(o.getBounds());
		return b;
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

	static function getParentGroup(elt: PrefabElement) {
		while(elt != null) {
			if(elt.type == "object")
				return elt;
			elt = elt.parent;
		}
		return null;
	}
}