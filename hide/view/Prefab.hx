package hide.view;

import hide.prefab.Prefab in PrefabElement;

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
	var data : hxd.prefab.Library;
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
	var currentSign : String;

	override function getDefaultContent() {
		return haxe.io.Bytes.ofString(ide.toJSON(new hxd.prefab.Library().save()));
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
		super.save();
	}

	override function onDisplay() {
		saveDisplayKey = "Prefab:" + getPath().split("\\").join("/").substr(0,-1);
		data = new hxd.prefab.Library();
		var content = sys.io.File.getContent(getPath());
		data.load(haxe.Json.parse(content));
		currentSign = haxe.crypto.Md5.encode(content);

		element.html('
			<div class="flex vertical">
				<div class="toolbar"></div>
				<div class="flex">
					<div class="scene">
					</div>
					<div class="tabs">
						<div class="tab expand" name="Scene" icon="sitemap">
							<div class="hide-block">
								<div class="hide-list hide-scene-tree">
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
		element.find(".hide-scene-tree").first().append(sceneEditor.tree.element);
		element.find(".tab").first().append(sceneEditor.properties.element);
		element.find(".scene").first().append(sceneEditor.scene.element);
		currentVersion = undo.currentID;
	}

	public function onSceneReady() {
		light = sceneEditor.scene.s3d.find(function(o) return Std.instance(o, h3d.scene.fwd.DirLight));
		if( light == null ) {
			light = new h3d.scene.fwd.DirLight(scene.s3d);
			light.enableSpecular = true;
		} else
			light = null;

		tools.saveDisplayKey = "Prefab/tools";
		tools.addButton("video-camera", "Perspective camera", () -> sceneEditor.resetCamera());

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
		if( light != null ) {
			var angle = Math.atan2(cam.target.y - cam.pos.y, cam.target.x - cam.pos.x);
			light.setDirection(new h3d.Vector(
				Math.cos(angle) * lightDirection.x - Math.sin(angle) * lightDirection.y,
				Math.sin(angle) * lightDirection.x + Math.cos(angle) * lightDirection.y,
				lightDirection.z
			));
		}
		if( autoSync && (currentVersion != undo.currentID || lastSyncChange != properties.lastChange) ) {
			save();
			lastSyncChange = properties.lastChange;
			currentVersion = undo.currentID;
		}
	}

	static var _ = FileTree.registerExtension(Prefab,["prefab"],{ icon : "sitemap", createNew : "Prefab" });
}