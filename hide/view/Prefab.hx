package hide.view;

import hrt.prefab.Prefab in PrefabElement;

@:access(hide.view.Prefab)
private class PrefabSceneEditor extends hide.comp.SceneEditor {
	var parent : Prefab;
	public function new(view, data) {
		super(view, data);
		parent = cast view;
	}
	override function onSceneReady() {
		super.onSceneReady();
		parent.onSceneReady();
	}
	override function update(dt) {
		super.update(dt);
		parent.onUpdate(dt);
	}
	override function refresh(?mode, ?callb:Void->Void) {
		refreshScene();
		refreshTree(callb);
	}
}

class Prefab extends FileView {

	var sceneEditor : PrefabSceneEditor;
	var data : hrt.prefab.Library;
	var tabs : hide.comp.Tabs;

	var tools : hide.comp.Toolbar;
	var light : h3d.scene.fwd.DirLight;
	var lightDirection = new h3d.Vector( 1, 2, -4 );

	var scene(get, null):  hide.comp.Scene;
	function get_scene() return sceneEditor.scene;
	var properties(get, null):  hide.comp.PropsEditor;
	function get_properties() return sceneEditor.properties;

	// autoSync
	var autoSync : Bool;
	var currentVersion : Int = 0;
	var lastSyncChange : Float = 0.;

	override function getDefaultContent() {
		return haxe.io.Bytes.ofString(ide.toJSON(new hrt.prefab.Library().saveData()));
	}

	override function save() {
		var content = ide.toJSON(data.saveData());
		currentSign = haxe.crypto.Md5.encode(content);
		sys.io.File.saveContent(getPath(), content);
		super.save();
	}

	override function onDisplay() {
		if( sceneEditor != null ) sceneEditor.dispose();

		data = new hrt.prefab.Library();
		var content = sys.io.File.getContent(getPath());
		data.loadData(haxe.Json.parse(content));
		currentSign = haxe.crypto.Md5.encode(content);

		element.html('
			<div class="flex vertical prefabview">
				<div class="toolbar"></div>
				<div class="flex-elt">
					<div class="heaps-scene">
					</div>
					<div class="tabs">
						<div class="tab expand" name="Scene" icon="sitemap">
							<div class="hide-block">
								<div class="hide-list scenetree">
								</div>
							</div>
						</div>
					</div>
				</div>
			</div>
		');
		tools = new hide.comp.Toolbar(null,element.find(".toolbar"));
		tabs = new hide.comp.Tabs(null,element.find(".tabs"));
		sceneEditor = new PrefabSceneEditor(this, data);
		element.find(".scenetree").first().append(sceneEditor.tree.element);
		element.find(".tab").first().append(sceneEditor.properties.element);
		element.find(".heaps-scene").first().append(sceneEditor.scene.element);
		currentVersion = undo.currentID;
	}

	public function onSceneReady() {
		tabs.allowMask(scene);

		// TOMORROW this isn't in the Level3D view
		{
			light = sceneEditor.scene.s3d.find(function(o) return Std.downcast(o, h3d.scene.fwd.DirLight));
			if( light == null ) {
				light = new h3d.scene.fwd.DirLight(scene.s3d);
				light.enableSpecular = true;
			} else
				light = null;
		}

		tools.saveDisplayKey = "Prefab/tools";

		tools.addToggle("arrows", "2D Camera", (b) -> sceneEditor.camera2D = b);
		tools.addButton("video-camera", "Default camera", () -> sceneEditor.resetCamera());

		tools.addColor("Background color", function(v) {
			scene.engine.backgroundColor = v;
		}, scene.engine.backgroundColor);
		tools.addToggle("refresh", "Auto synchronize", function(b) {
			autoSync = b;
		});
		tools.addRange("Speed", function(v) {
			scene.speed = v;
		}, scene.speed);
	}

	function onUpdate(dt:Float) {
		var cam = scene.s3d.camera;

		// TOMORROW this isn't in the Level3D view
		{
			if( light != null ) {
				var angle = Math.atan2(cam.target.y - cam.pos.y, cam.target.x - cam.pos.x);
				light.setDirection(new h3d.Vector(
					Math.cos(angle) * lightDirection.x - Math.sin(angle) * lightDirection.y,
					Math.sin(angle) * lightDirection.x + Math.cos(angle) * lightDirection.y,
					lightDirection.z
				));
			}
		}

		if( autoSync && (currentVersion != undo.currentID || lastSyncChange != properties.lastChange) ) {
			save();
			lastSyncChange = properties.lastChange;
			currentVersion = undo.currentID;
		}
	}

	override function onDragDrop(items : Array<String>, isDrop : Bool) {
		return sceneEditor.onDragDrop(items,isDrop);
	}

	// TOMORROW Comment this? but then the transition breaks existing tabs
	// static var _ = FileTree.registerExtension(Prefab,["prefab"],{ icon : "sitemap" });
}