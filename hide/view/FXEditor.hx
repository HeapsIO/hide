package hide.view;
import hide.view.FileTree;
import hrt.prefab.Light;
using Lambda;

import hide.Element;
import hrt.prefab.Prefab in PrefabElement;
import hrt.prefab.Curve;
import hrt.prefab.fx.Event;
import hide.view.CameraController.CamController;

typedef PropTrackDef = {
	name: String,
	?def: Float
};

typedef Section = {
	root: PrefabElement,
	curves: Array<Curve>,
	children: Array<Section>,
	events: Array<IEvent>
};

@:access(hide.view.FXEditor)
class FXEditContext extends hide.prefab.EditContext {
	var parent : FXEditor;
	public function new(parent) {
		super();
		this.parent = parent;
	}
	override function onChange(p, propName) {
		super.onChange(p, propName);
		parent.onPrefabChange(p, propName);
	}

	override function rebuildPrefab(p : hrt.prefab.Prefab, ?sceneOnly) {
		parent.sceneEditor.refreshScene();
	}
}

@:access(hide.view.FXEditor)
private class FXSceneEditor extends hide.comp.SceneEditor {
	var parent : hide.view.FXEditor;
	public var grid2d : h2d.Graphics;
	public var is2D : Bool = false;


	public function new(view,  data) {
		super(view, data);
		parent = cast view;
	}

	override function onSceneReady() {
		super.onSceneReady();
		parent.onSceneReady();
	}

	override function onPrefabChange(p: PrefabElement, ?pname: String) {
		super.onPrefabChange(p, pname);
		parent.onPrefabChange(p, pname);
	}

	override function update(dt) {
		super.update(dt);
		parent.onUpdate(dt);
	}

	override function updateStats() {
		super.updateStats();

		if( statusText.visible ) {
			var emitters = scene.s3d.findAll(o -> Std.downcast(o, hrt.prefab.fx.Emitter.EmitterObject));
			var totalParts = 0;
			for(e in emitters) {
				totalParts += @:privateAccess e.numInstances;
			}

			var emitterTime = 0.0;
			for (e in emitters) {
				emitterTime += e.tickTime;
			}

			var trails = scene.s3d.findAll(o -> Std.downcast(o, hrt.prefab.l3d.Trails.TrailObj));
			var trailTime = 0.0;


			var poolSize = 0;
			@:privateAccess
			for (trail in trails) {
				for (head in trail.trails) {
					var p = head.firstPoint;
					var len = 0;
					while(p != null) {
						len ++;
						p = p.next;
					}
				}
				trailTime += trail.lastUpdateDuration;
			}

			var text : Array<String> = [
				'Particles: $totalParts',
				'Particles CPU time: $emitterTime',
				'Trails CPU time: $trailTime',
			];
			statusText.text += "\n" + text.join("\n");
		}
	}

	override function createDroppedElement(path:String, parent:PrefabElement):hrt.prefab.Object3D {
		var type = hrt.prefab.Prefab.getPrefabType(path);
		if(type == "fx") {
			var relative = ide.makeRelative(path);
			var ref = new hrt.prefab.fx.SubFX(parent, null);
			ref.source = relative;
			ref.name = new haxe.io.Path(relative).file;
			return ref;
		}
		return super.createDroppedElement(path, parent);
	}

	override function updateGrid() {
		super.updateGrid();

		var showGrid = getOrInitConfig("sceneeditor.gridToggle", false);

		if(grid2d != null) {
			grid2d.remove();
			grid2d = null;
		}

		if(!showGrid)
			return;

		if (is2D) {
			grid2d = new h2d.Graphics(scene.s2d);
			grid2d.scale(1);

			grid2d.lineStyle(1.0, 12632256, 1.0);
			grid2d.moveTo(0, -2000);
			grid2d.lineTo(0, 2000);
			grid2d.moveTo(-2000, 0);
			grid2d.lineTo(2000, 0);
			grid2d.lineStyle(0);

			return;
		}
	}

	override function setElementSelected( p : PrefabElement, b : Bool ) {
		if( p.findParent(hrt.prefab.fx.Emitter) != null )
			return false;
		return super.setElementSelected(p, b);
	}

	override function selectElements( elts, ?mode ) {
		super.selectElements(elts, mode);
		parent.onSelect(elts);
	}

	override function refresh(?mode: hide.comp.SceneEditor.RefreshMode, ?callb:Void->Void) {
		// Always refresh scene
		refreshScene();
		refreshTree(callb);
		parent.onRefreshScene();
	}



	override function applyTreeStyle(p: PrefabElement, el: Element, ?pname: String) {
		super.applyTreeStyle(p, el, pname);
		if (el == null)
			return;

		var asCurve = Std.downcast(p, Curve);
		if (asCurve != null) {
			if (asCurve.blendMode == Blend || asCurve.blendMode == Reference) {
				var paramName = asCurve.blendParam;
				var color = 0xFFFFFF;
				var missing = false;
				var icon = "ico-random";
				if (asCurve.blendMode == Blend) {
					var fx = Std.downcast(this.parent.data, hrt.prefab.fx.FX);
					if (fx == null) {
						return;
					}
					var param = fx.parameters.find(function (p) {return p.name == paramName;});
					missing = param == null;
					color = param?.color;

				}
				else {
					var ref = (cast this.parent.data: hrt.prefab.Prefab).locatePrefab(asCurve.blendParam);
					if (ref == null) {
						missing = true;
					}
					icon = "ico-link";
				}

				var colorCode = StringTools.hex(missing ? 0xFF0000 : color, 6);
				var paramEl = el.find('>a>.fx-parameter');
				if (paramEl.length == 0 ){
					var v = new Element('<span class="fx-parameter"><i class="ico $icon"></i><span class="fx-param-name"></span></span>');
					el.find("a").first().append(v);
					paramEl = v;
				}
				var paramNameEl = paramEl.find(".fx-param-name");
				paramNameEl.get(0).innerText = '$paramName';
				paramEl.css("color", '#$colorCode');
				paramEl.toggleClass("missing", missing);
			}
			else {
				el.find(".fx-parameter").remove();
			}
		}
	}

	override function getNewContextMenu(current: PrefabElement, ?onMake: PrefabElement->Void=null, ?groupByType = true ) {
		if(current != null && current.to(hrt.prefab.Shader) != null) {
			var ret : Array<hide.comp.ContextMenu.ContextMenuItem> = [];
			ret.push({
				label: "Animation",
				menu: parent.getNewTrackMenu(current)
			});
			return ret;
		}
		var allTypes = super.getNewContextMenu(current, onMake, false);
		var recents = getNewRecentContextMenu(current, onMake);

		var menu = [];



		var shaderItems : Array<hide.comp.ContextMenu.ContextMenuItem> = [];

		if (parent.is2D) {
			for(name in ["Group 2D", "Bitmap", "Anim2D", "Atlas", "Particle2D", "Text", "Shader", "Shader Graph", "Placeholder"]) {
				var item = allTypes.find(i -> i.label == name);
				if(item == null) continue;
				allTypes.remove(item);
				if (name == "Shader") {
					shaderItems = item.menu;
					continue;
				}
				menu.push(item);
			}
			if(current != null) {
				menu.push({
					label: "Animation",
					menu: parent.getNewTrackMenu(current)
				});
			}
		} else {
			for(name in ["Group", "Polygon", "Model", "Shader", "Emitter", "Trails"]) {
				var item = allTypes.find(i -> i.label == name);
				if(item == null) continue;
				allTypes.remove(item);
				if (name == "Shader") {
					shaderItems = item.menu;
					continue;
				}
				menu.push(item);
			}
			if(current != null) {
				menu.push({
					label: "Animation",
					menu: parent.getNewTrackMenu(current)
				});
			}

			menu.push({
				label: "Material",
				menu: [
					getNewTypeMenuItem("material", current, onMake, "Default"),
					getNewTypeMenuItem("material", current, function (p) {
						// TODO: Move material presets to props.json
						p.props = {
							PBR: {
								mode: "BeforeTonemapping",
								blend: "Alpha",
								shadows: false,
								culling: "Back",
								colorMask: 0xff
							}
						}
						if(onMake != null) onMake(p);
					}, "Unlit")
				]
			});
			menu.sort(function(l1,l2) return Reflect.compare(l1.label,l2.label));
		}

		var events = allTypes.filter(i -> StringTools.endsWith(i.label, "Event"));
		if(events.length > 0) {
			menu.push({
				label: "Events",
				menu: events
			});
			for(e in events)
				allTypes.remove(e);
		}

		menu.push({label: null, isSeparator: true});

		splitMenu(menu, "Shader", shaderItems);

		menu.push({label: null, isSeparator: true});

		splitMenu(menu, "Other", allTypes);


		menu.unshift({
			label : "Recents",
			menu : recents,
		});
		return menu;
	}

