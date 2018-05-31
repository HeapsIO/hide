package hide.view;
using Lambda;

import hide.Element;
import hide.prefab.Prefab in PrefabElement;
import hide.prefab.Curve;

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
		var allowed = ["model", "object", "shader"];
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

	var xScale = 200.;
	var xOffset = 0.;

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
			</div>');
		tools = new hide.comp.Toolbar(null,element.find(".toolbar"));
		tabs = new hide.comp.Tabs(null,element.find(".tabs"));
		sceneEditor = new FXSceneEditor(this, context, data);
		element.find(".hide-scene-tree").first().append(sceneEditor.tree.element);
		element.find(".tab").first().append(sceneEditor.properties.element);
		element.find(".scene").first().append(sceneEditor.scene.element);
		element.resize(function(e) {
			refreshTimeline(false);
			rebuildAnimPanel();
		});
		currentVersion = undo.currentID;

		var timeline = element.find(".timeline");
		timeline.mousedown(function(e) {
			var lastX = e.clientX;
			element.mousemove(function(e) {
				var dt = (e.clientX - lastX) / xScale;
				if(e.which == 2) {
					xOffset -= dt;
					xOffset = hxd.Math.max(xOffset, 0);
				}
				else if(e.which == 1) {
					currentTime = ixt(e.clientX - timeline.offset().left);
					currentTime = hxd.Math.max(currentTime, 0);
				}
				lastX = e.clientX;
				refreshTimeline(true);
				afterPan(true);
			});
			element.mouseup(function(e) {
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

		selectMin = 0.6;
		selectMax = 3.2;
		previewMin = 0.6;
		previewMax = 3.2;
		refreshTimeline(false);
	}

	public function onSceneReady() {
		light = sceneEditor.scene.s3d.find(function(o) return Std.instance(o, h3d.scene.DirLight));
		if( light == null ) {
			light = new h3d.scene.DirLight(new h3d.Vector(), scene.s3d);
			light.enableSpecular = true;
		} else
			light = null;

		tools.saveDisplayKey = "FXScene/tools";
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
		var maxX = Math.ceil(ixt(width));
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

		var preview = new Element('<span class="preview"></span>').appendTo(overlay);
		preview.css({left: xt(previewMin), width: xt(previewMax) - xt(previewMin)});
		var prevLeft = new Element('<span class="preview-left"></span>').appendTo(overlay);
		prevLeft.css({left: xt(previewMin)});
		var prevRight = new Element('<span class="preview-right"></span>').appendTo(overlay);
		prevRight.css({left: xt(previewMax)});
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
		trackToggle.click(function(e) {
			expand = !expand;
			saveDisplayState(trackKey, expand);
			updateExpanded();
		});
		var dopesheet = trackEl.find(".dopesheet");
		var trackEdits : Array<hide.comp.CurveEditor> = [];

		function backupCurves() {
			return [for(c in curves) haxe.Json.parse(haxe.Json.stringify(c.save()))];
		}
		var lastBackup = backupCurves();

		function beforeChange() {
			lastBackup = backupCurves();
		}

		function dragKey(from: hide.comp.CurveEditor, prevTime: Float, newTime: Float) {
			var tolerance = 0.25;
			for(edit in trackEdits) {
				if(edit == from) continue;
				// edit.curve.keys.find(k -> hxd.Math.abs(k.time - prevTime) < 
				var k = edit.curve.findKey(prevTime, tolerance);
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

		var refreshDopesheet : Void -> Void;

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
				function update() keyEl.css({left: xt(refKeys[ik].time)});
				update();
				keyEl.mousedown(function(e) {
					var offset = dopesheet.offset();
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
						update();
					}, function(e) {
						afterChange();
					});
				});
				refreshDopesheetKeys.push(function(anim) {
					update();
				});
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
			curveEdit.onKeyMove = function(key, ptime, pval) {
				dragKey(curveEdit, ptime, key.time);
			}
			trackEdits.push(curveEdit);
			curveEdits.push(curveEdit);
		}
		refreshDopesheet();
		updateExpanded();
	}

	static function getTrackGroups(curves: Array<Curve>) {
		var groups : Array<{name: String, items: Array<Curve>}> = [];
		for(c in curves) {
			var prefix = c.name.split(".")[0];
			var g = groups.find(g -> g.name == prefix);
			if(g == null) {
				groups.push({
					name: prefix,
					items: [c]
				});
			}
			else {
				g.items.push(c);
			}
		}
		return groups;
	}

	function rebuildAnimPanel() {
		var selection = sceneEditor.getSelection();
		var scrollPanel = element.find(".anim-scroll");
		scrollPanel.empty();
		curveEdits = [];
		refreshDopesheetKeys = [];

		for(elt in selection) {
			var objPanel = new Element('<div>
				<label>${upperCase(elt.name)}</label><input class="addtrack" type="button" value="[+]"></input><div class="tracks"></div>
			</div>').appendTo(scrollPanel);
			var addTrackEl = objPanel.find(".addtrack");
			var objElt = Std.instance(elt, hide.prefab.Object3D);
			var shaderElt = Std.instance(elt, hide.prefab.Shader);

			addTrackEl.click(function(e) {
				var menuItems: Array<hide.comp.ContextMenu.ContextMenuItem>= [];
				inline function hasTrack(pname) {
					return getTrack(elt, pname) != null;
				}

				if(objElt != null) {
					var defaultTracks = ["x", "y", "z", "rotationX", "rotationY", "rotationZ", "scaleX", "scaleY", "scaleZ", "visibility"];
					for(t in defaultTracks) {
						menuItems.push({
							label: upperCase(t),
							click: function() {
								addTracks(elt, [t]);
							},	
							enabled: !hasTrack(t)});
					}
				}
				else if(shaderElt != null && shaderElt.shaderDef != null) {
					var params = shaderElt.shaderDef.shader.data.vars.filter(v -> v.kind == Param);
					for(param in params) {
						var tracks = null;
						switch(param.type) {
							case TVec(n, VFloat):
								if(n <= 4) {
									if(param.name.toLowerCase().indexOf("color") >= 0) {
										tracks = [for(i in 0...n) ["h", "s", "l", "a"][i]];
									}
									else {
										tracks = [for(i in 0...n) ["x", "y", "z", "w"][i]];
									}
								}
							default:
						}
						if(tracks != null && tracks.length > 0) {
							menuItems.push({
								label: upperCase(param.name),
								click: function() {
									addTracks(elt, [for(t in tracks) param.name + "." + t]);
								},
								enabled: true});
						}
					}
				}
				new hide.comp.ContextMenu(menuItems);
			});
			var tracksEl = objPanel.find(".tracks");
			var curves = elt.getAll(Curve);

			var groups = getTrackGroups(curves);
			for(group in groups) {
				addTrackEdit(group.name, group.items, tracksEl);
			}
		}
	}

	function startDrag(onMove: js.jquery.Event->Void, onStop: js.jquery.Event->Void) {
		var el = new Element(element[0].ownerDocument.body);
		el.on("mousemove.fxedit", onMove);
		el.on("mouseup.fxedit", function(e: js.jquery.Event) {
			el.off("mousemove.fxedit");
			el.off("mouseup.fxedit");
			e.preventDefault();
			e.stopPropagation();
			onStop(e);
		});
	}

	static function getTrack(element : PrefabElement, propName : String) {
		return element.getOpt(Curve, propName);
	}

	function addTracks(element : PrefabElement, props : Array<String>) {
		var added = [];
		for(propName in props) {
			if(element.getOpt(Curve, propName) != null)
				return;
			var curve = new Curve(element);
			curve.name = propName;
			added.push(curve);
		}

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
	}

	function removeTrack(element : PrefabElement, propName : String) {
		// TODO
		// return element.get(Curve, propName);
	}

	function onUpdate(dt:Float) {

		var allObjects = data.getAll(hide.prefab.Object3D);
		for(element in allObjects) {
			var obj3d = sceneEditor.getObject(element);
			if(obj3d == null)
				continue;
			var curves = data.getCurves(element);
			var mat = data.getTransform(curves, currentTime);
			mat.multiply(element.getTransform(), mat);
			obj3d.setTransform(mat);
			if(curves.visibility != null) {
				var visible = curves.visibility.getVal(currentTime) > 0.5;
				obj3d.visible = element.visible && visible;
			}
		}

		if(true) {
			currentTime += dt / hxd.Timer.wantedFPS;
			if(timeLineEl != null)
				timeLineEl.css({left: xt(currentTime)});
			if(currentTime >= selectMax) {
				currentTime = selectMin;
			}
		}

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

	static function upperCase(prop: String) {
		return prop.charAt(0).toUpperCase() + prop.substr(1);
	}

	static var _ = FileTree.registerExtension(FXScene,["fx"], { icon : "sitemap", createNew : "FX" });
}