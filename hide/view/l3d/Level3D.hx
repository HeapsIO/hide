package hide.view.l3d;
using Lambda;

import hxd.Math;
import hxd.Key as K;

import hide.prefab.Prefab as PrefabElement;
import hide.prefab.Object3D;
import hide.prefab.l3d.Instance;
import hide.prefab.l3d.Layer;
import h3d.scene.Object;


class LevelEditContext extends hide.prefab.EditContext {
	var parent : Level3D;
	public function new(parent, context) {
		super(context);
		this.parent = parent;
	}
}

@:access(hide.view.l3d.Level3D)
class CamController extends h3d.scene.CameraController {
	var level3d : Level3D;

	public function new(parent, level3d) {
		super(null, parent);
		this.level3d = level3d;
	}

	override function onEvent( e : hxd.Event ) {
		switch( e.kind ) {
		case EWheel:
			zoom(e.wheelDelta);
		case EPush:
			@:privateAccess scene.events.startDrag(onEvent, function() pushing = -1, e);
			pushing = e.button;
			pushX = e.relX;
			pushY = e.relY;
		case ERelease, EReleaseOutside:
			if( pushing == e.button ) {
				pushing = -1;
				@:privateAccess scene.events.stopDrag();
			}
		case EMove:
			switch( pushing ) {
			case 1:
				var m = 0.001 * curPos.x * panSpeed / 25;
				if(hxd.Key.isDown(hxd.Key.SHIFT)) {
					pan(-(e.relX - pushX) * m, (e.relY - pushY) * m);
				}
				else {
					var se = level3d.sceneEditor;
					var fromPt = se.screenToWorld(pushX, pushY);
					var toPt = se.screenToWorld(e.relX, e.relY);
					var delta = toPt.sub(fromPt).toVector();
					delta.w = 0;
					targetOffset = targetOffset.sub(delta);
				}
				pushX = e.relX;
				pushY = e.relY;
			case 2:
				rot(e.relX - pushX, e.relY - pushY);
				pushX = e.relX;
				pushY = e.relY;
			default:
			}
		default:
		}
	}
}

@:access(hide.view.l3d.Level3D)
private class Level3DSceneEditor extends hide.comp.SceneEditor {
	var parent : Level3D;

	public function new(view, context, data) {
		super(view, context, data);
		parent = cast view;
		this.localTransform = false; // TODO: Expose option
	}

	override function makeCamController() {
		var c = new CamController(scene.s3d, parent);
		c.friction = 0.9;
		c.panSpeed = 0.6;
		c.zoomAmount = 1.05;
		c.smooth = 0.7;
		return c;
	}

	override function refresh(?callback) {
		super.refresh(callback);
		parent.onRefresh();
	}

	override function refreshScene() {
		super.refreshScene();
		parent.onRefreshScene();
	}

	override function update(dt) {
		super.update(dt);
		parent.onUpdate(dt);
	}

	override function onSceneReady() {
		super.onSceneReady();
		parent.onSceneReady();
	}

	override function selectAll() {
		var all = [for(e in getAllSelectable()) if(e.to(Layer) == null) e];
		selectObjects(all);
	}

	override function updateTreeStyle(p: PrefabElement, el: Element) {
		super.updateTreeStyle(p, el);
		parent.updateTreeStyle(p, el);
	}

	override function onPrefabChange(p: PrefabElement, ?pname: String) {
		super.onPrefabChange(p, pname);
		parent.onPrefabChange(p, pname);
	}

	override function projectToGround(ray: h3d.col.Ray) {
		var polygons = parent.getGroundPolys();
		var minDist = -1.;
		for(polygon in polygons) {
			var ctx = getContext(polygon);
			var mesh = Std.instance(ctx.local3d, h3d.scene.Mesh);
			if(mesh == null)
				continue;
			var collider = mesh.getGlobalCollider();
			var d = collider.rayIntersection(ray, true);
			if(d > 0 && (d < minDist || minDist < 0)) {
				minDist = d;
			}
		}
		if(minDist >= 0)
			return minDist;
		return super.projectToGround(ray);
	}

