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
private class Level3DSceneEditor extends hide.comp.SceneEditor {
	var parent : Level3D;

	public function new(view, context, data) {
		super(view, context, data);
		parent = cast view;
	}

	override function refresh(?callback) {
		super.refresh(callback);
		parent.refreshLayerIcons();
	}
	override function update(dt) {
		super.update(dt);
		parent.onUpdate(dt);
	}
	override function onSceneReady() {
		super.onSceneReady();
		parent.onSceneReady();
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
			var collider = polygon.mesh.getGlobalCollider();
			var d = collider.rayIntersection(ray, true);
			if(d > 0 && (d < minDist || minDist < 0)) {
				minDist = d;
			}
		}
		if(minDist >= 0)
			return minDist;
		return super.projectToGround(ray);
	}
	override function getNewContextMenu() {
		var current = tree.getCurrentOver();
		var newItems = new Array<hide.comp.ContextMenu.ContextMenuItem>();
		var allRegs = @:privateAccess hide.prefab.Library.registeredElements;
		var allowed = ["model", "object", "layer", "box", "polygon"];
		for( ptype in allowed ) {
			var pcl = allRegs.get(ptype);
			var props = Type.createEmptyInstance(pcl).getHideProps();
			newItems.push({
				label : props.name,
				click : function() {

					function make(?path) {
						var p = Type.createInstance(pcl, [current == null ? sceneData : current]);
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

		function addNewInstances() {
			if(current == null)
				return;
			var curLayer = current.to(hide.prefab.l3d.Layer);
			if(curLayer == null)
				return;
			var cdbSheet = curLayer.getCdbModel();
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
							p.props = {};
							for( c in cdbSheet.columns ) {
								var d = cdbSheet.base.getDefault(c);
								if( d != null )
									Reflect.setField(p.props, c.name, d);
							}
							p.name = kind.charAt(0).toLowerCase + kind.substr(1) + "_";
							Reflect.setField(p.props, refCol.col.name, kind);
							autoName(p);
							addObject(p);
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
						autoName(p);
						addObject(p);
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
	var light : h3d.scene.DirLight;
	var lightDirection = new h3d.Vector( 1, 2, -4 );

	var layerToolbar : hide.comp.Toolbar;	
	var layerButtons : Map<PrefabElement, hide.comp.Toolbar.ToolToggle>;

	var grid : h3d.scene.Graphics;
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

		root.html('
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
							<div class="hide-block">
								<div class="hide-list hide-scene-tree">
								</div>
							</div>
						</div>
						<div class="tab" name="Properties" icon="cog">
							<div class="level-props"></div>
						</div>
					</div>
				</div>
			</div>
		');
		tools = new hide.comp.Toolbar(root.find(".tools-buttons"));
		layerToolbar = new hide.comp.Toolbar(root.find(".layer-buttons"));
		tabs = new hide.comp.Tabs(root.find(".tabs"));
		currentVersion = undo.currentID;

		levelProps = new hide.comp.PropsEditor(root.find(".level-props"), undo);
		sceneEditor = new Level3DSceneEditor(this, context, data);
		sceneEditor.addSearchBox(root.find(".hide-scene-tree").first());
		root.find(".hide-scene-tree").first().append(sceneEditor.tree.root);
		root.find(".tab").first().append(sceneEditor.properties.root);
		root.find(".scene").first().append(sceneEditor.scene.root);
		sceneEditor.tree.root.addClass("small");

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
		light = sceneEditor.scene.s3d.find(function(o) return Std.instance(o, h3d.scene.DirLight));
		if( light == null ) {
			light = new h3d.scene.DirLight(new h3d.Vector(), scene.s3d);
			light.enableSpecular = true;
		}
		else
			light = null;

		tools.saveDisplayKey = "Level3D/toolbar";
		tools.addButton("video-camera", "Perspective camera", () -> sceneEditor.resetCamera(false));
		tools.addButton("arrow-down", "Top camera", () -> sceneEditor.resetCamera(true));
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
		if(grid == null) {
			grid = new h3d.scene.Graphics(scene.s3d);
			grid.scale(1);
		}
		else {
			grid.clear();
		}

		grid.lineStyle(1, 0x404040, 1.0);
		// var offset = size/2;
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
		if( light != null ) {
			var angle = Math.atan2(cam.target.y - cam.pos.y, cam.target.x - cam.pos.x);
			light.direction.set(
				Math.cos(angle) * lightDirection.x - Math.sin(angle) * lightDirection.y,
				Math.sin(angle) * lightDirection.x + Math.cos(angle) * lightDirection.y,
				lightDirection.z
			);
		}
		if( autoSync && (currentVersion != undo.currentID || lastSyncChange != properties.lastChange) ) {
			save();
			lastSyncChange = properties.lastChange;
			currentVersion = undo.currentID;
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
				sceneEditor.dropModels(models);
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
		}
		initDone = true;
	}

	function updateTreeStyle(p: PrefabElement, el: Element) {
		var layer = p.to(hide.prefab.l3d.Layer);
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
		}
	}

	function onPrefabChange(p: PrefabElement, ?pname: String) {
		var level3d = p.to(hide.prefab.l3d.Level3D);
		if(level3d != null) {
			updateGrid();
			return;
		}
		var layer = p.to(hide.prefab.l3d.Layer);
		if(layer != null) {
			var obj3ds = layer.getAll(hide.prefab.Object3D);
			for(obj in obj3ds) {
				var i = @:privateAccess sceneEditor.interactives.get(obj);
				if(i != null) i.visible = !layer.locked;
			}
			for(box in layer.getAll(hide.prefab.Box)) {
				box.setColor(layer.color);
			}
			for(poly in layer.getAll(hide.prefab.l3d.Polygon)) {
				poly.setColor(layer.color);
			}
		}
	}

	function getGroundPolys() {
		var gname = props.get("l3d.groundLayer");
		var groundLayer = data.get(Layer, gname);
		var polygons = groundLayer.getAll(hide.prefab.l3d.Polygon);
		return polygons;
	}

	static var _ = FileTree.registerExtension(Level3D,["l3d"],{ icon : "sitemap", createNew : "Level3D" });

}