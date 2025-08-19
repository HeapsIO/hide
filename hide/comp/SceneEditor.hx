package hide.comp;

import hrt.prefab.ContextShared;
using hrt.prefab.Object3D; // GetLocal3D
using hrt.prefab.Object2D; // GetLocal2D

using Lambda;
import hrt.tools.MapUtils;

import hrt.prefab.Reference;
import h3d.scene.Mesh;
import h3d.col.FPoint;
import h3d.col.Ray;
import h3d.col.PolygonBuffer;
import h3d.prim.HMDModel;
import h3d.col.Collider.OptimizedCollider;
import h3d.Vector;
import hxd.Key as K;
import hxd.Math as M;

import h3d.shader.pbr.Slides.DebugMode;
import h3d.scene.pbr.Renderer.DisplayMode;

import hrt.prefab.Prefab as PrefabElement;
import hrt.prefab.Object2D;
import hrt.prefab.Object3D;
import h3d.scene.Object;

import hide.comp.cdb.DataFiles;
import hide.view.CameraController;

using hide.tools.Extensions.ArrayExtensions;
import hide.comp.CameraControllerEditor;

enum SelectMode {
	/**
		Update tree, add undo command
	**/
	Default;
	/**
		Update tree only
	**/
	NoHistory;
	/**
		Add undo but don't update tree
	**/
	NoTree;
	/**
		Don't refresh tree and don't undo command
	**/
	Nothing;
}

@:access(hide.comp.SceneEditor)
class RulerTool {
	var editor : SceneEditor;

	var interactive : h2d.Interactive;
	var graphics : h3d.scene.Graphics;
	var text : h2d.Text;

	var current : h3d.Vector;
	var start : h3d.Vector;
	var end : h3d.Vector;

	public function new(editor: SceneEditor) {
		this.editor = editor;

		interactive = new h2d.Interactive(10000,10000, editor.scene.s2d);
		interactive.propagateEvents = true;
		interactive.cancelEvents = false;

		interactive.onPush = function(e) {
			if (e.button == 0) {
				e.propagate = false;
				if ((end == null) == (start == null)) {
					start = editor.screenToGround(editor.scene.s2d.mouseX, editor.scene.s2d.mouseY);
					end = null;
				} else {
					end = editor.screenToGround(editor.scene.s2d.mouseX, editor.scene.s2d.mouseY);
				}
			}
		}

		interactive.onClick = function(e) {
			if (e.button == 0) {
				e.propagate = false;
			}
		}

		interactive.onRelease = function(e) {
			if (e.button == 0) {
				e.propagate = false;
			}
		}

		interactive.onMove = function(e) {
			current = editor.screenToGround(editor.scene.s2d.mouseX, editor.scene.s2d.mouseY);
		};

		graphics = new h3d.scene.Graphics(editor.scene.s3d);
		graphics.material.mainPass.setPassName("ui");
		graphics.material.mainPass.depth(false, Always);
		text = new h2d.Text(hxd.res.DefaultFont.get(), editor.scene.s2d);
		text.dropShadow = {
			dx: 1,
			dy: 1,
			color: 0,
			alpha: 0.5,
		};
	}

	public function update(dt: Float) {
		graphics.clear();
		text.visible = false;

		var start = start ?? current;
		var endPt = end ?? current;
		if (endPt != null) {
			graphics.lineStyle(10.0, 0x00AEFF);
			graphics.moveTo(start.x, start.y, start.z);
			graphics.lineTo(endPt.x, endPt.y, endPt.z);

			var to : h3d.Vector = (endPt - start);
			var dist : Float = to.length();

			var screenStart = editor.worldToScreen(start.x, start.y, start.z);
			var screenEnd = editor.worldToScreen(endPt.x, endPt.y, endPt.z);

			var screenMid = (screenStart + screenEnd) * 0.5;
			text.setPosition(screenMid.x, screenMid.y-8.0);

			var str = SceneEditor.splitCentainesFloat(dist, 2);
			text.text = str;
			text.visible = true;
		}

	}

	public function dispose() {
		interactive.remove();
		graphics.remove();
		text.remove();
	}

}

@:access(hide.comp.SceneEditor)
class ViewportOverlaysPopup extends hide.comp.Popup {
	var editor:SceneEditor;

