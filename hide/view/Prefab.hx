package hide.view;
import hrt.prefab.l3d.Instance;
import hide.view.CameraController.CamController;
using Lambda;

import hxd.Math;
import hxd.Key as K;

import hrt.prefab.Prefab as PrefabElement;
import hrt.prefab.Object3D;
import hide.comp.cdb.DataFiles;



class FiltersPopup extends hide.comp.Popup {
	var editor:Prefab;
	public function new(?parent:Element, ?root:Element, editor:Prefab, filters:Map<String, Bool>, type:String) {
		super(parent, root);
		this.editor = editor;
		popup.addClass("settings-popup");
		popup.css("max-width", "300px");

		var form_div = new Element("<div>").addClass("form-grid").appendTo(popup);

		{
			for (typeid in filters.keys()) {
				var on = filters[typeid];
				var input = new Element('<input type="checkbox" id="$typeid" value="$typeid"/>');
				if (on)
					input.get(0).toggleAttribute("checked", true);

				input.change((e) -> {
					var on = !filters[typeid];
					filters.set(typeid, on);

					switch (type) {
						case "Graphics":
							@:privateAccess editor.applyGraphicsFilter(typeid, on);
						case "Scene":
							@:privateAccess editor.applySceneFilter(typeid, on);
					}
				});
				form_div.append(input);
				var nameCap = typeid.substr(0, 1).toUpperCase() + typeid.substr(1);
				form_div.append(new Element('<label for="$typeid" class="left">$nameCap</label>'));
			}
		}
	}
}
@:access(hide.view.Prefab)
class PrefabSceneEditor extends hide.comp.SceneEditor {
	var parent : Prefab;

	public function new(view, data) {
		super(view, data);
		parent = cast view;
		this.localTransform = false; // TODO: Expose option
	}

	override function update(dt) {
		super.update(dt);
		parent.onUpdate(dt);
	}

	override function onSceneReady() {
		super.onSceneReady();
		parent.onSceneReady();
	}

	override function applyTreeStyle(p: PrefabElement, el: Element, ?pname: String, ?tree: hide.comp.IconTree<PrefabElement>) {
		super.applyTreeStyle(p, el, pname, tree);
		parent.applyTreeStyle(p, el, pname);
	}

	override function applySceneStyle(p:PrefabElement) {
		parent.applySceneStyle(p);
	}

	override function onPrefabChange(p: PrefabElement, ?pname: String) {
		super.onPrefabChange(p, pname);
		parent.onPrefabChange(p, pname);
	}

	override function getNewContextMenu(current: PrefabElement, ?onMake: PrefabElement->Void=null, ?groupByType = true ) {
		var newItems = super.getNewContextMenu(current, onMake, groupByType);
		var recents = getNewRecentContextMenu(current, onMake);

		function setup(p : PrefabElement) {
			autoName(p);
			haxe.Timer.delay(() -> addElements([p]), 0);
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
					var p = new Instance(current == null ? sceneData : current, null);
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
		newItems.unshift({
			label : "Recents",
			menu : recents,
		});


		var shaders = newItems.find(i -> i.label == "Shader");
		if (shaders != null) {
			newItems.push({label: null, isSeparator: true});
			newItems.remove(shaders);
			splitMenu(newItems, "Shader", shaders.menu);
		}

		return newItems;
	}

	override function getAvailableTags(p:PrefabElement) {
		return cast ide.currentConfig.get("sceneeditor.tags");
	}
}

@:keep
class Prefab extends hide.view.FileView {

	public var sceneEditor : PrefabSceneEditor;
	var data : hrt.prefab.Prefab;

	var tools : hide.comp.Toolbar;

	var layerToolbar : hide.comp.Toolbar;
	var layerButtons : Map<PrefabElement, hide.comp.Toolbar.ToolToggle>;

	var resizablePanel : hide.comp.ResizablePanel;