	override function getAvailableTags(p:PrefabElement) {
		return cast ide.currentConfig.get("fx.tags");
	}
}

class FXEditor extends hide.view.FileView {

	var sceneEditor : FXSceneEditor;
	var data : hrt.prefab.fx.BaseFX;
	var is2D : Bool = false;

	var tools : hide.comp.Toolbar;
	var treePanel : hide.comp.ResizablePanel;
	var animPanel : hide.comp.ResizablePanel;
	var leftAnimPanel : hide.comp.ResizablePanel;
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

	var lastPan : h2d.col.Point;

	var timelineLeftMargin = 10;
	var xScale = 200.;
	var xOffset = 0.;
	var tlKeys: Array<{name:String, shortcut:String}> = [];

	var pauseButton : hide.comp.Toolbar.ToolToggle;
	@:isVar var currentTime(get, set) : Float;
	var selectMin : Float;
	var selectMax : Float;
	var previewMin : Float;
	var previewMax : Float;
	var curveEditor : hide.comp.CurveEditor;
	var afterPanRefreshes : Array<Bool->Void> = [];
	var statusText : h2d.Text;

	var scriptEditor : hide.comp.ScriptEditor;
	//var fxScriptParser : hrt.prefab.fx.FXScriptParser;
	var cullingPreview : h3d.scene.Sphere;

    var viewModes : Array<String>;

	override function getDefaultContent() {
		@:privateAccess return haxe.io.Bytes.ofString(ide.toJSON(new hrt.prefab.fx.FX(null, null).serialize()));
	}

	override function canSave() {
		return data != null;
	}

	override function save() {
		if( !canSave() )
			return;
		@:privateAccess var content = ide.toJSON(cast(data, hrt.prefab.Prefab).serialize());
		var newSign = ide.makeSignature(content);
		if(newSign != currentSign)
			haxe.Timer.delay(saveBackup.bind(content), 0);
		currentSign = newSign;
		sys.io.File.saveContent(getPath(), content);
		super.save();
	}

