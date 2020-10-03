package hide.view.l3d;
using Lambda;

import hxd.Math;
import hxd.Key as K;

import hrt.prefab.Prefab as PrefabElement;
import hrt.prefab.Object3D;
import hrt.prefab.l3d.Instance;
import h3d.scene.Object;
import hide.comp.cdb.DataFiles;


class LevelEditContext extends hide.prefab.EditContext {
	public var parent : Level3D;
	public function new(parent, context) {
		super(context);
		this.parent = parent;
	}
}

@:access(hide.view.l3d.Level3D)
class CamController extends h3d.scene.CameraController {
	var level3d : Level3D;
	var startPush : h2d.col.Point;

	public function new(parent, level3d) {
		super(null, parent);
		this.level3d = level3d;
	}

	override function onEvent( e : hxd.Event ) {
		if(curPos == null) return;
		switch( e.kind ) {
		case EWheel:
			zoom(e.wheelDelta);
		case EPush:
			pushing = e.button;
			pushX = e.relX;
			pushY = e.relY;
			pushTime = haxe.Timer.stamp();
			pushStartX = pushX = e.relX;
			pushStartY = pushY = e.relY;
			startPush = new h2d.col.Point(pushX, pushY);
		case ERelease, EReleaseOutside:
			if( pushing == e.button ) {
				pushing = -1;
				startPush = null;
				if( e.kind == ERelease && haxe.Timer.stamp() - pushTime < 0.2 && hxd.Math.distance(e.relX - pushStartX,e.relY - pushStartY) < 5 )
					onClick(e);
			}
		case EMove:
			switch( pushing ) {
			case 1:
				if(startPush != null && startPush.distance(new h2d.col.Point(e.relX, e.relY)) > 3) {
					var lowAngle = hxd.Math.degToRad(30);
					var angle = hxd.Math.abs(Math.PI/2 - phi);
					if(hxd.Key.isDown(hxd.Key.SHIFT) || angle < lowAngle) {
						var m = 0.001 * curPos.x * panSpeed / 25;
						pan(-(e.relX - pushX) * m, (e.relY - pushY) * m);
					}
					else {
						var se = level3d.sceneEditor;
						var fromPt = se.screenToGround(pushX, pushY);
						var toPt = se.screenToGround(e.relX, e.relY);
						if(fromPt == null || toPt == null)
							return;
						var delta = toPt.sub(fromPt).toVector();
						delta.w = 0;
						targetOffset = targetOffset.sub(delta);
					}
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

	public function new(view, data) {
		super(view, data, true);
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

	override function refresh(?mode, ?callback) {
		parent.onRefresh();
		super.refresh(mode, callback);
	}

	override function update(dt) {
		super.update(dt);
		parent.onUpdate(dt);
	}

	override function onSceneReady() {
		super.onSceneReady();
		parent.onSceneReady();
	}

	override function applyTreeStyle(p: PrefabElement, el: Element, ?pname: String) {
		super.applyTreeStyle(p, el, pname);
		parent.applyTreeStyle(p, el, pname);
	}

	override function applySceneStyle(p:PrefabElement) {
		parent.applySceneStyle(p);
	}

	override function onPrefabChange(p: PrefabElement, ?pname: String) {
		super.onPrefabChange(p, pname);
		parent.onPrefabChange(p, pname);
	}

	override function getGroundPrefabs():Array<PrefabElement> {
		var prefabs = parent.getGroundPrefabs();
		if( prefabs != null )
			return prefabs;
		return super.getGroundPrefabs();
	}

	override function getNewContextMenu(current: PrefabElement, ?onMake: PrefabElement->Void=null, ?groupByType = true ) {
		var newItems = super.getNewContextMenu(current, onMake, groupByType);

		function setup(p : PrefabElement) {
			var proj = screenToGround(scene.s2d.width/2, scene.s2d.height/2);
			var obj3d = p.to(hrt.prefab.Object3D);
			var autoCenter = proj != null && obj3d != null && (Type.getClass(p) != Object3D || p.parent != sceneData);
			if(autoCenter) {
				var parentMat = worldMat(getObject(p.parent));
				parentMat.invert();
				var localMat = new h3d.Matrix();
				localMat.initTranslation(proj.x, proj.y, proj.z);
				localMat.multiply(localMat, parentMat);
				obj3d.setTransform(localMat);
			}

			autoName(p);
			haxe.Timer.delay(addObject.bind([p]), 0);
		}

		function addNewInstances() {
			var items = new Array<hide.comp.ContextMenu.ContextMenuItem>();
			for(type in DataFiles.getAvailableTypes() ) {
				var typeId = DataFiles.getTypeName(type);
				var label = typeId.charAt(0).toUpperCase() + typeId.substr(1);

				var refCols = Instance.findRefColumns(type);
				var refSheet = refCols == null ? null : type.base.getSheet(refCols.sheet);
				var idCol = refCols == null ? null : Instance.findIDColumn(refSheet);

				function make(name) {
					var p = new hrt.prefab.l3d.Instance(current == null ? sceneData : current);
					p.name = name;
					p.props = makeCdbProps(p, type);
					setup(p);
					if(onMake != null)
						onMake(p);
					return p;
				}

				if(idCol != null && refSheet.props.dataFiles == null ) {
					var kindItems = new Array<hide.comp.ContextMenu.ContextMenuItem>();
					for(line in refSheet.lines) {
						var kind : String = Reflect.getProperty(line, idCol.name);
						kindItems.push({
							label : kind,
							click : function() {
								var p = make(kind.charAt(0).toLowerCase() + kind.substr(1));
								var obj : Dynamic = p.props;
								for( c in refCols.cols ) {
									if( c == refCols.cols[refCols.cols.length-1] )
										Reflect.setField(obj, c.name, kind);
									else {
										var s = Reflect.field(obj,c.name);
										if( s == null ) {
											s = {};
											Reflect.setField(obj, c.name, s);
										}
										obj = s;
									}
								}
							}
						});
					}
					items.unshift({
						label : label,
						menu: kindItems
					});
				}
				else {
					items.push({
						label : label,
						click : make.bind(typeId)
					});
				}
			}
			newItems.unshift({
				label : "Instance",
				menu: items
			});
		};
		addNewInstances();
		return newItems;
	}

	override function getAvailableTags(p:PrefabElement) {
		return cast ide.currentConfig.get("l3d.tags");
	}
}

class Level3D extends FileView {

	public var sceneEditor : Level3DSceneEditor;
	var data : hrt.prefab.l3d.Level3D;
	var tabs : hide.comp.Tabs;

	var tools : hide.comp.Toolbar;

	var levelProps : hide.comp.PropsEditor;

	var layerToolbar : hide.comp.Toolbar;
	var layerButtons : Map<PrefabElement, hide.comp.Toolbar.ToolToggle>;

	var grid : h3d.scene.Graphics;
	var curGridSize : Int;
	var curGridWidth : Int;
	var curGridHeight : Int;

	var showGrid = false;
	var currentVersion : Int = 0;
	var lastSyncChange : Float = 0.;
	var sceneFilters : Map<String, Bool>;
	var statusText : h2d.Text;
	var posToolTip : h2d.Text;

	var scene(get, null):  hide.comp.Scene;
	function get_scene() return sceneEditor.scene;
	public var properties(get, null):  hide.comp.PropsEditor;
	function get_properties() return sceneEditor.properties;

	override function onDisplay() {
		data = cast(hrt.prefab.Library.create("l3d"), hrt.prefab.l3d.Level3D);
		var content = sys.io.File.getContent(getPath());
		data.loadData(haxe.Json.parse(content));
		currentSign = haxe.crypto.Md5.encode(content);

		element.html('
			<div class="flex vertical">
				<div style="flex: 0 0 30px;">
					<span class="tools-buttons"></span>
					<span class="layer-buttons"></span>
				</div>
				<div style="display: flex; flex-direction: row; flex: 1; overflow: hidden;">
					<div class="heaps-scene">
					</div>
					<div class="hide-scene-outliner">
						<div class="favorites" style="height:20%;">
							<label>Favorites</label>
							<div class="favorites-tree"></div>
						</div>
						<div style="height:80%;" class="flex vertical">
							<div class="hide-toolbar" style="zoom: 80%">
								<div class="button collapse-btn" title="Collapse all">
									<div class="icon fa fa-reply-all"></div>
								</div>
							</div>
							<div class="hide-scenetree"></div>
						</div>
					</div>
					<div class="tabs">
						<div class="tab expand" name="Scene" icon="sitemap">
							<div class="hide-scroll"></div>
						</div>
						<div class="tab expand" name="Properties" icon="cog">
							<div class="level-props"></div>
						</div>
					</div>
				</div>
			</div>
		');
		tools = new hide.comp.Toolbar(null,element.find(".tools-buttons"));
		layerToolbar = new hide.comp.Toolbar(null,element.find(".layer-buttons"));
		tabs = new hide.comp.Tabs(null,element.find(".tabs"));
		tabs.allowMask();
		currentVersion = undo.currentID;

		levelProps = new hide.comp.PropsEditor(undo,null,element.find(".level-props"));
		sceneEditor = new Level3DSceneEditor(this, data);
		sceneEditor.addSearchBox(element.find(".hide-scenetree").first());
		element.find(".hide-scenetree").first().append(sceneEditor.tree.element);
		element.find(".favorites-tree").first().append(sceneEditor.favTree.element);
		element.find(".hide-scroll").first().append(sceneEditor.properties.element);
		element.find(".heaps-scene").first().append(sceneEditor.scene.element);
		sceneEditor.tree.element.addClass("small");
		sceneEditor.favTree.element.addClass("small");
		element.find(".collapse-btn").click(function(e) {
			sceneEditor.collapseTree();
		});

		// Level edit
		{
			var edit = new LevelEditContext(this, sceneEditor.context);
			edit.prefabPath = state.path;
			edit.properties = levelProps;
			edit.scene = sceneEditor.scene;
			edit.cleanups = [];
			data.edit(edit);
		}

		refreshSceneFilters();
	}

	public function onSceneReady() {

		tools.saveDisplayKey = "Level3D/toolbar";
		tools.addButton("video-camera", "Perspective camera", () -> resetCamera(false));
		tools.addButton("video-camera", "Top camera", () -> resetCamera(true)).find(".icon").css({transform: "rotateZ(90deg)"});
		tools.addToggle("anchor", "Snap to ground", (v) -> sceneEditor.snapToGround = v, sceneEditor.snapToGround);
		var localToggle = tools.addToggle("compass", "Local transforms", (v) -> sceneEditor.localTransform = v, sceneEditor.localTransform);
		keys.register("sceneeditor.toggleLocal", () -> localToggle.toggle(!localToggle.isDown()));
		var gridToggle = tools.addToggle("th", "Show grid", function(v) { showGrid = v; updateGrid(); }, showGrid);
		keys.register("sceneeditor.toggleGrid", () -> gridToggle.toggle(!gridToggle.isDown()));
		tools.addButton("sun-o", "Bake Lights", () -> bakeLights());
		tools.addButton("map", "Bake Volumetric Lightmaps", () -> { bakeLights(); bakeVolumetricLightmaps(); });


		statusText = new h2d.Text(hxd.res.DefaultFont.get(), scene.s2d);
		statusText.setPosition(5, 5);
		statusText.visible = false;
		var texContent : Element = null;
		tools.addToggle("info-circle", "Scene information", function(b) statusText.visible = b).rightClick(function() {
			if( texContent != null ) {
				texContent.remove();
				texContent = null;
			}
			new hide.comp.ContextMenu([
				{
					label : "Show Texture Details",
					click : function() {
						var memStats = scene.engine.mem.stats();
						var texs = @:privateAccess scene.engine.mem.textures;
						var list = [for(t in texs) {
							n: '${t.width}x${t.height}  ${t.format}  ${t.name}',
							size: t.width * t.height
						}];
						list.sort((a, b) -> Reflect.compare(b.size, a.size));
						var content = new Element('<div tabindex="1" class="overlay-info"><h2>Scene info</h2><pre></pre></div>');
						new Element(element[0].ownerDocument.body).append(content);
						var pre = content.find("pre");
						pre.text([for(l in list) l.n].join("\n"));
						texContent = content;
						content.blur(function(_) {
							content.remove();
							texContent = null;
						});
					}
				}
			]);
		});

		tools.addColor("Background color", function(v) {
			scene.engine.backgroundColor = v;
			updateGrid();
		}, scene.engine.backgroundColor);

		posToolTip = new h2d.Text(hxd.res.DefaultFont.get(), scene.s2d);
		posToolTip.dropShadow = { dx : 1, dy : 1, color : 0, alpha : 0.5 };

		updateStats();
		updateGrid();
	}

	function updateStats() {
		var memStats = scene.engine.mem.stats();
		@:privateAccess
		var lines : Array<String> = [
			'Scene objects: ${scene.s3d.getObjectsCount()}',
			'Interactives: ' + sceneEditor.interactives.count(),
			'Contexts: ' + sceneEditor.context.shared.contexts.count(),
			'Triangles: ${scene.engine.drawTriangles}',
			'Buffers: ${memStats.bufferCount}',
			'Textures: ${memStats.textureCount}',
			'FPS: ${Math.round(scene.engine.realFps)}',
			'Draw Calls: ${scene.engine.drawCalls}',
		];
		statusText.text = lines.join("\n");
		sceneEditor.event.wait(0.5, updateStats);
	}

	function bakeLights() {
		var curSel = sceneEditor.curEdit.elements;
		sceneEditor.selectObjects([]);
		var passes = [];
		for( m in scene.s3d.getMaterials() ) {
			var s = m.getPass("shadow");
			if( s != null && !s.isStatic ) passes.push(s);
		}
		for( p in passes )
			p.isStatic = true;

		function isDynamic(elt: hrt.prefab.Prefab) {
			var p = elt;
			while(p != null) {
				if(p.name == "dynamic")
					return true;
				p = p.parent;
			}
			return false;
		}

		for(elt in data.flatten()) {
			if(Std.is(elt, Instance) || isDynamic(elt)) {
				var mats = sceneEditor.context.shared.getMaterials(elt);
				for(mat in mats) {
					var p = mat.getPass("shadow");
					if(p != null)
						p.isStatic = false;
				}
			}
		}

		scene.s3d.computeStatic();
		for( p in passes )
			p.isStatic = false;
		var lights = data.getAll(hrt.prefab.Light);
		for( l in lights ) {
			if(!l.visible)
				continue;
			l.saveBaked(sceneEditor.context);
		}
		sceneEditor.selectObjects(curSel);
	}

	function bakeVolumetricLightmaps(){
		var volumetricLightmaps = data.getAll(hrt.prefab.vlm.VolumetricLightmap);
		var total = 0;
		for( v in volumetricLightmaps )
			total += v.volumetricLightmap.getProbeCount();
		if( total == 0 )
			return;
		if( !ide.confirm("Bake "+total+" probes?") )
			return;
		function bakeNext() {
			var v = volumetricLightmaps.shift();
			if( v == null ) {
				ide.message("Done");
				return;
			}
			v.startBake(sceneEditor.curEdit, bakeNext);
			sceneEditor.selectObjects([v]);
		}
		bakeNext();
	}

	function resetCamera( top : Bool ) {
		var targetPt = new h3d.col.Point(0, 0, 0);
		var curEdit = sceneEditor.curEdit;
		if(curEdit != null && curEdit.rootObjects.length > 0) {
			targetPt = curEdit.rootObjects[0].getAbsPos().getPosition().toPoint();
		}
		if(top)
			sceneEditor.cameraController.set(200, Math.PI/2, 0.001, targetPt);
		else
			sceneEditor.cameraController.set(200, -4.7, 0.8, targetPt);
		sceneEditor.cameraController.toTarget();
	}

	override function getDefaultContent() {
		return haxe.io.Bytes.ofString(ide.toJSON(new hrt.prefab.l3d.Level3D().saveData()));
	}

	override function save() {
		var content = ide.toJSON(data.saveData());
		var newSign = haxe.crypto.Md5.encode(content);
		if(newSign != currentSign)
			haxe.Timer.delay(saveBackup.bind(content), 0);
		currentSign = newSign;
		sys.io.File.saveContent(getPath(), content);
		super.save();
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
		curGridSize = data.gridSize;
		curGridWidth = data.width;
		curGridHeight = data.height;

		var col = h3d.Vector.fromColor(scene.engine.backgroundColor);
		var hsl = col.toColorHSL();
		if(hsl.z > 0.5) hsl.z -= 0.1;
		else hsl.z += 0.1;
		col.makeColor(hsl.x, hsl.y, hsl.z);

		grid.lineStyle(1.0, col.toColor(), 1.0);
		for(ix in 0... hxd.Math.floor(data.width / data.gridSize )+1) {
			grid.moveTo(ix * data.gridSize, 0, 0);
			grid.lineTo(ix * data.gridSize, data.height, 0);
		}
		for(iy in 0...  hxd.Math.floor(data.height / data.gridSize )+1) {
			grid.moveTo(0, iy * data.gridSize, 0);
			grid.lineTo(data.width, iy * data.gridSize, 0);
		}
		grid.lineStyle(0);
	}

	function onUpdate(dt:Float) {
		if(hxd.Key.isDown(hxd.Key.ALT)) {
			posToolTip.visible = true;
			var proj = sceneEditor.screenToGround(scene.s2d.mouseX, scene.s2d.mouseY);
			posToolTip.text = proj != null ? '${Math.fmt(proj.x)}, ${Math.fmt(proj.y)}, ${Math.fmt(proj.z)}' : '???';
			posToolTip.setPosition(scene.s2d.mouseX, scene.s2d.mouseY - 12);
		}
		else {
			posToolTip.visible = false;
		}

		if( curGridSize != data.gridSize || curGridWidth != data.width || curGridHeight != data.height ) {
			updateGrid();
		}

	}

	function onRefresh() {
	}

	override function onDragDrop(items : Array<String>, isDrop : Bool) {
		return sceneEditor.onDragDrop(items, isDrop);
	}

	function applySceneFilter(typeid: String, visible: Bool) {
		saveDisplayState("sceneFilters/" + typeid, visible);
		var all = data.flatten(hrt.prefab.Prefab);
		for(p in all) {
			if(p.type == typeid || p.getCdbType() == typeid) {
				sceneEditor.applySceneStyle(p);
			}
		}
	}

	function refreshSceneFilters() {
		var filters : Array<String> = ide.currentConfig.get("l3d.filterTypes");
		filters = filters.copy();
		for(sheet in DataFiles.getAvailableTypes()) {
			filters.push(DataFiles.getTypeName(sheet));
		}
		sceneFilters = new Map();
		for(f in filters) {
			sceneFilters.set(f, getDisplayState("sceneFilters/" + f) != false);
		}

		if(layerButtons != null) {
			for(b in layerButtons)
				b.element.remove();
		}
		layerButtons = new Map<PrefabElement, hide.comp.Toolbar.ToolToggle>();
		var initDone = false;
		for(typeid in sceneFilters.keys()) {
			var btn = layerToolbar.addToggle("", typeid, typeid.charAt(0).toLowerCase() + typeid.substr(1), function(on) {
				sceneFilters.set(typeid, on);
				if(initDone)
					applySceneFilter(typeid, on);
			});
			if(sceneFilters.get(typeid) != false)
				btn.toggle(true);
		}
		initDone = true;
	}

	function applyTreeStyle(p: PrefabElement, el: Element, pname: String) {
		/*
		var styles = ide.currentConfig.get("l3d.treeStyles");
		var style: Dynamic = null;
		var typeId = getCdbTypeId(p);
		if(typeId != null) {
			style = Reflect.field(styles, typeId);
		}
		if(style == null) {
			style = Reflect.field(styles, p.name);
		}
		var a = el.find("a").first();
		a.addClass("crop");
		if(style == null)
			a.removeAttr("style");
		else
			a.css(style);
			*/
	}

	function onPrefabChange(p: PrefabElement, ?pname: String) {

	}

	function applySceneStyle(p: PrefabElement) {
		var level3d = Std.downcast(p, hrt.prefab.l3d.Level3D); // don't use "to" (Reference)
		if(level3d != null) {
			updateGrid();
			return;
		}
		var obj3d = p.to(Object3D);
		if(obj3d != null) {
			var visible = obj3d.visible && !sceneEditor.isHidden(obj3d) && sceneFilters.get(p.type) != false;
			if(visible) {
				var cdbType = p.getCdbType();
				if(cdbType != null && sceneFilters.get(cdbType) == false)
					visible = false;
			}
			for(ctx in sceneEditor.getContexts(obj3d)) {
				ctx.local3d.visible = visible;
			}
		}
		var color = getDisplayColor(p);
		if(color != null){
			color = (color & 0xffffff) | 0xa0000000;
			var box = p.to(hrt.prefab.Box);
			if(box != null) {
				var ctx = sceneEditor.getContext(box);
				box.setColor(ctx, color);
			}
			var poly = p.to(hrt.prefab.l3d.Polygon);
			if(poly != null) {
				var ctx = sceneEditor.getContext(poly);
				poly.setColor(ctx, color);
			}
		}
	}

	function getDisplayColor(p: PrefabElement) : Null<Int> {
		var typeId = p.getCdbType();
		if(typeId != null) {
			var colors = ide.currentConfig.get("l3d.colors");
			var color = Reflect.field(colors, typeId);
			if(color != null) {
				return Std.parseInt("0x"+color.substr(1)) | 0xff000000;
			}
		}
		return null;
	}

	function getGroundPrefabs() {
		var groundGroups = data.findAll(p -> if(p.name == "ground") p else null);
		if( groundGroups.length == 0 )
			return null;
		var ret : Array<hrt.prefab.Prefab> = [];
		for(group in groundGroups)
			group.findAll(function(p) : hrt.prefab.Prefab {
				if(p.name == "nocollide")
					return null;
				return p;
			},ret);
		return ret;
	}

	static var _ = FileTree.registerExtension(Level3D,["l3d"],{ icon : "sitemap", createNew : "Level3D" });
}