	public function new(?parent : Element, editor: SceneEditor) {
		super(parent);
		this.editor = editor;

		element.append(new Element("<p>Viewport Overlays</p>"));
		element.addClass("settings-popup");
		element.css("max-width", "300px");

		element.append(new Element('
			<h2>Guides</h2>
			<div class="form-grid" id="guidesGroup"></div>
			<h2>Selection</h2>
			<div class="form-grid" id="selectionGroup"></div>
			<h2>Debug</h2>
			<div class="form-grid" id="debug"></div>
			<h2>Icons</h2>
			<div class="form-grid" id="showIconGroup"></div>
			<div class="form-grid" id="allIcons"></div>
		'));


		function addButton(label: String, icon: String, key: String, cb: () -> Void) : Element {
			var e = new Element('
			<div class="tb-group small">
				<div class="button2" id="$key">
					<div class="icon ico ico-$icon"></div>
				</div>
			</div>
			<label class="left">$label</label>');
			var btn = e.find('#$key');
			var store = 'sceneeditor.$key';
			var v = ide.currentConfig.get(store, false);
			btn.get(0).toggleAttribute("checked", v);

			btn.click(function(e) {
				if (e.button == 0) {
					var v = !editor.ide.currentConfig.get(store);
					editor.ide.currentConfig.set(store, v);
					btn.get(0).toggleAttribute("checked", v);
					cb();
				}
			});
			return e;
		}

		{
			var group = element.find("#guidesGroup");
			addButton("Grid", "th", "gridToggle", () -> editor.updateGrid()).appendTo(group);
			addButton("Axis", "arrows", "axisToggle", () -> editor.updateBasis()).appendTo(group);
			addButton("Joints", "share-alt", "jointsToggle", () -> editor.updateJointsVisibility()).appendTo(group);
			addButton("Colliders", "codepen", "colliderToggle", () -> editor.updateCollidersVisibility()).appendTo(group);
			addButton("Other", "question-circle", "showOtherGuides", () -> editor.updateOtherGuidesVisibility()).appendTo(group);

			{
				var key = "backgroundColor";
				var e = new Element('
				<div class="tb-group small">
					<div class="button2" id="$key">
					</div>
				</div>
				<label class="left">Background color</label>').appendTo(group);
				var store = 'sceneeditor.$key';
				var color = new hide.comp.ColorPicker.ColorBox(e.find('#$key'), null, true);
				color.value = editor.ide.currentConfig.get(store);
				color.element.height("100%");
				color.element.width("100%");
				color.onChange = function(move) {
					editor.ide.currentConfig.set(store, color.value);
					editor.updateBackgroundColor();
				}

				onShouldCloseOnClick = function(e) {
					return !color.isPickerOpen();
				}
			}
		}

		{
			var group = element.find("#selectionGroup");
			addButton("Gizmo", "arrows-alt", "showGizmo", () -> editor.updateGizmoVisibility()).appendTo(group);
			addButton("Outline", "dot-circle-o", "showOutlines", () -> editor.updateOutlineVisibility()).appendTo(group);
		}


		{
			var group = element.find("#debug");
			var btn = addButton("Scene Info", "info-circle", "sceneInformationToggle", () -> editor.updateStatusTextVisibility()).appendTo(group);
			addButton("Wireframe", "connectdevelop", "wireframeToggle", () -> editor.updateWireframe()).appendTo(group);
			addButton("Disable Scene Render", "eye-slash", "tog-scene-render", () -> {}).appendTo(group);
		}


		var allIcons = element.find("#allIcons");
		function refreshIconMenu() {
			var visible = editor.ide.currentConfig.get("sceneeditor.iconVisibility");
			if (visible) {
				allIcons.show();
			} else {
				allIcons.hide();
			}
		}

		{
			var group = element.find("#showIconGroup");
			addButton("3D Icons", "image", "iconVisibility", () -> {refreshIconMenu(); editor.updateIconsVisibility();}).appendTo(group);

			allIcons.css("margin-left", "3px");
			for (k => v in ide.show3DIconsCategory) {
				var input = new Element('<input type="checkbox" name="snap" id="$k" value="$k"/>');
				if (v)
					input.get(0).toggleAttribute("checked", true);
				input.change((e) -> {
					var val = !ide.show3DIconsCategory.get(k);
					ide.show3DIconsCategory.set(k, val);
					js.Browser.window.localStorage.setItem(hrt.impl.EditorTools.iconVisibilityKey(k), val ? "true" : "false");

					if (k.match(hrt.impl.EditorTools.IconCategory.Object3D)) {
						for (p in editor.sceneData.all()) {
							var obj3D = Std.downcast(p, Object3D);

							if (obj3D != null) {
								obj3D.removeEditorUI();
								obj3D.addEditorUI();
							}
						}
					}
				});
				allIcons.append(input);
				allIcons.append(new Element('<label for="$k" class="left">$k</label>'));
			}
		}


		refreshIconMenu();



		// <input type="checkbox" name"showAxis" id="showAxis"/><label for="showAxis" class="left">Axis</label>


		// {
		// 	var input = element.find("#showGrid");
		// 	input.get(0).toggleAttribute("checked", editor.showGrid);
		// 	input.click(function(e){
		// 		if (e.button == 0) {
		// 			var v = !editor.ide.currentConfig.get("sceneeditor.gridToggle", false);
		// 			editor.ide.currentConfig.set("sceneeditor.gridToggle", v);
		// 			input.get(0).toggleAttribute("checked", v);
		// 			editor.updateGrid();
		// 		}
		// 	});
		// }

		// {
		// 	var input = element.find("#showAxis");
		// 	input.prop("checked", editor.showBasis);
		// 	input.on("change", function(){
		// 		editor.showBasis = input.prop("checked");
		// 		editor.updateBasis();
		// 	});
		// }
	}
}

class SnapSettingsPopup extends hide.comp.Popup {
	var editor : SceneEditor;

	public function new(?parent : Element, editor: SceneEditor) {
		super(parent);
		this.editor = editor;

		element.append(new Element("<p>Snap Settings</p>"));
		element.addClass("settings-popup");
		element.css("max-width", "300px");

		var form_div = new Element("<div>").addClass("form-grid").appendTo(element);

		var editMode : hrt.tools.Gizmo.EditMode = @:privateAccess editor.gizmo.editMode;

		var steps : Array<Float> = [];
		switch (editMode) {
			case Translation:
				steps = editor.view.config.get("sceneeditor.gridSnapSteps");
			case Rotation:
				steps = editor.view.config.get("sceneeditor.rotateStepCoarses");
			case Scaling:
				steps = editor.view.config.get("sceneeditor.gridSnapSteps");
		}

		for (value in steps) {
			var input = new Element('<input type="radio" name="snap" id="snap$value" value="$value"/>');

			var equals = switch (editMode) {
				case Translation:
					editor.snapMoveStep == value;
				case Rotation:
					editor.snapRotateStep == value;
				case Scaling:
					editor.snapScaleStep == value;
			}

			if (equals)
				input.get(0).toggleAttribute("checked", true);
			input.change((e) -> {
				switch (editMode) {
					case Translation:
						editor.snapMoveStep = value;
					case Rotation:
						editor.snapRotateStep = value;
					case Scaling:
						editor.snapScaleStep = value;
				}
				editor.updateGrid();
				editor.saveSnapSettings();
			});
			form_div.append(input);
			form_div.append(new Element('<label for="snap$value" class="left">$value${editMode==Rotation ? "°" : ""}</label>'));

		}


		{
			var input = new Element('<input type="checkbox" name="forceSnapGrid" id="forceSnapGrid"/>').appendTo(form_div);
			new Element('<label for="forceSnapGrid" class="left">Force On Grid</label>').appendTo(form_div);

			if (editor.snapForceOnGrid)
				input.get(0).toggleAttribute("checked", true);

			input.change((e) -> {
				editor.snapForceOnGrid = !editor.snapForceOnGrid;
				editor.saveSnapSettings();
			});
		}
	}
}

@:access(hide.comp.SceneEditor)
class SceneEditorContext extends hide.prefab.EditContext {

	public var editor(default, null) : SceneEditor;
	public var elements : Array<PrefabElement>;
	public var rootObjects(default, null): Array<Object>;
	public var rootObjects2D(default, null): Array<h2d.Object>;
	public var rootElements(default, null): Array<PrefabElement>;

	public function new(elts, editor) {
		super();
		this.editor = editor;
		this.updates = @:privateAccess editor.updates;
		this.elements = elts;
		rootElements = [];
		rootObjects = [];
		rootObjects2D = [];
		cleanups = [];
		for(elt in elements) {
			var obj3d = elt.to(Object3D);
			if(obj3d != null) {
				if(!SceneEditor.hasParent(elt, elements)) {
					rootElements.push(elt);
					var pobj = elt.parent == editor.sceneData ? obj3d.local3d : obj3d.parent.getLocal3d();
					if (pobj != null)
						rootObjects.push(pobj);
				}
			}

			var obj2d = elt.to(Object2D);
			if (obj2d != null) {
				if(!SceneEditor.hasParent(elt, elements)) {
					rootElements.push(elt);
					var pobj = elt.parent == editor.sceneData ? obj2d.local2d : obj2d.parent.getLocal2d();
					if (pobj != null)
						rootObjects2D.push(pobj);
				}
			}
		}
	}

	override function screenToGround(x:Float, y:Float, ?forPrefab:hrt.prefab.Prefab) {
		return editor.screenToGround(x, y, forPrefab);
	}

	override function positionToGroundZ(x:Float, y:Float, ?forPrefab:hrt.prefab.Prefab):Float {
		return editor.getZ(x, y, forPrefab);
	}

	override function getCurrentProps( p : hrt.prefab.Prefab ) {
		var cur = editor.curEdit;
		return cur != null && cur.elements[0] == p ? editor.properties.element : new Element();
	}

	/*function getContextRec( p : hrt.prefab.Prefab ) {
		if( p == null )
			return editor.context;
		var c = editor.context.shared.contexts.get(p);
		if( c == null )
			return getContextRec(p.parent);
		return c;
	}*/

	override function rebuildProperties() {
		editor.scene.setCurrent();
		editor.selectElements(elements, NoHistory);
	}

	override function rebuildPrefab( p : hrt.prefab.Prefab, ?sceneOnly : Bool) {
		editor.queueRebuild(p);
	}

	public function cleanup() {
		for( c in cleanups.copy() )
			c();
		cleanups = [];
	}

	override function onChange(p : PrefabElement, pname: String) {
		super.onChange(p, pname);
		editor.onPrefabChange(p, pname);
	}
}

enum RefreshMode {
	Partial;
	Full;
}

typedef CustomPivot = { elt : PrefabElement, mesh : Mesh, locPos : Vector };
typedef TagInfo = {id: String, color: String};

class ViewModePopup extends hide.comp.Popup {
	static var viewFilter : Array<{name: String, inf: {display: DisplayMode, debug: DebugMode}}> = [
		{
			name : "LIT",
			inf : {
				display : Pbr,
				debug : Normal
			},
		},
		{
			name: "Full",
			inf : {
				display: Debug,
				debug: Full
			}
		},
		{
			name: "Albedo",
			inf : {
				display: Debug,
				debug: Albedo
			}
		},
		{
			name: "Normal",
			inf : {
				display: Debug,
				debug: Normal
			}
		},
		{
			name: "Roughness",
			inf : {
				display: Debug,
				debug: Roughness
			}
		},
		{
			name: "Metalness",
			inf : {
				display: Debug,
				debug: Metalness
			}
		},
		{
			name: "Emissive",
			inf : {
				display: Debug,
				debug: Emissive
			}
		},
		{
			name: "AO",
			inf : {
				display: Debug,
				debug: AO
			}
		},
		{
			name: "Shadows",
			inf : {
				display: Debug,
				debug: Shadow
			}
		},
		{
			name: "Performance",
			inf : {
				display: Performance,
				debug: Normal
			}
		},
		{
			name : "UVChecker",
			inf : {
				display : Pbr,
				debug : Normal
			},
		},
		{
			name : "Displacement",
			inf : {
				display : Debug,
				debug : Albedo
			},
		},
		{
			name : "Velocity",
			inf : {
				display : Debug,
				debug : Velocity
			},
		}
	];
	var renderer:h3d.scene.pbr.Renderer;
	var editor : SceneEditor;

	public function new(?parent:Element, engineRenderer:h3d.scene.pbr.Renderer, editor: SceneEditor) {
		super(parent);
		this.renderer = engineRenderer;
		this.editor = editor;

		element.addClass("settings-popup");
		element.css("max-width", "300px");

		if (renderer == null)
			return;

		var form_div = new Element("<div>").addClass("form-grid").appendTo(element);

		var slides = @:privateAccess renderer.slides;
		for (v in viewFilter) {
			var typeid = v.name;
			var on = renderer.displayMode == v.inf.display;
			switch ( renderer.displayMode) {
			case Debug:
				on = on && slides.shader.mode == v.inf.debug;
			default:
				on = on && v.name != "UVChecker" && v.name != "Displacement";
			}

			if (v.name == "UVChecker" && isUvChecker())
				on = true;
			if(  v.name == "Displacement" && isDisplacementDisplay() )
				on = true;

			var input = new Element('<input type="radio" name="filter" id="$typeid" value="$typeid"/>');
			if (on)
				input.get(0).toggleAttribute("checked", true);

			input.change((e) -> {
				this.applyViewMode(input, v);
			});

			form_div.append(input);
			form_div.append(new Element('<label for="$typeid" class="left">$typeid</label>'));
		}
	}

	public function applyViewMode(input: Element, v: Dynamic) {
		var slides = @:privateAccess renderer.slides;
			if (slides == null)
				return;

			if (input.is(':checked')) {
				this.saveDisplayState("ViewMode", v.name);
			}

			renderer.displayMode = v.inf.display;
			if (renderer.displayMode == Debug) {
				slides.shader.mode = v.inf.debug;
			}

			var s3d = @:privateAccess editor.scene.s3d;

			var isUvChecker = v.name == "UVChecker" && input.is(":checked");
			function checkUV(obj: Object) {
				var mesh = Std.downcast(obj, Mesh);

				if (mesh != null && mesh.primitive != null && mesh.primitive.buffer != null &&
					!mesh.primitive.buffer.isDisposed() &&
					mesh.primitive.buffer.format != null &&
					mesh.primitive.buffer.format.getInput("uv") != null) {
					for (mat in mesh.getMaterials(null, false)) {
						if (isUvChecker) {
							if (mat.mainPass.getShader(h3d.shader.Checker) == null)
								mat.mainPass.addShader(new h3d.shader.Checker());
						} else {
						var s = mat.mainPass.getShader(h3d.shader.Checker);
						if (s != null)
							mat.mainPass.removeShader(s);
						}
					}
				}
				for (idx in 0...obj.numChildren)
					checkUV(obj.getChildAt(idx));
			}
			checkUV(s3d);


			var isDisplacementDisplay = v.name == "Displacement" && input.is(":checked");
			for ( m in s3d.getMeshes() ) {
				for ( mat in m.getMaterials(false) ) {
					if ( mat.specularTexture == null )
						continue;
					var s = mat.mainPass.getShader(h3d.shader.DisplacementDisplay);
					if ( s != null )
						mat.mainPass.removeShader(s);
					if ( isDisplacementDisplay ) {
						var s = new h3d.shader.DisplacementDisplay();
						s.tex = mat.specularTexture;
						@:privateAccess mat.mainPass.addSelfShader(s);
					}
				}
			}
	}

	public function isUvChecker() {
		function hasCheckUV(obj: Object) {
				var mesh = Std.downcast(obj, Mesh);

				if (mesh != null && mesh.primitive != null && mesh.primitive.buffer != null &&
					!mesh.primitive.buffer.isDisposed() &&
					mesh.primitive.buffer.format != null &&
					mesh.primitive.buffer.format.getInput("uv") != null) {
					for (mat in mesh.getMaterials(null, false)) {
						if (mat.mainPass.getShader(h3d.shader.Checker) != null)
							return true;
					}
				}

				for (idx in 0...obj.numChildren)
					hasCheckUV(obj.getChildAt(idx));

				return false;
			}

		@:privateAccess return hasCheckUV(editor.scene.s3d);
	}

	public function isDisplacementDisplay() {
		var hasShader = false;
		for ( m in editor.scene.s3d.getMaterials() ) {
			if ( m.mainPass.getShader(h3d.shader.DisplacementDisplay) != null ) {
				hasShader = true;
				return true;
			}
		}
		return false;
	}
}

class IconVisibilityPopup extends hide.comp.Popup {
	 var editor : SceneEditor;

	 public function new(?parent : Element, editor: SceneEditor) {
		  super(parent);
		  this.editor = editor;

		  element.append(new Element("<p>Icon Visibility</p>"));
		  element.addClass("settings-popup");
		  element.css("max-width", "300px");

		  var form_div = new Element("<div>").addClass("form-grid").appendTo(element);

		  var editMode : hrt.tools.Gizmo.EditMode = @:privateAccess editor.gizmo.editMode;

		var ide = hide.Ide.inst;
		  for (k => v in ide.show3DIconsCategory) {
				var input = new Element('<input type="checkbox" name="snap" id="$k" value="$k"/>');
				if (v)
					 input.get(0).toggleAttribute("checked", true);
				input.change((e) -> {
				var val = !ide.show3DIconsCategory.get(k);
				ide.show3DIconsCategory.set(k, val);
				js.Browser.window.localStorage.setItem(hrt.impl.EditorTools.iconVisibilityKey(k), val ? "true" : "false");
				});
				form_div.append(input);
				form_div.append(new Element('<label for="$k" class="left">$k</label>'));
		  }
	 }
}

class HelpPopup extends hide.comp.Popup {
	var editor : SceneEditor;

	public function new(?parent : Element, editor: SceneEditor, ?shortcuts: Array<{name:String, shortcut:String}>) {
		  super(parent);
		  this.editor = editor;

		  element.append(new Element("<p>Shortcuts</p>"));
		  element.addClass("settings-popup");
		  element.css("max-width", "300px");

		var form_div = new Element("<div>").addClass("form-grid").appendTo(element);

		if (shortcuts != null) {
			for (shortcut in shortcuts) {
				form_div.append(new Element('<label>${shortcut.name}</label><span>${shortcut.shortcut}</span>'));
			}

			return;
		}

		var categories = editor.view.keys.sortDocCategories(editor.view.config);
		for (cat => sc in categories) {
			if (cat == "none")
				continue;
			form_div.append(new Element('<p style="grid-column: 1 / -1">$cat</p>'));
			for (s in sc) {
				form_div.append(new Element('<label>${s.name}</label><span>${s.shortcut}</span>'));
			}
		}
	}
}

class RenderPropsPopup extends Popup {
	var editor:SceneEditor;
	var view: hide.view.FileView;

	public function new(?parent:Element, view:hide.view.FileView, editor:SceneEditor, isSearchable = false, canChangeCurrRp = false) {
		super(parent, isSearchable);
		this.editor = editor;
		this.view = view;

		element.addClass("settings-popup");
		element.css("max-width", "300px");

		var form_div = new Element("<div>").addClass("form-grid").appendTo(element);
		var renderProps = @:privateAccess editor.previousSceneRenderProps;

		var fullPath = [];

		if (renderProps != null && !canChangeCurrRp) {
			var path = renderProps.getAbsPath(false, true);
			var renderPropsSource = StringTools.replace(path, ".", "<wbr>.<wbr>");
			form_div.append(new Element('<p>A render props (<code>$renderPropsSource</code>) already exists in the scene.</p>'));
			return;
		}

		// Render props edition parameter for prefab, fx and model view
		var tmpView : Dynamic = cast Std.downcast(view, hide.view.Prefab);
		if (tmpView == null)
			tmpView = cast Std.downcast(view, hide.view.Model);
		if (tmpView == null)
			tmpView = cast Std.downcast(view, hide.view.FXEditor);

		if (tmpView != null) {
			var rpEditionEl = new Element('<div><input type="checkbox" id="cb-rp-edition"/><label>Edit render props</label></div>').insertBefore(element.children().first());
			var cb = rpEditionEl.find('input');
			cb.prop('checked', Ide.inst.currentConfig.get("sceneeditor.renderprops.edit", false));
			cb.on('change', function(){
				var v = cb.prop('checked');
				Ide.inst.currentConfig.set("sceneeditor.renderprops.edit", v);
				tmpView.setRenderPropsEditionVisibility(v);

				@:privateAccess
				if (editor.renderPropsRoot != null) {
					editor.removeInstance(editor.renderPropsRoot);

					// clear selection
					editor.selectElements([]);
					editor.renderPropsRoot = null;
					editor.queueRefreshRenderProps();
				}
			});

			rpEditionEl.find('label').css({ 'padding-left' : '8px' });
			rpEditionEl.css({ 'padding-bottom' : '5px' });
		}

		var renderProps = view.config.getLocal("scene.renderProps");

		if (renderProps is String) {
			var s_renderProps:String = cast renderProps;

			var input = new Element('<input type="radio" name="renderProps" id="${s_renderProps}" value="${s_renderProps}"/>');
			input.get(0).toggleAttribute("checked", true);

			form_div.append(input);
				form_div.append(new Element('<label for="${s_renderProps}" class="left">${s_renderProps}</label>'));
			return;
		}

		if (renderProps is Array) {
			var a_renderProps = cast (renderProps, Array<Dynamic>);
			var selectedRenderProps = editor.view.getDisplayState("renderProps");

			for (idx in 0...a_renderProps.length) {
				var rp = a_renderProps[idx];
				var input = new Element('<input type="radio" name="renderProps" id="${rp.name}" value="${rp.name}"/>');

				var isDefaultRenderProp = selectedRenderProps == null && idx == 0;
				var isSelectedRenderProp = selectedRenderProps != null && rp.value == selectedRenderProps.value;
				if (isDefaultRenderProp || isSelectedRenderProp)
					input.get(0).toggleAttribute("checked", true);

				input.change((e) -> {
					editor.view.saveDisplayState("renderProps", rp);
					@:privateAccess editor.queueRefreshRenderProps();
				});

				form_div.append(input);
				form_div.append(new Element('<label for="${rp.name}" class="left">${rp.name}</label>'));
			}
			return;
		}

		form_div.append(new Element("<p>No render props detected in .json file.</p>"));
	}

	override function onSearchChanged(searchBar:Element) {
		var search = searchBar.val();
		var form_div = element.find(".form-grid");

		form_div.find("label").remove();
		form_div.find('input[type=radio]').remove();

		var renderProps = view.config.getLocal("scene.renderProps");
		if (renderProps is Array) {
			var a_renderProps = cast (renderProps, Array<Dynamic>);
			var selectedRenderProps = editor.view.getDisplayState("renderProps");

			for (idx in 0...a_renderProps.length) {
				var rp = a_renderProps[idx];

				if (!StringTools.contains(rp.name.toLowerCase(), search.toLowerCase()))
					continue;

				var input = new Element('<input type="radio" name="renderProps" id="${rp.name}" value="${rp.name}"/>');

				var isDefaultRenderProp = selectedRenderProps == null && idx == 0;
				var isSelectedRenderProp = selectedRenderProps != null && rp.value == selectedRenderProps.value;
				if (isDefaultRenderProp || isSelectedRenderProp)
					input.get(0).toggleAttribute("checked", true);

				input.change((e) -> {
					editor.view.saveDisplayState("renderProps", rp);
					editor.refreshScene();
				});

				form_div.append(input);
				form_div.append(new Element('<label for="${rp.name}" class="left">${rp.name}</label>'));
			}
			return;
		}
	}
}

@:access(hide.comp.SceneEditor)
class CustomEditor {

	 var ide(get, never) : hide.Ide;
	function get_ide() { return editor.ide; }
	 var editor : SceneEditor;

	var element : hide.Element;

	public function new( editor : SceneEditor ) {
		this.editor = editor;
	}

	 public function setElementSelected( p : hrt.prefab.Prefab, b : Bool ) {
		return true;
	 }

	public function update( dt : Float ) {

	}

	function iterPrefabsUntil( p : hrt.prefab.Prefab, fct : hrt.prefab.Prefab -> Bool, maxDepth = -1 ) {
		var queue : Array<hrt.prefab.Prefab> = [p];
		var cDepth = 0;
		while( queue.length > 0 ) {
			if( maxDepth >= 0 && cDepth > maxDepth )
				return null;
			var prefab = queue.shift();
			if( prefab == null ) {
				cDepth++;
				continue;
			}
			if( fct(prefab) )
				return prefab;
			for( p in prefab.children ) {
				queue.push(p);
			}
			var ref = Std.downcast(prefab, hrt.prefab.Reference);
			if( ref != null && ref.refInstance != null ) {
				queue.push(ref.refInstance);
			}
			queue.push(null);
		}
		return null;
	}

	function refresh( ?callb: Void->Void ) {
		editor.queueRebuild(editor.sceneData);
		editor.queueRebuildCallback(callb);
		//editor.refresh(Full, callb);
	}

	function show( elt : hide.Element ) {
		element = new hide.Element('<div class="custom-editor"></div>');
		editor.scene.element.append(element);
		elt.appendTo(element);
	}

	function hide() {
		if( element != null )
			element.remove();
	}

}

enum Tree {
	SceneTree;
	RenderPropsTree;
	All;
}

class SceneEditor {

	public var sceneTree : FancyTree<PrefabElement>;
	public var renderPropsTree : FancyTree<PrefabElement>; // Used to display render props edition.

	public var scene : hide.comp.Scene;
	public var properties : hide.comp.PropsEditor;

	public var curEdit(default, null) : SceneEditorContext;
	public var snapToGround = false;

	public var snapToggle = false;
	public var snapMoveStep = 1.0;
	public var snapRotateStep = 15.0;
	public var snapScaleStep = 1.0;
	public var snapForceOnGrid = false;

	public var localTransform = true;
	public var selfOnlyTransform = false;
	public var cameraController : CameraControllerBase;
	public var cameraController2D : hide.view.l3d.CameraController2D;
	public var editorDisplay(default,set) : Bool;
	public var camera2D(default,set) : Bool = false;
	public var objectAreSelectable = true;
	public var renderPropsRoot : Reference;
	public var previousSceneRenderProps : hrt.prefab.RenderProps;
	var updates : Array<Float -> Void> = [];

	var showGizmo = true;
	var gizmo : hrt.tools.Gizmo;
	var gizmo2d : hide.view.l3d.Gizmo2D;
	var basis : h3d.scene.Object;
	public var showBasis = false;
	static var customPivot : CustomPivot;
	var interactives : Map<PrefabElement, h3d.scene.Interactive> = [];
	var interactives2d : Map<PrefabElement, h2d.Interactive> = [];
	public var ide : hide.Ide;
	public var event(default, null) : hxd.WaitEvent;
	var hideList : Map<PrefabElement, Bool> = new Map();
	public var selectedPrefabs : Array<PrefabElement> = [];

	public var guide2d : h2d.Object = null;
	public var grid2d : h2d.Graphics = null;
	public var root2d : h2d.Object = null;
	public var root3d : h3d.scene.Object = null;

	public var showOverlays : Bool = true;
	var grid : h3d.scene.Graphics;
	public var gridStep : Float = 0.;
	public var gridSize : Int;
	public var showGrid = false;

	var currentRenderProps: hrt.prefab.RenderProps;

	var statusText : h2d.Text;
	var ready = false;
	var readyDelayed : Array<() -> Void> = [];

	function getRootObjects3d() : Array<Object> {
		var arr = [];
		for (e in selectedPrefabs) {
			var loc = e.getLocal3d();
			if (loc != null)
				arr.push(loc);
		}
		return arr;
	}

	function getRootObjects2d() : Array<h2d.Object> {
		var arr = [];
		for (e in selectedPrefabs) {
			var loc = e.getLocal2d();
			if (loc != null)
				arr.push(loc);
		}
		return arr;
	}

	var undo(get, null):hide.ui.UndoHistory;
	function get_undo() { return view.undo; }

	public var view(default, null) : hide.view.FileView;
	var sceneData : PrefabElement;

	var customEditor : CustomEditor;

	var ruler : RulerTool;

	public var lastFocusObjects : Array<Object> = [];


	// Called when the sceneEditor scene has finished loading
	// Use it to call setPrefab() to set the content of the scene
	dynamic public function onSceneReady() {

	}

	public function new(view) {
		ready = false;
		ide = hide.Ide.inst;
		this.view = view;

		event = new hxd.WaitEvent();

		var propsEl = new Element('<div class="props"></div>');
		properties = new hide.comp.PropsEditor(undo,null,propsEl);
		properties.onRefresh = refreshProps;
		properties.saveDisplayKey = view.saveDisplayKey + "/properties";

		sceneTree = buildTree(SceneTree);
		renderPropsTree = buildTree(RenderPropsTree);

		var sceneEl = new Element('<div class="heaps-scene"></div>');
		scene = new hide.comp.Scene(view.config, null, sceneEl);
		scene.editor = this;
		scene.onReady = onSceneReadyInternal;
		scene.onResize = function() {
			if( cameraController2D != null ) cameraController2D.toTarget();
			onResize();
		};

		hide.tools.DragAndDrop.makeDropTarget(scene.element.get(0), onDropEvent);

		scene.element.get(0).addEventListener("blur", (e) -> {
			scene.sevents.stopCapture();
		});

		scene.element.get(0).addEventListener("focus", (e) -> {
			scene.sevents.stopCapture();
		});

		editorDisplay = true;

		view.keys.register("copy", {name: "Copy", category: "Edit"}, onCopy);
		view.keys.register("paste", {name: "Paste", category: "Edit"}, onPaste);
		view.keys.register("cancel", {name: "De-select", category: "Scene"}, deselect);
		view.keys.register("selectAll", {name: "Select All", category: "Scene"}, selectAll);
		view.keys.register("selectInvert", {name: "Invert Selection", category: "Scene"}, selectInvert);

		view.keys.register("duplicate", {name: "Duplicate", category: "Scene"}, duplicate.bind(true));
		view.keys.register("duplicateInPlace", {name: "Duplicate in place", category: "Scene"}, duplicate.bind(false));
		view.keys.register("debugSceneRefresh", {name: "Refresh debug scene", category: "Scene"}, () -> {ide.quickMessage("Debug : rebuild(sceneData)"); queueRebuild(sceneData);});
		view.keys.register("debugSelectionRefresh", {name: "Refresh debug Selection", category: "Scene"}, () -> {ide.quickMessage("Debug : rebuild(selectedPrefabs)"); for (s in selectedPrefabs) queueRebuild(s);});

		view.keys.register("group", {name: "Group Selection", category: "Scene"}, groupSelection);
		view.keys.register("delete", {name: "Delete", category: "Scene"}, () -> deleteElements(selectedPrefabs));

		view.keys.register("sceneeditor.focus", {name: "Focus Selection", category: "Scene"}, function() { focusSelection(); });
		view.keys.register("sceneeditor.lasso", {name: "Lasso Select", category: "Scene"}, startLassoSelect);
		view.keys.register("sceneeditor.hide", {name: "Hide Selection", category: "Scene"}, function() {
			if (selectedPrefabs.length > 0) {
				var isHidden = isHidden(selectedPrefabs[0]);
				setVisible(selectedPrefabs, isHidden);
			}
		});
		view.keys.register("sceneeditor.isolate", {name: "Isolate", category: "Scene"}, function() {	isolate(selectedPrefabs); });
		view.keys.register("sceneeditor.showAll", {name: "Show all", category: "Scene"}, function() {	setVisible(selectedPrefabs, true); });
		view.keys.register("sceneeditor.selectParent", {name: "Select Parent", category: "Scene"}, function() {
			if(selectedPrefabs.length > 0) {
				var p = selectedPrefabs[0].parent;
				if( p != null && p != sceneData ) selectElements([p]);
			}
		});
		view.keys.register("sceneeditor.reparent", {name: "Reparent", category: "Scene"}, function() {
			if(selectedPrefabs.length > 1) {
				var children = selectedPrefabs.copy();
				var parent = children.pop();
				reparentElement(children, parent, 0);
			}
		});
		view.keys.register("sceneeditor.editPivot", {name: "Edit Pivot", category: "Scene"}, editPivot);
		view.keys.register("sceneeditor.gatherToMouse", {name: "Gather to mouse", category: "Scene"}, gatherToMouse);
		view.keys.register("sceneeditor.radialViewModes", {name: "Radial view modes", category: "Scene"}, function() {
			var renderer = Std.downcast(@:privateAccess scene.s3d.renderer, h3d.scene.pbr.Renderer);
			var shader = @:privateAccess renderer.slides.shader;
			hide.comp.RadialMenu.createFromPoint(ide.mouseX, ide.mouseY, [
				{ label: "Performance", icon:"adjust", click: () -> { renderer.displayMode = DisplayMode.Performance; } },
				{ label: "Shadows", icon:"adjust", click: () -> { renderer.displayMode = DisplayMode.Debug; shader.mode = DebugMode.Shadow; } },
				{ label: "AO", icon:"adjust", click: () -> { renderer.displayMode = DisplayMode.Debug; shader.mode = DebugMode.AO; } },
				{ label: "Emissive", icon:"adjust", click: () -> { renderer.displayMode = DisplayMode.Debug; shader.mode = DebugMode.Emissive; } },
				{ label: "Metalness", icon:"adjust", click: () -> { renderer.displayMode = DisplayMode.Debug; shader.mode = DebugMode.Metalness; } },
				{ label: "Roughness", icon:"adjust", click: () -> { renderer.displayMode = DisplayMode.Debug; shader.mode = DebugMode.Roughness; } },
				{ label: "Normal", icon:"adjust", click: () -> { renderer.displayMode = DisplayMode.Debug; shader.mode = DebugMode.Normal; } },
				{ label: "Albedo", icon:"adjust", click: () -> { renderer.displayMode = DisplayMode.Debug; shader.mode = DebugMode.Albedo; } },
				{ label: "Full", icon:"adjust", click: () -> { renderer.displayMode = DisplayMode.Debug; shader.mode = DebugMode.Full; } },
				{ label: "LIT", icon:"adjust", click: () -> { renderer.displayMode = DisplayMode.Pbr; } }
			]);
		});

		var customEditorProps = @:privateAccess ide.config.current.get("customEditor");
		if( customEditorProps != null ) {
			var cl = try js.Lib.eval(customEditorProps) catch( e : Dynamic ) null;
			if( cl == null  ) {
				ide.error(customEditorProps+" could not be found");
				return;
			}
			customEditor = Type.createInstance(cl,[this]);
		}
	}

	public function toggleRuler(?force: Bool) {
		var enable : Bool = force ?? (ruler == null);
		if (scene.s3d != null) {
			if (ruler != null)
			{
				ruler.dispose();
				ruler = null;
			}

			if (enable) {
				ruler = new RulerTool(this);
			}
		}
	}

	public function setViewportOverlaysVisibility(visible: Bool) {
		ide.currentConfig.set("sceneeditor.showViewportOverlays", visible);
		updateViewportOverlays();
	}

	function getOrInitConfig(key:String, def:Dynamic) : Dynamic {
		var v = ide.currentConfig.get(key);
		if (v == null) {
			ide.currentConfig.set(key, def);
			return def;
		}
		return v;
	}
	public function updateViewportOverlays() {
		showOverlays = getOrInitConfig("sceneeditor.showViewportOverlays", true);


		updateGrid();
		updateBasis();
		updateGizmoVisibility();
		updateOutlineVisibility();
		updateOtherGuidesVisibility();
		updateJointsVisibility();
		updateCollidersVisibility();
		updateIconsVisibility();
		updateStatusTextVisibility();
		updateWireframe();
		updateBackgroundColor();
	}

	public function updateBackgroundColor() {
		var color = getOrInitConfig("sceneeditor.backgroundColor", 0x333333);
		scene.engine.backgroundColor = color;
		updateGrid();
	}

	public function updateStatusTextVisibility() {
		statusText.visible = getOrInitConfig("sceneeditor.sceneInformationToggle", false) && showOverlays;
	}

	public function updateWireframe() {
		var visible = getOrInitConfig("sceneeditor.wireframeToggle", false) && showOverlays;
		setWireframe(visible);
	}

	public function updateJointsVisibility() {
		var visible = getOrInitConfig("sceneeditor.jointsToggle", false) && showOverlays;
		setJoints(visible, null);
	}

	public function updateCollidersVisibility() {
		var visible = getOrInitConfig("sceneeditor.colliderToggle", false) && showOverlays;
		setCollider(visible);
	}

	public function updateGizmoVisibility() {
		if (gizmo == null)
			return;

		moveGizmoToSelection();
	}

	public function updateIconsVisibility() {
		var visible = getOrInitConfig("sceneeditor.iconVisibility", true) && showOverlays;
		ide.show3DIcons = visible;
	}

	public function updateOtherGuidesVisibility() {
		if (scene?.s3d?.renderer == null)
			return;

		var show = showOverlays && getOrInitConfig("sceneeditor.showOtherGuides", true);
		scene.s3d.renderer.showEditorGuides = show;
	}

	public function updateOutlineVisibility() {
		if (scene?.s3d?.renderer == null)
			return;

		var show = showOverlays && getOrInitConfig("sceneeditor.showOutlines", true);
		scene.s3d.renderer.showEditorOutlines = show;
	}

	public function delayReady(callback: () -> Void) {
		if (ready) {
			callback();
		}
		else {
			readyDelayed.push(callback);
		}
	}

	public function updateGrid() {
		if(grid != null) {
			grid.remove();
			grid = null;
		}

		showGrid = getOrInitConfig("sceneeditor.gridToggle", false);
		if(!showGrid || !showOverlays || camera2D)
			return;

		grid = new h3d.scene.Graphics(scene.s3d);
		grid.scale(1);
		grid.material.mainPass.setPassName("overlay");

		  if (snapToggle) {
	 		gridStep = snapMoveStep;
		  }
		  else {
				gridStep = ide.currentConfig.get("sceneeditor.gridStep");
		  }
		gridSize = ide.currentConfig.get("sceneeditor.gridSize");

		var col = h3d.Vector.fromColor(scene?.engine?.backgroundColor ?? 0);
		var hsl = col.toColorHSL();

		  var mov = 0.1;

		  if (snapToggle) {
				mov = 0.2;
				hsl.y += (1.0-hsl.y) * 0.2;
		  }
		if(hsl.z > 0.5) hsl.z -= mov;
		else hsl.z += mov;

		col.makeColor(hsl.x, hsl.y, hsl.z);

		grid.lineStyle(1.0, col.toColor(), 1.0);
		for(i in 0...(hxd.Math.floor(gridSize / gridStep) + 1)) {
			grid.moveTo(i * gridStep, 0, 0);
			grid.lineTo(i * gridStep, gridSize, 0);

			grid.moveTo(0, i * gridStep, 0);
			grid.lineTo(gridSize, i * gridStep, 0);
		}
		grid.lineStyle(0);
		grid.setPosition(-1 * gridSize / 2, -1 * gridSize / 2, 0);
	}

	public function createGrid(origin : Vector, normal : h3d.Vector, gridSize : Float, gridStep : Float, color : Vector) : h3d.scene.Object {
		var grid = new h3d.scene.Graphics(scene.s3d);
		grid.scale(1);
		grid.material.mainPass.setPassName("overlay");

		var hsl = color.toColorHSL();

		  var mov = 0.1;

		  if (snapToggle) {
				mov = 0.2;
				hsl.y += (1.0-hsl.y) * 0.2;
		  }
		if(hsl.z > 0.5) hsl.z -= mov;
		else hsl.z += mov;

		color.makeColor(hsl.x, hsl.y, hsl.z);

		grid.lineStyle(1.0, color.toColor(), 1.0);
		var start = -1 * gridSize / 2;
		for(i in 0...(hxd.Math.floor(gridSize / gridStep) + 1)) {
			grid.moveTo(0, start + (i * gridStep), start);
			grid.lineTo(0, start + (i * gridStep), start + gridSize);

			grid.moveTo(0, start, start + (i * gridStep));
			grid.lineTo(0, start + gridSize, start + (i * gridStep));
		}

		grid.lineStyle(0);

		grid.setPosition(origin.x, origin.y, origin.z);
		grid.setDirection(normal * -1.0, new h3d.Vector(0, 0, 1));

		return grid;
	}

	static public function splitCentainesFloat(v: Float, precision: Int) {
		var str = Std.string(hxd.Math.round(v * hxd.Math.pow(10, precision)));
		var endStr = "";
		var reset = 0;
		for (char in 0...str.length) {
			if (char == precision) {
				endStr = "." + endStr;
				reset = char + 1;
			}

			if ((char - reset) % 3 == 0 && (char - reset) > 0) {
				endStr = " " + endStr;
			}
			endStr = str.charAt(str.length - char - 1) + endStr;
		}
		return endStr;
	}

	static public function splitCentaines(v: Int) {
		var str = Std.string(v);
		var endStr = "";
		for (char in 0...str.length) {
			if (char % 3 == 0 && char > 0) {
				endStr = " " + endStr;
			}
			endStr = str.charAt(str.length - char - 1) + endStr;
		}
		return endStr;
	}

	function updateStats() {
		if( statusText.visible ) {
			var memStats = scene.engine.mem.stats();


			@:privateAccess
			var lines : Array<String> = [
				'Scene objects: ${splitCentaines(scene.s3d.getObjectsCount())}',
				'Interactives: ' + splitCentaines(interactives.count()),
				'Interactives 2d: ' + splitCentaines(interactives2d.count()),
				'Triangles: ${splitCentaines(Std.int(scene.engine.drawTriangles))}',
				'Buffers: ${splitCentaines(memStats.bufferCount)}',
				'Textures: ${splitCentaines(memStats.textureCount)}',
				'FPS: ${Math.round(scene.engine.realFps)}',
				'Draw Calls: ${splitCentaines(scene.engine.drawCalls)}',
				'V Ram: ${Std.int(memStats.totalMemory / (1024 * 1024))} Mb',
			];
			statusText.text = lines.join("\n");
		}
		haxe.Timer.delay(function() event.wait(0.5, updateStats), 0);
	}

	public function getSnapStatus() : Bool {
		var ctrl = K.isDown(K.CTRL);
		return (snapToggle && !ctrl) || (!snapToggle && ctrl);
	};

	public function snap(value: Float, step:Float) : Float {
		if (step > 0.0 && getSnapStatus())
			value = hxd.Math.round(value / step) * step;
		return value;
	}

	public function gizmoSnap(value: Float, mode: hrt.tools.Gizmo.EditMode) : Float {
		switch(mode) {
			case Translation:
				return snap(value, snapMoveStep);
			case Rotation:
				return snap(value, snapRotateStep);
			case Scaling:
				return snap(value, snapScaleStep);
		}
		return value;
	}

	public function dispose() {
		scene.dispose();
		ruler?.dispose();
		ruler = null;
		clearWatches();
	}

	function set_camera2D(b) {
		if( cameraController != null ) cameraController.visible = !b;
		if( cameraController2D != null ) cameraController2D.visible = b;
		return camera2D = b;
	}

	public function onResourceChanged(lib : hxd.fmt.hmd.Library) {

		var models = sceneData.findAll(PrefabElement);
		var toRebuild : Array<PrefabElement> = [];
		for(m in models) {
			if(Ide.inst.getPath(m.source) == Reflect.getProperty(lib.resource.entry, "originalPath")) {
				if (toRebuild.indexOf(m) < 0) {
					toRebuild.push(m);
				}
			}
		}

		for(m in toRebuild) {
			removeInstance(m);
			makePrefab(m);
		}
	}

	public dynamic function onResize() {
	}

	function set_editorDisplay(v) {
		return editorDisplay = v;
	}

	public function getSelection() {
		return selectedPrefabs != null ? selectedPrefabs : [];
	}

	function makeCamController() : CameraControllerBase {
		var c = new hide.view.CameraController.FlightController(scene.s3d, this);
		return c;
	}

	public function setFullScreen( b : Bool ) {
		view.fullScreen = b;
		if( b ) {
			view.element.find(".tabs").hide();
		} else {
			view.element.find(".tabs").show();
		}
		var pview = Std.downcast(view, hide.view.Prefab);
		if(pview != null) {
			if(b) pview.hideColumns();
			else pview.showColumns();
		}
	}

	function makeCamController2D() {
		return new hide.view.l3d.CameraController2D(root2d);
	}

	function focusSelection() {
		var arr = [];
		for (pref in sceneTree.getSelectedItems()) {
			var local3d = pref.getLocal3d();
			var mat = Std.downcast(pref, hrt.prefab.Material);
			if (mat != null && @:privateAccess mat.previewSphere != null)
				local3d = @:privateAccess mat.previewSphere;
			if (local3d != null) {
				arr.push(local3d);
				var isRevealed = true;
				var p = pref.parent;
				while (p != null) {
					var data = @:privateAccess sceneTree.itemMap.get(p);
					if (data == null)
						break;

					isRevealed = isRevealed && @:privateAccess sceneTree.isOpen(data);
					p = p.parent;
				}

				if (!isRevealed) {
					var parent = pref.parent;
					while(parent != null) {
						sceneTree.openItem(parent, true);
						parent = parent.parent;
					}
				}
			}
		}

		focusObjects(arr);
	}

	public function focusObjects(objs : Array<Object>) {
		var focusChanged = false;
		for (o in objs) {
			if (!lastFocusObjects.contains(o)) {
				focusChanged = true;
				break;
			}
		}

		if(objs.length > 0) {
			var bnds = new h3d.col.Bounds();
			var centroid = new h3d.Vector();
			for(obj in objs) {
				centroid = centroid.add(obj.getAbsPos().getPosition());
				bnds.add(obj.getBounds());
			}
			if(!bnds.isEmpty()) {
				var s = bnds.toSphere();
				var r = focusChanged ? null : s.r * 4.0;
				cameraController.set(r, null, null, s.getCenter());
			}
			else {
				centroid.scale(1.0 / objs.length);
				cameraController.set(centroid.toPoint());
			}
		}
		lastFocusObjects = objs;
	}

	function getAvailableTags() : Array<TagInfo>{
		return null;
	}

	public function getTag(p: PrefabElement) : TagInfo {
		if(p.props != null) {
			var tagId = Reflect.field(p.props, "tag");
			if(tagId != null) {
				var tags = getAvailableTags();
				if(tags != null)
					return Lambda.find(tags, t -> t.id == tagId);
			}
		}
		return null;
	}

	public function setTags(prefabs: Array<PrefabElement>, tag: String) {
		var oldValues = [for (prefab in prefabs) (prefab.props:Dynamic)?.tag];

		function exec(isUndo : Bool) {
			for (i => prefab in prefabs) {
				prefab.props ??= {};
				if (!isUndo) {
					(prefab.props:Dynamic).tag = tag;
				}
				else {
					(prefab.props:Dynamic).tag = oldValues[i];
				}
				applySceneStyle(prefab);
				refreshTreeStyle(prefab, All);
			}
		}
		exec(false);
		undo.change(Custom(exec));
	}

	function splitMenu(menu : Array<hide.comp.ContextMenu.MenuItem>, name : String, entries : Array<hide.comp.ContextMenu.MenuItem>, len : Int = 30) {
		entries.sort((a,b) -> Reflect.compare(a.label, b.label));

		var pos = 0;
		while(true) {
			var arr = entries.slice(pos, pos+len);
			if (arr.length == 0) {
				break;
			}
			var label = name;
			var firstChar = arr[0].label.charAt(0);
			var endChar = (entries.length < pos+len) ? "Z" : arr[arr.length-1].label.charAt(0);

			var label = name + " " + firstChar + "-" + endChar;
			if (pos == 0 && arr.length < len) {
				label = name;
			}
			menu.push({
				label: label,
				menu: arr
			});

			pos += len;
		}
	}

	function getTagMenu(prefabs: Array<PrefabElement>) : Array<hide.comp.ContextMenu.MenuItem> {
		var tags = getAvailableTags();
		if(tags == null) return null;
		tags = tags.copy();
		var ret = [];
		var noTag = {id: "-- none --", color: "rgba(0,0,0,0)"};
		tags.unshift(noTag);
		for(tag in tags) {
			var style = 'background-color: ${tag.color};';
			var checked = false;
			for (p in prefabs) {
				if (getTag(p) == tag)
					checked = true;
			}
			ret.push({
				label: '<span class="tag-disp-expand"><span class="tag-disp" style="$style">${tag.id}</span></span>',
				click: function () {
					if (tag == noTag) {
						setTags(prefabs, null);
					} else {
						setTags(prefabs, tag.id);
					}
				},
				stayOpen: true,
				radio: () -> {
					for (p in prefabs) {
						if ((p.props:Dynamic)?.tag == tag.id || ((p.props:Dynamic)?.tag == null && tag == noTag))
							return true;
					}
					return false;
				}
			});
		}
		return ret;
	}

	public function switchCamController(camClass : Class<CameraControllerBase>) {
		// Temp save all cam parameters before re-applying them on the new instance
		var settings = getCameraControllerSettings();

		if (cameraController != null)
			cameraController.remove();

		cameraController = Type.createInstance(camClass, [scene.s3d, this]);
		setupCameraEvents(cameraController);

		if (settings != null) {
			for (i in 0...CameraControllerEditor.controllersClasses.length) {
				if (CameraControllerEditor.controllersClasses[i].cl == camClass) {
					Reflect.setProperty(settings, "camTypeIndex", i);
					break;
				}
			}

			applyCameraControllerSettings(settings);
		}
	}

	function getCameraControllerSettings() : Dynamic {
		var cam = scene.s3d.camera;
		if (cam == null)
			return null;

		var settings = {
			x : cam.pos.x,
			y : cam.pos.y,
			z : cam.pos.z,
			tx : cam.target.x,
			ty : cam.target.y,
			tz : cam.target.z,
			ux : cam.up.x,
			uy : cam.up.y,
			uz : cam.up.z
		};

		for (i in 0...CameraControllerEditor.controllersClasses.length) {
			if (CameraControllerEditor.controllersClasses[i].cl == Type.getClass(cameraController)) {
				Reflect.setProperty(settings, "camTypeIndex", i);
				break;
			}
		}

		cameraController.saveSettings(settings);

		return settings;
	}

	function applyCameraControllerSettings(settings : Dynamic) {
		if (!camera2D)
			resetCamera();

		if (settings == null)
			return;

		var id = Std.parseInt(settings.camTypeIndex) ?? 0;
		  var newClass = CameraControllerEditor.controllersClasses[id];
		  if (Type.getClass(cameraController) != newClass.cl)
				switchCamController(newClass.cl);

		scene.s3d.camera.pos.set(settings.x, settings.y, settings.z);
		scene.s3d.camera.target.set(settings.tx, settings.ty, settings.tz);

		if (settings.ux == null) {
			scene.s3d.camera.up.set(0,0,1);
		}
		else {
			scene.s3d.camera.up.set(settings.ux,settings.uy,settings.uz);
		}

		cameraController.loadSettings(settings);
		cameraController.loadFromCamera();
	}

	public function loadCam3D() {
		if (cameraController == null)
			cameraController = Type.createInstance(CamController, [scene.s3d, this]);

		setupCameraEvents(cameraController);

		var settings = @:privateAccess view.getDisplayState("Camera");
		var isGlobalSettings = Ide.inst.currentConfig.get("sceneeditor.camera.isglobalsettings", false);
		if (isGlobalSettings) {
			settings = haxe.Json.parse(js.Browser.window.localStorage.getItem("Global/Camera"));
		}

		applyCameraControllerSettings(settings);
	}

	function setupCameraEvents(cameraController: Dynamic) {
		cameraController.onClick = function(e) {
			switch( e.button ) {
			case K.MOUSE_RIGHT:
				selectNewObject(e);
			}
		};

		var startDrag : Array<Float> = null;
		var curDrag = null;
		var dragBtn = -1;
		var lastPush : Array<Float> = null;
		var delaySelection : Bool = true;

		function doPickSelect(allowCycle: Bool, ?elts: Array<{d: Float, prefab: PrefabElement}>) {
			allowCycle = allowCycle && Ide.inst.ideConfig.sceneEditorClickCycleObjects;
			elts ??= getAllPrefabsUnderMouse();
			if (elts.length > 0) {
				if(K.isDown(K.SHIFT)) {
					var elt = elts[0].prefab;
					if (selectedPrefabs.length > 0 && elts.find((e) -> e.prefab == selectedPrefabs[0]) != null) {
						elt = selectedPrefabs[0];
					}
					if(Type.getClass(elt.parent) == hrt.prefab.Object3D)
						selectElements([elt.parent]);
					else
						selectElements(elt.parent.children);

				}
				else if (K.isDown(K.CTRL)) {
					var sel = selectedPrefabs.copy();
					sel.pushUnique(elts[0].prefab);
					selectElements(sel);
				}
				else {
					if (selectedPrefabs.length != 1 || !allowCycle) {
						selectElements([elts[0].prefab]);
					} else {
						var found = false;
						for (index => elt in elts) {
							if (elt.prefab == selectedPrefabs[0]) {
								selectElements([elts[(index + 1) % elts.length].prefab]);
								found = true;
								break;
							}
						}

						if (!found) {
							selectElements([elts[0].prefab]);
						}
					}
				}
			} else {
				selectElements([]);
			}
		}

		function customEventHandler(e: hxd.Event) {
			switch(e.kind) {
			case ERelease:
				if( e.button == K.MOUSE_MIDDLE ) return;
				if (e.button == K.MOUSE_LEFT && startDrag != null) {
					if (delaySelection)
						doPickSelect(true);
				}
				startDrag = null;
				curDrag = null;
				dragBtn = -1;
				delaySelection = true;
				if (e.button == K.MOUSE_LEFT) {
					scene.sevents.stopCapture();
					e.propagate = false;
				}
			case EMove:
				if(startDrag != null && hxd.Math.distance(startDrag[0] - scene.s2d.mouseX, startDrag[1] - scene.s2d.mouseY) > 5 ) {
					if(dragBtn == K.MOUSE_LEFT && selectedPrefabs.length > 0) {
						if( selectedPrefabs[0].to(Object3D) != null ) {
							moveGizmoToSelection();
							gizmo.startMove(MoveXY);
						}
						if( selectedPrefabs[0].to(Object2D) != null ) {
							moveGizmoToSelection();
							gizmo2d.startMove(Pan);
						}
					}
					e.propagate = false;
					startDrag = null;
				}
			case EPush:
				if( e.button == K.MOUSE_MIDDLE ) return;
				delaySelection = true;

				// try to reset capture if stopCapture didn't fired off
				if (e.button == K.MOUSE_LEFT) {
					scene.sevents.stopCapture();
					e.propagate = false;
				}

				var elts = getAllPrefabsUnderMouse();
				if (elts.length <= 0)
					return;

				var anyElementOrParentSelected = false;
				for (elt in elts) {
					for (selected in selectedPrefabs) {
						var curr = elt.prefab;
						while(curr != null) {
							if (curr == selected) {
								anyElementOrParentSelected = true;
								break;
							}
							curr = curr.parent;
						}
					}
				}

				if (e.button == K.MOUSE_LEFT && (selectedPrefabs.length < 0 || !anyElementOrParentSelected)) {
					doPickSelect(false, elts);
					delaySelection = false;
				}

				startDrag = [scene.s2d.mouseX, scene.s2d.mouseY];
				if( e.button == K.MOUSE_RIGHT )
					lastPush = startDrag;
				dragBtn = e.button;

				// ensure we get onMove even if outside our interactive, allow fast click'n'drag
				if( e.button == K.MOUSE_LEFT ) {
					scene.sevents.startCapture(customEventHandler);
				}
			default:
			}
		}

		cameraController.onCustomEvent = customEventHandler;
	}

	public function saveCam3D() {
		var cam = scene.s3d.camera;
		if (cam == null)
			return;

		var settings = getCameraControllerSettings();
		cameraController.saveSettings(settings);

		var isGlobalSettings = Ide.inst.currentConfig.get("sceneeditor.camera.isglobalsettings", false);
		if (isGlobalSettings) {
			js.Browser.window.localStorage.setItem("Global/Camera", haxe.Json.stringify(settings));
		}
		else {
			@:privateAccess view.saveDisplayState("Camera", settings);
		}
	}

	function loadSnapSettings() {
		function sanitize(value:Dynamic, def: Dynamic) {
			if (value == null || value == 0.0)
					return def;
			return value;
		}
		@:privateAccess snapMoveStep = sanitize(view.getDisplayState("snapMoveStep"), snapMoveStep);
		@:privateAccess snapRotateStep = sanitize(view.getDisplayState("snapRotateStep"), snapRotateStep);
		@:privateAccess snapScaleStep = sanitize(view.getDisplayState("snapScaleStep"), snapScaleStep);
		@:privateAccess snapForceOnGrid = view.getDisplayState("snapForceOnGrid");
	}

	public function saveSnapSettings() {
		@:privateAccess view.saveDisplayState("snapMoveStep", snapMoveStep);
		@:privateAccess view.saveDisplayState("snapRotateStep", snapRotateStep);
		@:privateAccess view.saveDisplayState("snapScaleStep", snapScaleStep);
		@:privateAccess view.saveDisplayState("snapForceOnGrid", snapForceOnGrid);
	}

	function toggleSnap(?force: Bool) {
		if (force != null)
			snapToggle = force;
		else
			snapToggle = !snapToggle;

		var snap = new Element("#snap").get(0);
		if (snap != null) {
			snap.toggleAttribute("checked", snapToggle);
		}

		updateGrid();
	}

	public function setPrefab(prefab: hrt.prefab.Prefab) {
		sceneData = prefab;
		refreshScene();
	}

	function onSceneReadyInternal() {
		gizmo = new hrt.tools.Gizmo(scene.s3d, scene.s2d);
		view.keys.register("sceneeditor.translationMode", gizmo.translationMode);
		view.keys.register("sceneeditor.rotationMode", gizmo.rotationMode);
		view.keys.register("sceneeditor.scalingMode", gizmo.scalingMode);
		view.keys.register("sceneeditor.switchMode", gizmo.switchMode);

		statusText = new h2d.Text(hxd.res.DefaultFont.get(), scene.s2d);
		statusText.setPosition(5, 5);
		statusText.dropShadow = {
			dx: 1,
			dy: 1,
			color: 0,
			alpha: 0.5
		};
		updateStats();

		gizmo2d = new hide.view.l3d.Gizmo2D();
		scene.s2d.add(gizmo2d, 2); // over local3d

		basis = new h3d.scene.Object(scene.s3d);

		// Note : we create 2 different graphics because
		// 1 graohic can only handle one line style, and
		// we want the forward vector to be thicker so
		// it's easier to recognise
		{
			var fwd = new h3d.scene.Graphics(basis);
			fwd.is3D = false;
			fwd.lineStyle(1.25, 0xFF0000);
			fwd.lineTo(1.0,0.0,0.0);

			var mat = fwd.getMaterials()[0];
			mat.mainPass.depth(false, Always);
			mat.mainPass.setPassName("ui");
			mat.mainPass.blend(SrcAlpha, OneMinusSrcAlpha);
		}

		{
			var otheraxis = new h3d.scene.Graphics(basis);

			otheraxis.lineStyle(.75, 0x00FF00);

			otheraxis.moveTo(0.0,0.0,0.0);
			otheraxis.setColor(0x00FF00);
			otheraxis.lineTo(0.0,2.0,0.0);

			otheraxis.moveTo(0.0,0.0,0.0);
			otheraxis.setColor(0x0000FF);
			otheraxis.lineTo(0.0,0.0,2.0);

			var mat = otheraxis.getMaterials()[0];
			mat.mainPass.depth(false, Always);
			mat.mainPass.setPassName("ui");
			mat.mainPass.blend(SrcAlpha, OneMinusSrcAlpha);
		}

		basis.visible = true;

		loadCam3D();
		loadSnapSettings();

		scene.onUpdate = update;

		ready = true;

		onSceneReady();

		selectElements([], NoHistory);
		this.camera2D = camera2D;

		updateViewportOverlays();

		makeGuide2d();


		for (callback in readyDelayed) {
			callback();
		}
		readyDelayed.empty();
	}

	function checkAllowParent(prefabInf:hrt.prefab.Prefab.PrefabInfo, prefabParent : PrefabElement) : Bool {
		if (prefabInf.inf.allowParent == null)
			if (prefabParent == null || prefabParent.getHideProps().allowChildren == null || (prefabParent.getHideProps().allowChildren != null && prefabParent.getHideProps().allowChildren(prefabInf.prefabClass)))
				return true;
			else return false;

		if (prefabParent == null)
			if (prefabInf.inf.allowParent(sceneData))
				return true;
			else return false;

		if ((prefabParent.getHideProps().allowChildren == null || prefabParent.getHideProps().allowChildren != null && prefabParent.getHideProps().allowChildren(prefabInf.prefabClass))
		&& prefabInf.inf.allowParent(prefabParent))
			return true;
		return false;
	};


	var treeRefreshing = false;
	var queueRefresh : Array<() -> Void> = null;

	function buildTree(targetTree : Tree) : FancyTree<PrefabElement> {
		var isSceneTree = targetTree.match(SceneTree);
		var icons = new Map();
		var iconsConfig = view.config.get("sceneeditor.icons");
		for( f in Reflect.fields(iconsConfig) )
			icons.set(f, Reflect.field(iconsConfig,f));

		var saveDisplayKey = isSceneTree ? view.saveDisplayKey + '/tree' : view.saveDisplayKey + '/renderPropsTree';
		var tree = new FancyTree<hrt.prefab.Prefab>(null, { saveDisplayKey: saveDisplayKey, quickGoto: false });
		tree.getChildren = (p : hrt.prefab.Prefab) -> {
			if (p == null) {
				if (isSceneTree)
					return sceneData == null ? [] : sceneData.children;
				return renderPropsRoot == null ? [] : [renderPropsRoot];
			}

			var ref = Std.downcast(p, Reference);
			var children = (ref != null && (ref.editMode == Edit || ref.editMode == Override)) ? ref.refInstance.children : p.children;

			var props = p.getHideProps();
			if (props != null && props.hideChildren != null)
				return children.filter((p) -> !props.hideChildren(p));
			return children;

		}
		tree.getName = (p : hrt.prefab.Prefab) -> {
			return p.name;
		}
		tree.getUniqueName = (p : hrt.prefab.Prefab) -> {
			var path = p.getUniqueName();
			var parent = p.parent;
			while(parent != null) {
				path += parent.getUniqueName() + "/" + path;
				parent = parent.parent;
			}
			return path;
		}
		tree.getIcon = (p: hrt.prefab.Prefab) -> {
			var icon = p.getHideProps().icon;
			var ct = p.getCdbType();
			if( ct != null && icons.exists(ct) )
				icon = icons.get(ct);
			return '<div class="ico ico-${icon}"></div>';
		}
		tree.onSelectionChanged = (enterKey : Bool) -> {
			if (isSceneTree)
				renderPropsTree.clearSelection();
			else
				sceneTree.clearSelection();
			selectElements(tree.getSelectedItems(), NoTree);
		}
		tree.onDoubleClick = (p : hrt.prefab.Prefab) -> {
			var obj = p.getLocal3d();
			if (obj == null)
				return;
			focusObjects([obj]);
		}
		tree.onNameChange = (p : hrt.prefab.Prefab, newName : String) -> {
			var oldName = p.name;
			p.name = newName;

			// When renaming a material, we want to rename every references in .props files
			// of it, if it is a part of a material library
			var prefabView = Std.downcast(view, hide.view.Prefab);
			var mat = Std.downcast(p, hrt.prefab.Material);
			if (prefabView != null && @:privateAccess prefabView.matLibPath != null && mat != null) {
				// We do not allow several materials with the same name in mat libs
				// since they are referenced by their name
				var matWithNewName = 0;
				for (m in sceneData.flatten(hrt.prefab.Material)) {
					if (m.parent == sceneData.getRoot() && m.name == newName) {
						matWithNewName++;
						if (matWithNewName > 1) {
							Ide.inst.quickError("Materials with same names aren\'t allowed in a material library!");
							return;
						}
					}
				}

				var found = false;
				for (entry in @:privateAccess prefabView.renameMatsHistory) {
					if (entry.prefab == mat) {
						entry.newName = newName;
						found = true;
						break;
					}
				}

				if (!found)
					@:privateAccess prefabView.renameMatsHistory.push({ previousName: oldName, newName: newName, prefab: p });
			}

			undo.change(Field(p, "name", oldName), function() {
				sceneTree.refreshItem(p);
				(cast view:Dynamic).onPrefabChange(p, "name");
				p.updateInstance("name");
			});

			(cast view:Dynamic).onPrefabChange(p, "name");
			p.updateInstance("name");
			sceneTree.refreshItem(p);
		}
		tree.applyStyle = (p : hrt.prefab.Prefab, el : js.html.Element) -> {
			applyTreeStyle(p, targetTree);
		}
		tree.getButtons = (p : hrt.prefab.Prefab) -> {
			var buttons: Array<hide.comp.FancyTree.TreeButton<hrt.prefab.Prefab>> = [];

			buttons.push({
				getIcon: (p: hrt.prefab.Prefab) ->  {
					return p.locked ? '<div class="ico ico-lock"></div>' : '<div class="ico ico-unlock"></div>';
				},
				click: (p: hrt.prefab.Prefab) -> {
					setLock([p], !p.locked);
				},
				forceVisiblity: (p: hrt.prefab.Prefab) -> p.locked,
			});

			buttons.push({
				getIcon: (p: hrt.prefab.Prefab) ->  {
					return !isHidden(p) ? '<div class="ico ico-eye"></div>' : '<div class="ico ico-eye-slash"></div>';
				},
				click: (p: hrt.prefab.Prefab) -> {
					var selection = tree.getSelectedItems();
					setVisible(selection.contains(p) ? selection : [p], isHidden(p));
				},
				forceVisiblity: (p: hrt.prefab.Prefab) -> isHidden(p),
			});

			return buttons;
		}

		tree.dragAndDropInterface =
		{
			onDragStart: function(p: hrt.prefab.Prefab, dragData: hide.tools.DragAndDrop.DragData) : Bool {
				var selection = tree.getSelectedItems();
				if (selection.length <= 0)
					return false;
				dragData.data.set("drag/scenetree", cast selection);
				ide.setData("drag/scenetree", cast selection);
				return true;
			},
			getItemDropFlags: function(target: hrt.prefab.Prefab, dragData: hide.tools.DragAndDrop.DragData) : hide.comp.FancyTree.DropFlags {
				var prefabs : Array<hrt.prefab.Prefab> = cast dragData.data.get("drag/scenetree");
				if (prefabs != null) {
					for (p in prefabs) {
						if (checkAllowParent({prefabClass : Type.getClass(p), inf : p.getHideProps()}, target))
							return (Reorder:hide.comp.FancyTree.DropFlags) | Reparent;
					}
				}

				var files : Array<hide.tools.FileManager.FileEntry> = cast dragData.data.get("drag/filetree");
				if (files != null) {
					for (f in files) {
						var ptype = hrt.prefab.Prefab.getPrefabType(f.relPath);
						var ext = f.relPath.substring(f.relPath.lastIndexOf(".") + 1);

						if (ptype != null) {
							return (Reorder:hide.comp.FancyTree.DropFlags) | Reparent;
						}
						else if (ext == "fbx" || ext == "hmd") {
							var model = new hrt.prefab.Model(null, null);
							if (checkAllowParent({prefabClass : hrt.prefab.Model, inf : model.getHideProps()}, target))
								return (Reorder:hide.comp.FancyTree.DropFlags) | Reparent;
						}
					}
				}

				return Reorder;
			},
			onDrop: function(target: hrt.prefab.Prefab, operation: hide.comp.FancyTree.DropOperation, dragData: hide.tools.DragAndDrop.DragData) : Bool {
				if (target == null)
					target = sceneData;
				var parent = operation.match(hide.comp.FancyTree.DropOperation.Inside) ? target : target?.parent;
				var tChildren = target.parent == null ? target.children : target.parent.children;

				var prefabs : Array<hrt.prefab.Prefab> =  cast ide.popData("drag/scenetree");
				if (prefabs != null) {
					// Avoid moving target onto itelf
					for (prefab in prefabs.copy()) {
						if (target.findParent((p) -> p == prefab) != null) {
							prefabs.remove(prefab);
						}
					}

					var idx = tChildren.indexOf(target);
					if (operation.match(hide.comp.FancyTree.DropOperation.After))
						idx++;
					reparentElement(prefabs, parent, idx);
					refreshTree(targetTree);
					return true;
				}

				var files : Array<hide.tools.FileManager.FileEntry> =  cast ide.popData("drag/filetree");
				if (files != null) {
					var createdPrefab : Array<{ p : hrt.prefab.Prefab, idx: Int }> = [];
					for (f in files) {
						var idx = switch (operation) {
							case hide.comp.FancyTree.DropOperation.Inside:
								parent.children.length;
							case hide.comp.FancyTree.DropOperation.After:
								tChildren.indexOf(target) + 1;
							case hide.comp.FancyTree.DropOperation.Before:
								tChildren.indexOf(target);
						}

						var p = createDroppedElement(f.relPath, parent, dragData.shiftKey);
						if (p == null)
							continue;
						parent.children.remove(p);
						parent.children.insert(idx, p);
						queueRebuild(p);
						createdPrefab.push({ p : p, idx : idx });
					}

					undo.change(Custom((undo) -> {
						if (undo) {
							for (p in createdPrefab) {
								parent.children.remove(p.p);
								p.p.editorRemoveInstanceObjects();
							}
						}
						else {
							for (p in createdPrefab) {
								parent.children.insert(p.idx, p.p);
								queueRebuild(p.p);
							}
						}

						refreshTree(targetTree);
					}));

					refreshTree(targetTree);
					return true;
				}

				return false;
			}
		}
		function ctxMenu(p: hrt.prefab.Prefab, e: js.html.Event) {
			e.preventDefault();
			e.stopPropagation();
			if (p != null && (selectedPrefabs == null || selectedPrefabs.indexOf(p) < 0))
				selectElements([p]);

			var newItems = getNewContextMenu(p);
			var menuItems : Array<hide.comp.ContextMenu.MenuItem> = [
				{ label : "New...", menu : newItems },
			];
			var actionItems : Array<hide.comp.ContextMenu.MenuItem> = [
				{ label : "Rename", enabled : p != null, click : function() { tree.rename(p); }, keys : view.config.get("key.rename") },
				{ label : "Delete", enabled : p != null, click : function() deleteElements(selectedPrefabs), keys : view.config.get("key.delete") },
				{ label : "Duplicate", enabled : p != null, click : duplicate.bind(false), keys : view.config.get("key.duplicateInPlace") },
			];
			var collapseItems : Array<hide.comp.ContextMenu.MenuItem> = [
				{ label : "Collapse", enabled : p != null, click : () -> {
					var curItem = @:privateAccess tree.itemMap.get(p);
					while (curItem.children == null || curItem.children.length <= 0) {
						if (curItem.parent == null)
							break;
						curItem = curItem.parent;
					}
					tree.collapseItem(curItem.item);
				} },
				{ label : "Collapse All", enabled : p != null, click : collapseTree },
			];

			var isObj = p != null && (p.to(Object3D) != null || p.to(Object2D) != null);
			var isRef = isReference(p);

			if( p != null ) {
				menuItems.push({ label : "Enable", checked : p.enabled, stayOpen : true, click : function() setEnabled(selectedPrefabs, !p.enabled) });
				menuItems.push({ label : "Editor only", checked : p.editorOnly, stayOpen : true, click : function() setEditorOnly(selectedPrefabs, !p.editorOnly) });
				menuItems.push({ label : "In game only", checked : p.inGameOnly, stayOpen : true, click : function() setInGameOnly(selectedPrefabs, !p.inGameOnly) });
			}

			if( isObj ) {
				menuItems = menuItems.concat([
					{ label : "Show in editor" , checked : !isHidden(p), stayOpen : true, click : function() setVisible(selectedPrefabs, isHidden(p)), keys : view.config.get("key.sceneeditor.hide") },
					{ label : "Locked", checked : p.locked, stayOpen : true, click : function() {
						setLock(selectedPrefabs, !p.locked);
					} },
					{ label : "Select all", click : selectAll, keys : view.config.get("key.selectAll") },
					{ label : "Select children", enabled : p != null, click : function() selectElements(p.flatten()) },
				]);
				var exportMenu = new Array<hide.comp.ContextMenu.MenuItem>();
				exportMenu.push({ label : "Export (default)", enabled : curEdit != null && canExportSelection(), click : function() exportSelection({forward:"0", forwardSign:"1", up:"2", upSign:"1"}), keys : null });
				exportMenu.push({ label : "Export (-X Forward, Z Up)", enabled : curEdit != null && canExportSelection(), click : function() exportSelection({forward:"0", forwardSign:"-1", up:"2", upSign:"1"}), keys : null });

				actionItems = actionItems.concat([
					{ label : "Isolate", click : function() isolate(selectedPrefabs), keys : view.config.get("key.sceneeditor.isolate") },
					{ label : "Group", enabled : selectedPrefabs != null && canGroupSelection(), click : groupSelection, keys : view.config.get("key.group") },
					{ label : "Reset transform", click : function() resetTransform(selectedPrefabs) },
					{ label : "Export", enabled : curEdit != null && canExportSelection(), menu : exportMenu },
				]);
			}

			if (isMatLib()) {
				var matLibs = scene.listMatLibraries(sceneData.shared.currentPath);

				var menu : Array<hide.comp.ContextMenu.MenuItem> = [];

				for (matLib in matLibs) {
					if (matLib.path == view.state.path) {
						continue;
					}

					menu.push(
					{
						label: matLib.name,
						click: migrateMaterialLibrary.bind(selectedPrefabs, matLib.path),
					});
				}

				if (menu.length > 0) {
					actionItems.push(
						{
							label: "Migrate Material",
							enabled: selectedPrefabs.find((f) -> f.to(hrt.prefab.Material) != null || f.find(hrt.prefab.Material) != null) != null,
							menu: menu,
						}
					);
				}
			}

			if( p != null ) {
				var menu = getTagMenu(selectedPrefabs);
				if(menu != null)
					menuItems.push({ label : "Tag", menu: menu });
			}

			menuItems.push({ isSeparator: true });
			menuItems = menuItems.concat(collapseItems);
			menuItems.push({ isSeparator : true, label : "Actions" });
			menuItems = menuItems.concat(actionItems);

			// Gather custom context menu entries
			{
				var customContextMenus: Array<hide.comp.ContextMenu.MenuItem> = [];
				var uniqueClasses : Map<{}, Bool> = [];

				for (prefab in selectedPrefabs) {
					var currentClass = Type.getClass(prefab);
					while (currentClass != null && uniqueClasses.get(cast currentClass) == null) {
						uniqueClasses.set(cast currentClass, true);
						currentClass = cast Type.getSuperClass(currentClass);
					}
				}

				for (cl => _ in uniqueClasses) {
					var cb = contextMenuExtRegistry.get(cl);
					if (cb != null) {
						var newEntries = cb(selectedPrefabs.filter((f) -> f.to(cast cl) != null));
						customContextMenus = customContextMenus.concat(newEntries);
					}
				}

				if (customContextMenus.length > 0) {
					menuItems.push({ isSeparator : true, label : "Prefabs" });
					menuItems = menuItems.concat(customContextMenus);
				}
			}

			hide.comp.ContextMenu.createFromEvent(cast e, menuItems);
		}
		tree.onContextMenu = ctxMenu;
		return tree;
	}

	function migrateMaterialLibrary(prefabs: Array<hrt.prefab.Prefab>, newPath: String) {
		if(!ide.confirm("Move " + prefabs + " to " + newPath + " ? (Cannot be undone)"))
			return;

		var absPath = ide.getPath(newPath);
		var targetPrefab = hxd.res.Loader.currentInstance.load(newPath).toPrefab().loadBypassCache();

		// only keep roots from selection
		for (mat in prefabs) {
			var p = mat.parent;
			while(p != null) {
				if (prefabs.contains(p)) {
					prefabs.remove(p);
					break;
				}
				p = p.parent;
			}
		}

		var movedMats : Array<hrt.prefab.Material> = [];
		for (prefab in prefabs) {
			var flat = prefab.flatten();
			for (child in flat) {
				var mat = child.to(hrt.prefab.Material);
				if (mat != null) {
					movedMats.push(mat);
				}
			}
		}

		for (prefab in prefabs) {
			prefab.parent = targetPrefab;
		}

		var ser = ide.toJSON(targetPrefab.serialize());

		sys.io.File.saveContent(absPath, ser);
		view.save();

		var path = ide.getRelPath(@:privateAccess view.getPath());
		ide.filterPaths((ctx: hide.Ide.FilterPathContext) -> {
			if (path == ctx.valueCurrent) {
				var name = ctx.currentObject.name;
				if (name != null) {
					for (mat in movedMats) {
						if (name == mat.name) {
							ctx.change(newPath);
							return;
						}
					}
				}
			}
			else {
				for (mat in movedMats) {
					if (ctx.valueCurrent == path + "/" + mat.name) {
						ctx.change(newPath + "/" + mat.name);
						return;
					}
				}
			}
		});

		view.rebuild();
	}

	function refreshTree(target: Tree, ?callb) {
		if (treeRefreshing) {
			queueRefresh ??= [];
			if (callb != null)
				queueRefresh.push(callb);
			return;
		}
		treeRefreshing = true;

		function refresh(tree : FancyTree<hrt.prefab.Prefab>) @:privateAccess {
			var selection = tree.getSelectedItems();
			tree.rebuildTree();
			var datas = [for (p in selection) tree.itemMap.get(cast p)];
			if (datas != null) {
				for (idx => d in datas) {
					tree.refreshItem(selection[idx]);
					tree.setSelection(d, true);
				}
			}
			selectElements(selection, SelectMode.NoHistory);
		}

		switch (target) {
			case RenderPropsTree:
				refresh(renderPropsTree);
			case SceneTree:
				refresh(sceneTree);
			case All:
				var selectInSceneTree = true;
				var selection = sceneTree.getSelectedItems();
				if (selection.length == 0) {
					selection = renderPropsTree.getSelectedItems();
					selectInSceneTree = false;
				}
				sceneTree.rebuildTree();
				renderPropsTree.rebuildTree();
				var tree = selectInSceneTree ? sceneTree : renderPropsTree;
				var datas = [for (p in selection) @:privateAccess tree.itemMap.get(cast p)];
				if (datas != null) {
					for (idx => d in datas) {
						tree.refreshItem(selection[idx]);
						@:privateAccess tree.setSelection(d, true);
					}
				}
				selectElements(selection, SelectMode.NoHistory);
		}

		if(callb != null) callb();
		treeRefreshing = false;

		if (queueRefresh != null) {
			var list = queueRefresh;
			queueRefresh = null;
			refreshTree(All, () -> for (cb in list) cb());
		}
	}

	function refreshTreeStyle(p : hrt.prefab.Prefab, targetTree: Tree) {
		function exec(targetTree: Tree) {
			applyTreeStyle(p, targetTree);
		}

		switch (targetTree) {
			case SceneTree:
				exec(SceneTree);
			case RenderPropsTree:
				exec(RenderPropsTree);
			case All:
				exec(SceneTree);
				exec(RenderPropsTree);
		}
	}

	public function applyTreeStyle(p: PrefabElement, tree : Tree) {
		var tree = tree == SceneTree ? sceneTree : renderPropsTree;
		var el = @:privateAccess tree.itemMap.get(p)?.element;
		if (el == null) return;

		function set(p: hrt.prefab.Prefab, className : String, enabled : Bool) {
			var data = @:privateAccess tree.itemMap.get(p);
			if (data.element == null)
				return;

			if (enabled && !data.element.classList.contains(className))
				data.element.classList.add(className);
			else if (!enabled)
				data.element.classList.remove(className);

			if (data.children != null) {
				for (c in data.children)
					set(c.item, className, enabled);
			}
		}

		function is(p: hrt.prefab.Prefab, status : (p : hrt.prefab.Prefab) -> Bool) {
			var res = status(p);
			var parent = p.parent;
			while (parent != null) {
				res = res || status(parent);
				parent = parent.parent;
			}

			return res;
		}

		set(p, "disabled", is(p, (p) -> !p.enabled));
		set(p, "editorOnly", is(p, (p) -> p.editorOnly));
		set(p, "inGameOnly", is(p, (p) -> p.inGameOnly));
		set(p, "locked", is(p, (p) -> p.locked));

		var tag = getTag(p);
		if(tag != null) {
			el.style.background = tag.color;
			el.style.color = tag.color + "90";
		}
		else {
			el.style.background = null;
			el.style.color = null;
		}

		var shader = Std.downcast(p, hrt.prefab.Shader);
		if (shader != null && (shader.getShaderDefinition() == null)) {
			el.style.textDecoration = "line-through";
			el.style.color = "#ff5555";
		}

		// Reference
		var isOverride = false;
		var isOverriden = false;
		var isOverridenNew = false;
		var inRef = false;
		if (p.shared.parentPrefab != null) {
			var parentRef = Std.downcast(p.shared.parentPrefab, Reference);
			if (parentRef != null) {
				if (parentRef.editMode == Override) {
					isOverride = true;

					var path = [];
					var current = p;
					while (current != null) {
						path.push(current);
						current = current.parent;
					}

					var currentOverride = @:privateAccess parentRef.computeDiffFromSource();

					// skip first item in the path
					path.pop();
					while(currentOverride != null && path.length > 0) {
						var current = path.pop();
						if (currentOverride.children != null) {
							currentOverride = Reflect.field(currentOverride.children, current.name);
						}
					}

					if (currentOverride != null) {
						var overridenFields = Reflect.fields(currentOverride);
						overridenFields.remove("children");
						if (overridenFields.length > 0) {
							isOverriden = true;
							if (currentOverride.type != null) {
								isOverridenNew = true;
							}
						}
					}

				} else {
					inRef = true;
				}
			}
		}

		set(p, "inRef", is(p, (p) -> {
			var r = Std.downcast(p.shared.parentPrefab, Reference);
			return r != null && r.editMode == Edit;
		}));
		set(p, "isOverride", isOverride);
		set(p, "isOverriden", isOverriden);
		set(p, "isOverridenNew", isOverridenNew);

		set(p, "hidden", is(p, (p) -> {
			var obj = p.getLocal3d();
			var obj2d = p.getLocal2d();
			var objVisible = true;
			if (obj != null)
				objVisible = obj.visible;
			if (obj2d != null)
				objVisible = obj2d.visible;
			return isHidden(p) || !objVisible;
		}));
	}

	public function collapseTree() {
		function collapse(p : hrt.prefab.Prefab) {
			sceneTree.collapseItem(p);
			for (c in p.children)
				collapse(c);
		}

		collapse(sceneData);
	}


	function refreshProps() {
		selectElements(selectedPrefabs, Nothing);
	}

	var refWatches : Map<String,{ callb : Void -> Void, ignoreCount : Int }> = [];

	public function watchIgnoreChanges( source : String ) {
		var w = refWatches.get(source);
		if( w == null ) return;
		w.ignoreCount++;
	}

	public function watch( source : String ) {
		var w = refWatches.get(source);
		if( w != null ) return;
		w = { callb : function() {
			if( w.ignoreCount > 0 ) {
				w.ignoreCount--;
				return;
			}
			if( view.modified && !ide.confirm('${source} has been modified, reload and ignore local changes?') )
				return;
			view.undo.clear();
			view.rebuild();
		}, ignoreCount : 0 };
		refWatches.set(source, w);
		ide.fileWatcher.register(source, w.callb, false, scene.element);
	}

	function clearWatches() {
		var prev = refWatches;
		refWatches = [];
		for( source => w in prev )
			ide.fileWatcher.unregister(source, w.callb);
	}

	function teardownRenderer() {
		scene.s3d.renderer.dispose();
		scene.s3d.renderer = h3d.mat.MaterialSetup.current.createRenderer();
	}

	@:access(hrt.prefab.RenderProps)
	function setRenderProps(?renderProps: hrt.prefab.RenderProps) {
		/*
			Order of priority for render props :
			1. The render props passed as parameter to this function
			2. The first currently selected render props
			3. The first render props in the scene with isDefault == true
			4. The first render props in the scene
			5. The chosen default render props in the render props settings
		*/

		function filter(p: hrt.prefab.RenderProps) : Bool {
			return p.enabled == true && p.visible == true && !isHidden(p);
		}

		// 1.
		if (renderProps == null) {

			// 2.
			for (prefab in selectedPrefabs) {
				var asRenderProps = Std.downcast(prefab, hrt.prefab.RenderProps);
				if (asRenderProps != null && filter(asRenderProps) && checkIsInWorld(asRenderProps)) {
					renderProps = asRenderProps;
					break;
				}
			}
		}

		if (renderProps == null) {
			var all = sceneData.findAll(hrt.prefab.RenderProps, filter, true);
			// 3.
			for (rp in all) {
				if (rp.isDefault == true) {
					renderProps = rp;
					break;
				}
			}

			// 4.
			if (renderProps == null) {
				renderProps = all[0];
			}
		}

		// 5.
		if (renderProps == null) {
			// no enabled render props was found, create an external render props (and don't show it in the scene)
			refreshDefaultRenderProps();
			previousSceneRenderProps = null;
			return;
		}


		// Init a render props in the scene

		// remove the last external render props if it exists
		if (renderPropsRoot != null) {
			removeInstance(renderPropsRoot);
			renderPropsRoot = null;
			previousSceneRenderProps = null;
			refreshTree(RenderPropsTree);
		}

		if (previousSceneRenderProps != renderProps)
			teardownRenderer();
		renderProps.applyProps(scene.s3d.renderer);
		previousSceneRenderProps = renderProps;
	}

	function getRenderPropsPath() : String {
		var renderProps = view.config.getLocal("scene.renderProps");
		if (renderProps is String) {
			return cast renderProps;
		}

		if (renderProps is Array) {
			var a_renderProps = cast (renderProps, Array<Dynamic>);
			var savedRenderProp = @:privateAccess view.getDisplayState("renderProps");

			// Check if the saved render prop hasn't been deleted from json
			var isRenderPropAvailable = false;
			for (idx in 0...a_renderProps.length) {
				if (savedRenderProp != null && a_renderProps[idx].value == savedRenderProp.value)
					isRenderPropAvailable = true;
			}

			var source = view.config.getLocal("scene.renderProps")[0].value;
			if (savedRenderProp != null && isRenderPropAvailable)
				source = savedRenderProp.value;
			return source;
		}
		return null;
	}

	function refreshDefaultRenderProps(){
		var path = getRenderPropsPath();

		var needTeardown = false;
		// remove previous render props if it has changed
		if (renderPropsRoot != null) {
			if (renderPropsRoot.source != path) {
				removeInstance(renderPropsRoot);
				renderPropsRoot = null;
				needTeardown = true;
			}
		}

		if (previousSceneRenderProps != null) {
			previousSceneRenderProps = null;
			needTeardown = true;
		}

		if (needTeardown) {
			teardownRenderer();
		}

		if (renderPropsRoot == null && path != null) {
			renderPropsRoot = new hrt.prefab.Reference(null, new ContextShared());
			renderPropsRoot.setEditor(this, this.scene);
			renderPropsRoot.shared.customMake = customMake;
			renderPropsRoot.editMode = Ide.inst.currentConfig.get("sceneeditor.renderprops.edit", false) ? Edit : None;
			renderPropsRoot.name = "Render Props";
			renderPropsRoot.source = path;

			@:privateAccess renderPropsRoot.shared.root2d = renderPropsRoot.shared.current2d = root2d;
			@:privateAccess renderPropsRoot.shared.root3d = renderPropsRoot.shared.current3d = root3d;

			// Needed because make will call queueRefreshRenderProps
			refreshRenderPropsStack ++;

			renderPropsRoot = renderPropsRoot.make();

			refreshRenderPropsStack --;

			refreshTree(RenderPropsTree);
		}

		var wasSet = false;
		if( @:privateAccess renderPropsRoot?.refInstance != null ) {
			var renderProps = @:privateAccess renderPropsRoot.refInstance.getOpt(hrt.prefab.RenderProps, true);
			if( renderProps != null ) {
				renderProps.applyProps(scene.s3d.renderer);
				wasSet = true;
			}
		}


		// Clear render props
		if (!wasSet) {
			for(fx in scene.s3d.renderer.effects)
				if ( fx != null )
					fx.dispose();

			scene.s3d.renderer.props = scene.s3d.renderer.getDefaultProps();
		}
	}

	public function refreshScene() {

		clearWatches();

		if (root2d != null) root2d.remove();
		if (root3d != null) root3d.remove();

		if (sceneData == null)
			return;

		sceneData.dispose();

		hrt.impl.Gradient.purgeEditorCache();

		root3d = new h3d.scene.Object();
		root3d.name = "root3d";

		root2d = new h2d.Object();
		root2d.name = "root2d";

		scene.s3d.addChild(root3d);
		scene.s2d.addChildAt(root2d, 0); // make sure the 2d scene is behind the UI

		scene.s2d.defaultSmooth = true;
		root2d.x = scene.s2d.width >> 1;
		root2d.y = scene.s2d.height >> 1;

		cameraController2D = makeCamController2D();
		setupCameraEvents(cameraController2D);

		if (camera2D) {
			var cam2d = @:privateAccess view.getDisplayState("Camera2D");
			if( cam2d != null ) {
				root2d.x = scene.s2d.width*0.5 + cam2d.x;
				root2d.y = scene.s2d.height*0.5 + cam2d.y;
				root2d.setScale(cam2d.z);
			}
			cameraController2D.loadFromScene();
		}

		set_camera2D(camera2D);

		root2d.addChild(cameraController2D);
		scene.setCurrent();
		scene.onResize();

		@:privateAccess sceneData.setSharedRec(new ContextShared(root2d,root3d));
		sceneData.shared.currentPath = view.state.path;
		sceneData.shared.customMake = customMake;
		sceneData.setEditor(this, this.scene);

		var bgcol = scene.engine.backgroundColor;
		scene.init();
		scene.engine.backgroundColor = bgcol;

		// Load display state
		{
			var all = sceneData.flatten(PrefabElement, null);
			var list = @:privateAccess view.getDisplayState("hideList");
			if(list != null) {
				var m = [for(i in (list:Array<Dynamic>)) i => true];
				for(p in all) {
					if(m.exists(p.getAbsPath(true, true)))
						hideList.set(p, true);
				}
			}
		}

		rebuild(sceneData);

		var all = sceneData.all();
		for(elt in all)
			applySceneStyle(elt);

		refreshTree(All);

		setRenderProps();

		onRefresh();
	}

	function makeGuide2d() {
		guide2d = new h2d.Object();
		scene.s2d.add(guide2d, 1);
		grid2d = new h2d.Graphics(guide2d);
		//guide2d.visible = false;
	}

	function updateGuide2d() {
		//var any2DSelected = selectedPrefabs.find((p) -> Std.downcast(p, Object2D) != null) != null;
		guide2d.visible = camera2D && getOrInitConfig("sceneeditor.gridToggle", false) && showOverlays;

		if (!guide2d.visible)
			return;

		guide2d.x = root2d.x;
		guide2d.y = root2d.y;
		var z = root2d.scaleX;

		grid2d.clear();
		grid2d.removeChildren();

		var col = h3d.Vector.fromColor(scene?.engine?.backgroundColor ?? 0);
		var hsl = col.toColorHSL();

		  var mov = 0.1;

		  if (snapToggle) {
				mov = 0.2;
				hsl.y += (1.0-hsl.y) * 0.2;
		  }
		if(hsl.z > 0.5) hsl.z -= mov;
		else hsl.z += mov;

		col.makeColor(hsl.x, hsl.y, hsl.z);

		final guideColor = col.toColor();

		grid2d.lineStyle(1, guideColor, 0.5);
		grid2d.drawRect((-1920/2) * z - 1, -(1080/2) * z - 1, (1920)*z+2, 1080*z + 2);

		grid2d.lineStyle(1, guideColor, 0.25);
		grid2d.moveTo(-100000*z, 0);
		grid2d.lineTo(100000*z, 0);

		grid2d.moveTo(0, -100000*z);
		grid2d.lineTo(0, 100000*z);

		var label = new h2d.Text(hxd.res.DefaultFont.get(), grid2d);
		label.text = "1080p";
		label.textAlign = Right;
		label.x = (1920/2)*z;
		label.y = (1080/2)*z;
		label.smooth = false;
		label.color.setColor(guideColor | 0xFF000000);
		label.dropShadow = {
			dx: 1,
			dy: 1,
			color: 0,
			alpha: 0.5
		};
	}

	function refreshGuide2d() {
		var any2DSelected = selectedPrefabs.find((p) -> Std.downcast(p, Object2D) != null) != null;
		//guide2d.visible = any2DSelected;
	}

	function getAllWithRefs<T:PrefabElement>( p : PrefabElement, cl : Class<T>, ?arr : Array<T>, forceLoad: Bool = false ) : Array<T> {
		if( arr == null ) arr = [];
		var v = p.to(cl);
		if( v != null ) arr.push(v);
		for( c in p.children )
			getAllWithRefs(c, cl, arr);
		var ref = p.to(Reference);

		@:privateAccess
		if (ref != null && ref.enabled) {
			if (forceLoad) {
				ref.resolveRef();
			}
			if (ref.refInstance != null) getAllWithRefs(ref.refInstance, cl, arr, forceLoad);
		}
		return arr;
	}

	public dynamic function onRefresh() {
	}

	function makeInteractive( elt : PrefabElement) {
		var int = elt.makeInteractive();
		if( int != null ) {
			initInteractive(elt,cast int);
			if( isLocked(elt) ) toggleInteractive(elt, false);
		}
		var ref = Std.downcast(elt,Reference);
	}

	function toggleInteractive( e : PrefabElement, visible : Bool ) {
		var ints = getInteractives(e);
		for (int in ints) {
			var i2d = Std.downcast(int,h2d.Interactive);
			if (i2d != null) i2d.visible = visible;
			var i3d = Std.downcast(int,h3d.scene.Interactive);
			if (i3d != null) i3d.visible = visible;
		}
	}

	function initInteractive( elt : PrefabElement, int : {
		dynamic function onPush(e:hxd.Event) : Void;
		dynamic function onMove(e:hxd.Event) : Void;
		dynamic function onRelease(e:hxd.Event) : Void;
		dynamic function onClick(e:hxd.Event) : Void;
		function handleEvent(e:hxd.Event) : Void;
		function preventClick() : Void;
	} ) {
		if( int == null ) return;
		var i3d = Std.downcast(int, h3d.scene.Interactive);
		if (i3d != null) {
			interactives.set(elt,i3d);
			i3d.propagateEvents = true;
		}
		var i2d = Std.downcast(int, h2d.Interactive);
		if (i2d != null ) {
			interactives2d.set(elt, i2d);
			i2d.propagateEvents = true;
		}
	}


	var tmpPt : h2d.col.Point = new h2d.col.Point();

	function getAllPrefabsUnderMouse() : Array<{d: Float, prefab: PrefabElement}> {
		var camera = scene.s3d.camera;
		var ray = camera.rayFromScreen(scene.s2d.mouseX, scene.s2d.mouseY);

		var selectables = getAllSelectable(true, true);
		var hits : Array<{d: Float, prefab: PrefabElement}> = [];

		var order2d : Map<PrefabElement, Int> = null;

		for (selectable in selectables) {
			var int3d = interactives.get(selectable);
			if (int3d != null) {
				var distance = int3d.shape?.rayIntersection(ray, false);
				if (distance < 0)
					continue;

				var distance = int3d.preciseShape?.rayIntersection(ray, true) ?? distance;

				if (distance > 0) {
					hits.push({d: distance, prefab: selectable});
				}
			}

			var int2d = interactives2d.get(selectable);
			@:privateAccess if (int2d != null) {
				var dx = scene.s2d.mouseX - int2d.absX;
				var dy = scene.s2d.mouseY - int2d.absY;
				var rx = (dx * int2d.matD - dy * int2d.matC) * int2d.invDet;
				var ry = (dy * int2d.matA - dx * int2d.matB) * int2d.invDet;

				if ( int2d.shape != null ) {
					// Check collision for Shape Interactive.
					tmpPt.set(rx + int2d.shapeX,ry + int2d.shapeY);
					if ( !int2d.shape.contains(tmpPt) ) continue;
				} else {
					// Check AABB for width/height Interactive.
					if( ry < 0 || rx < 0 || rx >= int2d.width || ry >= int2d.height )
						continue;
				}

				if (order2d == null) {
					order2d = [];
					var flat = sceneData.flatten();
					for (i => prefab in flat) {
						order2d.set(prefab, i);
					}
				}

				var index = order2d.get(selectable);
				hits.push({d: -index, prefab: selectable});
			}
		}

		hits.sort((a,b) -> Reflect.compare(a.d, b.d));

		return hits;
	}

	function selectNewObject(e:hxd.Event) {
		if( !objectAreSelectable )
			return;
		var parentEl = sceneData;
		 // for now always create at scene root, not `selectedPrefabs[0];`
		var group = getParentGroup(parentEl);
		if( group != null )
			parentEl = group;

		var origTrans = getPickTransform(parentEl);
		if (origTrans == null) {
			origTrans = new h3d.Matrix();
			origTrans.identity();
		}

		var selectItems: Array<hide.comp.ContextMenu.MenuItem> = [];

		for (hit in getAllPrefabsUnderMouse()) {
			selectItems.push({
				label: hit.prefab.name,
				click: () -> selectElements([hit.prefab]),
			});
		}

		var originPt = origTrans.getPosition();
		var newItems = getNewContextMenu(parentEl, function(newElt) {
			var newObj3d = Std.downcast(newElt, Object3D);
			if(newObj3d != null) {
				var newPos = new h3d.Matrix();
				newPos.identity();
				newPos.setPosition(originPt);

				var obj = getObject(parentEl);
				var invParent : h3d.Matrix;
				if (obj != null) {
					invParent = obj.getAbsPos().clone();
					invParent.invert();
				}
				else {
					invParent = new h3d.Matrix();
					invParent.identity();
				}

				newPos.multiply(newPos, invParent);
				newObj3d.setTransform(newPos);
			}
			var newObj2d = Std.downcast(newElt, Object2D);
			if( newObj2d != null ) {
				var pt = new h2d.col.Point(scene.s2d.mouseX, scene.s2d.mouseY);
				var l2d = getObject2d(parentEl);
				l2d.globalToLocal(pt);
				newObj2d.x = pt.x;
				newObj2d.y = pt.y;
			}
		});
		var menuItems : Array<hide.comp.ContextMenu.MenuItem> = [
			{ label : "Select", menu: selectItems },
			{ label : "New...", menu : newItems },
			{ isSeparator : true, label : "" },
			{
				label : "Gather here",
				click : gatherToMouse,
				enabled : (selectedPrefabs.length > 0),
				keys : view.config.get("key.sceneeditor.gatherToMouse"),
			},
		];
		hide.comp.ContextMenu.createFromPoint(ide.mouseX, ide.mouseY, cast menuItems);
	}

	public function refreshInteractive(elt : PrefabElement) {
		for (p in elt.flatten(null, null)) {
			removeInteractive(p);
			makeInteractive(p);
		}
	}

	public function removeInteractive(elt: PrefabElement) {
		var int = interactives.get(elt);
		if(int != null) {
			int.remove();
			interactives.remove(elt);
		}

		var i2d = interactives2d.get(elt);
		if (i2d != null) {
			i2d.remove();
			interactives2d.remove(elt);
		}
	}

	function setupGizmo() {
		if(selectedPrefabs == null) return;

		var posQuant = view.config.get("sceneeditor.xyzPrecision");
		var scaleQuant = view.config.get("sceneeditor.scalePrecision");
		var rotQuant = view.config.get("sceneeditor.rotatePrecision");
		inline function quantize(x: Float, step: Float) {
			if(step > 0) {
				x = Math.round(x / step) * step;
				x = roundSmall(x);
			}
			return x;
		}

		gizmo.onStartMove = function(mode) {
			var objects3d = [for(o in selectedPrefabs) {
				var obj3d = o.to(hrt.prefab.Object3D);
				if(obj3d != null)
					obj3d;
			}];
			var sceneObjs : Array<Object> = [for(o in objects3d) o.getLocal3d()];
			var pivotPt = getPivot(sceneObjs);
			var pivot = new h3d.Matrix();
			pivot.initTranslation(pivotPt.x, pivotPt.y, pivotPt.z);
			var invPivot = pivot.clone();
			invPivot.invert();

			gizmo.snap = gizmoSnap;

			gizmo.shoudSnapOnGrid = function() {
				return this.snapForceOnGrid;
			}

			var localMats = [for(o in sceneObjs) {
				var m = worldMat(o);
				m.multiply(m, invPivot);
				m;
			}];

			var prevState = [for(o in objects3d) o.saveTransform()];
			gizmo.onMove = function(translate: h3d.Vector, rot: h3d.Quat, scale: h3d.Vector) {
				var transf = new h3d.Matrix();
				transf.identity();
				if(rot != null) {
					rot.toMatrix(transf);

					 }
				if(translate != null)
					transf.translate(translate.x, translate.y, translate.z);
				for(i in 0...sceneObjs.length) {
					var newMat = localMats[i].clone();
					newMat.multiply(newMat, transf);
					newMat.multiply(newMat, pivot);
					if(snapToGround && mode == MoveXY) {
						newMat.tz = getZ(newMat.tx, newMat.ty);
					}

					var obj = sceneObjs[i];
					if ( obj != null && obj.parent != null ) {
						var parentMat = obj.parent.getAbsPos().clone();
						if(obj.follow != null) {
							if(obj.followPositionOnly)
								parentMat.setPosition(obj.follow.getAbsPos().getPosition());
							else
								parentMat = obj.follow.getAbsPos().clone();
						}
						var invParent = parentMat;
						invParent.invert();
						newMat.multiply(newMat, invParent);
						if(scale != null) {
							newMat.prependScale(scale.x, scale.y, scale.z);
							// var previousScale = newMat.getScale();
							// newMat.prependScale(1 / previousScale.x, 1 / previousScale.y, 1 / previousScale.z);
							// newMat.prependScale(Math.max(0, previousScale.x  + scale.x), Math.max(0, previousScale.y + scale.y), Math.max(0, previousScale.z + scale.z));
						}
					}

					var obj3d = objects3d[i];
					var obj3dPrevTransform = obj3d.getTransform();
					var euler = newMat.getEulerAngles();
						  if (translate != null && translate.length() > 0.0001 && snapForceOnGrid) {
								obj3d.x = snap(quantize(newMat.tx, posQuant), snapMoveStep);
								obj3d.y = snap(quantize(newMat.ty, posQuant), snapMoveStep);
								obj3d.z = snap(quantize(newMat.tz, posQuant), snapMoveStep);
						  }
						  else { // Don't snap translation if the primary action wasn't a translation (i.e. Rotation around a pivot)
						obj3d.x = quantize(newMat.tx, posQuant);
						obj3d.y = quantize(newMat.ty, posQuant);
						obj3d.z = quantize(newMat.tz, posQuant);
					}

						  if (rot != null) {
								obj3d.rotationX = quantize(M.radToDeg(euler.x), rotQuant);
								obj3d.rotationY = quantize(M.radToDeg(euler.y), rotQuant);
								obj3d.rotationZ = quantize(M.radToDeg(euler.z), rotQuant);
					}

					if(scale != null) {
						var s = newMat.getScale();
						obj3d.scaleX = quantize(s.x, scaleQuant);
						obj3d.scaleY = quantize(s.y, scaleQuant);
						obj3d.scaleZ = quantize(s.z, scaleQuant);
					}
					obj3d.applyTransform();
					if( selfOnlyTransform )
						restoreChildTransform(obj3d, obj3dPrevTransform);
					if ( curEdit != null )
						curEdit.onChange(obj3d, null);
				}
			}

			gizmo.onFinishMove = function() {
				var newState = [for(o in objects3d) o.saveTransform()];
				var selfOnlyTransform = this.selfOnlyTransform;
				refreshProps();
				undo.change(Custom(function(undo) {
					for(i in 0...objects3d.length) {
						var obj3d = objects3d[i];
						var obj3dPrevTransform = obj3d.getTransform();
						obj3d.loadTransform(undo ? prevState[i] : newState[i]);
						obj3d.applyTransform();
						if( selfOnlyTransform )
							restoreChildTransform(obj3d, obj3dPrevTransform);
					}
					refreshProps();

					for(o in objects3d) {
						if ( curEdit != null )
							curEdit.onChange(o, null);
						o.updateInstance();
						applySceneStyle(o);
					}
				}));

				for(o in objects3d) {
					o.updateInstance();
					applySceneStyle(o);
				}
			}
		}
		gizmo2d.onStartMove = function(mode) {
			var objects2d = [for(o in selectedPrefabs) {
				var obj = o.to(hrt.prefab.Object2D);
				if(obj != null) obj;
			}];
			var sceneObjs = [for(o in objects2d) o.getLocal2d()];
			var pivot = getPivot2D(sceneObjs);
			var center = pivot.getCenter();
			var prevState = [for(o in objects2d) o.saveTransform()];
			var startPos = [for(o in sceneObjs) o.getAbsPos()];

			gizmo2d.onMove = function(t) {
				t.x = Math.round(t.x);
				t.y = Math.round(t.y);
				for(i in 0...sceneObjs.length) {
					var pos = startPos[i].clone();
					var obj = objects2d[i];
					switch( mode ) {
					case Pan:
						pos.x += t.x;
						pos.y += t.y;
					case ScaleX, ScaleY, Scale:
						// no inherited rotation
						if( pos.b == 0 && pos.c == 0 ) {
							pos.x -= center.x;
							pos.y -= center.y;
							pos.x *= t.scaleX;
							pos.y *= t.scaleY;
							pos.x += center.x;
							pos.y += center.y;
							obj.scaleX = quantize(t.scaleX * prevState[i].scaleX, scaleQuant);
							obj.scaleY = quantize(t.scaleY * prevState[i].scaleY, scaleQuant);
						} else {
							var m2 = new h2d.col.Matrix();
							m2.initScale(t.scaleX, t.scaleY);
							pos.x -= center.x;
							pos.y -= center.y;
							pos.multiply(pos,m2);
							pos.x += center.x;
							pos.y += center.y;
							var s = pos.getScale();
							obj.scaleX = quantize(s.x, scaleQuant);
							obj.scaleY = quantize(s.y, scaleQuant);
						}
					case Rotation:
						pos.x -= center.x;
						pos.y -= center.y;
						var ca = Math.cos(t.rotation);
						var sa = Math.sin(t.rotation);
						var px = pos.x * ca - pos.y * sa;
						var py = pos.x * sa + pos.y * ca;
						pos.x = px + center.x;
						pos.y = py + center.y;
						var r = M.degToRad(prevState[i].rotation) + t.rotation;
						r = quantize(M.radToDeg(r), rotQuant);
						obj.rotation = r;
					}
					var pt = pos.getPosition();
					sceneObjs[i].parent.globalToLocal(pt);
					obj.x = quantize(pt.x, posQuant);
					obj.y = quantize(pt.y, posQuant);
					obj.applyTransform(sceneObjs[i]);
					var fx2d = obj.findParent(hrt.prefab.fx.FX2D);
					if (fx2d != null && fx2d.local2d != null) {
						// recompute animations
						var anim : hrt.prefab.fx.FX2D.FX2DAnimation = cast fx2d.local2d;
						anim.setTime(anim.localTime);
					}
				}
			};
			gizmo2d.onFinishMove = function() {
				var newState = [for(o in objects2d) o.saveTransform()];
				refreshProps();
				undo.change(Custom(function(undo) {
					if( undo ) {
						for(i in 0...objects2d.length) {
							objects2d[i].loadTransform(prevState[i]);
							objects2d[i].applyTransform(sceneObjs[i]);
						}
						refreshProps();
					}
					else {
						for(i in 0...objects2d.length) {
							objects2d[i].loadTransform(newState[i]);
							objects2d[i].applyTransform(sceneObjs[i]);
						}
						refreshProps();
					}
					for(o in objects2d)
						o.updateInstance();
				}));
				for(o in objects2d)
					o.updateInstance();
			};
		};
	}

	public function updateBasis() {
		if (basis == null) return;
		showBasis = getOrInitConfig("sceneeditor.axisToggle", true);
		if (selectedPrefabs != null && selectedPrefabs.length == 1) {
			basis.visible = showBasis && showOverlays;
			var rootObj = selectedPrefabs[0].getLocal3d();
			if (rootObj == null) {
				basis.visible = false;
				return;
			}

			var pos = getPivot([rootObj]);
			basis.setPosition(pos.x, pos.y, pos.z);
			var obj = getRootObjects3d()[0];
			var mat = worldMat(obj);
			var s = mat.getScale();

			if(s.x != 0 && s.y != 0 && s.z != 0) {
				mat.prependScale(1.0 / s.x, 1.0 / s.y, 1.0 / s.z);
				basis.getRotationQuat().initRotateMatrix(mat);
			}

			var cam = scene.s3d.camera;
			var gpos = gizmo.getAbsPos().getPosition();
			var distToCam = cam.pos.sub(gpos).length();
			var engine = h3d.Engine.getCurrent();
			var ratio = 150 / engine.height;

				var scale = ratio * distToCam * Math.tan(cam.fovY * 0.5 * Math.PI / 180.0);
				if (cam.orthoBounds != null) {
					 scale = ratio *  (cam.orthoBounds.xSize) * 0.5;
				}
			basis.setScale(scale);

		} else {
			basis.visible = false;
		}
	}

	function moveGizmoToSelection() {
		// Snap Gizmo at center of objects
		gizmo.getRotationQuat().identity();
		var roots = getRootObjects3d();
		if(roots.length > 0) {
			var pos = getPivot(roots);
			gizmo.visible = showGizmo && getOrInitConfig("sceneeditor.showGizmo", true) && showOverlays;
			gizmo.setPosition(pos.x, pos.y, pos.z);

			if(roots.length >= 1 && (localTransform || K.isDown(K.ALT) || gizmo.editMode == Scaling)) {
				var obj = roots[roots.length-1];
				var mat = worldMat(obj);
				var s = mat.getScale();
				if(s.x != 0 && s.y != 0 && s.z != 0) {
					mat.prependScale(1.0 / s.x, 1.0 / s.y, 1.0 / s.z);
					gizmo.getRotationQuat().initRotateMatrix(mat);
				}
			}
		}
		else {
			gizmo.visible = false;
		}
		var root2d = getRootObjects2d();
		if( root2d.length > 0 && !gizmo.visible ) {
			var pos = getPivot2D(root2d);
			gizmo2d.visible = showGizmo && getOrInitConfig("sceneeditor.showGizmo", true) && showOverlays;
			gizmo2d.setPosition(pos.getCenter().x, pos.getCenter().y);
			gizmo2d.setSize(pos.width, pos.height);
		} else {
			gizmo2d.visible = false;
		}
	}

	var inLassoMode = false;
	function startLassoSelect() {
		if(inLassoMode) {
			inLassoMode = false;
			return;
		}
		scene.setCurrent();
		inLassoMode = true;
		var g = new h2d.Object(scene.s2d);
		var overlay = new h2d.Bitmap(h2d.Tile.fromColor(0xffffff, 10000, 10000, 0.1), g);
		var intOverlay = new h2d.Interactive(10000, 10000, scene.s2d);
		var lastPt = new h2d.col.Point(scene.s2d.mouseX, scene.s2d.mouseY);
		var points : h2d.col.Polygon = [lastPt];
		var polyG = new h2d.Graphics(g);
		event.waitUntil(function(dt) {
			var curPt = new h2d.col.Point(scene.s2d.mouseX, scene.s2d.mouseY);
			if(curPt.distance(lastPt) > 3.0) {
				points.push(curPt);
				polyG.clear();
				polyG.beginFill(0xff0000, 0.5);
				polyG.lineStyle(1.0, 0, 1.0);
				polyG.moveTo(points[0].x, points[0].y);
				for(i in 1...points.length) {
					polyG.lineTo(points[i].x, points[i].y);
				}
				polyG.endFill();
				lastPt = curPt;
			}

			var finish = false;
			if(!inLassoMode || K.isDown(K.ESCAPE) || K.isDown(K.MOUSE_RIGHT)) {
				finish = true;
			}

			if(K.isDown(K.MOUSE_LEFT)) {
				var all = getAllSelectable(true, false);
				var inside = [];
				for(elt in all) {
					if(elt.to(Object3D) == null)
						continue;
					var o = elt.getLocal3d();
					if(o == null || !o.visible)
						continue;
					var absPos = o.getAbsPos();
					var screenPos = worldToScreen(absPos.tx, absPos.ty, absPos.tz);
					if(points.contains(screenPos, false)) {
						inside.push(elt);
					}
				}
				selectElements(inside);
				finish = true;
			}

			if(finish) {
				intOverlay.remove();
				g.remove();
				inLassoMode = false;
				return true;
			}
			return false;
		});
	}

	public function setWireframe(val = true) {
		var engine = h3d.Engine.getCurrent();
		if( engine.driver.hasFeature(Wireframe) ) {
			for( m in scene.s3d.getMaterials() ) {
				if ( m.name == "$collider" )
					continue;
				m.mainPass.wireframe = val;
			}
		}
	}

	var jointsGraphics : h3d.scene.Graphics = null;
	@:access(h3d.scene.Skin)
	public function setJoints(showJoints = true, selectedJoints : Array<String>) {
		if( showJoints ) {
			if( jointsGraphics == null ) {
				jointsGraphics = new h3d.scene.Graphics(scene.s3d);
				jointsGraphics.material.mainPass.depth(false, Always);
				jointsGraphics.material.mainPass.setPassName("overlay");
			}

			jointsGraphics.clear();

			for ( m in scene.s3d.getMeshes() ) {
				var sk = Std.downcast(m,h3d.scene.Skin);
				if( sk != null ) {
					var topParent : h3d.scene.Object = sk;
					while( topParent.parent != null )
						topParent = topParent.parent;
					jointsGraphics.follow = topParent;

					if (selectedJoints != null) {
						for (selectedJoint in selectedJoints) {
							var skinData = sk.getSkinData();
							for( j in skinData.allJoints ) {
								var m = sk.jointsData[j.index].currentAbsPos;
								var mp = j.parent == null ? sk.absPos : sk.jointsData[j.parent.index].currentAbsPos;
								if ( j.name == selectedJoint ) {
									jointsGraphics.lineStyle(1, 0x00FF00FF);
									jointsGraphics.moveTo(mp._41, mp._42, mp._43);
									jointsGraphics.lineTo(m._41, m._42, m._43);
								}
							}
						}
					}

					sk.showJoints = true;
				}
			}
		} else if( jointsGraphics != null ) {
			jointsGraphics.remove();
			jointsGraphics = null;
			for ( m in scene.s3d.getMeshes() ) {
				var sk = Std.downcast(m,h3d.scene.Skin);
				if( sk != null ) {
					sk.showJoints = false;
				}
			}
		}
	}

	var collider : h3d.scene.Object = null;
	public function setCollider(showCollider = true) {
		if( showCollider ) {
			if( collider == null )
				collider = new h3d.scene.Object(scene.s3d);
			collider.removeChildren();
			var meshes = scene.s3d.getMeshes();
			meshes = meshes.filter(function (m : h3d.scene.Mesh) {
				var p = m.parent;
				while ( p != null ) {
					if ( p == gizmo )
						return false;
					p = p.parent;
				}
				return true;
			});
			for ( m in meshes ) {
				var prim = Std.downcast(m.primitive, h3d.prim.HMDModel);
				if ( prim == null )
					continue;
				var col = m.getCollider();
				if ( col == null )
					continue;
				var d = col.makeDebugObj();
				for ( mat in d.getMaterials() ) {
					mat.name = "$collider";
					mat.mainPass.setPassName("overlay");
					mat.shadows = false;
					mat.mainPass.wireframe = true;
				}
				collider.addChild(d);
			}
		} else if( collider != null ) {
			collider.remove();
			collider = null;
		}
	}

	public function onPrefabChange(p: PrefabElement, ?pname: String) {
		if(p != sceneData) {
			for (p in p.all())
				refreshTreeStyle(p, All);
		}

		var modifiedRef = Std.downcast(p.shared.parentPrefab, hrt.prefab.Reference);
		if (modifiedRef != null && modifiedRef.editMode == Edit) {
			var path = modifiedRef.source;

			var others = sceneData.findAll(Reference, (r) -> r.source == path && r != modifiedRef, true);
			@:privateAccess
			if (others.length > 0) {
				var data = modifiedRef.refInstance.serialize();
				beginRebuild();
				for (ref in others) {
					removeInstance(ref.refInstance, false);
					@:privateAccess ref.setRef(data);
					queueRebuild(ref);
				}
				endRebuild();
				refreshTree(All);
			}
		}

		applySceneStyle(p);
	}

	public function applySceneStyle(p: PrefabElement) {
		var wasHandled = false;
		var obj3d = p.to(Object3D);
		if(obj3d != null) {
			var visible = obj3d.visible && !isHidden(obj3d);
			var local = obj3d.getLocal3d();
			if (local != null) {
				local.visible = visible;
			}
			wasHandled = true;
		}

		var obj2d = p.to(Object2D);
		if (obj2d != null) {
			var visible = obj2d.visible && !isHidden(obj2d);
			var local = obj2d.getLocal2d();
			if (local != null) {
				local.visible = visible;
			}
			wasHandled = true;
		}

		// Fallback : rebuild the prefab, the customMake will skip hidden prefabs
		if (!wasHandled && p.parent != null) {
			queueRebuild(p.parent);
		}
	}

	public function getInteractives(elt : PrefabElement) : Array<hxd.SceneEvents.Interactive> {
		var r : Array<hxd.SceneEvents.Interactive> = [];
		var i3d = interactives.get(elt);
		if (i3d != null) r.push(i3d);

		var i2d = interactives2d.get(elt);
		if (i2d != null) r.push(i2d);

		for(c in elt.children) {
			r = r.concat(getInteractives(c));
		}
		return r;
	}

	public function getObject(elt: PrefabElement) {
		return elt.getLocal3d() ?? root3d;
	}

	public function getObject2d(elt: PrefabElement) {
		return elt.getLocal2d() ?? root2d;
	}

	public function getSelfObject(elt: PrefabElement) {
		return getObject(elt);
	}

	function removeInstance(elt : PrefabElement, checkRebuild: Bool = true) : Void {
		function recRemove(e:PrefabElement) {
			for (c in e.children) {
				recRemove(c);
			}

			removeInteractive(e);
		}

		var parent = elt.parent;

		recRemove(elt);
		elt.editorRemoveObjects();
		elt.dispose();

		if (checkRebuild)
			checkWantRebuild(parent, elt);
	}

	function makePrefab(elt: PrefabElement) {
		queueRebuild(elt);
	}

	public function addElements(elts : Array<PrefabElement>, selectObj : Bool = true, doRefresh : Bool = true, enableUndo = true) {

		beginRebuild();
		for (e in elts) {
			makePrefab(e);
			if (e.parent != null && doRefresh)
				onPrefabChange(e.parent, "children");
		}
		if (doRefresh) {
			refreshTree(SceneTree, if (selectObj) () -> selectElements(elts, NoHistory) else null);
		}
		endRebuild();

		if( !enableUndo )
			return;

		function exec(undo) {
			var fullRefresh = false;
			if(undo) {
				beginRebuild();
				for (e in elts) {
					removeInstance(e);
					e.parent.children.remove(e);
				}
				endRebuild();
				refreshTree(SceneTree, () -> selectElements([], NoHistory));
			}
			else {

				beginRebuild();
				for (e in elts) {
					e.parent.children.push(e);
					makePrefab(e);
					if (e.parent != null && doRefresh)
						onPrefabChange(e.parent, "children");
				}
				endRebuild();
				refreshTree(SceneTree, if (selectObj) () -> selectElements(elts, NoHistory) else null);
			}
		}

		if (enableUndo) {
			undo.change(Custom(exec));
		}
	}

	function makeCdbProps( e : PrefabElement, type : cdb.Sheet ) {
		var props = type.getDefaults();
		Reflect.setField(props, "$cdbtype", DataFiles.getTypeName(type));
		if( type.idCol != null && !type.idCol.opt ) {
			var id = new haxe.io.Path(view.state.path).file;
			id = id.charAt(0).toUpperCase() + id.substr(1);
			id += "_"+e.name;
			Reflect.setField(props, type.idCol.name, id);
		}
		return props;
	}

	function serializeProps(fields : Array<hide.comp.PropsEditor.PropsField>) : String {
		var out = new Array<String>();
		for (field in fields) {
			@:privateAccess var accesses = field.getAccesses();
			for (a in accesses) {
				var v = Reflect.getProperty(a.obj, a.name);
				var json = haxe.Json.stringify(v);
				out.push('${a.name}:$json');
			}
		}
		return haxe.Json.stringify(out);
	}

	// Return true if unseialization was successfull
	function unserializeProps(fields : Array<hide.comp.PropsEditor.PropsField>, s : String) : Bool {
		var data : Null<Array<Dynamic>> = null;
		try {
			data = cast(haxe.Json.parse(s), Array<Dynamic>);
		}
		catch(_) {

		}
		if (data != null) {
			var map = new Map<String, Dynamic>();
			for (field in data) {
				var field : String = cast field;
				var delimPos = field.indexOf(":");
				var fieldName = field.substr(0, delimPos);
				var fieldData = field.substr(delimPos+1);

				var subdata : Dynamic = null;
				try {
					subdata = haxe.Json.parse(fieldData);
				}
				catch (_) {

				}

				if (subdata != null) {
					map.set(fieldName, subdata);
				}
			}

			for (field in fields) {
				@:privateAccess var accesses = field.getAccesses();
				for (a in accesses) {
					if (map.exists(a.name)) {
						@:privateAccess field.propagateValueChange(map.get(a.name), true);
						field.onChange(true);
					}
				}
			}

			return true;
		}
		return false;
	}

	function fillProps(edit : SceneEditorContext, e : PrefabElement, others: Array<PrefabElement> ) {
		properties.element.append(new Element('<h1 class="prefab-name">${e.getHideProps().name}</h1>'));

		var copyButton = new Element('<fancy-button title="Copy all properties">').append(new Element('<div class="icon ico ico-copy">'));

		function copyData() {
				var groupData = {};
				for (groupName => group in edit.properties.groups) {
					if (group.serialize != null) {
						var data = group.serialize();
						Reflect.setProperty(groupData, groupName, data);
					}
				}
				ide.setClipboard(haxe.Serializer.run({properties: "copy", data: groupData}));
		}
		copyButton.click(function(event : js.jquery.Event) { copyData(); });
		properties.element.append(copyButton);

		var pasteButton = new Element('<fancy-button title="Paste values from the clipboard">').append(new Element('<div class="icon ico ico-paste">'));

		function pasteData() {
			var res = try haxe.Unserializer.run(ide.getClipboard()) catch (e) null;
			if (res == null || res.properties != "copy")
				return;

			var tmpUndo = new hide.ui.UndoHistory();
			for (groupName => group in edit.properties.groups) {
				var groupData = Reflect.getProperty(res.data, groupName);
				if (groupData == null || group.pasteFn == null)
					continue;
				group.pasteFn(false, tmpUndo, groupData);
			}

			undo.change(tmpUndo.toElement());

			refreshProps();
		}
		pasteButton.click(function(event : js.jquery.Event) {
			pasteData();
		});
		properties.element.append(pasteButton);

		edit.properties.multiPropsEditor.clear();

		if (Type.getClass(e) == hrt.prefab.Prefab && others != null) {
			properties.add(new hide.Element('<p>The selected prefabs are too different to be multi edited</p>'));
			return;
		}

		try {
			if (others != null) {
				for (prefab in others) {
					var multiProps = new hide.comp.PropsEditor(null, null, new Element("<div>"));
					multiProps.isShadowEditor = true;
					edit.properties.multiPropsEditor.push(multiProps);
					var ctx = new SceneEditorContext([prefab], this);
					ctx.properties = multiProps;
					ctx.scene = this.scene;
					prefab.edit(ctx);
				}
			}
			e.edit(edit);
		} catch (e) {
			if (others != null) {
				// Multi edit non intrusive error
				properties.clear();
				var msg = e.toString();
				msg = StringTools.replace(msg, '\n', '</br>');
				var selection = [for (o in others) Type.getClassName(Type.getClass(o))].join(", ");
				var stack = e.stack.toString();
				stack = ~/\(chrome-extension:.*\)/g.replace(stack, "");
				stack = StringTools.replace(stack, '\n', '</br>');
				properties.add(new hide.Element('<p>Multi edit error</p><p>Selection : $selection</p><p>$msg</p><p>$stack</p>'));
				return;
			}
			throw e;
		}



		var typeName = e.getCdbType();
		if( typeName == null && e.props != null )
			return; // don't allow CDB data with props already used !

		var types = DataFiles.getAvailableTypes();
		if( types.length == 0 )
			return;

		var group = new hide.Element('
			<div class="group" name="CDB">
				<dl>
				<dt>
					<div class="btn-cdb-large ico ico-file-text" title="Detach panel"></div>
					Type
				</dt>
				<dd><select><option value="">- No props -</option></select></dd>
			</div>
		');

		var cdbLarge = @:privateAccess view.getDisplayState("cdbLarge");
		var detachable = new hide.comp.DetachablePanel();
		detachable.saveDisplayKey = "detachedCdb";
		group.find(".btn-cdb-large").click((_) -> {
			cdbLarge = !cdbLarge;
			@:privateAccess view.saveDisplayState("cdbLarge", cdbLarge);
			group.toggleClass("cdb-large", cdbLarge);
			detachable.setDetached(cdbLarge);
		});
		group.toggleClass("cdb-large", cdbLarge == true);
		detachable.setDetached(cdbLarge == true);

		var select = group.find("select");
		for(t in types) {
			var id = DataFiles.getTypeName(t);
			new hide.Element("<option>").attr("value", id).text(id).appendTo(select);
		}

		var curType = DataFiles.resolveType(typeName);
		if(curType != null) select.val(DataFiles.getTypeName(curType));

		function changeProps(props: Dynamic) {
			properties.undo.change(Field(e, "props", e.props), ()->edit.rebuildProperties());
			e.props = props;
			edit.onChange(e, "props");
			edit.rebuildProperties();
		}

		select.change(function(v) {
			var typeId = select.val();
			if(typeId == null || typeId == "") {
				changeProps(null);
				return;
			}
			var props = makeCdbProps(e, DataFiles.resolveType(typeId));
			changeProps(props);
		});

		properties.add(group);

		if(curType != null) {
			var props = new hide.Element('<div></div>').appendTo(group.find(".content"));
			var fileRef = view.state.path;
			detachable.element.appendTo(props);
			var editor = new hide.comp.cdb.ObjEditor(curType, view.config, e.props, fileRef, detachable.element);
			editor.onScriptCtrlS = function() {
				view.save();
			}
			editor.undo = properties.undo;
			editor.fileView = view;

			editor.onChange = function(pname) {
				edit.onChange(e, 'props.$pname');
				var e = Std.downcast(e, Object3D);
				if( e != null ) {
					e.addEditorUI();
				}
			}
		}
	}

	function makeEditContext(elts : Array<PrefabElement>) : SceneEditorContext {
		var edit : SceneEditorContext = new SceneEditorContext(elts, this);

		edit.rootPrefab = sceneData;
		edit.properties = properties;
		edit.scene = scene;
		return edit;
	}

	public function showProps(e: PrefabElement) {
		scene.setCurrent();
		var edit = makeEditContext([e]);
		properties.clear();
		fillProps(edit, e, null);
	}

	function setElementSelected( p : PrefabElement, b : Bool ) {
		if( customEditor != null && !customEditor.setElementSelected(p, b) )
			return false;
		return p.setSelected(b);
	}

	public dynamic function onSelectionChanged(elts : Array<PrefabElement>, ?mode : SelectMode = Default) {};

	public function selectElements( elts : Array<PrefabElement>, ?mode : SelectMode = Default ) {
		function impl(elts,mode:SelectMode) {
			scene.setCurrent();
			if( curEdit != null )
				curEdit.cleanup();
			var edit = makeEditContext(elts);

			var doRefreshRenderProps = false;
			for (p in selectedPrefabs) {
				if (Std.downcast(p, hrt.prefab.RenderProps) != null) {
					doRefreshRenderProps = true;
					break;
				}
			}

			selectedPrefabs = elts;

			for (p in selectedPrefabs) {
				if (Std.downcast(p, hrt.prefab.RenderProps) != null && (p.shared.parentPrefab == null || p.shared.parentPrefab != renderPropsRoot)) {
					doRefreshRenderProps = true;
					break;
				}
			}

			if (elts.length == 0 || (customPivot != null && customPivot.elt != selectedPrefabs[0])) {
				customPivot = null;
			}
			properties.clear();
			if( elts.length > 0 ) {
				if (elts.length > 1) {
					var commonClass = hrt.tools.ClassUtils.getCommonClass(elts, hrt.prefab.Prefab);

					var proxyPrefab = Type.createInstance(commonClass, [null, new ContextShared()]);
					proxyPrefab.load(haxe.Json.parse(haxe.Json.stringify(elts[0].save())));
					fillProps(edit, proxyPrefab, elts);
				}
				else
				{
					fillProps(edit, elts[0], null);
				}
			}

			switch( mode ) {
				case Default, NoHistory:
					sceneTree.clearSelection();
					for (e in elts)
						sceneTree.selectItem(e, true, false);
				case Nothing, NoTree:
			}

			var map = new Map<PrefabElement,Bool>();
			function selectRec(e : PrefabElement, b:Bool) {
				if( map.exists(e) )
					return;
				map.set(e, true);
				if(setElementSelected(e, b))
					for( e in e.children )
						selectRec(e,b);
			}

			for( e in elts )
				selectRec(e, true);

			edit.cleanups.push(function() {
				for( e in map.keys() ) {
					if( hasBeenRemoved(e) ) continue;
					setElementSelected(e, false);
				}
			});

			curEdit = edit;
			showGizmo = false;
			for( e in elts )
				if( !isLocked(e) ) {
					showGizmo = true;
					break;
				}
			curEdit = edit;
			setupGizmo();

			refreshGuide2d();

			onSelectionChanged(elts, mode);

			if (doRefreshRenderProps) {
				queueRefreshRenderProps();
			}
		}

		var prev : Array<PrefabElement> = null;
		if( selectedPrefabs != null && mode.match(Default|NoTree) ) {
			prev = selectedPrefabs.copy();
			undo.change(Custom(function(u) {
				if(u) impl(prev,NoHistory);
				else impl(elts,NoHistory);
			}),true);
		}

		impl(elts,mode);
	}

	/**
		Select prefabs that are in a clone of sceneData
	**/
	public function selectElementsIndirect(elts : Array<PrefabElement>, ?mode : SelectMode = Default) {
		var toSelect : Array<PrefabElement> = [];
		var flat = sceneData.flatten();
		for (elt in elts) {
			var idx = elt.getRoot().flatten().indexOf(elt);
			var found = flat[idx];
			if (found != null)
				toSelect.push(found);
		}
		selectElements(toSelect, mode);
	}

	function hasBeenRemoved( e : hrt.prefab.Prefab ) {
		var root = e;

		if (root.shared != null && root.shared.parentPrefab != null) {
			if (hasBeenRemoved(root.shared.parentPrefab))
				return true;
			root = null;
		}

		while( e != null && e != root ) {
			if( e.parent != null && e.parent.children.indexOf(e) < 0 )
				return true;
			e = e.parent;
		}
		return e != root;
	}

	public function resetCamera(distanceFactor = 1.5) {
		if( camera2D ) {
			cameraController2D.initFromScene();
		} else {
			scene.s3d.camera.zNear = scene.s3d.camera.zFar = 0;
			scene.s3d.camera.fovY = 60; // reset to default fov
			scene.resetCamera(distanceFactor);
			cameraController.lockZPlanes = scene.s3d.camera.zNear != 0;
			cameraController.loadFromCamera();
		}
	}

	var previewDraggedObj : h3d.scene.Object;
	public function onDropEvent(event: hide.tools.DragAndDrop.DropEvent, dragData : hide.tools.DragAndDrop.DragData) : Void {
		switch(event) {
			case Move:
				var files : Array<hide.tools.FileManager.FileEntry> = dragData.data.get("drag/filetree");

				if (files == null || files.length <= 0) {
					dragData.dropTargetValidity = ForbidDrop;
					return;
				}


				if (previewDraggedObj == null) {
					try {
						previewDraggedObj = getPreviewObject(files);
						scene.s3d.addChild(previewDraggedObj);
						dragData.setThumbnailVisiblity(false);
					} catch (e) {
						dragData.dropTargetValidity = ForbidDrop;
						return;
					}
				}

				// Do not update every frame because it can be very heavy on large prefabs
				if (hxd.Timer.frameCount % 2 != 0)
					return;
				// previewDraggedObj.setTransform();
				previewDraggedObj.setTransform(getDragPreviewTransform());
			case Enter:
			case Leave:
				previewDraggedObj?.remove();
				previewDraggedObj = null;
			case Drop:
				var files : Array<hide.tools.FileManager.FileEntry> = dragData.data.get("drag/filetree");
				if (files == null || files.length <= 0)
					return;

				var supported = @:privateAccess hrt.prefab.Prefab.extensionRegistry;
				var paths = [];
				for (f in files) {
					var ext = haxe.io.Path.extension(f.path).toLowerCase();
					if( supported.exists(ext) || ext == "fbx" || ext == "hmd" || ext == "json")
						paths.push(f.path);
				}

				var elts : Array<hrt.prefab.Prefab> = [];
				for (path in paths) {
					var prefab = createDroppedElement(path, sceneData, dragData.shiftKey);
					if (prefab == null)
						continue;
					var obj3d = Std.downcast(prefab, Object3D);
					if (obj3d != null)
						obj3d.setTransform(getDragPreviewTransform());
					elts.push(prefab);
				}

				beginRebuild();
				for(e in elts)
					queueRebuild(e);
				endRebuild();

				refreshTree(SceneTree, () -> selectElements(elts, NoHistory));

				undo.change(Custom(function(undo) {
					if( undo ) {
						beginRebuild();
						for(e in elts) {
							removeInstance(e);
							e.parent.children.remove(e);
						}
						endRebuild();
						refreshTree(SceneTree, () -> selectElements([], NoHistory));
					}
					else {
						beginRebuild();
						for(e in elts) {
							e.parent.children.push(e);
							makePrefab(e);
						}
						endRebuild();
						refreshTree(SceneTree, () -> selectElements(elts, NoHistory));
					}
				}));
		}
	}

	function getPreviewObject(files : Array<hide.tools.FileManager.FileEntry>) : h3d.scene.Object {
		var root = new h3d.scene.Object();

		for (f in files) {
			var ptype = hrt.prefab.Prefab.getPrefabType(f.path);
			if (ptype != null) {
				var ref = new hrt.prefab.Reference(null, sceneData.shared);
				ref.source = ide.makeRelative(f.path);
				ref.make();
				if (ref.local3d != null)
					root.addChild(ref.local3d);
			}

			if (f.path.substr(f.path.lastIndexOf(".") + 1) == "fbx") {
				var mesh = sceneData.shared.loadModel(ide.makeRelative(f.path));
				root.addChild(mesh);
			}
		}

		return root;
	}

	function getDragPreviewTransform() : h3d.Matrix {
		var transform = new h3d.Matrix();
		transform.identity();

		var camera = scene.s3d.camera;
		var ray = camera.rayFromScreen(scene.s2d.mouseX, scene.s2d.mouseY);

		var minDist = -1.;
		var hitObj : h3d.scene.Object = null;
		for (obj in scene.s3d) {
			function get(obj : Object) {
				if (obj == previewDraggedObj || Std.isOfType(obj, hrt.tools.Gizmo))
					return;
				if (!obj.getBounds().inFrustum(camera.frustum))
					return;

				try {
					var dist = obj.getCollider().rayIntersection(ray, true);
					if (minDist < 0 || (dist >= 0 && dist < minDist)) {
						minDist = dist;
						hitObj = obj;
					}
				}
				catch (e : Dynamic) {};

				for (c in @:privateAccess obj.children)
					get(c);
			}

			get(obj);
		}

		if (minDist >= 0) {
			// Find hit normal
			var center = ray.getPoint(minDist);
			var dx : h3d.col.Point = null;
			var dy : h3d.col.Point = null;
			var ray2 = camera.rayFromScreen(scene.s2d.mouseX + 1, scene.s2d.mouseY);
			dx = ray2.getPoint(hitObj.getCollider().rayIntersection(ray2, true));

			var ray3 = camera.rayFromScreen(scene.s2d.mouseX - 1, scene.s2d.mouseY + 1);
			dy = ray3.getPoint(hitObj.getCollider().rayIntersection(ray3, true));

			var ddx = dx - center;
			var ddy = dy - center;
			var norm = ddx.cross(ddy);
			norm.normalize();

			if (ide.ideConfig.orientMeshOnDrag) {
				var q = new h3d.Quat();
				q.initMoveTo(new h3d.Vector(0, 0, 1), norm);
				transform = q.toMatrix();
			}
			else {
				transform = new h3d.Matrix();
				transform.identity();
			}

			transform.setPosition(center);
			return transform;
		}

		// If there is no collision with objects, try to collide with z=0 plane
		var zPlane = h3d.col.Plane.Z(0);
		var pt = ray.intersect(zPlane);
		if (pt != null) {
			transform.setPosition(pt);
			return transform;
		}

		transform.setPosition(ray.getPoint(minDist));
		return transform;
	}

	function createDroppedElement(path: String, parent: PrefabElement, inlinePrefab : Bool) : hrt.prefab.Prefab {
		var prefab : hrt.prefab.Prefab = null;
		var relative = ide.makeRelative(path);

		var ptype = hrt.prefab.Prefab.getPrefabType(path);
		var index = parent.children.length;
		if (ptype == "shgraph") {
			var p = parent;
			while (p != null && Std.downcast(p, Object3D) == null && Std.downcast(p, Object2D) == null && Std.downcast(p, hrt.prefab.Material) == null) {
				index = (p.parent?.children.indexOf(p) ?? 0 ) + 1;
				p = p.parent;
			}
			parent = p;
			if (parent == null) {
				ide.quickError("Please drop the shadergraph on a valid parent in the scene tree");
				return null;
			}

			var shgraph = new hrt.prefab.DynamicShader(null, null);
			shgraph.source = relative;
			shgraph.name = new haxe.io.Path(relative).file;
			prefab = shgraph;
		}
		else if(ptype != null) {
			// Inline reference if shift is held
			if (inlinePrefab) {
				var inlineRef = hxd.res.Loader.currentInstance.load(relative).toPrefab().load();
				// create a root group
				var root = new hrt.prefab.Object3D(null, parent.shared);

				// attach all the children of the loaded reference to the root
				for (child in inlineRef.children) {
					child.clone(root);
				}

				prefab = root;
			} else {
				var ref = new hrt.prefab.Reference(null, null);
				ref.source = relative;

				prefab = ref;
			}

			prefab.name = new haxe.io.Path(relative).file;
		}
		else if(haxe.io.Path.extension(path).toLowerCase() == "json") {
			prefab = new hrt.prefab.l3d.Particles3D(null, null);
			prefab.source = relative;
			prefab.name = new haxe.io.Path(relative).file;
		}
		else {
			var model = new hrt.prefab.Model(null, null);
			model.source = relative;
			prefab = model;
		}

		if (prefab == null)
			return null;

		prefab.parent = parent;
		parent.children.remove(prefab);
		parent.children.insert(index, prefab);

		var ref = Std.downcast(prefab, Reference);
		if (ref != null && (ref.hasCycle() || ref.source == @:privateAccess view.state.path) ) {
			parent.children.remove(ref);
			hide.Ide.inst.quickError('Reference to $relative is creating a cycle. The reference creation was aborted.');
			return null;
		}

		autoName(prefab);
		return prefab;
	}



	public function getPickTransform(parent: PrefabElement) {
		var proj = screenToGround(scene.s2d.mouseX, scene.s2d.mouseY);
		if(proj == null) return null;

		var localMat = new h3d.Matrix();
		localMat.initTranslation(proj.x, proj.y, proj.z);

		if(parent == null)
			return localMat;

		var parentMat = worldMat(getObject(parent));
		parentMat.invert();

		localMat.multiply(localMat, parentMat);
		return localMat;
	}

	function gatherToMouse() {
		var prevParent = sceneData;
		var localMat = getPickTransform(prevParent);
		if( localMat == null ) return;

		var objects3d = [for(o in selectedPrefabs) {
			var obj3d = o.to(hrt.prefab.Object3D);
			if( obj3d != null && !obj3d.locked )
				obj3d;
		}];
		if( objects3d.length == 0 ) return;

		var sceneObjs = [for(o in objects3d) o.getLocal3d()];
		var prevState = [for(o in objects3d) o.saveTransform()];

		for( obj3d in objects3d ) {
			if( obj3d.parent != prevParent ) {
				prevParent = obj3d.parent;
				localMat = getPickTransform(prevParent);
			}
			if( localMat == null ) continue;
			obj3d.x = hxd.Math.round(localMat.tx * 10) / 10;
			obj3d.y = hxd.Math.round(localMat.ty * 10) / 10;
			obj3d.z = hxd.Math.floor(localMat.tz * 10) / 10;
			obj3d.updateInstance();
		}
		var newState = [for(o in objects3d) o.saveTransform()];
		refreshProps();
		undo.change(Custom(function(undo) {
			if( undo ) {
				for(i in 0...objects3d.length) {
					objects3d[i].loadTransform(prevState[i]);
					objects3d[i].applyTransform();
				}
				refreshProps();
			}
			else {
				for(i in 0...objects3d.length) {
					objects3d[i].loadTransform(newState[i]);
					objects3d[i].applyTransform();
				}
				refreshProps();
			}
			for(o in objects3d)
				o.updateInstance();
		}));
	}

	function canGroupSelection() {
		var elts = selectedPrefabs;
		if(elts.length == 0)
			return false;

		if(elts.length == 1)
			return true;

		// Only allow grouping of sibling elements
		var parent = elts[0].parent;
		for(e in elts)
			if(e.parent != parent)
				return false;

		return true;
	}

	function canExportSelection() {
		var elts = curEdit.rootElements;
		if(elts.length == 0)
			return false;

		// Only allow export of sibling element
		var parent = elts[0].parent;
		for(e in elts)
			if(e.parent != parent)
				return false;

		return true;
	}

	function exportSelection(?params : Dynamic) {
		// Handle the export of selection into a fbx file
		Ide.inst.chooseFileSave("Export.fbx", function(filePath) {
			new hxd.fmt.fbx.Writer(null).export(
				[for (p in curEdit.elements) p.getLocal3d()],
				Ide.inst.getPath(filePath),
				() -> Ide.inst.message('Successfully exported object at path : ${filePath}'),
				params);
		});
	}

	function groupSelection() {
		if(!canGroupSelection()) {
			return;
		  }

		// Sort the selection to match the scene order
		var elts : Array<hrt.prefab.Prefab> = [];

		for (p in sceneData.flatten()) {
			if (selectedPrefabs.contains(p))
				elts.push(p);
		}

		var any2d = elts.find((f) -> Std.downcast(f, Object2D) != null) != null;
		var any3d = elts.find((f) -> Std.downcast(f, Object3D) != null) != null;

		var parent = elts[0].parent;

		var group : hrt.prefab.Prefab = null;
		if (any2d && !any3d) {
			var parentMat = worldMat2d(parent);
			var invParentMat = parentMat.clone();
			invParentMat.invert();

			var pivot = new h2d.col.Point();
			{
				var count = 0;
				for (elt in selectedPrefabs) {
					var m = worldMat2d(elt);
					if (m != null) {
						pivot.add(m.getPosition());
						 ++count;
					}
				}
			}

			var local = new h2d.col.Matrix();
			local.initTranslate(pivot.x, pivot.y);
			local.multiply(local, invParentMat);

			var group2d = new Object2D(parent, null);
			group = group2d;
			autoName(group);
			group2d.x = local.x;
			group2d.y = local.y;
		}
		else {
			var parentMat = worldMat(parent);
			var invParentMat = parentMat.clone();
			invParentMat.invert();

			var pivot = new h3d.Vector();
			{
				var count = 0;
				for(elt in selectedPrefabs) {
					var m = worldMat(elt);
					if(m != null) {
						pivot = pivot.add(m.getPosition());
						++count;
					}
				}
				pivot.scale(1.0 / count);
			}
			var local = new h3d.Matrix();
			local.initTranslation(pivot.x, pivot.y, pivot.z);
			local.multiply(local, invParentMat);

			var group3d = new hrt.prefab.Object3D(parent, null);
			group = group3d;
			autoName(group);
			group3d.x = local.tx;
			group3d.y = local.ty;
			group3d.z = local.tz;
		}


		group.shared.current2d = parent.findFirstLocal2d();
		group.shared.current3d = parent.findFirstLocal3d();
		group.make();

		var effectFunc = reparentImpl(elts, group, 0);
		undo.change(Custom(function(undo) {
			if(undo) {
				effectFunc(true);
				group.parent = null;
			}
			else {
				group.parent = parent;
				effectFunc(false);
			}
			if(undo)
				refreshTree(SceneTree, ()->selectElements([],NoHistory));
			else
				refreshTree(SceneTree, ()->selectElements([group],NoHistory));
		}));
		effectFunc(false);
	}

	// Restore child transform after reset / move only parent transform
	function restoreChildTransform(obj3d : Object3D, prevTransform : h3d.Matrix) {
		var newTransform = obj3d.getTransform();
		newTransform.invert();
		prevTransform.multiply(prevTransform, newTransform);
		var scale = prevTransform.getScale();
		if ( scale.x != scale.y || scale.x != scale.z ) {
			ide.quickError("Parent scale is not uniform, the resulting transformation may not be accurate.");
		}
		for( c in obj3d.children ) {
			var c3d = c.to(Object3D);
			if( c3d != null ) {
				var newPos = c3d.getTransform();
				newPos.multiply(newPos, prevTransform);
				c3d.setTransform(newPos);
				c3d.applyTransform();
				if ( curEdit != null )
					curEdit.onChange(c3d, null);
			}
		}
	}

	function resetTransform(elts : Array<PrefabElement>) {
		if(elts == null) return;
		var pivot = new h3d.Matrix();
		pivot.identity();
		var objects3d = [for(o in elts) { var obj3d = o.to(hrt.prefab.Object3D); if(obj3d != null) obj3d; }];
		var prevState = [for(o in objects3d) o.saveTransform()];
		function doReset(undo) {
			for(i in 0...objects3d.length) {
				var obj3d = objects3d[i];
				var prevTrans = obj3d.getTransform();
				if( undo ) {
					obj3d.loadTransform(prevState[i]);
				} else {
					obj3d.setTransform(pivot);
				}
				obj3d.applyTransform();
				restoreChildTransform(obj3d, prevTrans);
				if ( curEdit != null )
					curEdit.onChange(obj3d, null);
			}
			refreshProps();
		}
		doReset(false);
		undo.change(Custom(doReset));
	}

	function onCopy() {
		if(selectedPrefabs == null) return;

		var ser : Array<String> = [];
		for (prefab in selectedPrefabs) {
			ser.push(prefab.serialize());
		}

		view.setClipboard(Ide.inst.toJSON(ser), "prefab", {source : view.state.path});
	}

	function getDataPath( prefabName : String, ?sourceFile : String ) {
		if( sourceFile == null ) sourceFile = view.state.path;
		var datPath = new haxe.io.Path(sourceFile);
		datPath.ext = "dat";
		return ide.getPath(datPath.toString()+"/"+prefabName);
	}

	function onPaste() {
		var parent : PrefabElement = sceneData;
		if(selectedPrefabs != null && selectedPrefabs.length > 0) {
			parent = selectedPrefabs[0];
		}

		var opts : { ref : {source:String} } = { ref : null };
		var objs : Array<Dynamic> = haxe.Json.parse(view.getClipboard("prefab",opts));
		if (objs == null)
			return;

		var createdPrefabs : Array<hrt.prefab.Prefab> = [];
		for(obj in objs) {
			if (!Reflect.hasField(obj, "type"))
				continue;

			var p = hrt.prefab.Prefab.createFromDynamic(obj, parent);
			p.shared.current2d = parent.findFirstLocal2d();
			p.shared.current3d = parent.findFirstLocal3d();
			var prevName = p.name;
			autoName(p);
			createdPrefabs.push(p);

			if( opts.ref != null && opts.ref.source != null && prevName != null ) {
				// copy data

				var srcDir = getDataPath(prevName, opts.ref.source);

				if( sys.FileSystem.exists(srcDir) && sys.FileSystem.isDirectory(srcDir) ) {
					var dstDir = getDataPath(p.name);
					function copyRec( src : String, dst : String ) {
						if( !sys.FileSystem.exists(dst) ) sys.FileSystem.createDirectory(dst);
						for( f in sys.FileSystem.readDirectory(src) ) {
							var file = src+"/"+f;
							if( sys.FileSystem.isDirectory(file) ) {
								copyRec(file,dst+"/"+f);
								continue;
							}
							sys.io.File.copy(file,dst+"/"+f);
						}
					}
					copyRec(srcDir, dstDir);
				}
			}
		}

		addElements(createdPrefabs);
	}

	public function isVisible(elt: PrefabElement) {
		if(elt == sceneData)
			return true;
		var visible = elt.to(Object3D)?.visible || elt.to(Object2D)?.visible;
		return visible && !isHidden(elt) && (elt.parent != null ? isVisible(elt.parent) : true);
	}

	public function getAllSelectable(include3d: Bool, include2d: Bool) : Array<PrefabElement> {
		var ret = [];

		function rec(prefab: PrefabElement) {
			if (prefab == null)
				return;

			var o3d = prefab.to(Object3D);
			var o2d = prefab.to(Object2D);

			var visible = if (o3d != null) {
				o3d.visible;
			} else if (o2d != null) {
				o2d.visible;
			} else true;

			if (!visible || isHidden(prefab))
				return;
			if (!isLocked(prefab)) {
				if (interactives.get(prefab) != null) ret.push(prefab)
				else if (interactives2d.get(prefab) != null) ret.push(prefab);
			}

			for (child in prefab.children) {
				rec(child);
			}

			var ref = Std.downcast(prefab, Reference);
			if (ref != null && ref.editMode != None) {
				rec(ref.refInstance);
			}
		}

		rec(sceneData);

		return ret;
	}

	public function selectAll() {
		selectElements(getAllSelectable(true, false));
	}

	public function selectInvert() {
		var all = sceneData.flatten();
		all = all.filter((prefab) -> !selectedPrefabs.contains(prefab));
		selectElements(all);
	}

	public function deselect() {
		selectElements([]);
	}

	public function isSelected( p : PrefabElement ) {
		return selectedPrefabs != null && selectedPrefabs.indexOf(p) >= 0;
	}

	public function setEnabled(elements : Array<PrefabElement>, enable: Bool) {
		var old = [for(e in elements) e.enabled];
		function apply(on) {
			beginRebuild();
			for(i in 0...elements.length) {
				elements[i].enabled = on ? enable : old[i];
				onPrefabChange(elements[i]);
				queueRebuild(elements[i]);
			}
			endRebuild();
		}
		apply(true);
		undo.change(Custom(function(undo) {
			if(undo)
				apply(false);
			else
				apply(true);
		}));
	}

	public function setEditorOnly(elements : Array<PrefabElement>, enable: Bool) {
		var old = [for(e in elements) e.editorOnly];
		function apply(on) {
			beginRebuild();
			for(i in 0...elements.length) {
				elements[i].editorOnly = on ? enable : old[i];
				onPrefabChange(elements[i]);
				queueRebuild(elements[i]);
			}
			endRebuild();
		}
		apply(true);
		undo.change(Custom(function(undo) {
			if(undo)
				apply(false);
			else
				apply(true);
		}));
	}

	public function setInGameOnly(elements : Array<PrefabElement>, enable: Bool) {
		var old = [for(e in elements) e.inGameOnly];
		function apply(on) {
			beginRebuild();
			for(i in 0...elements.length) {
				elements[i].inGameOnly = on ? enable : old[i];
				onPrefabChange(elements[i]);
				queueRebuild(elements[i]);
			}
			endRebuild();
		}
		apply(true);
		undo.change(Custom(function(undo) {
			if(undo)
				apply(false);
			else
				apply(true);
		}));
	}

	public function isHidden(e: PrefabElement) {
		if(e == null)
			return false;
		return hideList.exists(e);
	}

	public function isLocked(e: PrefabElement) {
		while( e != null ) {
			if( e.locked ) return true;
			e = e.parent;
		}
		return false;
	}

	function saveDisplayState() {
		var state = [for (h in hideList.keys()) h.getAbsPath(true, true)];
		@:privateAccess view.saveDisplayState("hideList", state);
	}

	public function setVisible(elements : Array<PrefabElement>, visible: Bool) {
		function exec(undo : Bool) {
			for(o in elements) {
				for(c in o.flatten(hrt.prefab.Prefab)) {
					if (visible)
						undo ? hideList.set(o, true) : hideList.remove(c);
					else
						undo ?  hideList.remove(c) : hideList.set(o, true);
					applySceneStyle(c);
					refreshTreeStyle(c, All);
					if (Std.downcast(c, hrt.prefab.RenderProps) != null)
						queueRefreshRenderProps();
				}
			}
			saveDisplayState();
		}

		exec(false);
		undo.change(Custom(exec), null, true);
	}

	public function setLock(elements : Array<PrefabElement>, locked: Bool, enableUndo : Bool = true) {
		var elements = elements.copy();
		var prev = [for( o in elements ) o.locked];
		for(o in elements) {
			o.locked = locked;
			for( c in o.all()) {
				applySceneStyle(c);
				refreshTreeStyle(c, All);
				toggleInteractive(c,!isLocked(c));
			}
		}
		if (enableUndo) {
			undo.change(Custom(function(isUndo) {
				for( i in 0...elements.length )
					elements[i].locked = !isUndo ? locked : prev[i];
				queueRebuild(sceneData);
				refreshTree(SceneTree);
				saveDisplayState();
				showGizmo = !isUndo ? !locked : locked;
				moveGizmoToSelection();
			}));
		}

		saveDisplayState();
		showGizmo = !locked;
		moveGizmoToSelection();
	}

	function isolate(elts : Array<PrefabElement>) {
		var toShow = elts.copy();
		var toHide = [];
		function hideSiblings(elt: PrefabElement) {
			var p = elt.parent;
			for(c in p.children) {
				var needsVisible = c == elt || toShow.indexOf(c) >= 0 || hasChild(c, toShow);
				if(!needsVisible) {
					toHide.push(c);
				}
			}
			if(p != sceneData) {
				hideSiblings(p);
			}
		}
		for(e in toShow) {
			hideSiblings(e);
		}
		setVisible(toHide, false);
	}

	var isDuplicating = false;
	function duplicate(thenMove: Bool) {
		if(selectedPrefabs == null) return;
		var elements = selectedPrefabs;
		if(elements == null || elements.length == 0)
			return;
		if( isDuplicating )
			return;
		isDuplicating = true;
		if( gizmo.moving ) {
			@:privateAccess gizmo.finishMove();
		}
		var undoes = [];
		var newElements = [];
		var lastElem = elements[elements.length-1];
		var lastIndex = lastElem.parent.children.indexOf(lastElem);
		beginRebuild();
		for(i => elt in elements) {
			@:pirvateAccess var clone = hrt.prefab.Prefab.createFromDynamic(haxe.Json.parse(Ide.inst.toJSON(elt.serialize())), null, elt.parent.shared);
			var index = lastIndex+1+i;
			elt.parent.children.insert(index, clone);
			@:bypassAccessor clone.parent = elt.parent;
			autoName(clone);

			queueRebuild(clone);

			newElements.push(clone);

			var all = clone.flatten();
			for (p in all) {
				refreshInteractive(p);
			}

			onPrefabChange(elt.parent, "children");

			undoes.push(function(undo) {
				if(undo) elt.parent.children.remove(clone);
				else elt.parent.children.insert(index, clone);
				onPrefabChange(elt.parent, "children");
			});
		}
		endRebuild();

		refreshTree(SceneTree, function() {
			selectElements(newElements, NoHistory);
			if(thenMove && selectedPrefabs.length > 0) {
				if (!gizmo.moving) {
					gizmo.startMove(MoveXY, true);
					gizmo.onFinishMove = function() {
						refreshProps();
						setupGizmo();
					}
				}
			}
			isDuplicating = false;
		});
		gizmo.translationMode();

		var prevSelection = selectedPrefabs.copy();
		undo.change(Custom(function(undo) {
			for(u in undoes) u(undo);

			if(undo) {
				beginRebuild();
				for(elt in newElements) {
					removeInstance(elt);
				}
				endRebuild();
			}

			if(!undo) {
				beginRebuild();
				for(elt in newElements)
					makePrefab(elt);
				endRebuild();
			}

			refreshTree(SceneTree, () -> selectElements(undo ? prevSelection : newElements, NoHistory));
		}));
	}

	function setTransform(elt: PrefabElement, ?mat: h3d.Matrix, ?position: h3d.Vector) {
		var obj3d = Std.downcast(elt, hrt.prefab.Object3D);
		if(obj3d == null)
			return;
		if(mat != null) {
			obj3d.loadTransform(makeTransform(mat));
		}
		else {
			obj3d.x = roundSmall(position.x);
			obj3d.y = roundSmall(position.y);
			obj3d.z = roundSmall(position.z);
		}
		obj3d.updateInstance();
	}

	public function deleteElements(elts : Array<PrefabElement>, ?then: Void->Void, doRefresh : Bool = true, enableUndo : Bool = true) {
		var undoes = [];
		beginRebuild();
		var uniqueParents : Map<PrefabElement, Bool> = [];
		for(elt in elts) {
			var parent = elt.parent;
			var index = elt.parent.children.indexOf(elt);
			removeInstance(elt);
			parent.children.remove(elt);
			uniqueParents.set(parent, true);
			undoes.unshift(function(undo) {
				if(undo) elt.parent.children.insert(index, elt);
				else elt.parent.children.remove(elt);
				onPrefabChange(elt.parent, "children");
			});
		}

		if (doRefresh) {
			for (parent => _ in uniqueParents) {
				onPrefabChange(parent, "children");
			}
		}

		endRebuild();

		if (doRefresh) {
			refreshTree(SceneTree, () -> selectElements([], NoHistory));
		}

		if (enableUndo) {
			undo.change(Custom(function(undo) {
				beginRebuild();
				if(!undo)
					for(e in elts) removeInstance(e);

				for(u in undoes) u(undo);

				if(undo)
					for(e in elts) rebuild(e);
				endRebuild();
				if (doRefresh) {
					refreshTree(SceneTree, () -> selectElements(undo ? elts : [], NoHistory));
				}
			}));
		}
	}

	function reparentElement(e : Array<PrefabElement>, to : PrefabElement, index : Int) {
		if( to == null )
			to = sceneData;
		if (e.length == 0)
			return;

		var ref = Std.downcast(to, Reference);
		@:privateAccess if( ref != null && ref.editMode != None ) to = ref.refInstance;

		// Sort node based on where they appear in the scene tree
		var flat = sceneData.flatten();
		var prefabIndex : Map<hrt.prefab.Prefab, Int> = [];
		for (i => p in flat) {
			prefabIndex.set(p,i);
		}

		e.sort(function (a: hrt.prefab.Prefab, b: hrt.prefab.Prefab) : Int {
			return Reflect.compare(prefabIndex.get(a), prefabIndex.get(b));
		});

		var offset = 0;
		for (p in e)
			if (p.parent == to && p.parent.children.indexOf(p) < index)
				offset++;
		var targetIndex = index - offset;
		var exec = reparentImpl(e, to, targetIndex);
		undo.change(Custom(function(undo) {
			exec(undo);
		}));
		exec(false);
	}

	function roundSmall(f: Float) {
		var num = 10_000.0;
		var r = hxd.Math.round(f * num) / num;
		// Avoid rounding floats that are too big
		return hxd.Math.abs(r-f) < 2.0 / num ? r : f;
	}

	function makeTransform(mat: h3d.Matrix) {
		var rot = mat.getEulerAngles();
		var x = roundSmall(mat.tx);
		var y = roundSmall(mat.ty);
		var z = roundSmall(mat.tz);
		var s = mat.getScale();
		var scaleX = roundSmall(s.x);
		var scaleY = roundSmall(s.y);
		var scaleZ = roundSmall(s.z);
		var rotationX = roundSmall(hxd.Math.radToDeg(rot.x));
		var rotationY = roundSmall(hxd.Math.radToDeg(rot.y));
		var rotationZ = roundSmall(hxd.Math.radToDeg(rot.z));
		return { x : x, y : y, z : z, scaleX : scaleX, scaleY : scaleY, scaleZ : scaleZ, rotationX : rotationX, rotationY : rotationY, rotationZ : rotationZ };
	}

	function reparentImpl(prefabs: Array<PrefabElement>, toPrefab: PrefabElement, index: Int) : Bool -> Void {
		var effects = [];
		for(i => prefab in prefabs) {
			var prevParent = prefab.parent;
			var prevIndex = prevParent.children.indexOf(prefab);
			for (p in prefab.flatten(null, null))
				p.shared = toPrefab.shared;
			var obj3d = prefab.to(Object3D);
			var preserveTransform = Std.isOfType(toPrefab, hrt.prefab.fx.Emitter) || Std.isOfType(prevParent, hrt.prefab.fx.Emitter);
			var prevTransform = null;
			var newTransform = null;
			if(obj3d != null && !preserveTransform) {
				var mat = worldMat(prefab);
				var parentMat = worldMat(toPrefab);
				parentMat.invert();
				mat.multiply(mat, parentMat);
				prevTransform = obj3d.saveTransform();
				newTransform = makeTransform(mat);
			}

			var obj2d = prefab.to(Object2D);
			var prevTransform2d = null;
			var newTransform2d = null;
			if (obj2d != null && !preserveTransform) {
				var mat = worldMat2d(obj2d);
				var parentMat = worldMat2d(toPrefab);
				parentMat.invert();
				mat.multiply(mat, parentMat);
				prevTransform2d = obj2d.getTransformMatrix();
				newTransform2d = mat;
			}


			effects.push(function(undo) {
				if( undo ) {
					prefab.parent = prevParent;
					checkWantRebuild(toPrefab, prefab);

					prevParent.children.remove(prefab);
					prevParent.children.insert(prevIndex, prefab);

					if(obj3d != null && prevTransform != null)
						obj3d.loadTransform(prevTransform);
					if (obj2d != null && prevTransform2d != null)
						obj2d.setTransformMatrix(prevTransform2d);
				} else {
					@:bypassAccessor prefab.parent = toPrefab;
					checkWantRebuild(prevParent, prefab);

					prefab.shared = toPrefab.shared;
					toPrefab.children.insert(index + i, prefab);
					if(obj3d != null && newTransform != null)
						obj3d.loadTransform(newTransform);
					if (obj2d != null && newTransform2d != null)
						obj2d.setTransformMatrix(newTransform2d);
				};

				onPrefabChange(prevParent, "children");
				onPrefabChange(toPrefab, "children");
			});
		}

		function exec(undo: Bool) {
			beginRebuild();

			for (prefab in prefabs) {
				prefab.parent.children.remove(prefab);
			}

			for (effect in effects) {
				effect(undo);
			}

			for (prefab in prefabs) {
				queueRebuild(prefab);
			}

			endRebuild();

			refreshTree(All, () -> selectElements(selectedPrefabs, NoHistory));
		}

		return exec;
	}

	function checkWantRebuild(target: PrefabElement, original: PrefabElement) {
		if (target == null) return;
		var wantRebuild = target.onEditorTreeChanged(original);
		switch(wantRebuild) {
			case Skip:
				checkWantRebuild(target.parent, original);
			case Rebuild:
				queueRebuild(target);
			case Notify(callback):
				rebuildQueue.set(target, wantRebuild);
				checkWantRebuild(target.parent, original);
		}

		if (target == sceneData) {
			var renderProps = original.find(hrt.prefab.RenderProps, null, true, false);
			if (renderProps != null)
				queueRebuild(target);
		}
	}

	var rebuildQueue : Map<PrefabElement, hrt.prefab.Prefab.TreeChangedResult> = null;
	var rebuildEndCallbacks : Array<Void -> Void> = null;
	/** Indicate that this prefab neet do be rebuild**/
	public function queueRebuild(prefab: PrefabElement) {
		if (rebuildStack > 0)
			return;

		if (rebuildQueue != null && rebuildQueue.exists(prefab))
			return;

		var instant = false;
		if (rebuildQueue == null) {
			beginRebuild();
			instant = true;
		}

		var parent = prefab.parent;
		checkWantRebuild(parent, prefab);

		rebuildQueue.set(prefab, Rebuild);
		if (instant) {
			endRebuild();
		}
	}

	var queuedRefreshRenderProps = false;
	var queuedRenderProps : hrt.prefab.RenderProps = null;
	var refreshRenderPropsStack = 0;
	public function queueRefreshRenderProps(?rp: hrt.prefab.RenderProps) {
		if (refreshRenderPropsStack > 0)
			return;
		refreshRenderPropsStack ++;
		if (rebuildQueue == null) {
			setRenderProps(rp);
			refreshRenderPropsStack --;
			return;
		}

		queuedRefreshRenderProps = true;
		queuedRenderProps = rp;
		refreshRenderPropsStack --;
	}

	/** Register a callback that will be called once all the prefabs in this begin/endRebuild pair have been rebuild**/
	public function queueRebuildCallback(callback: Void -> Void) {
		if (rebuildEndCallbacks != null) {
			rebuildEndCallbacks.push(callback);
		}
		else {
			callback();
		}
	}

	var beginRebuildStack = 0;
	function beginRebuild() {
		beginRebuildStack++;
		if (beginRebuildStack > 1)
			return;
		rebuildQueue = [];
		rebuildEndCallbacks = [];
	}

	function endRebuild() {
		beginRebuildStack --;
		if (beginRebuildStack > 0)
			return;

		var sort2d : Map<h2d.Object, Bool> = [];
		for (prefab => want in rebuildQueue) {
			switch (want) {
				case Skip:
					continue;
				case Notify(callback):
					rebuildEndCallbacks.push(callback);
				case Rebuild:
					var parent = prefab.parent ?? prefab.shared.parentPrefab;
					var skip = false;

					// don't rebuild this prefab if it's parent will get rebuild anyways
					while(parent != null) {
						if (rebuildQueue.get(parent) == Rebuild) {
							skip = true;
							break;
						}

						var next = parent.parent ?? parent.shared.parentPrefab;
						if (next == null)
							break;

						if (!next.children.contains(parent) && Std.downcast(next, Reference)?.refInstance != parent) {
							skip = true;
						}
						parent = next;
					}

					if (skip == true)
						continue;

					// Rebuilding the root fx will cause it's play time to be reset.
					// so we compensate for that here
					var fxTime = 0.0;
					if (prefab == sceneData && Std.downcast(prefab, hrt.prefab.fx.FX) != null) {
						var fxAnimation : hrt.prefab.fx.FX.FXAnimation = cast prefab.findFirstLocal3d();
						if (fxAnimation != null) {
							fxTime = fxAnimation.localTime;
						}
					}

					rebuild(prefab);

					if (prefab == sceneData && Std.downcast(prefab, hrt.prefab.fx.FX) != null) {
						var fxAnimation : hrt.prefab.fx.FX.FXAnimation = cast prefab.findFirstLocal3d();
						if (fxAnimation != null) {
							fxAnimation.setTimeInternal(fxTime, 0, true, true);
						}
					}

					if (Std.downcast(prefab, Object2D) != null) {
						var parent2d = prefab.findFirstLocal2d()?.parent;
						if (parent2d != null) {
							sort2d.set(parent2d, true);
						}
					}
			}
		}

		for (callback in rebuildEndCallbacks) {
			callback();
		}

		if (sort2d.iterator().hasNext()) {
			var flat = sceneData.flatten();
			var indexes : Map<h2d.Object, Int> = [];
			for (index => prefab in flat) {
				var local2d = Std.downcast(prefab, Object2D)?.local2d;
				if (local2d != null) {
					indexes.set(local2d, index);
				}
			}

			for (toSort => _ in sort2d) {
				var children = @:privateAccess toSort.children.copy();
				children.sort((a, b) -> Reflect.compare(indexes.get(a), indexes.get(b)));

				for (child in children) {
					toSort.addChild(child);
				}
			}
		}

		if (queuedRefreshRenderProps) {
			setRenderProps(queuedRenderProps);
			queuedRenderProps = null;
			queuedRefreshRenderProps = false;
		}
		rebuildQueue = null;
		rebuildEndCallbacks = null;
	}

	var rebuildStack = 0;

	function checkIsInWorld(prefab: hrt.prefab.Prefab) : Bool {
		var current = prefab;

		// check each parent in the parent (or reference) chain to
		// see if the parent has the current prefab as a child (or reference)
		while(current != null && current != sceneData) {
			var parent = current.parent ?? current.shared.parentPrefab;
			if (parent == null)
				break;
			var inParent = parent.children.contains(current);
			if (!inParent) {
				var ref = Std.downcast(parent, hrt.prefab.Reference);
				if (ref != null) {
					if (current == ref.refInstance) {
						inParent = true;
					}
				}
			}

			if (!inParent) {
				return false;
			}
			current = parent;
		}
		return current == sceneData;
	}

	function rebuild(prefab: PrefabElement) {
		rebuildStack ++;
		scene.setCurrent();

		removeInstance(prefab, false);

		var enabled = prefab.enabled && !prefab.inGameOnly;

		var actuallyInWorld = checkIsInWorld(prefab);
		if (enabled && actuallyInWorld) {
			prefab.shared.current3d = prefab.parent?.findFirstLocal3d(true) ?? root3d;
			prefab.shared.current2d = prefab.parent?.findFirstLocal2d(true) ?? root2d;
			if (prefab.shared.current3d.getScene() == null)
				throw "current3d is not in scene";
			prefab.setEditor(this, this.scene);
			prefab.make();
		}

		for( p in prefab.flatten(null, null) ) {
			makeInteractive(p);
			applySceneStyle(p);

			// Enforce interactive not being actually interactive because we do our own event handling
			var i3d = interactives.get(p);
			if (i3d != null) i3d.propagateEvents = true;

			var i2d = interactives2d.get(p);
			if (i2d != null) i2d.propagateEvents = true;
		}

		rebuildStack --;
	}

	function customMake(p: hrt.prefab.Prefab) {
		if (Std.downcast(p, Object3D) == null && Std.downcast(p, Object2D) == null && isHidden(p)) {
			return;
		}
		p.make(p.shared);
	}

	function isMatLib() {
		var prefabView = Std.downcast(view, hide.view.Prefab);
		return prefabView != null && @:privateAccess prefabView.matLibPath != null && @:privateAccess prefabView.matLibPath != "";
	}

	function autoName(p : PrefabElement) {
		var uniqueName = false;

		if( p.type == "volumetricLightmap" || p.type == "light" )
			uniqueName = true;

		if( !uniqueName && p.name != null && p.name.length > 0 && sys.FileSystem.exists(getDataPath(p.name)) )
			uniqueName = true;

		var mat = Std.downcast(p, hrt.prefab.Material);
		uniqueName = !uniqueName && mat != null && mat.parent == sceneData.getRoot() && isMatLib();

		var prefix = null;
		if(p.name != null && p.name.length > 0) {
			if(uniqueName)
				prefix = ~/_+[0-9]+$/.replace(p.name, "");
			else
				prefix = p.name;
		}
		else
			prefix = p.getDefaultEditorName();

		if(uniqueName) {
			prefix += "_";
			var id = 0;
			while( sceneData.find(hrt.prefab.Prefab, (p) -> p.name == prefix + id) != null )
				id++;

			p.name = prefix + id;
		}
		else
			p.name = prefix;

		for(c in p.children) {
			autoName(c);
		}
	}

	function update(dt:Float) {
		saveCam3D();

		if (camera2D) {
			var save = { x : root2d.x - scene.s2d.width*0.5, y : root2d.y - scene.s2d.height*0.5, z : root2d.scaleX };
			@:privateAccess view.saveDisplayState("Camera2D", save);
		}
		if(gizmo != null) {
			if(!gizmo.moving) {
				moveGizmoToSelection();
			}
			gizmo.update(dt, localTransform);
		}
		updateBasis();
		event.update(dt);
		for( f in updates )
			f(dt);
		if( customEditor != null )
			customEditor.update(dt);

		ruler?.update(dt);

		updateGuide2d();

		onUpdate(dt);
	}

	public dynamic function onUpdate(dt:Float) {
	}

	public function getRecentMenuKey() : String {
		return "sceneeditor.newrecents";
	}

	function getNewRecentContextMenu(current, ?onMake: PrefabElement->Void=null) : Array<hide.comp.ContextMenu.MenuItem> {
		var parent = current == null ? sceneData : current;
		var grecent = [];
		var recents : Array<String> = ide.currentConfig.get(getRecentMenuKey(), []);
		for( g in recents) {
			@:privateAccess var pmodel = hrt.prefab.Prefab.registry.get(g);
			if (pmodel != null && checkAllowParent(pmodel, parent))
				grecent.push(getNewTypeMenuItem(g, parent, onMake));
		}
		return grecent;
	}

	// Override
	function getNewContextMenu(current: PrefabElement, ?onMake: PrefabElement->Void=null, ?groupByType=true ) : Array<hide.comp.ContextMenu.MenuItem> {
		var newItems = new Array<hide.comp.ContextMenu.MenuItem>();

		@:privateAccess var allRegs = hrt.prefab.Prefab.registry.copy();
		allRegs.remove("reference");
		allRegs.remove("unknown");
		var parent = current == null ? sceneData : current;

		var groups = [];
		var gother = [];

		for( g in (view.config.get("sceneeditor.newgroups") : Array<String>) ) {
			var parts = g.split("|");
			var cl : Dynamic = Type.resolveClass(parts[1]);
			if( cl == null ) continue;
			groups.push({
				label : parts[0],
				cl : cl,
				group : [],
			});
		}
		for( ptype in allRegs.keys() ) {
			var pinf = allRegs.get(ptype);
			if (pinf.inf.hideInAddMenu) continue;

			if (!checkAllowParent(pinf, parent)) continue;
			if(ptype == "shader") {
				newItems.push(getNewShaderMenu(parent, onMake));
				continue;
			}

			var m = getNewTypeMenuItem(ptype, parent, onMake);
			if( !groupByType )
				newItems.push(m);
			else {
				var found = false;
				for( g in groups )
					if( hrt.prefab.Prefab.isOfType(hrt.prefab.Prefab.getPrefabInfoByName(ptype).prefabClass,g.cl) ) {
						g.group.push(m);
						found = true;
						break;
					}
				if( !found ) gother.push(m);
			}
		}
		function sortByLabel(arr:Array<hide.comp.ContextMenu.MenuItem>) {
			arr.sort(function(l1,l2) return Reflect.compare(l1.label,l2.label));
		}
		for( g in groups )
			if( g.group.length > 0 ) {
				sortByLabel(g.group);
				newItems.push({ label : g.label, menu : g.group });
			}
		sortByLabel(gother);
		sortByLabel(newItems);
		if( gother.length > 0 ) {
			if( newItems.length == 0 )
				return gother;
			newItems.push({ label : "Other", menu : gother });
		}

		return newItems;
	}

	function getNewTypeMenuItem(
		ptype: String,
		parent: PrefabElement,
		onMake: PrefabElement->Void,
		?label: String,
		?objectName: String,
		?path: String
	) : hide.comp.ContextMenu.MenuItem {
		var prefabInfo = hrt.prefab.Prefab.getPrefabInfoByName(ptype);
		return {
			label : label != null ? label : prefabInfo.inf.name,
			click : function() {
				function make(?sourcePath) {
					var p = Type.createInstance(prefabInfo.prefabClass, [parent]);
					//p.proto = new hrt.prefab.ProtoPrefab(p, sourcePath);
					if(sourcePath != null)
						p.source = sourcePath;
					if( objectName != null)
						p.name = objectName;
					else
						autoName(p);
					if(onMake != null)
						onMake(p);
					var recents : Array<String> = ide.currentConfig.get(getRecentMenuKey(), []);
					recents.remove(p.type);
					recents.unshift(p.type);
					var recentSize : Int = view.config.get("sceneeditor.recentsize");
					if (recents.length > recentSize) recents.splice(recentSize, recents.length - recentSize);
					ide.currentConfig.set(getRecentMenuKey(), recents);
					return p;
				}

				if( prefabInfo.inf.fileSource != null ) {
					if( path != null ) {
						var p = make(path);
						addElements([p]);
						var recents : Array<String> = ide.currentConfig.get(getRecentMenuKey(), []);
						recents.remove(p.type);
					} else {
						ide.chooseFile(prefabInfo.inf.fileSource, function(path) {
							addElements([make(path)]);
						});
					}
				}
				else
					addElements([make()]);
			},
			icon : prefabInfo.inf.icon,
		};
	}

	static var globalShaders : Array<Class<hxsl.Shader>> = [
		hrt.shader.DissolveBurn,
		hrt.shader.Bloom,
		hrt.shader.UVDebug,
		hrt.shader.GradientMap,
		hrt.shader.HeightGradient,
		hrt.shader.ParticleFade,
		hrt.shader.ParticleColorLife,
		hrt.shader.ParticleColorRandom,
		hrt.shader.MaskColorAlpha,
		hrt.shader.Spinner,
		hrt.shader.SDF,
		hrt.shader.FireShader,
		hrt.shader.MeshWave,
		hrt.shader.TextureRotate,
		hrt.shader.GradientMapLife,
		hrt.shader.TextureMult,
	];

	function getNewShaderMenu(parentElt: PrefabElement, ?onMake: PrefabElement->Void) : hide.comp.ContextMenu.MenuItem {
		function isClassShader(path: String) {
			return Type.resolveClass(path) != null || StringTools.endsWith(path, ".hx") || StringTools.endsWith(path, ".shgraph");
		}

		function getPackagePath(path: String) {
			var fullPath = null;
			for (shaderPath in @:privateAccess Ide.inst.shaderLoader.shaderPath) {
				fullPath = Ide.inst.projectDir + "/" + shaderPath + "/" + path;
				if (sys.FileSystem.exists(fullPath))
					break;
			}

			if (!sys.FileSystem.exists(fullPath))
				return null;

			return fullPath;
		}

		var shModel = hrt.prefab.Prefab.getPrefabInfoByName("shader");
		var graphModel = hrt.prefab.Prefab.getPrefabInfoByName("shgraph");
		var custom = {
			label : "Custom...",
			click : function() {
				ide.chooseFile(shModel.inf.fileSource.concat(graphModel.inf.fileSource).concat(["shgraph"]), function(path) {
					var cl = isClassShader(path) ? shModel.prefabClass : graphModel.prefabClass;
					var p = Type.createInstance(cl, [parentElt]);
					p.source = path;
					autoName(p);
					if(onMake != null)
						onMake(p);
					addElements([p]);
				});
			},
			icon : shModel.inf.icon,
		};

		function classShaderItem(path) : hide.comp.ContextMenu.MenuItem {
			var name = path;
			if(StringTools.endsWith(name, ".hx")) {
				name = new haxe.io.Path(path).file;
			}
			else {
				name = name.split(".").pop();
			}
			return getNewTypeMenuItem("shader", parentElt, onMake, name, name, path);
		}

		function graphShaderItem(path) : hide.comp.ContextMenu.MenuItem {
			var name = new haxe.io.Path(path).file;
			return getNewTypeMenuItem("shgraph", parentElt, onMake, name, name, path);
		}

		var menu : Array<hide.comp.ContextMenu.MenuItem> = [];

		var shaders : Array<String> = hide.Ide.inst.currentConfig.get("fx.shaders", []);
		for (sh in globalShaders) {
			var name = Type.getClassName(sh);
			if (!shaders.contains(name)) {
				shaders.push(name);
			}
		}

		for(path in shaders) {
			var strippedSlash = StringTools.endsWith(path, "/") ? path.substr(0, -1) : path;
			var fullPath = ide.getPath(strippedSlash);
			if( isClassShader(path) ) {
				menu.push(classShaderItem(path));
			} else if (StringTools.endsWith(path, ".shgraph") ) {
				menu.push(graphShaderItem(path));
			} else if( sys.FileSystem.exists(fullPath) && sys.FileSystem.isDirectory(fullPath) ) {
				for( c in sys.FileSystem.readDirectory(fullPath) ) {
					var relPath = ide.makeRelative(fullPath + "/" + c);
					if( isClassShader(relPath) ) {
						menu.push(classShaderItem(relPath));
					} else if( StringTools.endsWith(relPath, ".shgraph")) {
						menu.push(graphShaderItem(relPath));
					}
				}
			} else if (getPackagePath(path) != null) {
				function addShadersInFolder(path : String) {
					var files = sys.FileSystem.readDirectory(path);

					for (f in files) {
						var filePath = path + "/" + f;
						if (sys.FileSystem.isDirectory(filePath))
							addShadersInFolder(filePath);
						else if (isClassShader(filePath)){
							menu.push(classShaderItem(filePath));
						}
					}
				}

				addShadersInFolder(getPackagePath(path));
			}
		}


		menu.sort(function(l1,l2) return Reflect.compare(l1.label,l2.label));
		menu.unshift(custom);

		return {
			label: "Shader",
			menu: menu
		};
	}

	public function getZ(x: Float, y: Float, ?paintOn : hrt.prefab.Prefab) {
		var offset = 1000000;
		var ray = h3d.col.Ray.fromValues(x, y, offset, 0, 0, -1);
		var dist = projectToGround(ray, paintOn);
		if(dist >= 0) {
			return offset - dist;
		}
		return 0.;
	}

	function getAllPrefabs(data : PrefabElement) {
		var all = data.findAll(hrt.prefab.Prefab);
		for( a in all.copy() ) {
			var r = Std.downcast(a, hrt.prefab.Reference);
			if( r != null ) {
				var sub = @:privateAccess r.refInstance;
				if( sub != null ) all = all.concat(getAllPrefabs(sub));
			}
		}
		return all;
	}

	var groundPrefabsCache : Array<PrefabElement> = null;
	var groundPrefabsCacheTime : Float = -1e9;

	function getGroundPrefabs() : Array<PrefabElement> {
		var now = haxe.Timer.stamp();
		if (now - groundPrefabsCacheTime > 5) {
			var all = getAllPrefabs(sceneData);
			var grounds = [for( p in all ) if( p.getHideProps().isGround || (p.name != null && p.name.toLowerCase() == "ground")) p];
			grounds = grounds.filter((p) -> {
				while(p != null) {
					if (Std.downcast(p, Object3D)?.visible == false) {
						return false;
					}
					p = p.parent ?? p.shared.parentPrefab;
				}
				return true;
			});
			var results = [];
			for( g in grounds )
				results = results.concat(getAllPrefabs(g));
			groundPrefabsCache = results;
			groundPrefabsCacheTime = now;
		}
		return groundPrefabsCache.copy();
	}

	public function projectToGround(ray: h3d.col.Ray, ?paintOn : hrt.prefab.Prefab, ignoreTerrain: Bool = false) {
		var minDist = -1.;
		if (!ignoreTerrain) {
			var arr = (paintOn == null ? getGroundPrefabs() : [paintOn]);
			for( elt in arr ) {
				var obj = Std.downcast(elt, Object3D);
				if( obj == null ) continue;

				var local3d = obj.findFirstLocal3d();
				if (local3d == null) continue;
				var lray = ray.clone();
				lray.transform(local3d.getInvPos());
				var dist = obj.localRayIntersection(lray);
				if( dist > 0 ) {
					var pt = lray.getPoint(dist);
					pt.transform(local3d.getAbsPos());
					var dist = pt.sub(ray.getPos()).length();
					if( minDist < 0 || dist < minDist )
						minDist = dist;
				}
			}
			if( minDist >= 0 )
				return minDist;
		}


		var zPlane = h3d.col.Plane.Z(ray.pz >= 0 ? 0 : ray.pz - 10);
		var pt = ray.intersect(zPlane);
		if( pt != null ) {
			minDist = pt.sub(ray.getPos()).length();
			var dirToPt = pt.sub(ray.getPos());
			if( dirToPt.dot(ray.getDir()) < 0 )
				return -1;
		}

		return minDist;
	}

	public function screenDistToGround(sx : Float, sy : Float, ?paintOn : hrt.prefab.Prefab, ignoreTerrain: Bool = false) : Null<Float> {
		var camera = scene.s3d.camera;
		var ray = camera.rayFromScreen(sx, sy);
		var dist = projectToGround(ray, paintOn, ignoreTerrain);
		if( dist >= 0 )
			return dist + camera.zNear;
		return null;
	}

	public function screenToGround(sx: Float, sy: Float, ?paintOn : hrt.prefab.Prefab, ignoreTerrain: Bool = false) {
		var camera = scene.s3d.camera;
		var ray = camera.rayFromScreen(sx, sy);
		var dist = projectToGround(ray, paintOn, ignoreTerrain);
		if(dist >= 0) {
			return ray.getPoint(dist);
		}
		return null;
	}

	public function worldToScreen(wx: Float, wy: Float, wz: Float) {
		var camera = scene.s3d.camera;
		var pt = camera.project(wx, wy, wz, scene.s2d.width, scene.s2d.height);
		return new h2d.col.Point(pt.x, pt.y);
	}

	public function worldMat(?obj: Object, ?elt: PrefabElement) {
		if(obj != null) {
			if(obj.defaultTransform != null) {
				var m = obj.defaultTransform.clone();
				m.invert();
				m.multiply(m, obj.getAbsPos());
				return m;
			}
			else {
				return obj.getAbsPos().clone();
			}
		}
		else {
			var mat = new h3d.Matrix();
			mat.identity();
			var o = Std.downcast(elt, Object3D);
			while(o != null) {
				mat.multiply(mat, o.getTransform());
				o = o.parent != null ? o.parent.to(hrt.prefab.Object3D) : null;
			}
			return mat;
		}
	}

	public function worldMat2d(elt: PrefabElement) : h2d.col.Matrix {
		var mat = new h2d.col.Matrix();
		mat.identity();
		while(elt != null) {
			var o = Std.downcast(elt, Object2D);
			if (o != null) {
				mat.multiply(mat, o.getTransformMatrix());
				elt = o.parent;
			} else break;
		}
		return mat;
	}

	function editPivot() {
		if (selectedPrefabs.length == 1) {
			var ray = scene.s3d.camera.rayFromScreen(scene.s2d.mouseX, scene.s2d.mouseY);
			var polyColliders = new Array<PolygonBuffer>();
			var meshes = new Array<Mesh>();
			for (m in getRootObjects3d()[0].getMeshes()) {
				var hmdModel = Std.downcast(m.primitive, HMDModel);
				if (hmdModel != null) {
					var optiCollider = Std.downcast(hmdModel.getCollider(), OptimizedCollider);
					var polyCollider = Std.downcast(optiCollider.b, PolygonBuffer);
					if (polyCollider != null) {
						polyColliders.push(polyCollider);
						meshes.push(m);
					}
				}
			}
			if (polyColliders.length > 0) {
				var pivot = getClosestVertex(polyColliders, meshes, ray);
				if (pivot != null) {
					pivot.elt = selectedPrefabs[0];
					customPivot = pivot;
				} else {
					// mouse outside
				}
			} else {
				// no collider found
			}
		} else {
			throw "Can't edit when multiple objects are selected";
		}
	}

	function getClosestVertex( colliders : Array<PolygonBuffer>, meshes : Array<Mesh>, ray : Ray ) : CustomPivot {

		var best = -1.;
		var bestVertex : CustomPivot = null;
		for (idx in 0...colliders.length) {
			var c = colliders[idx];
			var m = meshes[idx];
			var r = ray.clone();
			r.transform(m.getInvPos());
			var rdir = new FPoint(r.lx, r.ly, r.lz);
			var r0 = new FPoint(r.px, r.py, r.pz);
			@:privateAccess var i = c.startIndex;
			@:privateAccess for( t in 0...c.triCount ) {
				var i0 = c.indexes[i++] * 3;
				var p0 = new FPoint(c.buffer[i0++], c.buffer[i0++], c.buffer[i0]);
				var i1 = c.indexes[i++] * 3;
				var p1 = new FPoint(c.buffer[i1++], c.buffer[i1++], c.buffer[i1]);
				var i2 = c.indexes[i++] * 3;
				var p2 = new FPoint(c.buffer[i2++], c.buffer[i2++], c.buffer[i2]);

				var e1 = p1.sub(p0);
				var e2 = p2.sub(p0);
				var p = rdir.cross(e2);
				var det = e1.dot(p);
				if( det < hxd.Math.EPSILON ) continue; // backface culling (negative) and near parallel (epsilon)

				var invDet = 1 / det;
				var T = r0.sub(p0);
				var u = T.dot(p) * invDet;

				if( u < 0 || u > 1 ) continue;

				var q = T.cross(e1);
				var v = rdir.dot(q) * invDet;

				if( v < 0 || u + v > 1 ) continue;

				var t = e2.dot(q) * invDet;

				if( t < hxd.Math.EPSILON ) continue;

				if( best < 0 || t < best ) {
					best = t;
					var ptIntersection = r.getPoint(t);
					var pI = new FPoint(ptIntersection.x, ptIntersection.y, ptIntersection.z);
					inline function distanceFPoints(a : FPoint, b : FPoint) : Float {
						var dx = a.x - b.x;
						var dy = a.y - b.y;
						var dz = a.z - b.z;
						return dx * dx + dy * dy + dz * dz;
					}
					var test0 = distanceFPoints(p0, pI);
					var test1 = distanceFPoints(p1, pI);
					var test2 = distanceFPoints(p2, pI);
					var locBestVertex : FPoint;
					if (test0 <= test1 && test0 <= test2) {
						locBestVertex = p0;
					} else if (test1 <= test0 && test1 <= test2) {
						locBestVertex = p1;
					} else {
						locBestVertex = p2;
					}
					bestVertex = { elt : null, mesh: m, locPos: new Vector(locBestVertex.x, locBestVertex.y, locBestVertex.z) };
				}
			}
		}
		return bestVertex;
	}

	static function isReference( what : PrefabElement ) : Bool {
		return what != null && what.to(hrt.prefab.Reference) != null;
	}

	static function getPivot(objects: Array<Object>) {
		if (customPivot != null) {
			return customPivot.mesh.localToGlobal(customPivot.locPos.toPoint());
		}
		var pos = new h3d.col.Point();
		for(o in objects) {
			if ( o == null )
				continue;
			pos = pos.add(o.getAbsPos().getPosition().toPoint());
		}
		pos.scale(1.0 / objects.length);
		return pos;
	}

	static function getPivot2D( objects : Array<h2d.Object> ) {
		var b = new h2d.col.Bounds();
		for( o in objects )
			b.addBounds(o.getBounds());
		return b;
	}

	public static function hasParent(elt: PrefabElement, list: Array<PrefabElement>) {
		for(p in list) {
			if(isParent(elt, p))
				return true;
		}
		return false;
	}

	public static function hasChild(elt: PrefabElement, list: Array<PrefabElement>) {
		for(p in list) {
			if(isParent(p, elt))
				return true;
		}
		return false;
	}

	public static function isParent(elt: PrefabElement, parent: PrefabElement) {
		var p = elt.parent;
		while(p != null) {
			if(p == parent) return true;
			p = p.parent;
		}
		return false;
	}

	static function getParentGroup(elt: PrefabElement) {
		while(elt != null) {
			if(elt.type == "object")
				return elt;
			elt = elt.parent;
		}
		return null;
	}

	static var contextMenuExtRegistry : Map<{}, (elements: Array<hrt.prefab.Prefab>) -> Array<hide.comp.ContextMenu.MenuItem>> = [];
	static public function registerContextMenuExtension(cl: Class<hrt.prefab.Prefab>, callback: (elements: Array<hrt.prefab.Prefab>) -> Array<hide.comp.ContextMenu.MenuItem>) : Int {
		contextMenuExtRegistry.set(cast cl, callback);
		return 0;
	}
}