	override function getNewContextMenu(current: PrefabElement) {
		var newItems = new Array<hide.comp.ContextMenu.ContextMenuItem>();
		var allRegs = @:privateAccess hide.prefab.Library.registeredElements;
		var allowed = ["model", "object", "layer", "box", "polygon", "light"];

		if(current != null && current.type == "object" && current.name == "settings" && current.parent == sceneData) {
			allowed = ["renderProps"];
		}

		if(current != null && (current.type == "model" || current.type == "polygon" || current.type == "object")) {
			allowed.push("material");
			allowed.push("shader");
		}

		var curLayer = current != null ? current.to(hide.prefab.l3d.Layer) : null;
		var cdbSheet = curLayer != null ? curLayer.getCdbModel(curLayer) : null;

		function setup(p : PrefabElement) {
			var proj = screenToWorld(scene.s2d.width/2, scene.s2d.height/2);
			var obj3d = p.to(hide.prefab.Object3D);
			if(proj != null && obj3d != null && p.to(hide.prefab.l3d.Layer) == null) {
				var parentMat = worldMat(getObject(p.parent));
				parentMat.invert();
				var localMat = new h3d.Matrix();
				localMat.initTranslation(proj.x, proj.y, proj.z);
				localMat.multiply(localMat, parentMat);
				obj3d.setTransform(localMat);
			}

			if(cdbSheet != null)
				p.props = cdbSheet.getDefaults();

			autoName(p);
			haxe.Timer.delay(addObject.bind(p), 0);
		}

		for( ptype in allowed ) {
			newItems.push(getNewTypeMenuItem(ptype, current == null ? sceneData : current));
		}

		function addNewInstances() {
			if(curLayer == null)
				return;
			if(cdbSheet == null)
				return;
			var refCol = Instance.findRefColumn(cdbSheet);
			if(refCol == null)
				return;
			var refSheet = cdbSheet.base.getSheet(refCol.sheet);
			var idCol = Instance.findIDColumn(refSheet);
			if(idCol != null) {
				var kindItems = new Array<hide.comp.ContextMenu.ContextMenuItem>();
				for(line in refSheet.lines) {
					var kind : String = Reflect.getProperty(line, idCol.name);
					kindItems.push({
						label : kind,
						click : function() {
							var p = new hide.prefab.l3d.Instance(current);
							p.name = kind.charAt(0).toLowerCase() + kind.substr(1);
							setup(p);
							Reflect.setField(p.props, refCol.col.name, kind);
						}
					});
				}
				newItems.unshift({
					label : "Instance",
					menu: kindItems
				});
			}
			else {
				newItems.unshift({
					label : "Instance",
					click : function() {
						var p = new hide.prefab.l3d.Instance(current);
						p.name = "object";
						setup(p);
					}
				});
			}
		};
		addNewInstances();
		return newItems;
	}
}

class Level3D extends FileView {

	var sceneEditor : Level3DSceneEditor;
	var data : hide.prefab.l3d.Level3D;
	var context : hide.prefab.Context;
	var tabs : hide.comp.Tabs;

	var tools : hide.comp.Toolbar;

	var levelProps : hide.comp.PropsEditor;

	var layerToolbar : hide.comp.Toolbar;
	var layerButtons : Map<PrefabElement, hide.comp.Toolbar.ToolToggle>;

	var grid : h3d.scene.Graphics;
	var showGrid = true;
	var autoSync : Bool;
	var currentVersion : Int = 0;
	var lastSyncChange : Float = 0.;
	var currentSign : String;

	var scene(get, null):  hide.comp.Scene;
	function get_scene() return sceneEditor.scene;
	var properties(get, null):  hide.comp.PropsEditor;
	function get_properties() return sceneEditor.properties;

	public function new(state) {
		super(state);
	}

