package hide.view;
using Lambda;

import hide.Element;
import hide.prefab.Prefab in PrefabElement;
import hide.prefab.Curve;
import hide.prefab.fx.Event;

typedef PropTrackDef = {
	name: String,
	?clamp: Array<Float>,
	?def: Float
};

@:access(hide.view.FXEditor)
class FXEditContext extends hide.prefab.EditContext {
	var parent : FXEditor;
	public function new(parent, context) {
		super(context);
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

	override function selectObjects( elts, ?includeTree=true) {
		super.selectObjects(elts, includeTree);
		parent.onSelect(elts);
	}

	override function refresh(?mode, ?callb:Void->Void) {
		// Always refresh scene
		refreshScene();
		refreshTree(callb);
	}

	override function getNewContextMenu(current: PrefabElement, ?onMake: PrefabElement->Void=null) {
		if(current != null && current.to(hide.prefab.Shader) != null) {
			return parent.getNewTrackMenu(current);
		}
		var allTypes = super.getNewContextMenu(current, onMake);

		var menu = [];
		for(name in ["Group", "Polygon", "Model", "Shaders"]) {
			var item = allTypes.find(i -> i.label == name);
			if(item == null) continue;
			allTypes.remove(item);
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
							mode: "Overlay",
							blend: "None",
							shadows: false
						}
					}
					if(onMake != null) onMake(p);
				}, "Unlit")
			]
		});
		menu.sort(function(l1,l2) return Reflect.compare(l1.label,l2.label));
		menu.push({label: null, isSeparator: true});
		menu.push({
			label: "Other",
			menu: allTypes
		});
		return menu;
	}
}

class FXEditor extends FileView {

	var sceneEditor : FXSceneEditor;
	var data : hide.prefab.fx.FX;
	var tabs : hide.comp.Tabs;
	var fxprops : hide.comp.PropsEditor;

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

	var showGrid = true;
	var grid : h3d.scene.Graphics;

	var timelineLeftMargin = 10;
	var xScale = 200.;
	var xOffset = 0.;

	var pauseButton : hide.comp.Toolbar.ToolToggle;
	var currentTime : Float;
	var selectMin : Float;
	var selectMax : Float;
	var previewMin : Float;
	var previewMax : Float;
	var curveEdits : Array<hide.comp.CurveEditor>;
	var timeLineEl : Element;
	var afterPanRefreshes : Array<Bool->Void> = [];
	var statusText : h2d.Text;

	var scriptEditor : hide.comp.ScriptEditor;
	var fxScriptParser : hide.prefab.fx.FXScriptParser;

