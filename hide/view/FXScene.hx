package hide.view;
using Lambda;

import hide.Element;
import hide.prefab.Prefab in PrefabElement;
import hide.prefab.Curve;

typedef PropTrackDef = {
	name: String,
	?clamp: Array<Float>
};

@:access(hide.view.FXScene)
class FXEditContext extends hide.prefab.EditContext {
	var parent : FXScene;
	public function new(parent, context) {
		super(context);
		this.parent = parent;
	}
	override function onChange(p, propName) {
		parent.onPrefabChange(p, propName);
	}
}

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

	override function onPrefabChange(p: PrefabElement, ?pname: String) {
		super.onPrefabChange(p, pname);
		parent.onPrefabChange(p, pname);
	}

	override function update(dt) {
		super.update(dt);
		parent.onUpdate(dt);
	}

	override function selectObjects( elts, ?includeTree) {
		super.selectObjects(elts, includeTree);
		parent.onSelect(elts);
	}

	override function getNewContextMenu(current: PrefabElement) {
		if(current != null && current.to(hide.prefab.Shader) != null) {
			return parent.getNewTrackMenu(current);
		}
		else {
			var registered = new Array<hide.comp.ContextMenu.ContextMenuItem>();

			registered.push({
				label: "Animation",
				menu: parent.getNewTrackMenu(current)
			});

			var allRegs = @:privateAccess hide.prefab.Library.registeredElements;
			var allowed = ["model", "object", "shader", "emitter", "constraint", "polygon", "material"];
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
}

class FXScene extends FileView {

	var sceneEditor : FXSceneEditor;
	var data : hide.prefab.fx.FXScene;
	var context : hide.prefab.Context;
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
	var refreshDopesheetKeys : Array<Bool->Void> = [];

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
		saveDisplayKey = "FXScene/" + getPath().split("\\").join("/").substr(0,-1);
		currentTime = 0.;
		data = new hide.prefab.fx.FXScene();
		var content = sys.io.File.getContent(getPath());
		data.load(haxe.Json.parse(content));
		currentSign = haxe.crypto.Md5.encode(content);

		context = new hide.prefab.Context();
		context.onError = function(e) {
			ide.error(e);
		};
		context.init();

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
						<div class="tab" name="Scene" icon="sitemap">
							<div class="hide-block" style="height:40%">
								<div class="hide-scene-tree hide-list">
								</div>
							</div>
							<div class="hide-scroll"></div>
						</div>
						<div class="tab" name="Properties" icon="cog">
							<div class="fx-props"></div>
						</div>
					</div>
				</div>
			</div>');
		tools = new hide.comp.Toolbar(null,element.find(".toolbar"));
		tabs = new hide.comp.Tabs(null,element.find(".tabs"));
		sceneEditor = new FXSceneEditor(this, context, data);
		element.find(".hide-scene-tree").first().append(sceneEditor.tree.element);
		element.find(".hide-scroll").first().append(sceneEditor.properties.element);
		element.find(".scene").first().append(sceneEditor.scene.element);
		element.resize(function(e) {
			refreshTimeline(false);
			rebuildAnimPanel();
		});
		fxprops = new hide.comp.PropsEditor(undo,null,element.find(".fx-props"));
		{
			var edit = new FXEditContext(this, context);
			edit.prefabPath = state.path;
			edit.properties = fxprops;
			edit.scene = sceneEditor.scene;
			edit.cleanups = [];
			data.edit(edit);
		}

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
				selectMin = ixt(e.clientX - xoffset);
			}
			else if(ctrl) {
				previewMin = ixt(e.clientX - xoffset);
			}

			function updateMouse(e: js.jquery.Event) {
				var dt = (e.clientX - lastX) / xScale;
				if(e.which == 2) {
					xOffset -= dt;
					xOffset = hxd.Math.max(xOffset, 0);
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
					previewMax = data.duration;
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
		previewMax = data.duration;
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
		axis.lineStyle(2,0xFF0000);
		axis.lineTo(1,0,0);
		axis.lineStyle(1,0x00FF00);
		axis.moveTo(0,0,0);
		axis.lineTo(0,1,0);
		axis.lineStyle(1,0x0000FF);
		axis.moveTo(0,0,0);
		axis.lineTo(0,0,1);
		axis.material.mainPass.setPassName("debuggeom");
		axis.visible = showGrid;

		tools.saveDisplayKey = "FXScene/tools";
		tools.addButton("video-camera", "Perspective camera", () -> sceneEditor.resetCamera(false));

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

		updateGrid();
	}

	function onPrefabChange(p: PrefabElement, ?pname: String) {
		if(p == data) {
			previewMax = hxd.Math.min(data.duration, previewMax);
			refreshTimeline(false);
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
				sceneEditor.dropModels(models, parent);
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
		var maxX = Math.ceil(hxd.Math.min(data.duration, ixt(width)));
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

		//var preview = new Element('<span class="preview"></span>').appendTo(overlay);
		// preview.css({left: xt(previewMin), width: xt(previewMax) - xt(previewMin)});
		var prevLeft = new Element('<span class="preview-left"></span>').appendTo(overlay);
		prevLeft.css({left: 0, width: xt(previewMin)});
		var prevRight = new Element('<span class="preview-right"></span>').appendTo(overlay);
		prevRight.css({left: xt(previewMax), width: xt(data.duration) - xt(previewMax)});
	}

	function afterPan(anim: Bool) {
		for(curve in curveEdits) {
			curve.setPan(xOffset, curve.yOffset);
		}
		for(clb in refreshDopesheetKeys) {
			clb(anim);
		}
	}

	function addTrackEdit(trackName: String, curves: Array<Curve>, tracksEl: Element) {
		var keyTimeTolerance = 0.05;
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
		}
		trackEl.find(".track-prop").click(function(e) {
			expand = !expand;
			saveDisplayState(trackKey, expand);
			updateExpanded();
		});
		var dopesheet = trackEl.find(".dopesheet");
		var trackEdits : Array<hide.comp.CurveEditor> = [];
		var evaluator = new hide.prefab.fx.FXScene.Evaluator(new hxd.Rand(0));

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
				cp.value = getKeyColor(key).toColor();
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
						setCurveVal(".a", col.a);
					}
					else {
						setCurveVal(".r", col.x);
						setCurveVal(".g", col.y);
						setCurveVal(".b", col.z);
						setCurveVal(".a", col.a);
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
				refreshDopesheetKeys.push(function(anim) {
					updatePos();
				});
				refreshKey(key, keyEl);
			}
		}
		for(curve in curves) {
			var curveContainer = new Element('<div class="curve"></div>').appendTo(curvesContainer);
			var curveEdit = new hide.comp.CurveEditor(this.undo, curveContainer);
			curveEdit.saveDisplayKey = getPath() + "/" + curve.getAbsPath();
			curveEdit.lockViewX = true;
			curveEdit.xOffset = xOffset;
			curveEdit.xScale = xScale;
			curveEdit.curve = curve;
			curveEdit.onChange = function(anim) {
				refreshDopesheet();
			}
			// curveEdit.onKeyMove = function(key, ptime, pval) {
			// 	dragKey(curveEdit, ptime, key.time);
			// }
			trackEdits.push(curveEdit);
			curveEdits.push(curveEdit);
		}
		refreshDopesheet();
		updateExpanded();
	}


	function rebuildAnimPanel() {
		var selection = sceneEditor.getSelection();
		var scrollPanel = element.find(".anim-scroll");
		scrollPanel.empty();
		curveEdits = [];
		refreshDopesheetKeys = [];

		var sections : Array<{
			elt: PrefabElement,
			curves: Array<Curve>
		}> = [];

		for(elt in selection) {
			var root = elt;
			if(Std.instance(elt, hide.prefab.Curve) != null) {
				root = elt.parent;
			}
			var sect = sections.find(s -> s.elt == root);
			if(sect == null) {
				sect = {elt: root, curves: []};
				sections.push(sect);
			}
			var curves = elt.flatten(hide.prefab.Curve);
			for(c in curves) {
				sect.curves.push(c);
			}
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
			var groups = hide.prefab.Curve.getGroups(sec.curves);
			for(group in groups) {
				addTrackEdit(group.name, group.items, tracksEl);
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

	function addTracks(element : PrefabElement, props : Array<PropTrackDef>) {
		var added = [];
		for(prop in props) {
			if(element.getOpt(Curve, prop.name) != null)
				continue;
			var curve = new Curve(element);
			curve.name = prop.name;
			if(prop.clamp != null) {
				curve.clampMin = prop.clamp[0];
				curve.clampMax = prop.clamp[1];
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
		var menuItems : Array<hide.comp.ContextMenu.ContextMenuItem> = [];

		inline function hasTrack(pname) {
			return getTrack(elt, pname) != null;
		}

		function trackItem(name: String, props: Array<PropTrackDef>) : hide.comp.ContextMenu.ContextMenuItem {
			var hasAllTracks = true;
			for(p in props) {
				if(getTrack(elt, p.name) == null)
					hasAllTracks = false;
			}
			return {
				label: upperCase(name),
				click: function() {
					var added = addTracks(elt, props);
				},
				enabled: !hasAllTracks };
		}

		function groupedTracks(prefix: String, props: Array<PropTrackDef>) : Array<hide.comp.ContextMenu.ContextMenuItem> {
			var allLabel = [for(p in props) upperCase(p.name)].join("/");
			var ret = [];
			for(p in props)
				p.name = prefix + "." + p.name;
			ret.push(trackItem(allLabel, props));
			for(p in props) {
				ret.push(trackItem(p.name, [p]));
			}
			return ret;
		}

		var hslaTracks : Array<PropTrackDef> = [{name: "h"}, {name: "s", clamp: [0., 1.]}, {name: "l", clamp: [0., 1.]}, {name: "a", clamp: [0., 1.]}];
		var xyzTracks : Array<PropTrackDef> = [{name: "x"}, {name: "y"}, {name: "z"}];

		if(objElt != null) {
			menuItems.push({
				label: "Position",
				menu: groupedTracks("position", xyzTracks),
			});
			menuItems.push({
				label: "Rotation",
				menu: groupedTracks("rotation", xyzTracks),
			});
			menuItems.push({
				label: "Scale",
				menu: groupedTracks("scale", xyzTracks),
			});
			menuItems.push({
				label: "Color",
				menu: groupedTracks("color", hslaTracks),
			});
			menuItems.push(trackItem("Visibility", [{name: "visibility", clamp: [0., 1.]}]));
		}
		if(shaderElt != null && shaderElt.shaderDef != null) {
			var params = shaderElt.shaderDef.shader.data.vars.filter(v -> v.kind == Param);
			for(param in params) {
				var tracks = null;
				var isColor = false;
				var subItems : Array<hide.comp.ContextMenu.ContextMenuItem> = [];
				switch(param.type) {
					case TVec(n, VFloat):
						if(n <= 4) {
							var components : Array<PropTrackDef> = [];
							if(param.name.toLowerCase().indexOf("color") >= 0)
								components = hslaTracks;
							else
								components = [{name:"x"}, {name:"y"}, {name:"z"}, {name:"w"}];
							subItems = groupedTracks(param.name, components);

						}
					default:
				}
				if(subItems.length > 0) {
					menuItems.push({
						label: upperCase(param.name),
						menu: subItems
					});
				}
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
		if(!pauseButton.isDown()) {
			currentTime += scene.speed * dt / hxd.Timer.wantedFPS;
			if(timeLineEl != null)
				timeLineEl.css({left: xt(currentTime)});
			if(currentTime >= previewMax) {
				currentTime = previewMin;
			}
		}
		
		var ctx = sceneEditor.getContext(data);
		if(ctx != null && ctx.local3d != null) {
			var anim : hide.prefab.fx.FXScene.FXAnimation = cast ctx.local3d;
			anim.setTime(currentTime);
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
	}


	static function getTrack(element : PrefabElement, propName : String) {
		return element.getOpt(Curve, propName);
	}


	static function upperCase(prop: String) {
		if(prop == null) return "";
		return prop.charAt(0).toUpperCase() + prop.substr(1);
	}

	static var _ = FileTree.registerExtension(FXScene,["fx"], { icon : "sitemap", createNew : "FX" });
}