	override function onDisplay() {
		saveDisplayKey = "Level3D:" + getPath().split("\\").join("/").substr(0,-1);
		data = new hide.prefab.l3d.Level3D();
		var content = sys.io.File.getContent(getPath());
		data.load(haxe.Json.parse(content));
		currentSign = haxe.crypto.Md5.encode(content);

		context = new hide.prefab.Context();
		context.onError = function(e) {
			ide.error(e);
		};
		context.init();

		element.html('
			<div class="flex vertical">
				<div class="toolbar">
					<span class="tools-buttons"></span>
					<span class="layer-buttons"></span>
				</div>
				<div class="flex">
					<div class="scene">
					</div>
					<div class="tabs">
						<div class="tab" name="Scene" icon="sitemap">
							<div class="hide-block" style="height:60%">
								<div class="hide-scene-tree hide-list">
								</div>
							</div>
							<div class="hide-scroll"></div>
						</div>
						<div class="tab" name="Properties" icon="cog">
							<div class="level-props"></div>
						</div>
					</div>
				</div>
			</div>
		');
		tools = new hide.comp.Toolbar(null,element.find(".tools-buttons"));
		layerToolbar = new hide.comp.Toolbar(null,element.find(".layer-buttons"));
		tabs = new hide.comp.Tabs(null,element.find(".tabs"));
		currentVersion = undo.currentID;

		levelProps = new hide.comp.PropsEditor(undo,null,element.find(".level-props"));
		sceneEditor = new Level3DSceneEditor(this, context, data);
		sceneEditor.addSearchBox(element.find(".hide-scene-tree").first());
		element.find(".hide-scene-tree").first().append(sceneEditor.tree.element);
		element.find(".hide-scroll").first().append(sceneEditor.properties.element);
		element.find(".scene").first().append(sceneEditor.scene.element);
		sceneEditor.tree.element.addClass("small");

		// Level edit
		{
			var edit = new LevelEditContext(this, context);
			edit.prefabPath = state.path;
			edit.properties = levelProps;
			edit.scene = sceneEditor.scene;
			edit.cleanups = [];
			data.edit(edit);
		}
	}

	public function onSceneReady() {

		tools.saveDisplayKey = "Level3D/toolbar";
		tools.addButton("video-camera", "Perspective camera", () -> sceneEditor.resetCamera(false));
		tools.addButton("video-camera", "Top camera", () -> sceneEditor.resetCamera(true)).find(".icon").css({transform: "rotateZ(90deg)"});
		tools.addToggle("anchor", "Snap to ground", (v) -> sceneEditor.snapToGround = v, sceneEditor.snapToGround);
		tools.addToggle("compass", "Local transforms", (v) -> sceneEditor.localTransform = v, sceneEditor.localTransform);
		tools.addToggle("th", "Show grid", function(v) { showGrid = v; updateGrid(); }, showGrid);

		tools.addColor("Background color", function(v) {
			scene.engine.backgroundColor = v;
			updateGrid();
		}, scene.engine.backgroundColor);

		tools.addToggle("refresh", "Auto save", function(b) {
			autoSync = b;
		});

		updateGrid();
	}

	override function getDefaultContent() {
		return haxe.io.Bytes.ofString(ide.toJSON(new hide.prefab.l3d.Level3D().save()));
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

	function updateGrid() {
		if(grid != null) {
			grid.remove();
			grid = null;
		}

		if(!showGrid)
			return;

		grid = new h3d.scene.Graphics(scene.s3d);
		grid.scale(1);
		grid.material.mainPass.setPassName("debuggeom");

		var col = h3d.Vector.fromColor(scene.engine.backgroundColor);
		var hsl = col.toColorHSL();
		if(hsl.z > 0.5) hsl.z -= 0.1;
		else hsl.z += 0.1;
		col.makeColor(hsl.x, hsl.y, hsl.z);

		grid.lineStyle(1.0, col.toColor(), 1.0);
		for(ix in 0...data.width+1) {
			grid.moveTo(ix, 0, 0);
			grid.lineTo(ix, data.height, 0);
		}
		for(iy in 0...data.height+1) {
			grid.moveTo(0, iy, 0);
			grid.lineTo(data.width, iy, 0);
		}
		grid.lineStyle(0);
	}

	function onUpdate(dt:Float) {
		var cam = scene.s3d.camera;
		if( autoSync && (currentVersion != undo.currentID || lastSyncChange != properties.lastChange) ) {
			save();
			lastSyncChange = properties.lastChange;
			currentVersion = undo.currentID;
		}
	}

	function onRefresh() {
		refreshLayerIcons();
	}

	function onRefreshScene() {
		var all = context.shared.contexts.keys();
		for(elt in all)
			refreshSceneStyle(elt);

		// Apply first render props
		var settings = data.children.find(c -> c.name == "settings");
		if(settings != null) {
			for(c in settings.children) {
				var renderProps = c.to(hide.prefab.RenderProps);
				if(renderProps != null) {
					renderProps.applyProps(scene.s3d.renderer);
					break;
				}
			}
		}
	}

	override function onDragDrop(items : Array<String>, isDrop : Bool) {
		var supported = ["fbx"];
		var models = [];
		for(path in items) {
			var ext = haxe.io.Path.extension(path).toLowerCase();
			if(supported.indexOf(ext) >= 0) {
				models.push(path);
			}
		}
		if(models.length > 0) {
			if(isDrop) {
				var curSel = sceneEditor.getSelection();
				var parent : PrefabElement = data;
				if(curSel.length > 0) {
					var curLayer = curSel[0].to(Layer);
					if(curLayer == null)
						curLayer = curSel[0].getParent(Layer);
					if(curLayer != null)
						parent = curLayer;
				}
				sceneEditor.dropModels(models, parent);
			}
			return true;
		}
		return false;
	}

	function refreshLayerIcons() {
		if(layerButtons != null) {
			for(b in layerButtons)
				b.element.remove();
		}
		layerButtons = new Map<PrefabElement, hide.comp.Toolbar.ToolToggle>();
		var all = context.shared.contexts.keys();
		var initDone = false;
		for(elt in all) {
			var layer = elt.to(hide.prefab.l3d.Layer);
			if(layer == null) continue;
			layerButtons[elt] = layerToolbar.addToggle("file", layer.name, layer.name, function(on) {
				if(initDone)
					sceneEditor.setVisible([layer], on);
			}, layer.visible);

			refreshLayerIcon(layer);
		}
		initDone = true;
	}

	function refreshLayerIcon(layer: hide.prefab.l3d.Layer) {
		var lb = layerButtons[layer];
		if(lb != null) {
			var color = "#" + StringTools.hex(layer.color & 0xffffff, 6);
			if(layer.visible != lb.isDown())
				lb.toggle(layer.visible);
			lb.element.find(".icon").css("color", color);
			var label = lb.element.find("label");
			if(layer.locked)
				label.addClass("locked");
			else
				label.removeClass("locked");
		}
	}

	function updateTreeStyle(p: PrefabElement, el: Element) {
		var layer = p.to(hide.prefab.l3d.Layer);
		if(layer != null) {
			var color = "#" + StringTools.hex(layer.color & 0xffffff, 6);
			el.find("i.jstree-themeicon").first().css("color", color);
			el.find("a").first().toggleClass("locked", layer.locked);
			refreshLayerIcon(layer);
		}
	}

	function onPrefabChange(p: PrefabElement, ?pname: String) {
		refreshSceneStyle(p);
	}

	function refreshSceneStyle(p: PrefabElement) {
		var level3d = p.to(hide.prefab.l3d.Level3D);
		if(level3d != null) {
			updateGrid();
			return;
		}
		var layer = p.to(hide.prefab.l3d.Layer);
		if(layer != null)
			applyLayerProps(layer);

		var box = p.to(hide.prefab.Box);
		if(box != null) {
			var ctx = sceneEditor.getContext(box);
			box.setColor(ctx, getDisplayColor(p));
		}
		var poly = p.to(hide.prefab.l3d.Polygon);
		if(poly != null) {
			var ctx = sceneEditor.getContext(poly);
			poly.updateInstance(ctx);
		}
	}

	function applyLayerProps(layer: hide.prefab.l3d.Layer) {
		var obj3ds = layer.getAll(hide.prefab.Object3D);
		for(obj in obj3ds) {
			var i = @:privateAccess sceneEditor.interactives.get(obj);
			if(i != null) i.visible = !layer.locked;
		}
		for(box in layer.getAll(hide.prefab.Box)) {
			var ctx = sceneEditor.getContext(box);
			box.setColor(ctx, getDisplayColor(box));
		}
		for(poly in layer.getAll(hide.prefab.l3d.Polygon)) {
			var ctx = sceneEditor.getContext(poly);
			poly.updateInstance(ctx);
		}
	}

	static function getDisplayColor(p: PrefabElement) {
		var color = 0x80ffffff;
		var layer = p.getParent(Layer);
		if(layer != null) {
			color = layer.color;
		}
		var kind = Instance.getCdbKind(p);
		if(kind != null) {
			var colorCol = kind.sheet.columns.find(c -> c.type == cdb.Data.ColumnType.TColor);
			if(colorCol != null) {
				color = cast Reflect.getProperty(kind.idx.obj, colorCol.name);
				color |= 0x80000000;
			}
		}
		return color;
	}

	function getGroundPolys() {
		var gname = props.get("l3d.groundLayer");
		var groundLayer = data.get(Layer, gname);
		var polygons = groundLayer.getAll(hide.prefab.l3d.Polygon);
		return polygons;
	}

	static var _ = FileTree.registerExtension(Level3D,["l3d"],{ icon : "sitemap", createNew : "Level3D" });

}