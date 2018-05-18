package hide.view;

import hide.prefab.Prefab in PrefabElement;

@:access(hide.view.Prefab)
private class PrefabSceneEditor extends hide.comp.SceneEditor {
	var parent : Prefab;
	public function new(view, context, data) {
		super(view, context, data);
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

	override function getNewContextMenu() {
		var current = tree.getCurrentOver();
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
						var p = Type.createInstance(pcl, [current == null ? sceneData : current]);
						@:privateAccess p.type = ptype;
						autoName(p);
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
		return registered;
	}
}

class Prefab extends FileView {

	var sceneEditor : PrefabSceneEditor;
	var data : hide.prefab.Library;
	var context : hide.prefab.Context;
	var tabs : hide.comp.Tabs;

	var tools : hide.comp.Toolbar;
	var light : h3d.scene.DirLight;
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
		saveDisplayKey = "Prefab:" + getPath().split("\\").join("/").substr(0,-1);
		data = new hide.prefab.Library();
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
				<div class="toolbar"></div>
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
					</div>
				</div>
			</div>
		');
		tools = new hide.comp.Toolbar(null,root.find(".toolbar"));
		tabs = new hide.comp.Tabs(null,root.find(".tabs"));
		sceneEditor = new PrefabSceneEditor(this, context, data);
		root.find(".hide-scene-tree").first().append(sceneEditor.tree.root);
		root.find(".tab").first().append(sceneEditor.properties.root);
		root.find(".scene").first().append(sceneEditor.scene.root);
		currentVersion = undo.currentID;
	}

	public function onSceneReady() {
		light = sceneEditor.scene.s3d.find(function(o) return Std.instance(o, h3d.scene.DirLight));
		if( light == null ) {
			light = new h3d.scene.DirLight(new h3d.Vector(), scene.s3d);
			light.enableSpecular = true;
		} else
			light = null;

		tools.saveDisplayKey = "Prefab/tools";
		tools.addButton("video-camera", "Perspective camera", () -> sceneEditor.resetCamera(false));
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
		tools.addRange("Speed", function(v) {
			scene.speed = v;
		}, scene.speed);
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

	static var _ = FileTree.registerExtension(Prefab,["prefab"],{ icon : "sitemap", createNew : "Prefab" });
}