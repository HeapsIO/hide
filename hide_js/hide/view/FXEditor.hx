package hide.view;
import hrt.prefab.Light;
using Lambda;

import hide.Element;
import hrt.prefab.Prefab in PrefabElement;
import hrt.prefab.fx.Curve;
import hrt.prefab.fx.Event;
import hide.tools.CameraController.CamController;

import hrt.tools.MapUtils;

typedef PropTrackDef = {
	name: String,
	?def: Float
};

typedef Section = {
	root: PrefabElement,
	curves: Array<Curve>,
	children: Array<Section>
};

@:access(hide.view.FXEditor)
class FXEditContext extends hide.prefab.EditContext {
	var parent : FXEditor;
	public function new(undo, parent) {
		super(undo);
		this.parent = parent;
	}
	override function onChange(p, propName) {
		super.onChange(p, propName);
		parent.onPrefabChange(p, propName);
	}
}

@:access(hide.view.FXEditor)
private class FXSceneEditor extends hide.comp.SceneEditor {
	var parent : hide.view.FXEditor;
	public var is2D : Bool = false;


	public function new(view) {
		super(view);
		parent = cast view;
	}

	override function onPrefabChange(p: PrefabElement, ?pname: String) {
		super.onPrefabChange(p, pname);
		parent.onPrefabChange(p, pname);
	}