	override function onDisplay() {
		if( sceneEditor != null ) sceneEditor.dispose();
		currentTime = 0.;
		xOffset = -timelineLeftMargin / xScale;
		var content = sys.io.File.getContent(getPath());
		var json = haxe.Json.parse(content);

		if (json.type == "fx2d") {
			is2D = true;
			sceneEditor.is2D = true;
		}
		data = cast(PrefabElement.createFromDynamic(json), hrt.prefab.fx.BaseFX);
		currentSign = ide.makeSignature(content);

		element.html('
			<div class="flex vertical">
				<div style="flex: 0 0 30px;">
					<span class="tools-buttons"></span>
				</div>
				<div class="scene-partition" style="display: flex; flex-direction: row; flex: 1; overflow: hidden;">
					<div style="display: flex; flex-direction: column; flex: 1; overflow: hidden;">
						<div class="flex heaps-scene"></div>
						<div class="fx-animpanel">
							<div class="help-button icon ico ico-question" title="help"></div>
							<div class="left-fx-animpanel"></div>
							<div class="right-fx-animpanel"></div>
							<div class="overlay-container">
								<div class="overlay"></div>
							</div>
						</div>
					</div>
					<div class="tree-column">
						<div class="flex vertical">
							<div class="hide-toolbar" style="zoom: 80%">
								<div class="button collapse-btn" title="Collapse all">
									<div class="icon ico ico-reply-all"></div>
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
							<div class="fx-props"></div>
						</div>
						<div class="tab expand" name="Script" icon="cog">
							<div class="fx-script"></div>
							<div class="fx-scriptParams"></div>
						</div>
					</div>
				</div>
			</div>');
		tools = new hide.comp.Toolbar(null,element.find(".tools-buttons"));
		var tabs = new hide.comp.Tabs(null,element.find(".tabs"));
		sceneEditor = new FXSceneEditor(this, cast(data, hrt.prefab.Prefab));
		element.find(".hide-scenetree").first().append(sceneEditor.tree.element);
		element.find(".hide-scroll").first().append(sceneEditor.properties.element);
		element.find(".heaps-scene").first().append(sceneEditor.scene.element);

		var treeColumn = element.find(".tree-column").first();
		treePanel = new hide.comp.ResizablePanel(Horizontal, treeColumn);
		treePanel.saveDisplayKey = "treeColumn";
		treePanel.onResize = () -> @:privateAccess if( scene.window != null) scene.window.checkResize();

		var fxPanel = element.find(".fx-animpanel").first();
		animPanel = new hide.comp.ResizablePanel(Vertical, fxPanel);
		animPanel.saveDisplayKey = "animPanel";
		animPanel.onResize = () -> @:privateAccess { if( scene.window != null) scene.window.checkResize(); if( this.curveEditor != null) this.curveEditor.refresh();}

		var leftFxPanel = element.find(".left-fx-animpanel").first();
		leftAnimPanel = new hide.comp.ResizablePanel(Horizontal, leftFxPanel, After);
		leftAnimPanel.saveDisplayKey = "leftAnimPanel";
		leftAnimPanel.onResize = () -> { @:privateAccess if( scene.window != null) scene.window.checkResize(); rebuildAnimPanel(); };

		tlKeys.empty();
		tlKeys.push({name:"Undo", shortcut:"Ctrl Z"});
		tlKeys.push({name:"Drag / zoom on Y axis", shortcut:"Hold shift during action"});
		tlKeys.push({name:"Drag / zoom on X axis", shortcut:"Hold alt during action"});
		tlKeys.push({name:"Edit keyframe", shortcut:"Right-click"});
		tlKeys.push({name:"Snap keyframe", shortcut:"Ctrl while dragging"});
		tlKeys.push({name:"Zoom on curves", shortcut:"F"});
		tlKeys.push({name:"Move in curve graph", shortcut:"Mouse wheel"});

		var helpButton = element.find(".help-button").first();
		var p : hide.comp.Popup = null;
		helpButton.click(function(e) {
			if (p == null) {
				p = new hide.comp.SceneEditor.HelpPopup(null, helpButton, sceneEditor, tlKeys);
				@:privateAccess p.popup.css({'position':'absolute', 'left':'30px','top':'800px'});
				//p = open(el);
				p.onClose = function() {
					p = null;
				}
			}
			else {
				p.close();
			}
		});

		refreshLayout();
		element.resize(function(e) {
			rebuildAnimPanel();
		});
		element.find(".collapse-btn").click(function(e) {
			sceneEditor.collapseTree();
		});
		var fxprops = new hide.comp.PropsEditor(undo,null,element.find(".fx-props"));
		{
			var edit = new FXEditContext(this);
			edit.properties = fxprops;
			edit.scene = sceneEditor.scene;
			edit.cleanups = [];
			cast(data, hrt.prefab.Prefab).edit(edit);
		}

		if (is2D) {
			sceneEditor.camera2D = true;
		}

		var scriptElem = element.find(".fx-script");
		scriptEditor = new hide.comp.ScriptEditor(data.scriptCode, null, scriptElem, scriptElem);
		function onSaveScript() {
			data.scriptCode = scriptEditor.code;
			save();
			skipNextChange = true;
			modified = false;
		}
		scriptEditor.onSave = onSaveScript;
		//fxScriptParser = new hrt.prefab.fx.FXScriptParser();
		data.scriptCode = scriptEditor.code;

		keys.register("playPause", function() { pauseButton.toggle(!pauseButton.isDown()); });

		currentVersion = undo.currentID;
		sceneEditor.tree.element.addClass("small");

		selectMin = 0.0;
		selectMax = 0.0;
		previewMin = 0.0;
		previewMax = data.duration == 0 ? 5000 : data.duration;
	}

	function refreshLayout() {
		if (animPanel != null) animPanel.setSize();
		if (treePanel != null) treePanel.setSize();
	}

	override function onActivate() {
		if( sceneEditor != null )
			refreshLayout();
		if (tools != null)
			tools.refreshToggles();
	}
	public function onSceneReady() {
		light = sceneEditor.scene.s3d.find(function(o) return Std.downcast(o, h3d.scene.fwd.DirLight));
		if( light == null ) {
			light = new h3d.scene.fwd.DirLight(scene.s3d);
			light.enableSpecular = true;
		} else
			light = null;

		var axis = new h3d.scene.Graphics(scene.s3d);
		axis.z = 0.001;
		axis.lineStyle(2,0xFF0000); axis.lineTo(1,0,0);
		axis.lineStyle(1,0x00FF00); axis.moveTo(0,0,0); axis.lineTo(0,1,0);
		axis.lineStyle(1,0x0000FF); axis.moveTo(0,0,0); axis.lineTo(0,0,1);
		axis.lineStyle();
		axis.material.mainPass.setPassName("debuggeom");
		axis.visible = !is2D;

		cullingPreview = new h3d.scene.Sphere(0xffffff, data.cullingRadius, true, scene.s3d);
		cullingPreview.material.mainPass.setPassName("debuggeom");
		cullingPreview.visible = !is2D;

		var toolsDefs = new Array<hide.comp.Toolbar.ToolDef>();
		toolsDefs.push({id: "perspectiveCamera", title : "Perspective camera", icon : "video-camera", type : Button(() -> sceneEditor.resetCamera()) });
		toolsDefs.push({id: "camSettings", title : "Camera Settings", icon : "camera", type : Popup((e : hide.Element) -> new hide.comp.CameraControllerEditor(sceneEditor, null,e)) });

		toolsDefs.push({id: "", title : "", icon : "", type : Separator});

		toolsDefs.push({id: "translationMode", title : "Gizmo translation Mode", icon : "arrows", type : Button(@:privateAccess sceneEditor.gizmo.translationMode)});
		toolsDefs.push({id: "rotationMode", title : "Gizmo rotation Mode", icon : "refresh", type : Button(@:privateAccess sceneEditor.gizmo.rotationMode)});
		toolsDefs.push({id: "scalingMode", title : "Gizmo scaling Mode", icon : "expand", type : Button(@:privateAccess sceneEditor.gizmo.scalingMode)});

		toolsDefs.push({id: "", title : "", icon : "", type : Separator});

		toolsDefs.push({id: "toggleSnap", title : "Snap Toggle", icon: "magnet", type : Toggle((v) -> {sceneEditor.snapToggle = v; sceneEditor.updateGrid();})});
		toolsDefs.push({id: "snap-menu", title : "", icon: "", type : Popup((e) -> new hide.comp.SceneEditor.SnapSettingsPopup(null, e, sceneEditor))});

		toolsDefs.push({id: "", title : "", icon : "", type : Separator});

		toolsDefs.push({id: "localTransformsToggle", title : "Local transforms", icon : "compass", type : Toggle((v) -> sceneEditor.localTransform = v)});

		toolsDefs.push({id: "", title : "", icon : "", type : Separator});

		toolsDefs.push({id: "showViewportOverlays", title : "Viewport Overlays", icon : "eye", type : Toggle((v) -> { sceneEditor.updateViewportOverlays(); }) });
		toolsDefs.push({id: "viewportoverlays-menu", title : "", icon: "", type : Popup((e) -> new hide.comp.SceneEditor.ViewportOverlaysPopup(null, e, sceneEditor))});


		toolsDefs.push({id: "", title : "", icon : "", type : Separator});


		tools.saveDisplayKey = "FXScene/tools";

		tools.makeToolbar(toolsDefs, config, keys);

		function renderProps() {
			properties.clear();
			var renderer = scene.s3d.renderer;
			var group = new Element('<div class="group" name="Renderer"></div>');
			renderer.editProps().appendTo(group);
			properties.add(group, renderer.props, function(_) {
				renderer.refreshProps();
				if( !properties.isTempChange ) renderProps();
			});
			var lprops = {
				power : Math.sqrt(light.color.r),
				enable: true
			};
			var group = new Element('<div class="group" name="Light">
				<dl>
				<dt>Power</dt><dd><input type="range" min="0" max="4" field="power"/></dd>
				</dl>
			</div>');
			properties.add(group, lprops, function(_) {
				var p = lprops.power * lprops.power;
				light.color.set(p, p, p);
			});
		}
		tools.addButton("gears", "Renderer Properties", renderProps);
		tools.addToggle("refresh", "refresh", "Auto synchronize", function(b) {
			autoSync = b;
		});

		tools.addSeparator();

		tools.addPopup(null, "View Modes", (e) -> new hide.comp.SceneEditor.ViewModePopup(null, e, Std.downcast(@:privateAccess scene.s3d.renderer, h3d.scene.pbr.Renderer), sceneEditor), null);

		tools.addSeparator();

		tools.addPopup(null, "Render Props", (e) -> new hide.comp.SceneEditor.RenderPropsPopup(null, e, this, sceneEditor, true), null);


		tools.addSeparator();


		pauseButton = tools.addToggle("pause", "pause", "Pause animation", function(v) {}, false, "play");
		tools.addRange("Speed", function(v) {
			scene.speed = v;
		}, scene.speed);



		var gizmo = @:privateAccess sceneEditor.gizmo;

		var onSetGizmoMode = function(mode: hrt.tools.Gizmo.EditMode) {
			tools.element.find("#translationMode").get(0).toggleAttribute("checked", mode == Translation);
			tools.element.find("#rotationMode").get(0).toggleAttribute("checked", mode == Rotation);
			tools.element.find("#scalingMode").get(0).toggleAttribute("checked", mode == Scaling);
		};

		gizmo.onChangeMode = onSetGizmoMode;
		onSetGizmoMode(gizmo.editMode);



		statusText = new h2d.Text(hxd.res.DefaultFont.get(), scene.s2d);
		statusText.setPosition(5, 5);
	}

	function onPrefabChange(p: PrefabElement, ?pname: String) {
		if(p == cast(data, hrt.prefab.Prefab)) {
			if (this.curveEditor != null) {
				previewMax = data.duration == 0 ? 5000 : data.duration;
				this.curveEditor.refreshTimeline(currentTime);
				this.curveEditor.refreshOverlay(data.duration);
			}

			previewMax = hxd.Math.min(data.duration == 0 ? 5000 : data.duration, previewMax);

			cullingPreview.radius = data.cullingRadius;

			if (pname == "parameters") {
				var all = p.flatten();
				for (e in all) {
					var el = sceneEditor.tree.getElement(e);
					if (el != null && el.toggleClass != null) {
						sceneEditor.applyTreeStyle(e, el, pname);
					}
				}
			}
		}

		if (pname == "blendMode") {
			var curve = Std.downcast(p, Curve);

			function removeCurves() {
				var toRemove: Array<Curve> = [];
				for (child in curve.children) {
					var c = Std.downcast(child, Curve);
					if (c != null)
						toRemove.push(c);
				}

				while (toRemove.length > 0) {
					var c = toRemove.pop();
					//c.removeInstance();
					c.parent.children.remove(c);
				}
			}

			if (curve != null) {
				if (curve.blendMode == CurveBlendMode.Blend || curve.blendMode == CurveBlendMode.RandomBlend) {
					if (curve.children.length != 2) {
						removeCurves();

						// We're currently supporting blending with only 2 curves
						for (i in 0...2) {
							var c = new Curve(null, null);
							c.parent = curve;
							c.name = '$i';
							if (i == 0) {
								for (k in curve.keys) {
									var newK = new hrt.prefab.Curve.CurveKey();
									@:privateAccess newK.copyFromOther(k);
									c.keys.push(newK);
								}
							}
						}
					}
				}
				else {
					removeCurves();
				}
			}

			sceneEditor.refresh();
			rebuildAnimPanel();
		}

		if (pname == "blendParam") {
			sceneEditor.refresh();
			rebuildAnimPanel();
		}

		if(pname == "time" || pname == "loop" || pname == "animation" || pname == "blendMode" || pname == "blendFactor") {
			afterPan(false);
			data.refreshObjectAnims();
		}

		if (pname == "loop") {
			rebuildAnimPanel();
		}

		if (pname == "parameters") {
			if (this.curveEditor != null) {
				var fx3d = Std.downcast(data, hrt.prefab.fx.FX);
				if (fx3d != null) {
					var params = fx3d.parameters;
					this.curveEditor.evaluator.setAllParameters(params);
				}
				this.curveEditor.refreshGraph();
			}
		}

	}

	function onRefreshScene() {
		var renderProps = cast(data, hrt.prefab.Prefab).find(hrt.prefab.RenderProps);
		if(renderProps != null)
			renderProps.applyProps(scene.s3d.renderer);
	}

	override function onDragDrop(items : Array<String>, isDrop : Bool) {
		return sceneEditor.onDragDrop(items,isDrop);
	}

	function onSelect(elts : Array<PrefabElement>) {
		rebuildAnimPanel();
	}

	inline function xt(x: Float) return Math.round((x - xOffset) * xScale);
	inline function ixt(px: Float) return px / xScale + xOffset;

	function afterPan(anim: Bool) {
		if(!anim) {
			this.curveEditor.setPan(xOffset, this.curveEditor.yOffset);
		}
		for(clb in afterPanRefreshes) {
			clb(anim);
		}
	}

	function addCurvesToCurveEditor(curves: Array<Curve>, events: Array<Dynamic>){
		var rightPanel = element.find(".right-fx-animpanel").first();
		rightPanel.empty();

		// Build new curve editor with all the required comps
		var previousTime = 0.0;
		if (this.curveEditor != null)
			previousTime = @:privateAccess this.curveEditor.currentTime;

		this.curveEditor = new hide.comp.CurveEditor(this.undo, rightPanel);

		var overviewEditor = new hide.comp.CurveEditor.OverviewEditor(rightPanel, this.curveEditor);
		var eventEditor = new hide.comp.CurveEditor.EventsEditor(rightPanel, this, this.curveEditor);
		for (e in events)
			eventEditor.events.push(e);

		var minHeight = 40;
		var curveEditorHeight = 100;

		for (curve in curves){
			var dispKey = getPath() + "/" + curve.getAbsPath(true);
			curve.maxTime = data.duration == 0 ? 5000 : data.duration;
			this.curveEditor.saveDisplayKey = dispKey;

			this.curveEditor.requestXZoom = function(xMin, xMax) {
				var margin = 10.0;
				var scroll = element.find(".timeline-scroll");
				var width = scroll.parent().width();
				xScale = (width - margin * 2.0) / (xMax);
				xOffset = 0.0;

				this.curveEditor.xOffset = xOffset;
				this.curveEditor.xScale = xScale;
			}

			if(["visibility", "s", "l", "a"].indexOf(curve.name.split(".").pop()) >= 0) {
				curve.minValue = 0;
				curve.maxValue = 1;
			}
			if(curve.name.indexOf("Rotation") >= 0 || curve.name.indexOf("Local Rotation") >= 0) {
				curve.minValue = -360;
				curve.maxValue = 360;
			}
			var shader = curve.parent.to(hrt.prefab.Shader);
			if(shader != null) {
				var sh = shader.getShaderDefinition();
				if(sh != null) {
					var v = sh.data.vars.find(v -> v.kind == Param && v.name == curve.name);
					if(v != null && v.qualifiers != null) {
						for( q in v.qualifiers )
							switch( q ) {
							case Range(rmin, rmax):
								curve.minValue = rmin;
								curve.maxValue = rmax;
							default:
						}
					}
				}
			}
			this.curveEditor.xOffset = xOffset;
			this.curveEditor.xScale = xScale;
			if(isInstanceCurve(curve) && curve.parent.to(hrt.prefab.fx.Emitter) == null || curve.name.indexOf("inst") >= 0)
				curve.maxTime = curve.name.indexOf("OverTime") >= 0 ? 5000 : 1.0;
				this.curveEditor.curves.push(curve);
				this.curveEditor.onChange = function(anim) {
					//refreshDopesheet();
				}

				rightPanel.on("mousewheel", function(e) {
				var step = e.originalEvent.wheelDelta > 0 ? 1.0 : -1.0;
				if(e.ctrlKey) {
					var prevH = rightPanel.height();
					var newH = hxd.Math.max(minHeight, prevH + Std.int(step * 20.0));
					rightPanel.height(newH);
					saveDisplayState(dispKey + "/height", newH);
					this.curveEditor.yScale *= newH / prevH;
					this.curveEditor.refresh();
					e.preventDefault();
					e.stopPropagation();
				}
			});
		}

		var fx3d = Std.downcast(data, hrt.prefab.fx.FX);
		if (fx3d != null) {
			var params = fx3d.parameters;
			this.curveEditor.evaluator.setAllParameters(params);
		}
		this.curveEditor.refreshTimeline(previousTime);
		this.curveEditor.refresh();
	}

	function addHeadersToCurveEditor(sections: Array<Section>) {
		var savedFoldList : Array<String> = getDisplayState("foldList") != null ? getDisplayState("foldList") : [];
		var toFoldList : Array<{ el: Element, parentEl: Element }> = [];

		var savedLockList : Array<String> = getDisplayState("lockList") != null ? getDisplayState("lockList") : [];
		var toLockList : Array<{ parentEl: Element, elements: Array<Dynamic> }> = [];

		var savedHiddenList : Array<String> = getDisplayState("hiddenList") != null ? getDisplayState("hiddenList") : [];
		var toHiddenList : Array<{ parentEl: Element, elements: Array<Dynamic> }> = [];

		var leftPanel = element.find(".left-fx-animpanel").first();

		function drawSection(parent : Element, section: Section, depth: Int) {

			function getTagRec(elt : PrefabElement) {
				var p = elt;
				while(p != null) {
					var tag = sceneEditor.getTag(p);
					if(tag != null)
						return tag;
					p = p.parent;
				}
				return null;
			}

			function areAllChildrenLocked(secRoot : PrefabElement) {
				for (c in secRoot.flatten(Curve))
					if(!c.lock)
						return false;

				return true;
			}

			function areAllChildrenHidden(secRoot : PrefabElement) {
				for (c in secRoot.flatten(Curve))
					if(!c.hidden)
						return false;

				return true;
			}

			function addVisibilityButtonListener(parentEl: Element, affectedElements : Array<Dynamic>) {
				var visibilityEl = parentEl.find(".visibility");
				var saveKey = affectedElements.length == 1 ? affectedElements[0].getAbsPath(true) : parentEl.hasClass("section") ? section.root.getAbsPath(true) : affectedElements[0].parent.getAbsPath(true);

				if (savedHiddenList.contains(saveKey))
					toHiddenList.push( {parentEl:parentEl, elements:affectedElements} );

				visibilityEl.click(function(e) {
					// Update the value of visibilityEl since at this time
					// the html tree might not be fully constructed
					visibilityEl = parentEl.find(".visibility");
					var visible = visibilityEl.first().hasClass("ico-eye");
					if (visible) {
						visibilityEl.removeClass("ico-eye").addClass("ico-eye-slash");

						savedHiddenList = savedHiddenList.filter(hidden -> !StringTools.contains(hidden, saveKey));
						savedHiddenList.push(saveKey);
					}
					else {
						visibilityEl.removeClass("ico-eye-slash").addClass("ico-eye");
						savedHiddenList = savedHiddenList.filter(hidden -> !StringTools.contains(saveKey, hidden));
					}

					saveDisplayState("hiddenList", savedHiddenList);

					for (c in affectedElements)
						c.hidden = visibilityEl.hasClass("ico-eye-slash");

					rebuildAnimPanel();
				});
			}

			function addLockButtonListener(parentEl: Element, affectedElements : Array<Dynamic>) {
				var lockEl = parentEl.find(".lock");
				var saveKey = affectedElements.length == 1 ? affectedElements[0].getAbsPath(true) : parentEl.hasClass("section") ? section.root.getAbsPath(true) : affectedElements[0].parent.getAbsPath(true);

				if (savedLockList.contains(saveKey))
					toLockList.push( {parentEl:parentEl, elements:affectedElements} );

				lockEl.click(function(e) {
					// Update the value of lockEl since at this time
					// the html tree might not be fully constructed
					lockEl = parentEl.find(".lock");
					var locked = lockEl.first().hasClass("ico-lock");

					if (locked) {
						lockEl.removeClass("ico-lock").addClass("ico-unlock");

						savedLockList = savedLockList.filter(lock -> !StringTools.contains(saveKey, lock));
					}
					else {
						lockEl.removeClass("ico-unlock").addClass("ico-lock");

						savedLockList = savedLockList.filter(lock -> !StringTools.contains(lock, saveKey));
						savedLockList.push(saveKey);
					}

					saveDisplayState("lockList", savedLockList);

					for (c in affectedElements)
						c.lock = lockEl.first().hasClass("ico-lock");

					rebuildAnimPanel();
				});
			}

			function addOnSelectListener(parentEl: Element, affectedElements : Array<Dynamic>) {
				var trackEl = parentEl.find(".track-header");
				trackEl.click(function(e) {

					for (c in this.curveEditor.curves)
						c.selected = false;

					for (c in affectedElements)
						c.selected = true;

					rebuildAnimPanel();
				});
			}

			function addFoldButtonListener(parentEl: Element) {
				var foldEl = parentEl.find(".fold");

				if (savedFoldList.contains(section.root.getAbsPath(true)))
					toFoldList.push( {el:foldEl, parentEl: parentEl} );

				foldEl.click(function(e) {
					var expanded = foldEl.hasClass("ico-angle-down");
					if (expanded) {
						foldEl.removeClass("ico-angle-down").addClass("ico-angle-right");
						parentEl.children().find(".tracks-header").addClass("hidden");
						parentEl.children().find(".track-header").addClass("hidden");

						if (!savedFoldList.contains(section.root.getAbsPath(true)))
							savedFoldList.push(section.root.getAbsPath(true));
					}
					else {
						foldEl.removeClass("ico-angle-right").addClass("ico-angle-down");
						parentEl.children().find(".ico-angle-right").removeClass("ico-angle-right").addClass("ico-angle-down");
						parentEl.children().find(".tracks-header").removeClass("hidden");
						parentEl.children().find(".track-header").removeClass("hidden");

						savedFoldList.remove(section.root.getAbsPath(true));
					}

					saveDisplayState("foldList", savedFoldList);
					rebuildAnimPanel();
				});
			}

			function addAddTrackButtonListener(parentEl: Element, secRoot : PrefabElement) {
				var addTrackEl = parentEl.find(".addtrack");
				var parentTag = getTagRec(secRoot);
				if(parentTag != null) {
					parentEl.find(".name").css("background", parentTag.color);
				}

				addTrackEl.click(function(e) {
					var menuItems = getNewTrackMenu(secRoot);
					new hide.comp.ContextMenu(menuItems);
				});
			}

			var allElements: Array<Dynamic> = [];
			var curves = section.root.flatten(Curve);
			for (c in curves)
				allElements.push(c);

			if (section.root is Curve) {
				curves.push(cast section.root);
				allElements.push(cast section.root);
			}

			var events: Array<IEvent> = [];
			for (e in section.root.flatten(Event)) {
				events.push(e);
				allElements.push(e);
			}
			for (e in section.root.flatten(hrt.prefab.fx.SubFX)) {
				events.push(e);
				allElements.push(e);
			}

			if (section.root is Event || section.root is hrt.prefab.fx.SubFX) {
				events.push(cast section.root);
				allElements.push(cast section.root);
			}

			var sectionEl = new Element('<div class="section" name="${section.root.name}">
			<div class="tracks-header" style="margin-left: ${depth * 10}px">
			<div class="track-button fold ico ico-angle-down"></div>
			<div class="track-button visibility ico ${areAllChildrenHidden(section.root) ? "ico-eye-slash" : "ico-eye"}"></div>
			<label class="name">${upperCase(section.root.name)}</label>
			<label class="abspath">${section.root.getAbsPath(true)}</label>
			${section.root is Curve ?'': '<div class="track-button align-right-first addtrack ico ico-plus-square"></div>'}
			<div class="track-button lock align-right-second ico ${areAllChildrenLocked(section.root) ? "ico-lock" : "ico-unlock"}"></div>
			</div>
			<div class="tracks"></div>
			</div>');

			addVisibilityButtonListener(sectionEl, allElements);
			addLockButtonListener(sectionEl, allElements);
			addOnSelectListener(sectionEl, allElements);
			addFoldButtonListener(sectionEl);
			addAddTrackButtonListener(sectionEl, section.root);

			if (section.curves.length > 0) {
				for (i in 0...section.curves.length) {
					var c = section.curves[i];

					var curveColor = hide.comp.CurveEditor.CURVE_COLORS[i];
					if (StringTools.contains(c.name, ".x") || StringTools.contains(c.name, ".h")) curveColor = hide.comp.CurveEditor.CURVE_COLORS[0];
					if (StringTools.contains(c.name, ".y") || StringTools.contains(c.name, ".s")) curveColor = hide.comp.CurveEditor.CURVE_COLORS[1];
					if (StringTools.contains(c.name, ".z") || StringTools.contains(c.name, ".l")) curveColor = hide.comp.CurveEditor.CURVE_COLORS[2];
					if (StringTools.contains(c.name, ".w") || StringTools.contains(c.name, ".a")) curveColor = hide.comp.CurveEditor.CURVE_COLORS[3];

					// Assign same color to curve and curve's header
					c.color = curveColor;
					var hexColor = '#${StringTools.hex(curveColor)}';

					var colorStyle = c.selected ? "style = color:#d59320" : "";
					var trackEl = new Element('<div>
						<div class="track-header" style="margin-left: ${(depth + 1) * 10}px">
							<div class="track-button color-id ico" style="background-color:${hexColor}"></div>
							<div class="track-button visibility ico ${c.hidden ? "ico-eye-slash" : "ico-eye"}"></div>
							<label class="name" ${colorStyle}>${upperCase(c.name)}</label>
							<div class="track-button lock align-right-second ico ${c.lock ? "ico-lock" : "ico-unlock"}"></div>
						</div>
						<div class="tracks"></div>
					</div>');

					sectionEl.append(trackEl);

					addVisibilityButtonListener(trackEl, [ c ]);
					addLockButtonListener(trackEl, [ c ]);
					addOnSelectListener(trackEl, [ c ]);
					addFoldButtonListener(trackEl);
				}

			}

			if (section.events.length > 0) {
				for (i in 0...section.events.length) {
					var e = section.events[i];

					var colorStyle = e.selected ? "style = color:#d59320" : "";
					var hexColor = '#FFFFFF';
					var trackEl = new Element('<div>
						<div class="track-header" style="margin-left: ${(depth + 1) * 10}px">
							<div class="track-button color-id ico" style="background-color:${hexColor}"></div>
							<div class="track-button visibility ico ${e.hidden ? "ico-eye-slash" : "ico-eye"}"></div>
							<label class="name" ${colorStyle}>${upperCase(e.getEventPrefab().name)}</label>
							<div class="track-button lock align-right-second ico ${e.lock ? "ico-lock" : "ico-unlock"}"></div>
						</div>
						<div class="tracks"></div>
					</div>');

					sectionEl.append(trackEl);

					addVisibilityButtonListener(trackEl, [ e ]);
					addLockButtonListener(trackEl, [ e ]);
					addOnSelectListener(trackEl, [ e ]);
					addFoldButtonListener(trackEl);
				}

			}

			if (section.root is Curve) {
				var c: Curve = cast section.root;

				// We don't want to show an header for the blending curve,
				// just for the parent blend curves.
				if (c.blendMode != CurveBlendMode.Blend && c.blendMode != CurveBlendMode.RandomBlend) {
					var hexColor = '#${StringTools.hex(c.color)}';
					var colorStyle = c.selected ? "style = color:#d59320" : "";
					var trackEl = new Element('<div>
						<div class="track-header" style="margin-left: ${(depth + 1) * 10}px">
							<div class="track-button color-id ico" style="background-color:${hexColor}"></div>
							<div class="track-button visibility ico ${c.hidden ? "ico-eye-slash" : "ico-eye"}"></div>
							<label class="name" ${colorStyle}>${upperCase(c.name)}</label>
							<div class="track-button lock align-right-second ico ${c.lock ? "ico-lock" : "ico-unlock"}"></div>
						</div>
						<div class="tracks"></div>
					</div>');

					sectionEl.append(trackEl);

					addVisibilityButtonListener(trackEl, curves);
					addLockButtonListener(trackEl, curves);
					addOnSelectListener(trackEl, curves);
					addFoldButtonListener(trackEl);
				}
			}

			if (section.root is IEvent) {
				var e: IEvent = cast section.root;
				var colorStyle = e.selected ? "style = color:#d59320" : "";
				var hexColor = '#FFFFFF';
				var trackEl = new Element('<div>
					<div class="track-header" style="margin-left: ${(depth + 1) * 10}px">
						<div class="track-button color-id ico" style="background-color:${hexColor}"></div>
						<div class="track-button visibility ico ${e.hidden ? "ico-eye-slash" : "ico-eye"}"></div>
						<label class="name" ${colorStyle}>${upperCase(e.getEventPrefab().name)}</label>
						<div class="track-button lock align-right-second ico ${e.lock ? "ico-lock" : "ico-unlock"}"></div>
					</div>
					<div class="tracks"></div>
				</div>');

				sectionEl.append(trackEl);

				addVisibilityButtonListener(trackEl, [ e ]);
				addLockButtonListener(trackEl, [ e ]);
				addOnSelectListener(trackEl, [ e ]);
				addFoldButtonListener(trackEl);
			}

			for (child in section.children)
				drawSection(sectionEl, child, depth + 1);

			parent.append(sectionEl);
		}

		for (sec in sections)
			drawSection(leftPanel, sec, 0);

		// Apply preferences of fold / lock / visibility
		for (fold in toFoldList) {
			fold.el.removeClass("ico-angle-down").addClass("ico-angle-right");
			fold.parentEl.children().find(".tracks-header").addClass("hidden");
			fold.parentEl.children().find(".track-header").addClass("hidden");
		}

		for (lock in toLockList) {
			var lockEl = lock.parentEl.find(".lock");
			lockEl.removeClass("ico-unlock").addClass("ico-lock");

			for (c in lock.elements)
				c.lock = lockEl.first().hasClass("ico-lock");
		}

		for (hidden in toHiddenList) {
			var visibilityEl = hidden.parentEl.find(".visibility");
			visibilityEl.removeClass("ico-eye").addClass("ico-eye-slash");

			for (c in hidden.elements)
				c.hidden = visibilityEl.hasClass("ico-eye-slash");
		}

		var prefWidth = leftAnimPanel.getDisplayState("size");
		if (prefWidth != null)
			leftPanel.width(prefWidth);
	}

	function rebuildAnimPanel() {
		if(element == null)
			return;

		var leftPanel = element.find(".left-fx-animpanel").first();
		leftPanel.empty();

		var selection = sceneEditor.getSelection();
		afterPanRefreshes = [];
		var curvesToDraw : Array<Curve> = [];
		var eventsToDraw : Array<IEvent> = [];

		function getSection(?root : PrefabElement, depth = 0): Section {
			var section: Section = { root:root, curves: [], children: [], events: []};
			var eventAdded = false;

			if (root is Curve)
				curvesToDraw.push(cast root);

			if (root is IEvent && depth == 0)
				eventsToDraw.push(cast root);

			for(child in root.children) {
				if (child.flatten(Curve).length > 0) {
					if (child is Curve) {
						var c = Std.downcast(child, Curve);
						curvesToDraw.push(c);

						if (c.blendMode == CurveBlendMode.Blend || c.blendMode == CurveBlendMode.RandomBlend)
							section.children.push(getSection(c,depth+1));
						else
							section.curves.push(c);
					}
					else {
						section.children.push(getSection(child,depth+1));
					}
				}

				if (child.flatten(Event).length > 0) {
					if (child is Event) {
						var e = Std.downcast(child, Event);
						section.events.push(e);
						eventsToDraw.push(e);
					}
				}

				if (child.flatten(hrt.prefab.fx.SubFX).length > 0) {
					if (child is hrt.prefab.fx.SubFX) {
						var s = Std.downcast(child, hrt.prefab.fx.SubFX);
						section.events.push(s);
						eventsToDraw.push(s);
					}
				}

			}

			return section;
		}

		var sections : Array<Section> = [];
		for (sel in selection) {
			sections.push(getSection(sel));
		}

		addHeadersToCurveEditor(sections);
		addCurvesToCurveEditor(curvesToDraw, eventsToDraw);

		this.curveEditor.refreshTimeline(currentTime);
		this.curveEditor.refreshOverlay(data.duration);
	}

	function startDrag(onMove: js.jquery.Event->Void, onStop: js.jquery.Event->Void, ?onKeyDown: js.jquery.Event->Void, ?onKeyUp: js.jquery.Event->Void) {
		var el = new Element(element[0].ownerDocument.body);
		var startX = null, startY = null;
		var dragging = false;
		var threshold = 3;
		el.keydown(onKeyDown);
		el.keyup(onKeyUp);
		el.on("mousemove.fxedit", function(e: js.jquery.Event) {
			if(startX == null) {
				startX = e.clientX;
				startY = e.clientY;
			}
			else {
				if(!dragging) {
					if(hxd.Math.abs(e.clientX - startX) + hxd.Math.abs(e.clientY - startY) > threshold) {
						dragging = true;
					}
				}
				if(dragging)
					onMove(e);
			}
		});
		el.on("mouseup.fxedit", function(e: js.jquery.Event) {
			el.off("mousemove.fxedit");
			el.off("mouseup.fxedit");
			e.preventDefault();
			e.stopPropagation();
			onStop(e);
		});
	}

	function addTracks(element : PrefabElement, props : Array<PropTrackDef>, ?prefix: String) {
		var added = [];
		for(prop in props) {
			var id = prefix != null ? prefix + "." + prop.name : prop.name;
			if(Curve.getCurve(element, id) != null)
				continue;
			var curve = new Curve(element,null);
			curve.name = id;
			if(prop.def != null)
				curve.addKey(0, prop.def, Linear);
			added.push(curve);
		}

		if(added.length == 0)
			return added;

		undo.change(Custom(function(undo) {
			for(c in added) {
				if(undo)
					element.children.remove(c);
				else
					element.children.push(c);
			}
			sceneEditor.refresh();
		}));
		sceneEditor.refresh(function() {
			sceneEditor.selectElements([element]);
		});
		return added;
	}

	public function getNewTrackMenu(elt: PrefabElement) : Array<hide.comp.ContextMenu.ContextMenuItem> {
		var obj3dElt = Std.downcast(elt, hrt.prefab.Object3D);
		var obj2dElt = Std.downcast(elt, hrt.prefab.Object2D);
		var shaderElt = Std.downcast(elt, hrt.prefab.Shader);
		var emitterElt = Std.downcast(elt, hrt.prefab.fx.Emitter);

		var particle2dElt = Std.downcast(elt, hrt.prefab.l2d.Particle2D);
		var menuItems : Array<hide.comp.ContextMenu.ContextMenuItem> = [];
		var lightElt = Std.downcast(elt, Light);

		inline function hasTrack(pname) {
			return getTrack(elt, pname) != null;
		}

		function trackItem(name: String, props: Array<PropTrackDef>, ?prefix: String) : hide.comp.ContextMenu.ContextMenuItem {
			var hasAllTracks = true;
			for(p in props) {
				if(getTrack(elt, prefix + "." + p.name) == null)
					hasAllTracks = false;
			}
			return {
				label: upperCase(name),
				click: function() {
					var added = addTracks(elt, props, prefix);
				},
				enabled: !hasAllTracks };
		}

		function groupedTracks(prefix: String, props: Array<PropTrackDef>) : Array<hide.comp.ContextMenu.ContextMenuItem> {
			var allLabel = [for(p in props) upperCase(p.name)].join("/");
			var ret = [];
			ret.push(trackItem(allLabel, props, prefix));
			for(p in props) {
				var label = upperCase(p.name);
				ret.push(trackItem(label, [p], prefix));
			}
			return ret;
		}

		var hslTracks : Void -> Array<PropTrackDef> = () -> [{name: "h", def: 0.0}, {name: "s", def: 0.0}, {name: "l", def: 1.0}];
		var alphaTrack : Void -> Array<PropTrackDef> = () -> [{name: "a", def: 1.0}];
		var xyzwTracks : Int -> Array<PropTrackDef> = (n) -> [{name: "x"}, {name: "y"}, {name: "z"}, {name: "w"}].slice(0, n);

		if (obj2dElt != null) {
			var scaleTracks = groupedTracks("scale", xyzwTracks(2));
			scaleTracks.unshift(trackItem("Uniform", [{name: "scale"}]));
			menuItems.push({
				label: "Position",
				menu: groupedTracks("position", xyzwTracks(2)),
			});
			menuItems.push(trackItem("Rotation", [{name: "rotation"}]));
			menuItems.push({
				label: "Scale",
				menu: scaleTracks,
			});
			menuItems.push({
				label: "Color",
				menu: [
					trackItem("HSL", hslTracks(), "color"),
					trackItem("Alpha", alphaTrack(), "color")
				]
			});
			menuItems.push(trackItem("Visibility", [{name: "visibility"}]));
		}
		if(obj3dElt != null) {
			var scaleTracks = groupedTracks("scale", xyzwTracks(3));
			scaleTracks.unshift(trackItem("Uniform", [{name: "scale"}]));
			menuItems.push({
				label: "Position",
				menu: groupedTracks("position", xyzwTracks(3)),
			});
			menuItems.push({
				label: "Local Position",
				menu: groupedTracks("localPosition", xyzwTracks(3)),
			});
			menuItems.push({
				label: "Rotation",
				menu: groupedTracks("rotation", xyzwTracks(3)),
			});
			menuItems.push({
				label: "Local Rotation",
				menu: groupedTracks("localRotation", xyzwTracks(3)),
			});
			menuItems.push({
				label: "Scale",
				menu: scaleTracks,
			});
			menuItems.push({
				label: "Color",
				menu: [
					trackItem("HSL", hslTracks(), "color"),
					trackItem("Alpha", alphaTrack(), "color")
				]
			});
			menuItems.push(trackItem("Visibility", [{name: "visibility"}]));
		}
		if(shaderElt != null) {
			var shader = shaderElt.makeShader();
			var inEmitter = shaderElt.findParent(hrt.prefab.fx.Emitter) != null;
			var params = shader == null ? [] : @:privateAccess shader.shader.data.vars.filter(v -> v.kind == Param);
			for(param in params) {
				if (param.qualifiers?.contains(Ignore) ?? false)
					continue;
				var item : hide.comp.ContextMenu.ContextMenuItem = switch(param.type) {
					case TVec(n, VFloat):
						var color = param.name.toLowerCase().indexOf("color") >= 0;
						var label = upperCase(param.name);
						var menu = null;
						if(color) {
							if(n == 3)
								menu = trackItem(label, hslTracks(), param.name);
							else if(n == 4)
								menu = trackItem(label, hslTracks().concat(alphaTrack()), param.name);
						}
						if(menu == null)
							menu = trackItem(label, xyzwTracks(n), param.name);
						menu;
					case TFloat:
						trackItem(upperCase(param.name), [{name: param.name}]);
					default:
						null;
				}
				if(item != null)
					menuItems.push(item);
			}
		}
		function addParam(param : hrt.prefab.fx.Emitter.ParamDef, prefix: String) {
			var label = prefix + (param.disp != null ? param.disp : upperCase(param.name));
			var item : hide.comp.ContextMenu.ContextMenuItem = switch(param.t) {
				case PVec(n, _):
					{
						label: label,
						menu: groupedTracks(param.name, xyzwTracks(n)),
					}
				default:
					trackItem(label, [{name: param.name}]);
			};
			menuItems.push(item);
		}
		if(emitterElt != null) {
			for(param in hrt.prefab.fx.Emitter.emitterParams) {
				if(!param.animate)
					continue;
				addParam(param, "");
			}
			for(param in hrt.prefab.fx.Emitter.instanceParams) {
				if(!param.animate)
					continue;
				addParam(param, "Instance ");
			}
		}

		if (particle2dElt != null) {
			for(param in hrt.prefab.l2d.Particle2D.emitter2dParams) {
				if(!param.animate)
					continue;
				addParam(param, "");
			}
		}

		if( lightElt != null ) {
			switch lightElt.kind {
				case Point:
					menuItems.push({
						label: "PointLight",
						menu: [	trackItem("Color", hslTracks(), "color"),
								trackItem("Power",[{name: "power"}]),
								trackItem("Size", [{name: "size"}]),
								trackItem("Range", [{name: "range"}]),
								]
					});
				case Directional:
					menuItems.push({
						label: "DirLight",
						menu: [	trackItem("Color", hslTracks(), "color"),
								trackItem("Power",[{name: "power"}]),
								]
					});
				case Spot:
					menuItems.push({
						label: "SpotLight",
						menu: [	trackItem("Color", hslTracks(), "color"),
								trackItem("Power",[{name: "power"}]),
								trackItem("Range", [{name: "range"}]),
								trackItem("Angle", [{name: "angle"}]),
								trackItem("FallOff", [{name: "fallOff"}]),
								]
					});
				case Capsule:
					menuItems.push({
						label: "CapsuleLight",
						menu: [	trackItem("Color", hslTracks(), "color"),
								trackItem("Power",[{name: "power"}]),
								trackItem("Range", [{name: "range"}]),
								trackItem("Angle", [{name: "angle"}]),
								trackItem("FallOff", [{name: "fallOff"}]),
								]
					});
			}
		}
		return menuItems;
	}

	function isPerInstance( v : hxsl.Ast.TVar ) {
		if( v.kind != Param )
			return false;
		if( v.qualifiers == null )
			return false;
		for( q in v.qualifiers )
			if( q.match(PerInstance(_)) )
				return true;
		return false;
	}

	function onUpdate(dt : Float) {
		if (is2D)
			onUpdate2D(dt);
		else
			onUpdate3D(dt);

		@:privateAccess scene.s3d.renderer.ctx.time = currentTime - scene.s3d.renderer.ctx.elapsedTime;
	}

	function onUpdate2D(dt:Float) {

		var anim = sceneEditor.root2d.find((p) -> Std.downcast(p, hrt.prefab.fx.FX2D.FX2DAnimation));

		if(!pauseButton.isDown()) {
			currentTime += scene.speed * dt;
			if(this.curveEditor != null) {
				this.curveEditor.refreshTimeline(currentTime);
				this.curveEditor.refreshOverlay(data.duration);
			}
			if(currentTime >= previewMax) {
				currentTime = previewMin;

				anim.setRandSeed(Std.random(0xFFFFFF));
			}
		}

		if(anim != null) {
			anim.setTime(currentTime);
		}

		if(statusText != null) {
			var lines : Array<String> = [
				'Time: ${Math.round(currentTime*1000)} ms',
				'Scene objects: ${scene.s2d.getObjectsCount()}',
				'Drawcalls: ${h3d.Engine.getCurrent().drawCalls}',
			];
			statusText.text = lines.join("\n");
		}

		if( autoSync && (currentVersion != undo.currentID || lastSyncChange != properties.lastChange) ) {
			save();
			lastSyncChange = properties.lastChange;
			currentVersion = undo.currentID;
		}

		if (sceneEditor.grid2d != null) {
			@:privateAccess sceneEditor.grid2d.setPosition(scene.s2d.children[0].x, scene.s2d.children[0].y);
		}

	}

	var avg_smooth = 0.0;
	var trailTime_smooth = 0.0;
	var num_trail_tri_smooth = 0.0;

	public static function floatToStringPrecision(n : Float, ?prec : Int = 2, ?showZeros : Bool = true) {
		if(n == 0) { // quick return
			if (showZeros)
				return "0." + ([for(i in 0...prec) "0"].join(""));
			return "0";
		}
		if (Math.isNaN(n))
			return "NaN";
		if (n >= Math.POSITIVE_INFINITY)
			return "+inf";
		else if (n <= Math.NEGATIVE_INFINITY)
			return "-inf";

		var p = Math.pow(10, prec);
		var fullDec = "";

		if (n > -1. && n < 1) {
			var minusSign:Bool = (n<0.0);
			n = Math.abs(n);
			var val = Math.round(p * n);
			var str = Std.string(val);
			var buf:StringBuf = new StringBuf();
			if (minusSign)
				buf.addChar("-".code);
			for (i in 0...(prec + 1 - str.length))
				buf.addChar("0".code);
			buf.addSub(str, 0);
			fullDec = buf.toString();
		} else {
			var val = Math.round(p * n);
			fullDec = Std.string(val);
		}

		var outStr = fullDec.substr(0, -prec) + '.' + fullDec.substr(fullDec.length - prec, prec);
		if (!showZeros) {
			var i = outStr.length - 1;
			while (i > 0) {
				if (outStr.charAt(i) == "0")
					outStr = outStr.substr(0, -1);
				else if (outStr.charAt(i) == ".") {
					outStr = outStr.substr(0, -1);
					break;
				} else
					break;
				i--;
			}
		}
		return outStr;
	}

	function onUpdate3D(dt:Float) {
		var local3d = sceneEditor.root3d;
		if(local3d == null)
			return;

		var allFx = local3d.findAll(o -> Std.downcast(o, hrt.prefab.fx.FX.FXAnimation));

		if(!pauseButton.isDown()) {
			currentTime += scene.speed * dt;
			if(this.curveEditor != null) {
				this.curveEditor.refreshTimeline(currentTime);
				this.curveEditor.refreshOverlay(data.duration);
			}
			if(currentTime >= previewMax) {
				currentTime = previewMin;

				//if(data.scriptCode != null && data.scriptCode.length > 0)
					//sceneEditor.refreshScene(); // This allow to reset the scene when values are modified causes edition issues, solves
				for(f in allFx)
					f.setRandSeed(Std.random(0xFFFFFF));
			}
		}

		for(fx in allFx)
			fx.setTime(currentTime - fx.startDelay);

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

	static function getTrack(element : PrefabElement, propName : String) {
		return Curve.getCurve(element, propName, false);
	}

	static function upperCase(prop: String) {
		if(prop == null) return "";
		return prop.charAt(0).toUpperCase() + prop.substr(1);
	}

	static function isInstanceCurve(curve: Curve) {
		return curve.findParent(hrt.prefab.fx.Emitter) != null;
	}

	static var _ = FileTree.registerExtension(FXEditor, ["fx"], { icon : "sitemap", createNew : "FX" });

	function set_currentTime(value:Float):Float {
		if (this.curveEditor != null)
			@:privateAccess this.curveEditor.currentTime = value;

		return this.currentTime = value;
	}

	function get_currentTime():Float {
		return @:privateAccess this.curveEditor.currentTime;
	}
}


class FX2DEditor extends FXEditor {

	override function getDefaultContent() {
		@:privateAccess return haxe.io.Bytes.ofString(ide.toJSON(new hrt.prefab.fx.FX2D(null, null).save()));
	}

	static var _2d = FileTree.registerExtension(FX2DEditor, ["fx2d"], { icon : "sitemap", createNew : "FX 2D" });
}