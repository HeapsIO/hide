package hide.view;

import hide.Element;
import hide.prefab.Prefab in PrefabElement;

@:access(hide.view.FXScene)
private class FXSceneEditor extends hide.comp.SceneEditor {
	var parent : hide.view.FXScene;
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

	override function selectObjects( elts, ?includeTree) {
		super.selectObjects(elts, includeTree);
		parent.onSelect(elts);
	}

	override function getNewContextMenu() {
		var current = tree.getCurrentOver();
		var registered = new Array<hide.comp.ContextMenu.ContextMenuItem>();
		var allRegs = @:privateAccess hide.prefab.Library.registeredElements;
		var allowed = ["model", "object"];
		for( ptype in allowed ) {
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

class FXScene extends FileView {

	var sceneEditor : FXSceneEditor;
	var data : hide.prefab.fx.FXScene;
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
		return haxe.io.Bytes.ofString(ide.toJSON(new hide.prefab.fx.FXScene().save()));
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
		saveDisplayKey = "FX:" + getPath().split("\\").join("/").substr(0,-1);
		data = new hide.prefab.fx.FXScene();
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
				<div class="fx-animpanel">
				</div>
			</div>
		');
		tools = new hide.comp.Toolbar(root.find(".toolbar"));
		tabs = new hide.comp.Tabs(root.find(".tabs"));
		sceneEditor = new FXSceneEditor(this, context, data);
		root.find(".hide-scene-tree").first().append(sceneEditor.tree.root);
		root.find(".tab").first().append(sceneEditor.properties.root);
		root.find(".scene").first().append(sceneEditor.scene.root);
		currentVersion = undo.currentID;

		var animPanel = root.find(".fx-animpanel");
		var curve = new hide.prefab.Curve();
		curve.duration = 3.;
		curve.keys.push({
			time: 0.1,
			value: 1.0,
			prevHandle: {
				dt: -0.09,
				dv: -0.1
			},
			nextHandle: {
				dt: 0.12,
				dv: -0.1
			},
		});
		for(i in 0...2) {
			curve.keys.push({
				time: i + 1.0,
				value: -1.0,
				prevHandle: {
					dt: -0.09,
					dv: -0.1
				},
				nextHandle: {
					dt: 0.3,
					dv: -0.1
				},
			});
		}
		var curveAnim = new hide.comp.CurveEditor(animPanel, curve, this.undo);
	}

	public function onSceneReady() {
		light = sceneEditor.scene.s3d.find(function(o) return Std.instance(o, h3d.scene.DirLight));
		if( light == null ) {
			light = new h3d.scene.DirLight(new h3d.Vector(), scene.s3d);
			light.enableSpecular = true;
		} else
			light = null;


		this.saveDisplayKey = "Scene:" + state.path;

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

	function onSelect(elts : Array<PrefabElement>) {

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

	static var _ = FileTree.registerExtension(FXScene,["fx"], { icon : "sitemap", createNew : "FX" });
}