	override function setupGizmo() {
		super.setupGizmo();

		if (selectedPrefabs == null)
			return;

		var onMove = gizmo.onMove;
		gizmo.onMove = (offsetPosition, offsetRotation, offsetScale) -> {
			onMove(offsetPosition, offsetRotation, offsetScale);
			parent.forceTick = true;
		};
		var onFinishMove = gizmo.onFinishMove;
		gizmo.onFinishMove = () -> {
			onFinishMove();
			parent.forceTick = true;
		};
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
			@:privateAccess
			for (trail in trails)
				trailTime += trail.lastUpdateDuration;

			var text : Array<String> = [
				'Particles: $totalParts',
				'Particles CPU time: ${FXEditor.floatToStringPrecision(emitterTime*1000.0, 2)} ms',
				'Trails CPU time: ${FXEditor.floatToStringPrecision(trailTime * 1000.0, 2)} ms',
			];
			statusText.text += "\n" + text.join("\n");
		}
	}

	override function createDroppedElement(path:String, parent:PrefabElement, inlinePrefab: Bool): hrt.prefab.Prefab {
		var type = hrt.prefab.Prefab.getPrefabType(path);
		if(type == "fx") {
			var relative = ide.makeRelative(path);
			var ref = new hrt.prefab.fx.SubFX(parent, null);
			ref.editorInit(relative);
			ref.name = new haxe.io.Path(relative).file;
			return ref;
		}
		return super.createDroppedElement(path, parent, inlinePrefab);
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

	override function buildTree(targetTree : hide.comp.SceneEditor.Tree) : hide.comp.FancyTree<hrt.prefab.Prefab> {
		var tree = super.buildTree(targetTree);

		var prev = tree.getButtons;
		tree.getButtons = (p : hrt.prefab.Prefab) -> {
			var buttons = prev(p);
			var curve = Std.downcast(p, Curve);
			if (curve == null || (curve.blendMode != Blend && curve.blendMode != Reference))
				return buttons;

			var paramName = curve.param;
			var color = 0xFFFFFF;
			var icon = "ico-random";
			var missing = false;

			if (curve.blendMode == Blend) {
				var fx = Std.downcast(this.parent.data, hrt.prefab.fx.FX);
				if (fx == null)
					return buttons;
				var param = fx.parameters.find(function (p) {return p.name == paramName;});
				missing = param == null;
				color = param?.color;
			}
			else {
				var ref = (cast this.parent.data: hrt.prefab.Prefab).locatePrefab(curve.refPath);
				if (ref == null)
					missing = true;
				icon = "ico-link";
			}

			var colorCode = StringTools.hex(missing ? 0xFF0000 : color, 6);

			buttons.insert(0, {
				getIcon: (p: hrt.prefab.Prefab) ->  {
					return '<span class="fx-parameter ${missing ? "missing" : ""}" style="color:#$colorCode"><i class="ico $icon"></i><span class="fx-param-name">$paramName</span></span>';
				},
				click: (p: hrt.prefab.Prefab) -> {},
				forceVisiblity: (p: hrt.prefab.Prefab) -> true,
			});

			return buttons;
		}

		return tree;
	}

	override function getRecentMenuKey() {
		if (parent.is2D) return "sceneeditor.newrecents2d";
		return super.getRecentMenuKey();
	}

	override function getNewContextMenu(current: PrefabElement, ?onMake: PrefabElement->Void=null, ?groupByType = true ) {
		if(current != null && current.to(hrt.prefab.Shader) != null) {
			var ret : Array<hrt.ui.HuiMenu.MenuItem> = [];
			ret.push({
				label: "Animation",
				menu: parent.getNewTrackMenu(current)
			});
			return ret;
		}
		var allTypes = super.getNewContextMenu(current, onMake, false);
		var allTypesGrouped = super.getNewContextMenu(current, onMake, true);
		var recents = getNewRecentContextMenu(current, onMake);

		var menu = [];
		var shaderItems : Array<hrt.ui.HuiMenu.MenuItem> = [];

		if (parent.is2D) {
			for(name in ["Group 2D", "Bitmap", "Anim2D", "Atlas", "Emitter 2D", "Text", "Shader", "Shader Graph", "Placeholder"]) {
				var item = allTypes.find(i -> i.label == name);
				if(item == null) continue;
				allTypes.remove(item);
				if (name == "Shader") {
					shaderItems = item.menu;
					continue;
				}
				menu.push(item);
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
		}

		if(current != null) {
			menu.push({
				label: "Animation",
				menu: parent.getNewTrackMenu(current)
			});
		}

		menu.sort(function(l1,l2) return Reflect.compare(l1.label,l2.label));

		var events = allTypes.filter(i -> StringTools.contains(i.label, "Event"));
		if(events.length > 0) {
			menu.push({
				label: "Events",
				menu: events
			});
			for(e in events)
				allTypes.remove(e);
		}

		menu.push({label: null, isSeparator: true});

		menu.push({label: "Shader", menu: shaderItems});

		var spawn = allTypesGrouped.find(t -> t.label == "Spawn");
		if ( spawn != null )
			menu.push({label: "Spawn", menu: spawn.menu});
		var simulation = allTypesGrouped.find(t-> t.label == "Simulation");
		if ( simulation != null )
			menu.push({label: "Simulation", menu: simulation.menu});

		menu.push({label: null, isSeparator: true});

		menu.push({label: "Other", menu: allTypes});

		menu.unshift({
			label : "Recents",
			menu : recents,
		});
		return menu;
	}

	override function getAvailableTags() {
		return cast ide.currentConfig.get("fx.tags");
	}

	override function endRebuild() {
		super.endRebuild();
	}
}

class FXEditor extends hide.view.FileView {

	var scene(get, null):  hide.comp.Scene;
	function get_scene() return sceneEditor.scene;
	var properties(get, null):  hide.comp.PropsEditor;
	function get_properties() return sceneEditor.properties;


	var sceneEditor : FXSceneEditor;
	var data : hrt.prefab.fx.BaseFX;
	var is2D : Bool = false;
	var tools : hide.comp.Toolbar;
	var treePanel : hide.comp.ResizablePanel;

	var fxprops : hide.comp.PropsEditor;

	var loopButton : hide.comp.Toolbar.ToolToggle;
	var paused = false;
	var currentTime : Float = 0.;
	var lastTime : Float;
	var lastSeek : Float = 0;
	var statusText : h2d.Text;
	var forceTick : Bool = false;
	var skipRebuildPannel = 0;

	var sceneReadyDelayed : Array<() -> Void> = [];
	var cullingPreview : h3d.scene.Sphere;

	// Timeline
	var timeline : Timeline;
	var timelineCurveColors : Map<Curve, Int> = new Map();
	var timelineRows : Array<{ name : String, element : js.html.Element }> = [];
	var selectedTimelineRow : String;
	var timelineFilter = "";

	override function getDefaultContent() {
		@:privateAccess return haxe.io.Bytes.ofString(ide.toJSON(new hrt.prefab.fx.FX(null, null).serialize()));
	}

	override function canSave() {
		return data != null;
	}

	override function save() {
		if( !canSave() )
			return;

		// Save render props
		sceneEditor.saveRenderProps();

		var scene = sceneEditor?.scene;
		if (scene != null && @:privateAccess scene.errorThisFrame) {
			var error = @:privateAccess scene.currentError.title;
			if (!ide.confirm('The scene has rendering errors :\n$error\n\nThe FX might not load in game. Save anyway?'))
				return;
		}

		@:privateAccess var content = ide.toJSON(cast(data, hrt.prefab.Prefab).editorDiscSerialize());
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
		var content = sys.io.File.getContent(getPath());
		var json = haxe.Json.parse(content);

		currentSign = ide.makeSignature(content);

		element.html('
			<div class="flex vertical">
				<div style="flex: 0 0 30px;">
					<span class="tools-buttons"></span>
				</div>
				<div class="scene-partition" style="display: flex; flex-direction: row; flex: 1; overflow: hidden;">
					<div style="display: flex; flex-direction: column; flex: 1; overflow: hidden;">
						<div class="flex heaps-scene"></div>
					</div>
					<div class="tree-column">
						<div class="flex vertical">
							<div class="hide-toolbar" style="zoom: 80%">
								<div class="button collapse-btn" title="Collapse all">
									<div class="icon ico ico-reply-all"></div>
								</div>
							</div>
							<div class="hide-scenetree"></div>
							<div class="render-props-edition">
								<div class="hide-toolbar">
									<div class="toolbar-label">
										<div class="icon ico ico-sun-o"></div>
										Render props
									</div>
								</div>
								<div class="hide-scenetree"></div>
							</div>
						</div>
					</div>
					<div class="tabs">
						<div class="tab expand" name="Scene" icon="sitemap">
							<div class="hide-scroll"></div>
						</div>
						<div class="tab expand" name="Properties" icon="cog">
							<div class="fx-props"></div>
						</div>
					</div>
				</div>
			</div>');
		tools = new hide.comp.Toolbar(null,element.find(".tools-buttons"));
		var tabs = new hide.comp.Tabs(null,element.find(".tabs"));
		sceneEditor = new FXSceneEditor(this);
		sceneEditor.onSceneReady = onSceneReady;
		sceneEditor.scene.onSceneGoto = (contextObject) -> {
			var obj = Std.downcast((contextObject : Dynamic), h3d.scene.Object);
			while (obj != null) {
				var p = cast(data, hrt.prefab.Prefab).find(hrt.prefab.Object3D, (p) -> p.local3d == obj);
				if (p != null)
					return () -> sceneEditor.selectElements([p]);
				obj = obj.parent;
			}
			return null;
		};

		for (callback in sceneReadyDelayed) {
			sceneEditor.delayReady(callback);
		}
		sceneReadyDelayed.empty();

		if (json.type == "fx2d") {
			is2D = true;
			sceneEditor.is2D = true;
		}

		element.find(".hide-scenetree").first().append(sceneEditor.sceneTree.element);
		element.find(".render-props-edition").find('.hide-scenetree').append(sceneEditor.renderPropsTree.element);
		element.find(".hide-scroll").first().append(sceneEditor.properties.element);
		element.find(".heaps-scene").first().append(sceneEditor.scene.element);

		var treeColumn = element.find(".tree-column").first();
		treePanel = new hide.comp.ResizablePanel(Horizontal, treeColumn);
		treePanel.saveDisplayKey = "treeColumn";
		treePanel.onResize = () -> @:privateAccess if( scene.window != null) scene.window.checkResize();

		refreshLayout();

		element.find(".collapse-btn").click(function(e) {
			sceneEditor.collapseTree();
		});
		fxprops = new hide.comp.PropsEditor(undo,null,element.find(".fx-props"));


		if (is2D) {
			sceneEditor.camera2D = true;
		}

		keys.register("playPause", function() { paused = !paused; });
		keys.register("loopAnim", function() { loopButton.toggle(!loopButton.isDown()); });
		keys.register("playFromLastSeek", function() { paused = false; currentTime = lastSeek; });
		keys.register("playFromStart", function() { paused = false; currentTime = 0; lastSeek = 0; });

		sceneEditor.sceneTree.element.addClass("small");
		sceneEditor.renderPropsTree.element.addClass("small");

		var rpEditionvisible = Ide.inst.currentConfig.get("sceneeditor.renderprops.edit", false);
		setRenderPropsEditionVisibility(rpEditionvisible);
	}

	override function onActivate() {
		if( sceneEditor != null )
			refreshLayout();
		if (tools != null)
			tools.refreshToggles();

		setRenderPropsEditionVisibility(Ide.inst.currentConfig.get("sceneeditor.renderprops.edit", false));

		for (t in ide.getViews(Timeline))
			bindTimeline(t);
	}

	override function onHide() {
		super.onHide();
		getTimeline()?.clear();
	}

	override function destroy() {
		getTimeline()?.clear();
		super.destroy();
	}

	/**
		Call a function when the sceneEditor is properly initialized
	**/
	public function delaySceneEditor(callback : () -> Void) {
		if (sceneEditor != null) {
			sceneEditor.delayReady(callback);
		}
		else {
			sceneReadyDelayed.push(callback);
		}
	}

	function refreshLayout() {
		if (treePanel != null) treePanel.setSize();
	}

	public function onSceneReady() {
		data = cast(hxd.res.Loader.currentInstance.load(state.path).toPrefab().load().clone(), hrt.prefab.fx.BaseFX);
		if (data == null) {
			throw "Prefab is not a FX";
			return;
		}

		sceneEditor.setPrefab(cast data);

		{
			var edit = new FXEditContext(undo, this);
			edit.properties = fxprops;
			edit.scene = sceneEditor.scene;
			edit.cleanups = [];
			cast(data, hrt.prefab.Prefab).edit(edit);
		}

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
		toolsDefs.push({id: "camSettings", title : "Camera Settings", icon : "camera", type : Popup((e : hide.Element) -> new hide.comp.CameraControllerEditor(sceneEditor, e)) });

		toolsDefs.push({id: "", title : "", icon : "", type : Separator});

		toolsDefs.push({id: "selectionMode", title : "Gizmo selection Mode", icon : "mouse-pointer", type : Button(@:privateAccess sceneEditor.gizmo.selectionMode)});
		toolsDefs.push({id: "translationMode", title : "Gizmo translation Mode", icon : "arrows", type : Button(@:privateAccess sceneEditor.gizmo.translationMode)});
		toolsDefs.push({id: "rotationMode", title : "Gizmo rotation Mode", icon : "refresh", type : Button(@:privateAccess sceneEditor.gizmo.rotationMode)});
		toolsDefs.push({id: "scalingMode", title : "Gizmo scaling Mode", icon : "expand", type : Button(@:privateAccess sceneEditor.gizmo.scalingMode)});

		toolsDefs.push({id: "", title : "", icon : "", type : Separator});

		toolsDefs.push({id: "toggleSnap", title : "Snap Toggle", icon: "magnet", type : Toggle((v) -> {sceneEditor.snapToggle = v; sceneEditor.updateGrid();})});
		toolsDefs.push({id: "snap-menu", title : "", icon: "", type : Popup((e) -> new hide.comp.SceneEditor.SnapSettingsPopup(e, sceneEditor))});

		toolsDefs.push({id: "", title : "", icon : "", type : Separator});

		toolsDefs.push({id: "localTransformsToggle", title : "Local transforms", icon : "compass", type : Toggle((v) -> sceneEditor.localTransform = v)});
		toolsDefs.push({id: "selfOnlyTransformsToggle", title : "Self only transforms", icon : "map-pin", type : Toggle((v) -> sceneEditor.selfOnlyTransform = v)});

		toolsDefs.push({id: "", title : "", icon : "", type : Separator});

		toolsDefs.push({id: "showViewportOverlays", title : "Viewport Overlays", icon : "eye", type : Toggle((v) -> { sceneEditor.updateViewportOverlays(); }) });
		toolsDefs.push({id: "viewportoverlays-menu", title : "", icon: "", type : Popup((e) -> new hide.comp.SceneEditor.ViewportOverlaysPopup(e, sceneEditor))});


		toolsDefs.push({id: "", title : "", icon : "", type : Separator});


		tools.saveDisplayKey = "FXScene/tools";

		tools.makeToolbar(toolsDefs, config, keys);

		tools.addSeparator();

		tools.addPopup(null, "View Modes", (e) -> new hide.comp.SceneEditor.ViewModePopup(e, Std.downcast(@:privateAccess scene.s3d.renderer, h3d.scene.pbr.Renderer), sceneEditor), null);

		tools.addSeparator();

		tools.addPopup(null, "Render Props", (e) -> new hide.comp.SceneEditor.RenderPropsPopup(e, this, sceneEditor, true), null);


		tools.addSeparator();


		loopButton = tools.addToggle("loop", "retweet", "Loop animation (O)", function(v) {
			var fxAnim = sceneEditor.root3d.find((f) -> Std.downcast(f, hrt.prefab.fx.FX.FXAnimation));

			@:privateAccess
			if (fxAnim != null) {
				fxAnim.loop = v;
				if (!fxAnim.loop) {
					fxAnim.playState = End;
				} else {
					if (fxAnim.playState == End) {
						fxAnim.playState = Loop;
					}
				}
			}
		}, false, null, State);



		var gizmo = @:privateAccess sceneEditor.gizmo;

		var onSetGizmoMode = function(mode: hrt.tools.Gizmo.EditMode) {
			tools.element.find("#selectionMode").get(0).toggleAttribute("checked", mode == Selection);
			tools.element.find("#translationMode").get(0).toggleAttribute("checked", mode == Translation);
			tools.element.find("#rotationMode").get(0).toggleAttribute("checked", mode == Rotation);
			tools.element.find("#scalingMode").get(0).toggleAttribute("checked", mode == Scale);
		};

		gizmo.onChangeMode = onSetGizmoMode;
		onSetGizmoMode(gizmo.mode);

		statusText = new h2d.Text(hxd.res.DefaultFont.get(), scene.s2d);
		statusText.setPosition(5, 5);

		var timelines = ide.getViews(Timeline);
		if (timelines.length == 0)
			ide.open("hide.view.Timeline", {});
		else if (isActive()) {
			for (t in timelines)
				bindTimeline(t);
		}
	}

	function onPrefabChange(p: PrefabElement, ?pname: String) {
		// force timeline jump
		forceTick = true;

		if(p == cast(data, hrt.prefab.Prefab)) {
			getTimeline()?.setDuration(data.duration);

			cullingPreview.radius = data.cullingRadius;

			if (pname == "parameters") {
				var all = p.flatten();
				for (e in all)
					sceneEditor.applyTreeStyle(e, All);
			}
		}

		if (pname == "speed" && p is hrt.prefab.fx.SubFX)
			refreshTimelineView();

		if (pname == "blendMode" || pname == "param") {
			Std.downcast(p, Curve)?.syncDatas();

			sceneEditor.queueRebuild(@:privateAccess sceneEditor.sceneData);
			refreshTimelineView();
		}

		if (pname == "refPath") {
			sceneEditor.queueRebuild(@:privateAccess sceneEditor.sceneData);
			refreshTimelineView();
		}

		if (pname == "scale" || pname == "offset") {
			refreshTimelineView();
			data.refreshObjectAnims();
		}

		if(p is Event || p is Curve) {
			data.refreshObjectAnims();
			refreshTimelineView();
			sceneEditor.sceneTree.refreshItem(p);
			var fx3d = Std.downcast((cast data : hrt.prefab.Prefab).findFirstLocal3d(), hrt.prefab.fx.FX.FXAnimation);
			if (fx3d != null) {
				fx3d.initLoop();
			}
		}

		if (pname == "parameters")
			refreshTimelineView();
	}

	function onSelect(elts : Array<PrefabElement>) {
		if (skipRebuildPannel > 0)
			return;
		refreshTimelineView();
		getTimeline()?.frameAll();
	}

	function getTimeline() {
		return timeline?.owner == this ? timeline : null;
	}

	public function bindTimeline(t : Timeline) {
		t.clear();
		t.owner = this;
		timeline = t;
		t.setUnit(Timeline.Unit.Second);
		t.setFramerate(60);
		t.setHasYAxis(true);
		t.setHasFilter(true);
		t.onFilterChange = (_) -> refreshTimelineView();

		t.getTime = () -> currentTime;
		t.setTime = (v : Float) -> currentTime = Math.max(v, 0.);
		t.isPaused = () -> paused;
		t.setPaused = (v : Bool) -> paused = v;
		t.getSpeed = () -> scene.speed;
		t.setSpeed = (v : Float) -> scene.speed = v;
		t.onSave = () -> save();
		t.onUndo = () -> undo.undo();
		t.onRedo = () -> undo.redo();

		t.onCurvesEdit = () -> forceTick = true;
		t.onCurvesChange = (curves : Array<hrt.impl.Curve>, before : Array<Dynamic>, after : Array<Dynamic>) -> {
			function apply(isUndo : Bool) {
				for (i => c in curves)
					@:privateAccess c.copyFromDynamic(hrt.prefab.Diff.deepCopy(isUndo ? before[i] : after[i]));
				onTimelineEdit();
				getTimeline()?.refresh();
			}
			undo.change(Custom(apply));
			onTimelineEdit();
		};

		refreshTimelineView();
		t.frameAll();
	}

	function onTimelineEdit() {
		forceTick = true;
		skipRebuildPannel++;
		@:privateAccess sceneEditor.selectElements(sceneEditor.selectedPrefabs, NoHistory);
		skipRebuildPannel--;
	}

	function refreshTimelineView() {
		var t = getTimeline();
		if (t == null || data == null || element == null || @:privateAccess !sceneEditor.ready)
			return;

		t.clear(Timeline.ClearFlag.Content);
		t.setDuration(data.duration);

		var curvesToDraw : Array<Curve> = [];

		// the curves of the emitter params are edited in the inspector of their emitter, shown here only when they are selected
		function getSection(root : PrefabElement, depth = 0, particles = false): Section {
			var section: Section = { root:root, curves: [], children: []};
			particles = particles || (depth == 0 && root is Curve);
			function shown(c: Curve) return particles || !c.isEmitterParamCurve();

			if (root is Curve && shown(cast root))
				curvesToDraw.push(cast root);

			for(child in root.children) {
				if (child.flatten(Curve).exists(shown)) {
					if (child is Curve) {
						var c = Std.downcast(child, Curve);
						curvesToDraw.push(c);
						section.curves.push(c);
					}
					else {
						section.children.push(getSection(child,depth+1,particles));
					}
				}
			}

			return section;
		}

		var hiddenList : Array<String> = getDisplayState("hiddenList") ?? new Array<String>();
		var foldList : Array<String> = getDisplayState("foldList") ?? new Array<String>();

		var sections = [for (sel in sceneEditor.getSelection()) getSection(sel)];

		// one color per curve, the same in the tracks and in the graph
		timelineCurveColors = new Map();
		var index = 0;
		for (c in curvesToDraw) {
			if (timelineCurveColors.exists(c))
				continue;
			var color = hide.comp.Timeline.getCurveColor(c.name, index++);
			if (c.blendMode == CurveBlendMode.Blend) {
				var param = Std.downcast(c.getRoot(false), hrt.prefab.fx.FX)?.parameters.find(p -> p.name == c.param);
				if (param != null)
					color = param.color;
			}
			timelineCurveColors.set(c, color);
		}

		timelineRows = [];
		timelineFilter = t.filter.toLowerCase().split(":").join(".");
		for (s in sections)
			addSectionTracks(t, s, 0, foldList, hiddenList);

		var shownCurves = [];
		for (c in curvesToDraw) {
			if (!isPathInList(c.getAbsPath(true), hiddenList) && curveMatchesFilter(c) && !shownCurves.contains(c))
				shownCurves.push(c);
		}
		addTimelineCurves(t, shownCurves);
		refreshTimelineRows();
	}

	static function isPathInList(path : String, list : Array<String>) {
		for (p in list) {
			if (path == p || StringTools.startsWith(path, p + "."))
				return true;
		}
		return false;
	}

	function togglePath(key : String, path : String) {
		var list : Array<String> = getDisplayState(key) ?? new Array<String>();
		var isIn = isPathInList(path, list);
		// the path, its parents and its children are removed, then the path is added if it was not in the list
		list = list.filter(p -> !(path == p || StringTools.startsWith(path, p + ".") || StringTools.startsWith(p, path + ".")));
		if (!isIn)
			list.push(path);
		saveDisplayState(key, list);
		refreshTimelineView();
	}

	function selectTimelineRow(name : String) {
		selectedTimelineRow = name;
		refreshTimelineRows();
	}

	function refreshTimelineRows() {
		for (r in timelineRows)
			r.element.classList.toggle("selected", r.name == selectedTimelineRow);
	}

	function getCurvePlayedValue(c : Curve) : Float -> Float {
		var evaluator = new hrt.prefab.fx.Evaluator();
		evaluator.setAllParameters(Std.downcast(c.getRoot(false), hrt.prefab.fx.FX)?.parameters);
		var value : hrt.prefab.fx.Value = try c.makeVal() catch (e : Dynamic) null;
		return (time : Float) -> value == null ? 0. : evaluator.getFloat(value, time);
	}

	function matchesFilter(name : String) {
		return timelineFilter == "" || (name ?? "").toLowerCase().split(":").join(".").indexOf(timelineFilter) >= 0;
	}

	function curveMatchesFilter(c : Curve) {
		var p : PrefabElement = c;
		while (p != null) {
			if (matchesFilter(p.name))
				return true;
			p = p.parent;
		}
		return false;
	}

	function sectionMatchesFilter(section : Section) : Bool {
		if (matchesFilter(section.root.name))
			return true;
		if (section.curves.exists(c -> matchesFilter(c.name)))
			return true;
		return section.children.exists(sectionMatchesFilter);
	}

	function addSectionTracks(t : Timeline, section : Section, depth : Int, foldList : Array<String>, hiddenList : Array<String>, showAll = false) {
		if (!showAll && !sectionMatchesFilter(section))
			return;
		var root = section.root;
		var path = root.getAbsPath(true);
		var showContent = showAll || matchesFilter(root.name);
		// the matching tracks are shown unfolded
		var isFolded = foldList.contains(path) && timelineFilter == "";
		var sectionName = "section:" + path;
		var tag = getTagRec(root);
		var isCurve = root is Curve;
		hide.html.Html.create(
			<div id="header" class="fx-track section" style={'--depth: $depth'} title={path}>
				<hide-icon icon={HideRes.icon.chevron_right} title={isFolded ? "Unfold" : "Fold"} class={isFolded ? "fold" : "fold open"} onclick={(e : js.html.MouseEvent) -> { e.stopPropagation(); togglePath("foldList", path); }}/>
				<span class={tag != null ? "name tagged" : "name"} style={tag != null ? 'background-color: ${tag.color}' : ""}>${upperCase(root.name)}</span>
				<span class="type">${root.getHideProps()?.name ?? ""}</span>
				<span class="buttons">
					<hide-icon id="add-button" icon={HideRes.icon.add} title="Add track" class="add" onclick={(e : js.html.MouseEvent) -> { e.stopPropagation(); openNewTrackMenu(root, addButton); }} if(!isCurve)/>
				</span>
			</div>
		);
		t.addTrack(sectionName, header);
		timelineRows.push({ name: sectionName, element: header });
		if (isFolded)
			return;

		var curves = section.curves.copy();
		if (isCurve)
			curves.push(cast root);
		for (c in curves) {
			if (!showContent && !matchesFilter(c.name))
				continue;
			var curvePath = c.getAbsPath(true);
			var trackName = "curve:" + curvePath;
			var color = timelineCurveColors.get(c);
			var shown = !isPathInList(curvePath, hiddenList);
			hide.html.Html.create(
				<div id="row" class="fx-track curve" style={'--depth: ${depth + 1}'} onclick={() -> { selectTimelineRow(trackName); t.selectKeys(shown ? [for (d in c.datas) for (k in d.keys) k] : []); }}>
					<div class={shown ? "check checked" : "check"} title={shown ? "Hide in the graph" : "Show in the graph"} style={'--check-color: #${StringTools.hex(color & 0xFFFFFF, 6)}'} onclick={(e : js.html.MouseEvent) -> { e.stopPropagation(); togglePath("hiddenList", curvePath); }}/>
					<span class="name">${c.name.split(":").join(".")}</span>
				</div>
			);
			t.addTrack(trackName, row);
			timelineRows.push({ name: trackName, element: row });
		}

		for (child in section.children)
			addSectionTracks(t, child, depth + 1, foldList, hiddenList, showContent);
	}

	function openNewTrackMenu(elt : PrefabElement, button : js.html.Element) {
		var menuItems = getNewTrackMenu(elt);
		if (menuItems.length == 0)
			menuItems = [{label: "No animation available", enabled: false}];
		hide.comp.ContextMenu.createDropdown(button, menuItems);
	}

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

	function addTimelineCurves(t : Timeline, curves : Array<Curve>) {
		for (c in curves) {
			var getValue = getCurvePlayedValue(c);
			var color = timelineCurveColors.get(c);

			// a curve of two datas: each one edited apart, the blend drawn as it is
			if (c.blendMode != CurveBlendMode.Range) {
				if (c.blendMode == CurveBlendMode.None)
					t.addCurve({ name: c.name, color: color, getValue: c.data.getVal, data: c.data });
				else
					t.addCurve({ name: c.name, color: color, getValue: getValue, dashed: c.blendMode == CurveBlendMode.Blend });

				// the curve remapped by its parameter
				if (c.blendMode == CurveBlendMode.None && c.param != null)
					t.addCurve({ name: c.name, color: color, getValue: getValue, dashed: true, faded: true });
			}
			if (c.datas.length > 1) {
				for (i => d in c.datas)
					t.addCurve({ name: c.name + " " + i, color: hide.comp.Timeline.getCurveColor(c.name + " " + i, i), getValue: d.getVal, data: d });
			}
		}
	}

	function addTracks(element : PrefabElement, props : Array<PropTrackDef>, ?prefix: String) {
		var added = [];
		for(prop in props) {
			var id = prefix != null ? prefix + ":" + prop.name : prop.name;
			for(k in hrt.prefab.fx.EmitterParam.animKeys(element, id) ?? [id]) {
				if(Curve.getCurve(element, k, false) != null)
					continue;
				var curve = new Curve(element, null);
				curve.name = k;
				var v = getAnimValue(element, k) ?? prop.def;
				if(v != null)
					curve.addKey(0, v, Linear);
				added.push(curve);
			}
		}

		if(added.length == 0)
			return added;

		undo.change(Custom(function(undo) {
			for(c in added) {
				if(undo)
					c.remove();
				else
					element.addChild(c);
			}
			sceneEditor.queueRebuild(@:privateAccess sceneEditor.sceneData);
			sceneEditor.queueRebuildCallback(() -> @:privateAccess sceneEditor.refreshTree(SceneTree, () -> sceneEditor.selectElements(!undo ? [for (a in added) a] : [], NoHistory)));
		}));
		sceneEditor.queueRebuild(@:privateAccess sceneEditor.sceneData);
		sceneEditor.queueRebuildCallback(() -> @:privateAccess sceneEditor.refreshTree(SceneTree, () -> sceneEditor.selectElements([for (a in added) a], NoHistory)));
		return added;
	}

	public function getNewTrackMenu(elt: PrefabElement) : Array<hrt.ui.HuiMenu.MenuItem> {
		var obj3dElt = Std.downcast(elt, hrt.prefab.Object3D);
		var obj2dElt = Std.downcast(elt, hrt.prefab.Object2D);
		var shaderElt = Std.downcast(elt, hrt.prefab.Shader);
		var rfxElt = Std.downcast(elt, hrt.prefab.rfx.RendererFX);
		var screenShaderGraph = Std.downcast(elt, hrt.prefab.rfx.ScreenShaderGraph);

		var emitter : hrt.prefab.fx.EmitterParam.IEmitter = elt is hrt.prefab.fx.EmitterParam.IEmitter ? cast elt : null;

		var particle2dElt = Std.downcast(elt, hrt.prefab.l2d.Particle2D);
		var menuItems : Array<hrt.ui.HuiMenu.MenuItem> = [];
		var lightElt = Std.downcast(elt, Light);

		inline function hasTrack(pname) {
			return getTrack(elt, pname) != null;
		}

		function trackItem(name: String, props: Array<PropTrackDef>, ?prefix: String) : hrt.ui.HuiMenu.MenuItem {
			var hasAllTracks = true;
			for(p in props) {
				if(getTrack(elt, prefix != null ? prefix + ":" + p.name : p.name) == null)
					hasAllTracks = false;
			}
			return {
				label: upperCase(name),
				click: function() {
					var added = addTracks(elt, props, prefix);
				},
				enabled: !hasAllTracks };
		}

		function groupedTracks(prefix: String, props: Array<PropTrackDef>) : Array<hrt.ui.HuiMenu.MenuItem> {
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
				label: "Rotation",
				menu: groupedTracks("rotation", xyzwTracks(3)),
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

		function makeShaderTracks(shader: hxsl.Shader) {
			if (shader == null)
				return;
			var params = @:privateAccess shader.shader.data.vars.filter(v -> v.kind == Param);
			for(param in params) {
				if (param.qualifiers?.contains(Ignore) ?? false)
					continue;
				var item : hrt.ui.HuiMenu.MenuItem = switch(param.type) {
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

		if(shaderElt != null) {
			makeShaderTracks(shaderElt.makeShader());
		}
		if (rfxElt != null) {
			if (screenShaderGraph != null) {
				@:privateAccess makeShaderTracks(screenShaderGraph.shader ?? screenShaderGraph.makeShader());
			}
			else {
				var serializedProps = rfxElt.getSerializableProps();
				for (f in serializedProps) {
					if (!(Reflect.field(rfxElt, f.name) is Float) || hasTrack(f.name))
						continue;

					menuItems.push(trackItem(f.name, [{name : f.name}]));
				}
			}
		}
		function addParam(param : hrt.prefab.fx.EmitterHelper.PropertyDef, prefix: String) {
			var label = prefix + (param.disp != null ? param.disp : upperCase(param.name));
			var item : hrt.ui.HuiMenu.MenuItem = switch(param.t) {
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

		if(emitter != null) {
			for(f in emitter.getFields())
				switch(f) {
					case Property(p) if(p.animate): addParam(p, "");
					default:
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
				case Rectangle:
					menuItems.push({
						label: "RectangleLight",
						menu: [	trackItem("Color", hslTracks(), "color"),
								trackItem("Power",[{name: "power"}]),
								trackItem("Range", [{name: "range"}]),
								trackItem("Height", [{name: "height"}]),
								trackItem("Width", [{name: "width"}]),
								trackItem("VerticalAngle", [{name: "verticalAngle"}]),
								trackItem("HorizontalAngle", [{name: "horizontalAngle"}]),
								trackItem("FallOff", [{name: "fallOff"}]),
								]
					});
			}
		}
		return menuItems;
	}

	function onUpdate(dt : Float) {
		if (is2D)
			onUpdate2D(dt);
		else
			onUpdate3D(dt);
		sceneEditor.curEdit2?.root?.refreshAnimatedFields();
		getTimeline()?.update();
	}

	function onUpdate2D(dt:Float) {

		var anim = sceneEditor.root2d.find((p) -> Std.downcast(p, hrt.prefab.fx.FX2D.FX2DAnimation));

		if (lastTime != currentTime) {
			lastSeek = currentTime;
		}

		if(!paused) {
			currentTime += scene.speed * dt;

			if(currentTime >= (data.duration == 0 ? 5000 : data.duration)) {
				currentTime = 0;
				lastTime = currentTime;
				anim.setRandSeed(Std.random(0xFFFFFF));
			}
		}

		if (paused || lastTime > currentTime) {
			@:privateAccess scene.s2d.renderer.time = currentTime;
			@:privateAccess scene.s3d.renderer.ctx.time = currentTime;
		}

		if(anim != null) {
			anim.setTime(currentTime);
		}

		lastTime = currentTime;
	}

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

		var fx = local3d.find(o -> {
			var fx = Std.downcast(o, hrt.prefab.fx.FX.FXAnimation);
			if (fx == null || @:privateAccess fx.parentFX != null)
				return null;
			return fx;
		});

		if (fx != null) {
			var hasJumped = currentTime != lastTime;

			if (hasJumped) {
				lastSeek = currentTime;
			}

			var localDt = (hasJumped || paused) ? 0 : scene.speed * dt;
			hasJumped = hasJumped || forceTick;
			var nextTime = currentTime + localDt;
			if (nextTime > fx.duration && fx.duration > 0) {
				nextTime = 0;
				localDt = 0;
				hasJumped = true;
				fx.reset();
				fx.setRandSeed(Std.random(0xFFFFFF));
			}
			@:privateAccess fx.setTimeInternal(nextTime, localDt, hasJumped);

			currentTime = fx.localTime;
			lastTime = currentTime;
			forceTick = false;

			if (hasJumped || paused) {
				@:privateAccess scene.s3d.renderer.ctx.time = currentTime;
			}
		}
	}

	static function getTrack(element : PrefabElement, propName : String) {
		var keys = hrt.prefab.fx.EmitterParam.animKeys(element, propName);
		return Curve.getCurve(element, keys != null ? keys[0] : propName, false);
	}

	static function getAnimValue(element : PrefabElement, key : String) : Null<Float> {
		inline function num(v: Dynamic) : Null<Float> return Std.isOfType(v, Float) || Std.isOfType(v, Int) ? (v : Float) : null;
		var parts = key.split(":");
		var isEmitter = element is hrt.prefab.fx.EmitterParam.IEmitter;
		var comp = parts.length > 1 ? parts[1] : "x";
		if(element is hrt.prefab.Object3D || element is hrt.prefab.Object2D) {
			switch(parts[0]) {
				case "position": return num(Reflect.field(element, comp));
				case "rotation" if(element is hrt.prefab.Object2D): return (cast element : hrt.prefab.Object2D).rotation;
				case "rotation", "scale": return num(Reflect.field(element, parts[0] + comp.toUpperCase()));
				default:
			}
		}
		if(element is hrt.prefab.Shader || element is hrt.prefab.rfx.ScreenShaderGraph) {
			var prop : Dynamic = element.props == null ? null : Reflect.field(element.props, parts[0]);
			if(Std.isOfType(prop, Array) && parts.length > 1)
				prop = (prop : Array<Dynamic>)[hrt.prefab.fx.EmitterParam.COMPONENTS.indexOf(parts[1])];
			return num(prop);
		}
		if(isEmitter || element is hrt.prefab.rfx.RendererFX || (element is Light && parts.length == 1))
			return num(Reflect.field(element, key));
		return null;
	}

	static function upperCase(prop: String) {
		if(prop == null) return "";
		return prop.charAt(0).toUpperCase() + prop.substr(1);
	}

	static var _ = Extension.registerExtension(FXEditor, ["fx"], { icon : "sitemap", createNew : "FX", name: "FX" });

	public function setRenderPropsEditionVisibility(visible : Bool) {
		var renderPropsEditionEl = this.element?.find('.render-props-edition');
		// can appen on close
		if (renderPropsEditionEl == null)
			return;

		if (!visible) {
			renderPropsEditionEl.css({ display : 'none' });
			return;
		}

		renderPropsEditionEl.css({ display : 'block' });
	}
}


class FX2DEditor extends FXEditor {

	override function getDefaultContent() {
		@:privateAccess return haxe.io.Bytes.ofString(ide.toJSON(new hrt.prefab.fx.FX2D(null, null).save()));
	}

	static var _2d = Extension.registerExtension(FX2DEditor, ["fx2d"], { icon : "sitemap", createNew : "FX 2D", name: "FX 2D" });
}