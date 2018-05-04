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
		tools = new hide.comp.Toolbar(root.find(".toolbar"));
		tabs = new hide.comp.Tabs(root.find(".tabs"));
		sceneEditor = new FXSceneEditor(this, context, data);
		root.find(".hide-scene-tree").first().append(sceneEditor.tree.root);
		root.find(".tab").first().append(sceneEditor.properties.root);
		root.find(".scene").first().append(sceneEditor.scene.root);
		root.resize(function(e) {
			refreshTimeline(false);
			rebuildAnimPanel();
		});
		currentVersion = undo.currentID;

		var timeline = root.find(".timeline");
		timeline.mousedown(function(e) {
			var lastX = e.clientX;
			root.mousemove(function(e) {
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
			root.mouseup(function(e) {
				root.off("mousemove");
				root.off("mouseup");
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

	function onSelect(elts : Array<PrefabElement>) {
		rebuildAnimPanel();
	}

	inline function xt(x: Float) return Math.round((x - xOffset) * xScale);
	inline function ixt(px: Float) return px / xScale + xOffset;

	function refreshTimeline(anim: Bool) {
		var scroll = root.find(".timeline-scroll");
		scroll.empty();
		var width = scroll.parent().width();
		var minX = Math.floor(ixt(0));
		var maxX = Math.ceil(ixt(width));
		for(ix in minX...(maxX+1)) {
			var mark = new Element('<span class="mark"></span>').appendTo(scroll);
			mark.css({left: xt(ix)});
			mark.text(ix + ".00");
		}

		var overlay = root.find(".overlay");
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

	function rebuildAnimPanel() {
		var selection = sceneEditor.getSelection();
		var scrollPanel = root.find(".anim-scroll");
		scrollPanel.empty();
		curveEdits = [];
		refreshDopesheetKeys = [];

		for(elt in selection) {
			var objPanel = new Element('<div>
				<label>${elt.name}</label><input class="addtrack" type="button" value="[+]"></input><div class="tracks"></div>
			</div>').appendTo(scrollPanel);
			var addTrackEl = objPanel.find(".addtrack");
			addTrackEl.click(function(e) {
				var menuItems: Array<hide.comp.ContextMenu.ContextMenuItem>= [];
				inline function hasTrack(pname) {
					return getTrack(elt, pname) != null;
				}

				if(Std.is(elt, hide.prefab.Object3D)) {
					var defaultTracks = ["x", "y", "z", "rotationX", "rotationY", "rotationZ", "scaleX", "scaleY", "scaleZ", "visibility"];
					for(t in defaultTracks) {
						menuItems.push({
							label: upperCase(t),
							click: ()->addTrack(elt, t),
							enabled: !hasTrack(t)});
					}
				}
				new hide.comp.ContextMenu(menuItems);
			});
			var tracksEl = objPanel.find(".tracks");
			var curves = elt.getAll(hide.prefab.Curve);
			for(curve in curves) {
				var trackEl = new Element('<div class="track">
					<div class="track-header">
						<div class="track-prop">
							<label>${curve.name}</label>
							<div class="track-toggle"><div class="icon fa"></div></div>
						</div>
						<div class="dopesheet"></div>
					</div>
					<div class="curve"></div>
				</div>');
				var trackToggle = trackEl.find(".track-toggle");
				tracksEl.append(trackEl);
				
				var curveEl = trackEl.find(".curve");
				var curveEdit = new hide.comp.CurveEditor(curveEl, this.undo);
				var cpath = curve.getAbsPath();
				var trackKey = "trackVisible:" + cpath;
				var expand = getDisplayState(trackKey) == true;
				curveEdit.saveDisplayKey = getPath() + "/" + cpath;
				curveEdit.lockViewX = true;
				curveEdit.xOffset = xOffset;
				curveEdit.xScale = xScale;
				curveEdit.curve = curve;
				curveEdits.push(curveEdit);
				function updateExpanded() {
					var icon = trackToggle.find(".icon");
					if(expand)
						icon.removeClass("fa-angle-right").addClass("fa-angle-down");
					else
						icon.removeClass("fa-angle-down").addClass("fa-angle-right");
					curveEl.toggleClass("hidden", !expand);
				}
				trackToggle.click(function(e) {
					expand = !expand;
					saveDisplayState(trackKey, expand);
					updateExpanded();
				});
				var dopesheet = trackEl.find(".dopesheet");
				function refreshDopesheet() {
					dopesheet.empty();
					for(key in curve.keys) {
						var keyEl = new Element('<span class="key">').appendTo(dopesheet);
						function update() keyEl.css({left: xt(key.time)});
						update();
						keyEl.mousedown(function(e) {
							var offset = dopesheet.offset();
							var prevVal = key.time;
							startDrag(function(e) {
								var x = ixt(e.clientX - offset.left);
								key.time = x;
								curveEdit.refreshGraph(true, key);
								update();
							}, function(e) {
								curveEdit.refreshGraph();
								var newVal = key.time;
								undo.change(Custom(function(undo) {
									if(undo)
										key.time = prevVal;
									else
										key.time = newVal;
									update();
									curveEdit.refreshGraph();
								}));
							});
						});
						refreshDopesheetKeys.push(function(anim) {
							update();
						});
					}
				}
				refreshDopesheet();
				curveEdit.onChange = function(anim) {
					refreshDopesheet();
				}
				updateExpanded();
			}
		}
	}

	function startDrag(onMove: js.jquery.Event->Void, onStop: js.jquery.Event->Void) {
		var el = new Element(root[0].ownerDocument.body);
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
		return element.getOpt(hide.prefab.Curve, propName);
	}

	function addTrack(element : PrefabElement, propName : String) {
		var curve = new hide.prefab.Curve(element);
		curve.name = upperCase(propName);
		rebuildAnimPanel();
		return curve;
	}

	function removeTrack(element : PrefabElement, propName : String) {
		// TODO
		// return element.get(hide.prefab.Curve, propName);
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