	// autoSync
	var autoSync : Bool;
	var currentVersion : Int = 0;
	var lastSyncChange : Float = 0.;
	var sceneFilters : Map<String, Bool>;
	var graphicsFilters : Map<String, Bool>;
	var viewModes : Map<String, Bool>;
	var posToolTip : h2d.Text;
	var matLibPath : String;
	var renameMatsHistory : Array<Dynamic>;

	var scene(get, null):  hide.comp.Scene;
	function get_scene() return sceneEditor.scene;
	public var properties(get, null):  hide.comp.PropsEditor;
	function get_properties() return sceneEditor.properties;


	override function new(state) {
		super(state);

		var config = hide.Config.loadForFile(ide, ide.getPath(state.path));
		var matLibs : Array<Dynamic> = config.get("materialLibraries");
		if (matLibs != null) {
			for (lib in matLibs) {
				if (state.path == lib.path) {
					matLibPath = lib.path;
					renameMatsHistory = [];
					break;
				}
			}
		}
	}

	function createData() {
		data = new hrt.prefab.Prefab(null, null);
	}

	function createEditor() {
		sceneEditor = new PrefabSceneEditor(this, data);
	}

	override function onDisplay() {
		if( sceneEditor != null ) sceneEditor.dispose();

		createData();
		var content = sys.io.File.getContent(getPath());
		data = hrt.prefab.Prefab.createFromDynamic(haxe.Json.parse(content));
		currentSign = ide.makeSignature(content);


		element.html('
			<div class="flex vertical">
				<div id="prefab-toolbar"></div>

				<div class="scene-partition" style="display: flex; flex-direction: row; flex: 1; overflow: hidden;">
					<div class="heaps-scene"></div>
					<div class="tree-column">
						<div class="flex vertical">
							<div class="hide-toolbar">
								<div class="toolbar-label">
									<div class="icon ico ico-sitemap"></div>
									Scene
								</div>
								<div class="button collapse-btn" title="Collapse all">
									<div class="icon ico ico-reply-all"></div>
								</div>

								<div class="button combine-btn layout-btn" title="Toggle columns layout">
									<div class="icon ico ico-compress"></div>
								</div>
								<div class="button separate-btn layout-btn" title="Toggle columns layout">
									<div class="icon ico ico-expand"></div>
								</div>

								<div
									class="button hide-cols-btn close-btn"
									title="Hide Tree & Props (${config.get("key.sceneeditor.toggleLayout")})"
								>
									<div class="icon ico ico-chevron-right"></div>
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

					<div class="props-column">
						<div class="hide-toolbar">
							<div class="toolbar-label">
								<div class="icon ico ico-sitemap"></div>
								Properties
							</div>
						</div>
							<div class="hide-scroll"></div>
					</div>

					<div
						class="button show-cols-btn close-btn"
						title="Show Tree & Props (${config.get("key.sceneeditor.toggleLayout")})"
					>
						<div class="icon ico ico-chevron-left"></div>
					</div>
				</div>
			</div>
		');

		tools = new hide.comp.Toolbar(null,element.find("#prefab-toolbar"));
		layerToolbar = new hide.comp.Toolbar(null,element.find(".layer-buttons"));
		currentVersion = undo.currentID;

		createEditor();
		element.find(".hide-scenetree").first().append(sceneEditor.tree.element);
		element.find(".render-props-edition").find('.hide-scenetree').append(sceneEditor.renderPropsTree.element);
		element.find(".hide-scroll").first().append(properties.element);
		element.find(".heaps-scene").first().append(scene.element);

		var treeColumn = element.find(".tree-column").first();
		resizablePanel = new hide.comp.ResizablePanel(Horizontal, treeColumn);
		resizablePanel.saveDisplayKey = "treeColumn";
		resizablePanel.onResize = () -> @:privateAccess if( scene.window != null) scene.window.checkResize();

		sceneEditor.tree.element.addClass("small");
		sceneEditor.renderPropsTree.element.addClass("small");

		refreshColLayout();
		element.find(".combine-btn").first().click((_) -> setCombine(true));
		element.find(".separate-btn").first().click((_) -> setCombine(false));

		element.find(".show-cols-btn").first().click(showColumns);
		element.find(".hide-cols-btn").first().click(hideColumns);

		element.find(".collapse-btn").click(function(e) {
			sceneEditor.collapseTree();
		});

		var rpEditionvisible = Ide.inst.currentConfig.get("sceneeditor.renderprops.edit", false);
		setRenderPropsEditionVisibility(rpEditionvisible);

		keys.register("sceneeditor.toggleLayout", () -> {
			if( element.find(".tree-column").first().css('display') == 'none' )
				showColumns();
			else
				hideColumns();
		});

		refreshSceneFilters();
		refreshGraphicsFilters();
		refreshViewModes();
	}

	override function onBeforeClose() {
		if(Ide.inst.ideConfig.autoSavePrefab)
			this.save();

		return super.onBeforeClose();
	}

	function refreshColLayout() {
		var config = ide.ideConfig;
		if( config.sceneEditorLayout == null ) {
			config.sceneEditorLayout = {
				colsVisible: true,
				colsCombined: false,
			};
		}
		setCombine(config.sceneEditorLayout.colsCombined);

		if( config.sceneEditorLayout.colsVisible )
			showColumns();
		else
			hideColumns();
		if (resizablePanel != null) resizablePanel.setSize();
	}

	override function onActivate() {
		if( element == null )
			return;
		if( sceneEditor != null )
			refreshColLayout();
		if (tools != null)
			tools.refreshToggles();

		setRenderPropsEditionVisibility(Ide.inst.currentConfig.get("sceneeditor.renderprops.edit", false));
	}

	public function hideColumns(?_) {
		element.find(".tree-column").first().hide();
		element.find(".props-column").first().hide();
		element.find(".splitter").first().hide();
		element.find(".show-cols-btn").first().show();
		ide.ideConfig.sceneEditorLayout.colsVisible = false;
		@:privateAccess ide.config.global.save();
		@:privateAccess if( scene.window != null) scene.window.checkResize();
	}

	public function showColumns(?_) {
		element.find(".tree-column").first().show();
		element.find(".props-column").first().show();
		element.find(".splitter").first().show();
		element.find(".show-cols-btn").first().hide();
		ide.ideConfig.sceneEditorLayout.colsVisible = true;
		@:privateAccess ide.config.global.save();
		@:privateAccess if( scene.window != null) scene.window.checkResize();
	}

	function setCombine(val) {
		var fullscene = element.find(".scene-partition").first();
		var props = element.find(".props-column").first();
		fullscene.toggleClass("reduced-columns", val);
		if( val ) {
			element.find(".hide-scenetree").first().parent().append(props);
			element.find(".combine-btn").first().hide();
			element.find(".separate-btn").first().show();
			resizablePanel.setSize();
		} else {
			fullscene.append(props);
			element.find(".combine-btn").first().show();
			element.find(".separate-btn").first().hide();
		}
		ide.ideConfig.sceneEditorLayout.colsCombined = val;
		@:privateAccess ide.config.global.save();
		@:privateAccess if( scene.window != null) scene.window.checkResize();
	}

	public function onSceneReady() {
		refreshSceneFilters();
		refreshGraphicsFilters();
		refreshViewModes();
		tools.saveDisplayKey = "Prefab/toolbar";

		/*gridStep = @:privateAccess sceneEditor.gizmo.moveStep;*/
		var toolsDefs = new Array<hide.comp.Toolbar.ToolDef>();

		toolsDefs.push({id: "perspectiveCamera", title : "Perspective camera", icon : "video-camera", type : Button(() -> resetCamera(false)) });
		toolsDefs.push({id: "camSettings", title : "Camera Settings", icon : "camera", type : Popup((e : hide.Element) -> new hide.comp.CameraControllerEditor(sceneEditor, null,e)) });

		toolsDefs.push({id: "topCamera", title : "Top camera", icon : "video-camera", iconStyle: { transform: "rotateZ(90deg)" }, type : Button(() -> resetCamera(true))});

		toolsDefs.push({id: "", title : "", icon : "", type : Separator});

		toolsDefs.push({id: "snapToGroundToggle", title : "Snap to ground", icon : "anchor", type : Toggle((v) -> sceneEditor.snapToGround = v)});

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

		var texContent : Element = null;
		// toolsDefs.push({id: "sceneInformationToggle", title : "Scene information", icon : "info-circle", type : Toggle((b) -> statusText.visible = b), rightClick: () -> {
		// 	if( texContent != null ) {
		// 		texContent.remove();
		// 		texContent = null;
		// 	}
		// 	new hide.comp.ContextMenu([
		// 		{
		// 			label : "Show Texture Details",
		// 			click : function() {
		// 				var memStats = scene.engine.mem.stats();
		// 				var texs = @:privateAccess scene.engine.mem.textures;
		// 				var list = [for(t in texs) {
		// 					n: '${t.width}x${t.height}  ${t.format}  ${t.name}',
		// 					size: t.width * t.height
		// 				}];
		// 				list.sort((a, b) -> Reflect.compare(b.size, a.size));
		// 				var content = new Element('<div tabindex="1" class="overlay-info"><h2>Scene info</h2><pre></pre></div>');
		// 				new Element(element[0].ownerDocument.body).append(content);
		// 				var pre = content.find("pre");
		// 				pre.text([for(l in list) l.n].join("\n"));
		// 				texContent = content;
		// 				content.blur(function(_) {
		// 					content.remove();
		// 					texContent = null;
		// 				});
		// 			}
		// 		}
		// 	]);
		// }});

		toolsDefs.push({id: "", title : "", icon : "", type : Separator});

		toolsDefs.push({id: "autoSyncToggle", title : "Auto synchronize", icon : "refresh", type : Toggle((b) -> autoSync = b)});

		toolsDefs.push({id: "", title : "", icon : "", type : Separator});


        toolsDefs.push({id: "help", title : "help", icon: "question", type : Popup((e) -> new hide.comp.SceneEditor.HelpPopup(null, e, sceneEditor))});

		toolsDefs.push({id: "", title : "", icon : "", type : Separator});

		toolsDefs.push({id: "viewModes", title: "View Modes", type: Popup((e) -> new hide.comp.SceneEditor.ViewModePopup(null, e, Std.downcast(@:privateAccess scene.s3d.renderer, h3d.scene.pbr.Renderer), sceneEditor))});

		toolsDefs.push({id: "", title : "", icon : "", type : Separator});

		toolsDefs.push({id: "graphicsFilters", title : "Graphics filters", type : Popup((e) -> new FiltersPopup(null, e, this, graphicsFilters, "Graphics"))});

		toolsDefs.push({id: "", title : "", icon : "", type : Separator});

		toolsDefs.push({id: "sceneFilters", title : "Scene filters", type : Popup((e) -> new FiltersPopup(null, e, this, sceneFilters, "Scene"))});

		toolsDefs.push({id: "", title : "", icon : "", type : Separator});

		toolsDefs.push({
			id: "renderProps",
			title: "Render props",
			type: Popup((e) -> new hide.comp.SceneEditor.RenderPropsPopup(null, e, this, sceneEditor, true))
		});

		toolsDefs.push({
			id: "",
			title: "",
			icon: "",
			type: Separator
		});

		toolsDefs.push({id: "sceneSpeed", title : "Speed", type : Range((v) -> scene.speed = v)});

		toolsDefs.push({id: "", title : "", icon : "", type : Separator});

		//toolsDefs.push({id: "test", title : "Hello", icon : "", type : Popup((e : hide.Element) -> new hide.comp.CameraControllerEditor(sceneEditor, null,e))});


		tools.makeToolbar(toolsDefs, config, keys);

		posToolTip = new h2d.Text(hxd.res.DefaultFont.get(), scene.s2d);
		posToolTip.dropShadow = { dx : 1, dy : 1, color : 0, alpha : 0.5 };


		var gizmo = @:privateAccess sceneEditor.gizmo;

		var onSetGizmoMode = function(mode: hrt.tools.Gizmo.EditMode) {
			tools.element.find("#translationMode").get(0).toggleAttribute("checked", mode == Translation);
			tools.element.find("#rotationMode").get(0).toggleAttribute("checked", mode == Rotation);
			tools.element.find("#scalingMode").get(0).toggleAttribute("checked", mode == Scaling);
		};

		gizmo.onChangeMode = onSetGizmoMode;
		onSetGizmoMode(gizmo.editMode);

		initGraphicsFilters();

		initSceneFilters();
		sceneEditor.onRefresh = () -> {
			initGraphicsFilters();
			initSceneFilters();
		}
	}

	function resetCamera( top : Bool ) {
		var targetPt = new h3d.col.Point(0, 0, 0);
		if(sceneEditor.selectedPrefabs.length > 0) {
			targetPt = sceneEditor.selectedPrefabs[0].findFirstLocal3d().getAbsPos().getPosition().toPoint();
		}
		if(top)
			sceneEditor.cameraController.set(200, Math.PI/2, 0.001, targetPt);
		else
			sceneEditor.cameraController.set(200, -4.7, 0.8, targetPt);
		sceneEditor.cameraController.toTarget();
	}

	override function getDefaultContent() {
		@:privateAccess return haxe.io.Bytes.ofString(ide.toJSON(new hrt.prefab.Prefab(null, null).serialize()));
	}

	override function canSave() {
		return data != null;
	}

	override function save() {
		if( !canSave() )
			return;

		// Save render props
		if (Ide.inst.currentConfig.get("sceneeditor.renderprops.edit", false) && sceneEditor.renderPropsRoot != null)
			sceneEditor.renderPropsRoot.save();

		@:privateAccess var content = ide.toJSON(data.serialize());
		var newSign = ide.makeSignature(content);
		if(newSign != currentSign)
			haxe.Timer.delay(saveBackup.bind(content), 0);
		currentSign = newSign;
		sys.io.File.saveContent(getPath(), content);
		super.save();

		// if (renameMatsHistory != null) {
		// 	for (entry in renameMatsHistory)
		// 		saveMatLibsRenames(entry.previousName, entry.newName, entry.prefab);

		// 	renameMatsHistory = [];
		// }
	}

	function saveMatLibsRenames(oldName : String, newName : String, prefab : hrt.prefab.Prefab) {
		function renameContent(content:Dynamic) {
			var visited = new Array<Dynamic>();

			function renamePath(p: String) {
				if( p == null )
					return null;

				var pos = p.indexOf(oldName);
				if (pos < 0)
					return p;

				if( p == newName )
					return p;

				if ((pos == 0 || p.charAt(pos -1) == '/') && (pos + oldName.length >= p.length || p.charAt(pos + oldName.length) == '/'))
					p = StringTools.replace(p, oldName, newName);

				return p;
			}

			function renameObj(obj:Dynamic) : Dynamic {
				switch( Type.typeof(obj) ) {
					case TObject:
						if( visited.indexOf(obj) >= 0 ) return null;
						visited.push(obj);
						if (Reflect.hasField(obj, "__ref") && Reflect.getProperty(obj, "__ref") != matLibPath)
							return null;
						for( f in Reflect.fields(obj) ) {
							var v : Dynamic = Reflect.field(obj, f);
							v = renameObj(v);
							if( v != null ) Reflect.setField(obj, f, v);
						}
					case TClass(Array):
						if( visited.indexOf(obj) >= 0 ) return null;
						visited.push(obj);
						var arr : Array<Dynamic> = obj;
						for( i in 0...arr.length ) {
							var v : Dynamic = arr[i];
							v = renameObj(v);
							if( v != null ) arr[i] = v;
						}
					case TClass(String):
						return renamePath(obj);

					default:
				}

				return null;
			}

			for( f in Reflect.fields(content) ) {
				var v = renameObj(Reflect.field(content,f));
				if( v != null ) Reflect.setField(content,f,v);
			}
		}

		ide.filterProps(function(content:Dynamic) {
			renameContent(content);
			return true;
		});
	}

	function onUpdate(dt:Float) {
		if(K.isDown(K.ALT)) {
			posToolTip.visible = true;
			var proj = sceneEditor.screenToGround(scene.s2d.mouseX, scene.s2d.mouseY);
			posToolTip.text = proj != null ? '${Math.fmt(proj.x)}, ${Math.fmt(proj.y)}, ${Math.fmt(proj.z)}' : '???';
			posToolTip.setPosition(scene.s2d.mouseX, scene.s2d.mouseY - 12);
		}
		else {
			posToolTip.visible = false;
		}

		if( autoSync && (currentVersion != undo.currentID || lastSyncChange != properties.lastChange) ) {
			save();
			lastSyncChange = properties.lastChange;
			currentVersion = undo.currentID;
		}

	}

	function onRefresh() {
	}

	override function onDragDrop(items : Array<String>, isDrop : Bool) {
		return sceneEditor.onDragDrop(items, isDrop);
	}

	function applyGraphicsFilter(typeid: String, enable: Bool) {
		saveDisplayState("graphicsFilters/" + typeid, enable);

		var r : h3d.scene.Renderer = scene.s3d.renderer;
		var all = data.findAll(hrt.prefab.Object3D, true);
		for (obj in all) {
			if (obj.getDisplayFilters().contains(typeid)) {
				obj.updateInstance();
			}
		}

		switch (typeid)
		{
		case "shadows":
			r.shadows = enable;
		default:
		}
	}

	function applySceneFilter(typeid: String, visible: Bool) {
		saveDisplayState("sceneFilters/" + typeid, visible);
		var all = [];
		if (typeid != 'light')
			all = data.findAll(hrt.prefab.Prefab, true);
		else
			all = data.flatten(hrt.prefab.Prefab);
		for(p in all) {
			if(p.type == typeid || p.getCdbType() == typeid) {
				sceneEditor.applySceneStyle(p);
			}
		}
	}

	function refreshSceneFilters() {
		var filters : Array<String> = ide.currentConfig.get("sceneeditor.filterTypes");
		filters = filters.copy();
		for(sheet in DataFiles.getAvailableTypes()) {
			filters.push(DataFiles.getTypeName(sheet));
		}
		sceneFilters = new Map();
		for(f in filters) {
			sceneFilters.set(f, getDisplayState("sceneFilters/" + f) != false);
		}
	}

	function initGraphicsFilters() {
		for (typeid in graphicsFilters.keys())
		{
			applyGraphicsFilter(typeid, graphicsFilters.get(typeid));
		}
	}

	function initSceneFilters() {
		for (typeid in sceneFilters.keys())
		{
			applySceneFilter(typeid, sceneFilters.get(typeid));
		}
	}

	function refreshGraphicsFilters() {
		var filters : Array<String> = ["shadows"];
		var all = data.findAll(hrt.prefab.Object3D, true);
		for (obj in all) {
			var objFilters = obj.getDisplayFilters();
			for (f in filters) {
				objFilters.remove(f);
			}
			filters = filters.concat(objFilters);
		}
		filters = filters.copy();
		graphicsFilters = new Map();
		for(f in filters) {
			graphicsFilters.set(f, getDisplayState("graphicsFilters/" + f) != false);
		}
	}

	function refreshViewModes() {
		var filters : Array<String> = ["LIT", "Full", "Albedo", "Normal", "Roughness", "Metalness", "Emissive", "AO", "Shadows", "Performance"];
		viewModes = new Map();
		for(f in filters) {
			viewModes.set(f, false);
		}
	}

	function filtersToMenuItem(filters : Map<String, Bool>, type : String) : Array<hide.comp.ContextMenu.ContextMenuItem> {
		var content : Array<hide.comp.ContextMenu.ContextMenuItem> = [];
		var initDone = false;
		for(typeid in filters.keys()) {
			if ( type == "View" ) {
				content.push({label : typeid, click : function() {
					var r = Std.downcast(scene.s3d.renderer, h3d.scene.pbr.Renderer);
					if ( r == null )
						return;
					var slides = @:privateAccess r.slides;
					if ( slides == null )
						return;
					switch(typeid) {
						case "LIT":
							r.displayMode = Pbr;
						case "Full":
							r.displayMode = Debug;
							slides.shader.mode = Full;
						case "Albedo":
							r.displayMode = Debug;
							slides.shader.mode = Albedo;
						case "Normal":
							r.displayMode = Debug;
							slides.shader.mode = Normal;
						case "Roughness":
							r.displayMode = Debug;
							slides.shader.mode = Roughness;
						case "Metalness":
							r.displayMode = Debug;
							slides.shader.mode = Metalness;
						case "Emissive":
							r.displayMode = Debug;
							slides.shader.mode = Emmissive;
						case "AO":
							r.displayMode = Debug;
							slides.shader.mode = AO;
						case "Shadows":
							r.displayMode = Debug;
							slides.shader.mode = Shadow;
						case "Performance":
							r.displayMode = Performance;
						default:
					}
				}
				});
			} else {
				content.push({label : typeid, checked : filters[typeid], click : function() {
					var on = !filters[typeid];
					filters.set(typeid, on);
				if(initDone)
					switch (type){
						case "Graphics":
							applyGraphicsFilter(typeid, on);
						case "Scene":
							applySceneFilter(typeid, on);
					}

				content.find(function(item) return item.label == typeid).checked = on;
				}});
			}
		}
		initDone = true;
		return content;
	}

	function applyTreeStyle(p: PrefabElement, el: Element, pname: String) {
	}

	function onPrefabChange(p: PrefabElement, ?pname: String) {

	}

	function applySceneStyle(p: PrefabElement) {
		var prefabView = Std.downcast(p, hrt.prefab.Prefab); // don't use "to" (Reference)
		if( prefabView != null && prefabView.parent == null ) {
			sceneEditor.updateGrid();
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
			if (obj3d.local3d != null) {
				obj3d.local3d.visible = visible;
			}
		}
		var color = getDisplayColor(p);
		if(color != null){
			color = (color & 0xffffff) | 0xa0000000;
			var box = p.to(hrt.prefab.l3d.Box);
			if(box != null) {
				box.setColor(color);
			}
			var poly = p.to(hrt.prefab.l3d.Polygon);
			if(poly != null) {
				poly.setColor(color);
			}
		}
	}

	public function setRenderPropsEditionVisibility(visible : Bool) {
		var renderPropsEditionEl = this.element.find('.render-props-edition');

		if (!visible) {
			renderPropsEditionEl.css({ display : 'none' });
			return;
		}

		renderPropsEditionEl.css({ display : 'block' });
	}

	function getDisplayColor(p: PrefabElement) : Null<Int> {
		var typeId = p.getCdbType();
		if(typeId != null) {
			var colors = ide.currentConfig.get("sceneeditor.colors");
			var color = Reflect.field(colors, typeId);
			if(color != null) {
				return Std.parseInt("0x"+color.substr(1)) | 0xff000000;
			}
		}
		return null;
	}

	static var _ = hide.view.FileTree.registerExtension(Prefab, ["prefab"], { icon : "sitemap", createNew : "Prefab" });
	static var _1 = hide.view.FileTree.registerExtension(Prefab, ["l3d"], { icon : "sitemap" });

}