	override function getDefaultContent() {
		return haxe.io.Bytes.ofString(ide.toJSON(new hide.prefab.fx.FX().save()));
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
		saveDisplayKey = "FXScene/" + getPath().split("\\").join("/").substr(0,-1);
		currentTime = 0.;
		xOffset = -timelineLeftMargin / xScale;
		data = new hide.prefab.fx.FX();
		var content = sys.io.File.getContent(getPath());
		data.load(haxe.Json.parse(content));
		currentSign = haxe.crypto.Md5.encode(content);

		element.html('
			<div class="flex vertical">
				<div class="toolbar"></div>
				<div class="flex">
					<div class="flex vertical">
						<div class="flex scene"></div>
						<div class="fx-animpanel">
							<div class="top-bar">
								<div class="timeline">
									<div class="timeline-scroll"/>
								</div>
							</div>
							<div class="anim-scroll"></div>
							<div class="overlay-container">
								<div class="overlay"></div>
							</div>
						</div>
					</div>
					<div class="tabs">
						<div class="tab expand" name="Scene" icon="sitemap">
							<div class="hide-block" style="height:40%">
								<div class="hide-scene-tree hide-list">
								</div>
							</div>
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
		tools = new hide.comp.Toolbar(null,element.find(".toolbar"));
		tabs = new hide.comp.Tabs(null,element.find(".tabs"));
		sceneEditor = new FXSceneEditor(this, data);
		element.find(".hide-scene-tree").first().append(sceneEditor.tree.element);
		element.find(".hide-scroll").first().append(sceneEditor.properties.element);
		element.find(".scene").first().append(sceneEditor.scene.element);
		element.resize(function(e) {
			refreshTimeline(false);
			rebuildAnimPanel();
		});
		fxprops = new hide.comp.PropsEditor(undo,null,element.find(".fx-props"));
		{
			var edit = new FXEditContext(this, sceneEditor.context);
			edit.prefabPath = state.path;
			edit.properties = fxprops;
			edit.scene = sceneEditor.scene;
			edit.cleanups = [];
			data.edit(edit);
		}

		var scriptElem = element.find(".fx-script");
		scriptEditor = new hide.comp.ScriptEditor(data.script, null, scriptElem, scriptElem);
		function onSaveScript() {
			data.script = scriptEditor.code;
			save();
			skipNextChange = true;
			modified = false;
		}
		scriptEditor.onSave = onSaveScript;
		fxScriptParser = new hide.prefab.fx.FXScriptParser();
		data.script = scriptEditor.code;

		keys.register("playPause", function() { pauseButton.toggle(!pauseButton.isDown()); });

		currentVersion = undo.currentID;
		sceneEditor.tree.element.addClass("small");

		var timeline = element.find(".timeline");
		timeline.mousedown(function(e) {
			var lastX = e.clientX;
			var shift = e.shiftKey;
			var ctrl = e.ctrlKey;
			var xoffset = timeline.offset().left;

			if(shift) {
				selectMin = hxd.Math.max(0, ixt(e.clientX - xoffset));
			}
			else if(ctrl) {
				previewMin = hxd.Math.max(0, ixt(e.clientX - xoffset));
			}

			function updateMouse(e: js.jquery.Event) {
				var dt = (e.clientX - lastX) / xScale;
				if(e.which == 2) {
					xOffset -= dt;
					xOffset = hxd.Math.max(xOffset, -timelineLeftMargin/xScale);
				}
				else if(e.which == 1) {
					if(shift) {
						selectMax = ixt(e.clientX - xoffset);
					}
					else if(ctrl) {
						previewMax = ixt(e.clientX - xoffset);
					}
					else {
						if(!pauseButton.isDown())
							pauseButton.toggle(true);
						currentTime = ixt(e.clientX - xoffset);
						currentTime = hxd.Math.max(currentTime, 0);
					}
				}
			}

			element.mousemove(function(e: js.jquery.Event) {
				updateMouse(e);
				lastX = e.clientX;
				refreshTimeline(true);
				afterPan(true);
			});
			element.mouseup(function(e: js.jquery.Event) {
				updateMouse(e);

				if(previewMax < previewMin + 0.1) {
					previewMin = 0;
					previewMax = data.duration == 0 ? 1 : data.duration;
				}
				if(selectMax < selectMin + 0.1) {
					selectMin = 0;
					selectMax = 0;
				}

				element.off("mousemove");
				element.off("mouseup");
				e.preventDefault();
				e.stopPropagation();
				refreshTimeline(false);
				afterPan(false);
			});
			e.preventDefault();
			e.stopPropagation();
		});
		timeline.on("mousewheel", function(e) {
			var step = e.originalEvent.wheelDelta > 0 ? 1.0 : -1.0;
			xScale *= Math.pow(1.125, step);
			e.preventDefault();
			e.stopPropagation();
			refreshTimeline(false);
			for(ce in curveEdits) {
				ce.xOffset = xOffset;
				ce.xScale = xScale;
				ce.refresh();
			}
			afterPan(false);
		});

		selectMin = 0.0;
		selectMax = 0.0;
		previewMin = 0.0;
		previewMax = data.duration == 0 ? 5000 : data.duration;
		refreshTimeline(false);
	}

	public function onSceneReady() {
		light = sceneEditor.scene.s3d.find(function(o) return Std.instance(o, h3d.scene.DirLight));
		if( light == null ) {
			light = new h3d.scene.DirLight(scene.s3d);
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
		axis.visible = showGrid;

		tools.saveDisplayKey = "FXScene/tools";
		tools.addButton("video-camera", "Perspective camera", () -> sceneEditor.resetCamera());

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

		tools.addToggle("th", "Show grid", function(v) {
			showGrid = v;
			axis.visible = v;
			updateGrid();
		}, showGrid);
		tools.addColor("Background color", function(v) {
			scene.engine.backgroundColor = v;
			updateGrid();
		}, scene.engine.backgroundColor);
		tools.addToggle("refresh", "Auto synchronize", function(b) {
			autoSync = b;
		});
		pauseButton = tools.addToggle("pause", "Pause animation", function(v) {}, false);
		tools.addRange("Speed", function(v) {
			scene.speed = v;
		}, scene.speed);

		statusText = new h2d.Text(hxd.res.DefaultFont.get(), scene.s2d);
		statusText.setPosition(5, 5);

		updateGrid();
	}

	function onPrefabChange(p: PrefabElement, ?pname: String) {
		if(p == data) {
			previewMax = hxd.Math.min(data.duration == 0 ? 5000 : data.duration, previewMax);
			refreshTimeline(false);
		}

		if(p.to(Event) != null) {
			afterPan(false);
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
				var parent : PrefabElement = data;
				sceneEditor.dropObjects(models, parent);
			}
			return true;
		}
		return false;
	}

	function onSelect(elts : Array<PrefabElement>) {
		rebuildAnimPanel();
	}

	inline function xt(x: Float) return Math.round((x - xOffset) * xScale);
	inline function ixt(px: Float) return px / xScale + xOffset;

	function refreshTimeline(anim: Bool) {
		var scroll = element.find(".timeline-scroll");
		scroll.empty();
		var width = scroll.parent().width();
		var minX = Math.floor(ixt(0));
		var maxX = Math.ceil(hxd.Math.min(data.duration == 0 ? 5000 : data.duration, ixt(width)));
		for(ix in minX...(maxX+1)) {
			var mark = new Element('<span class="mark"></span>').appendTo(scroll);
			mark.css({left: xt(ix)});
			mark.text(ix + ".00");
		}

		var overlay = element.find(".overlay");
		overlay.empty();
		timeLineEl = new Element('<span class="timeline"></span>').appendTo(overlay);
		timeLineEl.css({left: xt(currentTime)});

		var select = new Element('<span class="selection"></span>').appendTo(overlay);
		select.css({left: xt(selectMin), width: xt(selectMax) - xt(selectMin)});

		if(!anim && selectMax > selectMin + 1e-6) {
			var selLeft = new Element('<span class="selection-left"></span>').appendTo(overlay);
			var selRight = new Element('<span class="selection-right"></span>').appendTo(overlay);

			function updateSelectPos() {
				select.css({left: xt(selectMin), width: xt(selectMax) - xt(selectMin)});
				selLeft.css({left: xt(selectMin) - 4});
				selRight.css({left: xt(selectMax)});
			}
			updateSelectPos();

			function refreshViews() {
				for(ce in curveEdits) {
					ce.refreshGraph(false);
					ce.onChange(false);
				}
			}

			var curves = [for(ce in curveEdits) ce.curve];
			var backup = null;
			var prevSel = null;
			function beforeChange() {
				backup = [for(c in curves) haxe.Json.parse(haxe.Json.stringify(c.save()))];
				prevSel = [selectMin, selectMax];
			}

			function afterChange() {
				var newVals = [for(c in curves) haxe.Json.parse(haxe.Json.stringify(c.save()))];
				var newSel = [selectMin, selectMax];
				undo.change(Custom(function(undo) {
					if(undo) {
						for(i in 0...curves.length)
							curves[i].load(backup[i]);
						selectMin = prevSel[0];
						selectMax = prevSel[1];
					}
					else {
						for(i in 0...curves.length)
							curves[i].load(newVals[i]);
						selectMin = newSel[0];
						selectMax = newSel[1];
					}
					updateSelectPos();
					refreshViews();
				}));
				refreshViews();
			}

			function setupSelectDrag(element: js.jquery.JQuery, update: Float->Float->Void) {
				element.mousedown(function(e) {
					if(e.button != 0)
						return;
					var offset = scroll.offset();
					e.preventDefault();
					e.stopPropagation();
					var lastTime = ixt(e.clientX);
					beforeChange();
					startDrag(function(e) {
						var time = ixt(e.clientX);
						update(time, lastTime);
						updateSelectPos();
						lastTime = time;
					}, function(e) {
						afterChange();
					});
				});
			}

			setupSelectDrag(selRight, function(time, lastTime) {
				var shift = time - lastTime;
				if(selectMax > selectMin + 0.1) {
					var scaleFactor = (selectMax + shift - selectMin) / (selectMax - selectMin);

					for(ce in curveEdits) {
						for(key in ce.curve.keys) {
							if(key.time >= selectMin && key.time <= selectMax) {
								key.time = (key.time - selectMin) * scaleFactor + selectMin;
							}
						}
						ce.refreshGraph(true);
						ce.onChange(true);
					}

					selectMax += shift;
				}
			});

			setupSelectDrag(selLeft, function(time, lastTime) {
				var shift = time - lastTime;
				if(selectMax > selectMin + 0.1) {
					var scaleFactor = (selectMax - (selectMin + shift)) / (selectMax - selectMin);

					for(ce in curveEdits) {
						for(key in ce.curve.keys) {
							if(key.time >= selectMin && key.time <= selectMax) {
								key.time = selectMax - (selectMax - key.time) * scaleFactor;
							}
						}
						ce.refreshGraph(true);
						ce.onChange(true);
					}

					selectMin += shift;
				}
			});

			setupSelectDrag(select, function(time, lastTime) {
				var shift = time - lastTime;
				for(ce in curveEdits) {
					for(key in ce.curve.keys) {
						if(key.time >= selectMin && key.time <= selectMax) {
							key.time += shift;
						}
					}
					ce.refreshGraph(true);
					ce.onChange(true);
				}
				selectMin += shift;
				selectMax += shift;
			});
		}

		//var preview = new Element('<span class="preview"></span>').appendTo(overlay);
		// preview.css({left: xt(previewMin), width: xt(previewMax) - xt(previewMin)});
		var prevLeft = new Element('<span class="preview-left"></span>').appendTo(overlay);
		prevLeft.css({left: 0, width: xt(previewMin)});
		var prevRight = new Element('<span class="preview-right"></span>').appendTo(overlay);
		prevRight.css({left: xt(previewMax), width: xt(data.duration == 0 ? 5000 : data.duration) - xt(previewMax)});
	}

	function afterPan(anim: Bool) {
		for(curve in curveEdits) {
			curve.setPan(xOffset, curve.yOffset);
		}
		for(clb in afterPanRefreshes) {
			clb(anim);
		}
	}

	function addCurvesTrack(trackName: String, curves: Array<Curve>, tracksEl: Element) {
		var keyTimeTolerance = 0.05;
		var trackEdits : Array<hide.comp.CurveEditor> = [];
		var trackEl = new Element('<div class="track">
			<div class="track-header">
				<div class="track-prop">
					<label>${upperCase(trackName)}</label>
					<div class="track-toggle"><div class="icon fa"></div></div>
				</div>
				<div class="dopesheet"></div>
			</div>
			<div class="curves"></div>
		</div>');
		if(curves.length == 0)
			return;
		var parent = curves[0].parent;
		var isColorTrack = trackName.toLowerCase().indexOf("color") >= 0 && (curves.length == 3 || curves.length == 4);
		var isColorHSL = isColorTrack && curves.find(c -> StringTools.endsWith(c.name, ".h")) != null;

		var trackToggle = trackEl.find(".track-toggle");
		tracksEl.append(trackEl);
		var curvesContainer = trackEl.find(".curves");
		var trackKey = "trackVisible:" + parent.getAbsPath() + "/" + trackName;
		var expand = getDisplayState(trackKey) == true;
		function updateExpanded() {
			var icon = trackToggle.find(".icon");
			if(expand)
				icon.removeClass("fa-angle-right").addClass("fa-angle-down");
			else
				icon.removeClass("fa-angle-down").addClass("fa-angle-right");
			curvesContainer.toggleClass("hidden", !expand);
			for(c in trackEdits)
				c.refresh();
		}
		trackEl.find(".track-prop").click(function(e) {
			expand = !expand;
			saveDisplayState(trackKey, expand);
			updateExpanded();
		});
		var dopesheet = trackEl.find(".dopesheet");
		var evaluator = new hide.prefab.fx.Evaluator(new hxd.Rand(0));

		function getKeyColor(key) {
			return evaluator.getVector(hide.prefab.Curve.getColorValue(curves), key.time);
		}

		function dragKey(from: hide.comp.CurveEditor, prevTime: Float, newTime: Float) {
			for(edit in trackEdits) {
				if(edit == from) continue;
				var k = edit.curve.findKey(prevTime, keyTimeTolerance);
				if(k != null) {
					k.time = newTime;
					edit.refreshGraph(false, k);
				}
			}
		}
		function refreshCurves(anim: Bool) {
			for(c in trackEdits) {
				c.refreshGraph(anim);
			}
		}

		function refreshKey(key: hide.comp.CurveEditor.CurveKey, el: Element) {
			if(isColorTrack) {
				var color = getKeyColor(key);
				var colorStr = "#" + StringTools.hex(color.toColor() & 0xffffff, 6);
				el.css({background: colorStr});
			}
		}

		var refreshDopesheet : Void -> Void;

		function backupCurves() {
			return [for(c in curves) haxe.Json.parse(haxe.Json.stringify(c.save()))];
		}
		var lastBackup = backupCurves();

		function beforeChange() {
			lastBackup = backupCurves();
		}

		function afterChange() {
			var newVal = backupCurves();
			var oldVal = lastBackup;
			lastBackup = newVal;
			undo.change(Custom(function(undo) {
				if(undo) {
					for(i in 0...curves.length)
						curves[i].load(oldVal[i]);
				}
				else {
					for(i in 0...curves.length)
						curves[i].load(newVal[i]);
				}
				lastBackup = backupCurves();
				refreshCurves(false);
				refreshDopesheet();
			}));
			refreshCurves(false);
		}

		function addKey(time: Float) {
			beforeChange();
			for(curve in curves) {
				curve.addKey(time);
			}
			afterChange();
			refreshDopesheet();
		}


		function keyContextClick(key: hide.prefab.Curve.CurveKey, el: Element) {
			function setCurveVal(suffix: String, value: Float) {
				var c = curves.find(c -> StringTools.endsWith(c.name, suffix));
				if(c != null) {
					var k = c.findKey(key.time, keyTimeTolerance);
					if(k == null) {
						k = c.addKey(key.time);
					}
					k.value = value;
				}
			}

			if(isColorTrack) {
				var picker = new Element("<div></div>").css({
					"z-index": 100,
				}).appendTo(el);
				var cp = new hide.comp.ColorPicker(false, picker);
				var prevCol = getKeyColor(key);
				cp.value = prevCol.toColor();
				cp.open();
				cp.onClose = function() {
					picker.remove();
				};
				cp.onChange = function(dragging) {
					if(dragging)
						return;
					var col = h3d.Vector.fromColor(cp.value, 1.0);
					if(isColorHSL) {
						col = col.toColorHSL();
						setCurveVal(".h", col.x);
						setCurveVal(".s", col.y);
						setCurveVal(".l", col.z);
						setCurveVal(".a", prevCol.a);
					}
					else {
						setCurveVal(".r", col.x);
						setCurveVal(".g", col.y);
						setCurveVal(".b", col.z);
						setCurveVal(".a", prevCol.a);
					}
					refreshCurves(false);
					refreshKey(key, el);
				};
			}
		}

		refreshDopesheet = function () {
			dopesheet.empty();
			dopesheet.off();
			dopesheet.mouseup(function(e) {
				var offset = dopesheet.offset();
				if(e.ctrlKey) {
					var x = ixt(e.clientX - offset.left);
					addKey(x);
				}
			});
			var refKeys = curves[0].keys;
			for(ik in 0...refKeys.length) {
				var key = refKeys[ik];
				var keyEl = new Element('<span class="key">').appendTo(dopesheet);
				function updatePos() keyEl.css({left: xt(refKeys[ik].time)});
				updatePos();
				keyEl.contextmenu(function(e) {
					keyContextClick(key, keyEl);
					e.preventDefault();
					e.stopPropagation();
				});
				keyEl.mousedown(function(e) {
					var offset = dopesheet.offset();
					e.preventDefault();
					e.stopPropagation();
					if(e.button == 2) {
					}
					else {
						var prevVal = key.time;
						beforeChange();
						startDrag(function(e) {
							var x = ixt(e.clientX - offset.left);
							x = hxd.Math.max(0, x);
							var next = refKeys[ik + 1];
							if(next != null)
								x = hxd.Math.min(x, next.time - 0.01);
							var prev = refKeys[ik - 1];
							if(prev != null)
								x = hxd.Math.max(x, prev.time + 0.01);
							dragKey(null, key.time, x);
							updatePos();
						}, function(e) {
							afterChange();
						});
					}
				});
				afterPanRefreshes.push(function(anim) {
					updatePos();
				});
				refreshKey(key, keyEl);
			}
		}

		var minHeight = 40;
		for(curve in curves) {
			var dispKey = getPath() + "/" + curve.getAbsPath();
			var curveContainer = new Element('<div class="curve"><label class="curve-label">${curve.name}</alpha></div>').appendTo(curvesContainer);
			var height = getDisplayState(dispKey + "/height");
			if(height == null)
				height = 100;
			if(height < minHeight) height = minHeight;
			curveContainer.height(height);
			var curveEdit = new hide.comp.CurveEditor(this.undo, curveContainer);
			curveEdit.saveDisplayKey = dispKey;
			curveEdit.lockViewX = true;
			if(curves.length > 1)
				curveEdit.lockKeyX = true;
			curveEdit.xOffset = xOffset;
			curveEdit.xScale = xScale;
			curveEdit.curve = curve;
			if(curve.getParent(hide.prefab.fx.Emitter) != null)
				curveEdit.maxLength = 1.0;
			curveEdit.onChange = function(anim) {
				refreshDopesheet();
			}

			curveContainer.on("mousewheel", function(e) {
				var step = e.originalEvent.wheelDelta > 0 ? 1.0 : -1.0;
				if(e.ctrlKey) {
					var prevH = curveContainer.height();
					var newH = hxd.Math.max(minHeight, prevH + Std.int(step * 20.0));
					curveContainer.height(newH);
					saveDisplayState(dispKey + "/height", newH);
					curveEdit.yScale *= newH / prevH;
					curveEdit.refresh();
					e.preventDefault();
					e.stopPropagation();
				}
			});
			trackEdits.push(curveEdit);
			curveEdits.push(curveEdit);
		}
		refreshDopesheet();
		updateExpanded();
	}

	function addEventsTrack(events: Array<Event>, tracksEl: Element) {
		var trackEl = new Element('<div class="track">
			<div class="track-header">
				<div class="track-prop">
					<label>Events</label>
				</div>
				<div class="events"></div>
			</div>
		</div>');
		var eventsEl = trackEl.find(".events");
		var items : Array<{el: Element, event: Event }> = [];
		function refreshItems() {
			var yoff = 1;
			for(item in items) {
				var info = item.event.getDisplayInfo(sceneEditor.curEdit);
				item.el.css({left: xt(item.event.time), top: yoff});
				item.el.width(info.length * xScale);
				yoff += 21;
			}
			eventsEl.css("height", yoff + 1);
		}

		function refreshTrack() {
			trackEl.remove();
			trackEl = addEventsTrack(events, tracksEl);
		}

		for(event in events) {
			var info = event.getDisplayInfo(sceneEditor.curEdit);
			var evtEl = new Element('<div class="event">
				<i class="icon fa fa-play-circle"></i><label>${info.label}</label>
			</div>').appendTo(eventsEl);
			items.push({el: evtEl, event: event });

			evtEl.click(function(e) {
				sceneEditor.showProps(event);
			});

			evtEl.contextmenu(function(e) {
				e.preventDefault();
				e.stopPropagation();
				new hide.comp.ContextMenu([
					{
						label: "Delete", click: function() {
							events.remove(event);
							sceneEditor.deleteElements([event], refreshTrack);
						}
					}
				]);
			});

			evtEl.mousedown(function(e) {
				var offsetX = e.clientX - xt(event.time);
				e.preventDefault();
				e.stopPropagation();
				if(e.button == 2) {
				}
				else {
					var prevVal = event.time;
					startDrag(function(e) {
						var x = ixt(e.clientX - offsetX);
						x = hxd.Math.max(0, x);
						x = untyped parseFloat(x.toFixed(5));
						event.time = x;
						refreshItems();
					}, function(e) {
						undo.change(Field(event, "time", prevVal), refreshItems);
					});
				}
			});
		}
		refreshItems();
		afterPanRefreshes.push(function(anim) refreshItems());
		tracksEl.append(trackEl);
		return trackEl;
	}

	function rebuildAnimPanel() {
		var selection = sceneEditor.getSelection();
		var scrollPanel = element.find(".anim-scroll");
		scrollPanel.empty();
		curveEdits = [];
		afterPanRefreshes = [];

		var sections : Array<{
			elt: PrefabElement,
			curves: Array<Curve>,
			events: Array<Event>
		}> = [];

		for(elt in selection) {
			var root = elt;
			if(Std.instance(elt, hide.prefab.Curve) != null) {
				root = elt.parent;
			}
			var sect = sections.find(s -> s.elt == root);
			if(sect == null) {
				sect = {elt: root, curves: [], events: []};
				sections.push(sect);
			}

			inline function f(elt) {
				var curve = Std.instance(elt, hide.prefab.Curve);
				if(curve != null)
					sect.curves.push(curve);
				var evt = Std.instance(elt, Event);
				if(evt != null)
					sect.events.push(evt);
			}

			f(elt);
			for(child in elt.children)
				f(child);
		}

		for(sec in sections) {
			var objPanel = new Element('<div>
				<div class="tracks-header"><label>${upperCase(sec.elt.name)}</label><div class="addtrack fa fa-plus-circle"></div></div>
				<div class="tracks"></div>
			</div>').appendTo(scrollPanel);
			var addTrackEl = objPanel.find(".addtrack");
			var objElt = Std.instance(sec.elt, hide.prefab.Object3D);
			var shaderElt = Std.instance(sec.elt, hide.prefab.Shader);

			addTrackEl.click(function(e) {
				var menuItems = getNewTrackMenu(sec.elt);
				new hide.comp.ContextMenu(menuItems);
			});
			var tracksEl = objPanel.find(".tracks");

			if(sec.events.length > 0)
				addEventsTrack(sec.events, tracksEl);

			var groups = hide.prefab.Curve.getGroups(sec.curves);
			for(group in groups) {
				addCurvesTrack(group.name, group.items, tracksEl);
			}
		}
	}

	function startDrag(onMove: js.jquery.Event->Void, onStop: js.jquery.Event->Void) {
		var el = new Element(element[0].ownerDocument.body);
		var startX = null, startY = null;
		var dragging = false;
		var threshold = 3;
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
			var curve = new Curve(element);
			curve.name = id;
			if(prop.clamp != null) {
				curve.clampMin = prop.clamp[0];
				curve.clampMax = prop.clamp[1];
			}
			if(prop.def != null) {
				curve.addKey(0, prop.def, Linear);
			}
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
			sceneEditor.selectObjects([element]);
		});
		return added;
	}

	public function getNewTrackMenu(elt: PrefabElement) : Array<hide.comp.ContextMenu.ContextMenuItem> {
		var objElt = Std.instance(elt, hide.prefab.Object3D);
		var shaderElt = Std.instance(elt, hide.prefab.Shader);
		var emitterElt = Std.instance(elt, hide.prefab.fx.Emitter);
		var menuItems : Array<hide.comp.ContextMenu.ContextMenuItem> = [];

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

		var hslTracks : Void -> Array<PropTrackDef> = () -> [{name: "h", def: 0.0}, {name: "s", clamp: [0., 1.], def: 0.0}, {name: "l", clamp: [0., 1.], def: 1.0}];
		var alphaTrack : Void -> Array<PropTrackDef> = () -> [{name: "a", clamp: [0., 1.], def: 1.0}];
		var xyzwTracks : Int -> Array<PropTrackDef> = (n) -> [{name: "x"}, {name: "y"}, {name: "z"}, {name: "w"}].slice(0, n);
		var scaleTracks = groupedTracks("scale", xyzwTracks(3));
		scaleTracks.unshift(trackItem("Uniform", [{name: "scale"}]));

		if(objElt != null) {
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
			menuItems.push(trackItem("Visibility", [{name: "visibility", clamp: [0., 1.]}]));
		}
		if(shaderElt != null && shaderElt.shaderDef != null) {
			var params = shaderElt.shaderDef.shader.data.vars.filter(v -> v.kind == Param);
			for(param in params) {
				var tracks = null;
				var isColor = false;
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
		if(emitterElt != null) {
			function addParam(param : hide.prefab.fx.Emitter.ParamDef, prefix: String) {
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
			for(param in hide.prefab.fx.Emitter.emitterParams) {
				if(!param.animate)
					continue;
				addParam(param, "");
			}
			for(param in hide.prefab.fx.Emitter.instanceParams) {
				if(!param.animate)
					continue;
				addParam(param, "Instance ");
			}
		}
		return menuItems;
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

		var col = h3d.Vector.fromColor(scene.engine.backgroundColor);
		var hsl = col.toColorHSL();
		if(hsl.z > 0.5) hsl.z -= 0.1;
		else hsl.z += 0.1;
		col.makeColor(hsl.x, hsl.y, hsl.z);

		grid.lineStyle(1.0, col.toColor(), 1.0);
		for(ix in -10...11) {
			grid.moveTo(ix, -10, 0);
			grid.lineTo(ix, 10, 0);
			grid.moveTo(-10, ix, 0);
			grid.lineTo(10, ix, 0);

		}
		grid.lineStyle(0);
	}

	function onUpdate(dt:Float) {
		var anim : hide.prefab.fx.FX.FXAnimation = null;
		var ctx = sceneEditor.getContext(data);
		if(ctx != null && ctx.local3d != null) {
			anim = cast ctx.local3d;
		}
		if(!pauseButton.isDown()) {
			currentTime += scene.speed * dt;
			if(timeLineEl != null)
				timeLineEl.css({left: xt(currentTime)});
			if(currentTime >= previewMax) {
				currentTime = previewMin;
				if(data.script != null && data.script.length > 0)
					sceneEditor.refreshScene(); // This allow to reset the scene when values are modified causes edition issues, solves
				anim.setRandSeed(Std.random(0xFFFFFF));
			}
		}

		if(anim != null) {
			anim.setTime(currentTime, currentTime);
		}

		if(statusText != null) {
			var lines : Array<String> = [
				'Time: ${Math.round(currentTime*1000)} ms',
				'Scene objects: ${scene.s3d.getObjectsCount()}',
			];
			statusText.text = lines.join("\n");
		}

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

		if( data.script != scriptEditor.code || !fxScriptParser.firstParse ){
			modified = true;
			fxScriptParser.firstParse = true;
			data.script = scriptEditor.code;
			anim.script = fxScriptParser.createFXScript(scriptEditor.code, anim);
			fxScriptParser.generateUI(anim.script, this);
		}
	}

	static function getTrack(element : PrefabElement, propName : String) {
		return Curve.getCurve(element, propName, false);
	}

	static function upperCase(prop: String) {
		if(prop == null) return "";
		return prop.charAt(0).toUpperCase() + prop.substr(1);
	}

	static var _ = FileTree.registerExtension(FXEditor, ["fx"], { icon : "sitemap", createNew : "FX" });
}