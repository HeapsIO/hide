package hrt.prefab.l3d;

#if !editor

class PrefabSprayObject extends h3d.scene.Object {
}

class PrefabSpray extends Object3D {

	@:s var prefabs : Array<{ path : String }>;


	override function createObject( ctx : Context ) {
		var mspray = new PrefabSprayObject(ctx.local3d);
		return mspray;
	}


	override function make( ctx : Context ) {
		if( !enabled )
			return ctx;
		return super.make(ctx);
	}

	override function makeChild( ctx : Context, p : hrt.prefab.Prefab ) {
		children.sort(function(c1, c2) {
			return Std.isOfType(c1, Object3D) ? -1 : 1;
		});
		super.makeChild(ctx, p);
	}

	static var _ = Library.register("PrefabSpray", PrefabSpray);

}

#else

import h3d.Vector;
import hxd.Key as K;

typedef Prefab = {
	var path: String;
}

typedef PrefabSet = {
	var name: String;
	var prefabs: Array<Prefab>;
	var config: PrefabSprayConfig;
}

typedef PrefabSetGroup = {
	var name: String;
	var sets: Array<PrefabSet>;
}

typedef PrefabSprayConfig = {
	var density : Int;
	var step : Float;
	var densityOffset : Int;
	var radius : Float;
	var deleteRadius : Float;
	var scale : Float;
	var scaleOffset : Float;
	var rotation : Float;
	var rotationOffset : Float;
	var zOffset: Float;
	var dontRepeatPrefab : Bool;
	var enableBrush : Bool;
	var orientTerrain : Float;
	var tiltAmount : Float;
}


@:access(hrt.prefab.l3d.PrefabSpray)
class PrefabSprayObject extends h3d.scene.Object {

	var ps : PrefabSpray;

	public function new(ps,?parent) {
		this.ps = ps;
		super(parent);
	}

	public function redraw(updateShaders=false) {
		getBounds(); // force absBos calculus on children
		for( c in children ) {
			c.culled = false;
			if( c.alwaysSync ) continue;
		}
	}

}

class PrefabSpray extends Object3D {

	@:s var prefabs : Array<Prefab> = []; // specific set for this prefab spray
	@:s var defaultConfig: PrefabSprayConfig;
	@:s var currentPresetName : String = null;
	@:s var currentSetName : String = null;

	var sceneEditor : hide.comp.SceneEditor;

	var undo(get, null):hide.ui.UndoHistory;
	function get_undo() { return sceneEditor.view.undo; }

	var lastIndexPrefab = -1;
	var allSetGroups : Array<PrefabSetGroup>;
	var setGroup : PrefabSetGroup;
	var currentSet : PrefabSet;

	var currentPrefabs(get, null) : Array<Prefab>;
	function get_currentPrefabs() {
		if (currentSet != null)
			return currentSet.prefabs;
		else
			return prefabs;
	}

	var currentConfig(get, null) : PrefabSprayConfig;
	function get_currentConfig() {
		var config = (currentSet != null) ? currentSet.config : defaultConfig;
		if (config == null) config = getDefaultConfig();
		return config;
	}

	var sprayEnable : Bool = false;
	var interactive : h2d.Interactive;
	var gBrushes : Array<h3d.scene.Mesh>;

	var timerCicle : haxe.Timer;

	var lastSpray : Float = 0;
	var lastPrefabPos : h3d.col.Point;
	var invParent : h3d.Matrix;

	var shared : ContextShared;

	var PREFAB_SPRAY_CONFIG_FILE = "prefabSprayProps.json";
	var PREFAB_SPRAY_CONFIG_PATH(get, null) : String;
	function get_PREFAB_SPRAY_CONFIG_PATH() {
		return hide.Ide.inst.resourceDir + "/" + PREFAB_SPRAY_CONFIG_FILE;
	}

	override function save() {
		clearPreview();
		return super.save();
	}

	function clearPreview() {
		// prevent saving preview
		if( previewPrefabs.length > 0 ) {
			sceneEditor.deleteElements(previewPrefabs, () -> { }, false, false);
			previewPrefabs = [];
		}
	}

	function getDefaultConfig() : PrefabSprayConfig {
		return {
			density: 1,
			step : 0.,
			densityOffset: 0,
			radius: 0.1,
			deleteRadius: 5,
			scale: 1,
			scaleOffset: 0.1,
			rotation: 0,
			rotationOffset: 0,
			zOffset: 0,
			dontRepeatPrefab: true,
			enableBrush: true,
			orientTerrain : 0,
			tiltAmount : 0,
		};
	}

	override function getHideProps() : HideProps {
		return { icon : "paint-brush", name : "PrefabSpray", hideChildren : p -> return Std.isOfType(p, Object3D) };
	}

	function extractPrefabName( path : String ) : String {
		if( path == null ) return "None";
		var childParts = path.split("/");
		return childParts[childParts.length - 1].split(".")[0];
	}

	function setGroundPos( ectx : EditContext, obj : Object3D = null, absPos : h3d.col.Point = null ) : { mz : Float, rotX : Float, rotY : Float, rotZ : Float } {
		if (absPos == null && obj == null)
			throw "setGroundPos should use either object or absPos";
		var tx : Float; var ty : Float; var tz : Float;
		if ( absPos != null ) {
			tx = absPos.x;
			ty = absPos.y;
			tz = absPos.z;
		} else { // obj != null
			tx = obj.getAbsPos().tx;
			ty = obj.getAbsPos().ty;
			tz = obj.getAbsPos().tz;
		}
		var config = currentConfig;
		var groundZ = ectx.positionToGroundZ(tx, ty);
		var mz = config.zOffset + groundZ - tz;
		if ( obj != null )
			obj.z += mz;
		var orient = config.orientTerrain;
		var tilt = config.tiltAmount;

		inline function getPoint(dx,dy) {
			var dz = ectx.positionToGroundZ(tx + 0.1 * dx, ty + 0.1 * dy) - groundZ;
			return new h3d.col.Point(dx*0.1, dy*0.1, dz * orient);
		}

		var px = getPoint(1,0);
		var py = getPoint(0,1);
		var n = px.cross(py).normalized();
		var q = new h3d.Quat();
		q.initNormal(n);
		var m = q.toMatrix();
		m.prependRotation(Math.random()*tilt*Math.PI/8,0,  (config.rotation + (Std.random(2) == 0 ? -1 : 1) * Math.round(Math.random() * config.rotationOffset)) * Math.PI / 180);
		var a = m.getEulerAngles();
		var rotX = hxd.Math.fmt(a.x * 180 / Math.PI);
		var rotY = hxd.Math.fmt(a.y * 180 / Math.PI);
		var rotZ = hxd.Math.fmt(a.z * 180 / Math.PI);
		if ( obj != null ) {
			obj.rotationX = rotX;
			obj.rotationY = rotY;
			obj.rotationZ = rotZ;
		}
		return { mz : mz, rotX : rotX, rotY : rotY, rotZ : rotZ };
	}

	var wasEdited = false;
	var previewPrefabs : Array<hrt.prefab.Prefab> = [];
	var sprayedPrefabs : Array<hrt.prefab.Prefab> = [];
	var selectElement : hide.Element;
	override function edit( ectx : EditContext ) {

		invParent = getAbsPos().clone();
		invParent.invert();

		if (defaultConfig == null) defaultConfig = getDefaultConfig();
		if (sceneEditor == null) {
			allSetGroups = if( sys.FileSystem.exists(PREFAB_SPRAY_CONFIG_PATH) )
				try hide.Ide.inst.parseJSON(sys.io.File.getContent(PREFAB_SPRAY_CONFIG_PATH)) catch( e : Dynamic ) throw e+" (in "+PREFAB_SPRAY_CONFIG_PATH+")";
			else
				[];
		}
		sceneEditor = ectx.scene.editor;

		var props = new hide.Element('<div class="group" name="Prefabs"></div>');

		var preset = new hide.Element('<div class="btn-list" align="center" ></div>').appendTo(props);

		var presetChoice = new hide.Element('<div align="center" ></div>').appendTo(preset);

		var selectPresetElt = new hide.Element('<select style="width: 150px" ></select>').appendTo(presetChoice);

		function updateSelectPreset() {
			selectPresetElt.empty();
			var allSetGroupsName = [null];
			for (g in allSetGroups) allSetGroupsName.push(g.name);
			for (presetValue in allSetGroupsName) {
				var selected = (currentPresetName == presetValue);
				var presetName = (presetValue == null) ? "No preset" : presetValue;
				selectPresetElt.append(new hide.Element('<option ${(selected) ? 'selected=selected' : ''} value="${presetValue}"" >${presetName}</option>'));
			}
			selectPresetElt.append(new hide.Element('<option value="#add">-- Add preset --</option>'));
		}
		updateSelectPreset();

		var editPresetName = new hide.Element('<button>Edit</button>').appendTo(presetChoice);
		var deletePreset = new hide.Element('<button>Del.</button>').appendTo(presetChoice);

		var setsList = new hide.Element('<div align="center" ></div>').appendTo(preset);

		selectElement = new hide.Element('<select multiple size="6" style="width: 300px" ></select>').appendTo(props);
		function createPrefabElement(path: String) {
			var elt = new hide.Element('<option value="$path">${extractPrefabName(path)}</option>');
			elt.contextmenu(function(e) {
				e.preventDefault();
				new hide.comp.ContextMenu([
					{ label : "Swap Prefab", click : function() hide.Ide.inst.chooseFile(["prefab", "l3d"] , function (newPath) {
						removePrefabPath(elt.val());
						addPrefabPath(newPath);
						for (child in children) {
							var prefab = child.to(hrt.prefab.Object3D);
							if (prefab != null && prefab.source == elt.val()) {
								prefab.source = newPath;
							}
						}
						elt.val(newPath);
						elt.html(extractPrefabName(newPath));
						sceneEditor.refresh();
						undo.change(Custom(function(undo) {
							if(undo) {
								removePrefabPath(newPath);
								addPrefabPath(path);
								for (child in children) {
									var prefab = child.to(hrt.prefab.Object3D);
									if (prefab != null && prefab.source == elt.val()) {
										prefab.source = path;
									}
								}
								elt.val(path);
								elt.html(extractPrefabName(path));
								sceneEditor.refresh();
							}
							else {
								removePrefabPath(elt.val());
								addPrefabPath(newPath);
								for (child in children) {
									var prefab = child.to(hrt.prefab.Object3D);
									if (prefab != null && prefab.source == elt.val()) {
										prefab.source = newPath;
									}
								}
								elt.val(newPath);
								elt.html(extractPrefabName(newPath));
								sceneEditor.refresh();
							}
						}));
					}) },
				]);
				return false;
			});
			selectElement.append(elt);
		}

		function onChangeSet() {
			selectElement.empty();
			for (m in currentPrefabs.copy()) {
				var path : String = null;
				if (Std.isOfType(m, String)) { // retro-compatibility
					path = cast m;
					currentPrefabs.remove(m);
					addPrefabPath(path);
				} else {
					path = m.path;
				}
				createPrefabElement(path);
			}
			updateConfig();
		}

		var selectedSetElt : hide.Element = null;
		function setSet(set: PrefabSet, setElt : hide.Element) {
			currentSetName = (set != null) ? set.name : null;
			currentSet = set;
			if (selectedSetElt != null)
				selectedSetElt.css("border-color", "#444444");
			selectedSetElt = setElt;
			if (selectedSetElt != null)
				selectedSetElt.css("border-color", "green");
			onChangeSet();
		}

		function onChangePreset(init : Bool = false) {
			if (currentPresetName != null) {
				var tmp = allSetGroups.filter(g -> g.name == currentPresetName);
				if (tmp.length > 0)
					setGroup = tmp[0];
				else
					return;
			} else {
				setGroup = null;
				setSet(null, null);
			}
			setsList.empty();
			if (setGroup != null) {
				if (!init)
					currentSetName = setGroup.sets[0].name;
				for (s in setGroup.sets) {
					var setElt = new hide.Element('<div style="margin: 5px; padding: 10px; border: solid 1px #444444; display: inline-block;" ></div>').appendTo(setsList);
					var inputSetElt = new hide.Element('<input type="text" style="width: 75px; border: none; padding: 0; text-align: center;" value="${s.name}" />').appendTo(setElt);
					setElt.on("click", function(e) {
						setSet(s, setElt);
					});
					inputSetElt.on("change", function(e) {
						var value : String = inputSetElt.val();
						if (value != null && value.length > 0) {
							s.name = value;
						} else {
							inputSetElt.val(s.name);
						}
					});
					if (s.name == currentSetName) setSet(s, setElt);
				}
				var addSet = new hide.Element('<div style="margin: 5px; padding: 10px; border: solid 1px #444444; display: inline-block;" >Add set</div>').appendTo(setsList);
				addSet.on("click", function(e) {
					var name = hide.Ide.inst.ask("Name set:");
					if (name == null || name.length == 0) return;
					setGroup.sets.push({
						name: name,
						prefabs: [],
						config: getDefaultConfig()
					});
					currentSetName = name;
					onChangePreset();
				});
			}
		}
		selectPresetElt.on("change", function() {
			var value = selectPresetElt.val();
			if (value == "null") value = null;
			if (value == "#add") {
				var name = hide.Ide.inst.ask("Name preset:");
				var groups = allSetGroups.filter(g -> g.name == name);
				if (name == null || name.length == 0 || groups.length > 0)
					return;
				allSetGroups.push({
					name: name,
					sets: [{
						name: "SetName",
						prefabs: [],
						config: getDefaultConfig()
					}]
				});
				currentPresetName = name;
				currentSetName = "SetName";
				updateSelectPreset();
				onChangePreset();
				return;
			}
			currentPresetName = value;
			onChangePreset();
		});

		editPresetName.on("click", function() {
			if (currentPresetName == null) return;
			var preset = allSetGroups.filter(s -> s.name == currentPresetName);
			if (preset.length == 0) return;
			var name = hide.Ide.inst.ask("New name preset:");
			if (name == null || name.length == 0) return;
			preset[0].name = name;
			currentPresetName = name;
			updateSelectPreset();
			onChangePreset();
		});

		deletePreset.on("click", function() {
			if (currentPresetName == null) return;
			var preset = allSetGroups.filter(s -> s.name == currentPresetName);
			if (preset.length == 0) return;
			if(hide.Ide.inst.confirm("Are-you sure ?")) {
				allSetGroups.remove(preset[0]);
				currentPresetName = null;
				currentSetName = null;
				updateSelectPreset();
				onChangePreset();
			}
		});

		onChangePreset(true);

		var options = new hide.Element('
		<div>
			<div class="btn-list" align="center">
				<input type="button" value="Select all" id="select"/>
				<input type="button" value="Add" id="add"/>
				<input type="button" value="Remove" id="remove"/>
				<input type="button" value="Remove all prefabs" id="clean"/>
				<input type="button" value="Set to Ground" id="toground"/>
			</div>
			<p align="center">
				<label><input type="checkbox" id="repeatPrefab" style="margin-right: 5px;"/> Don\'t repeat same prefab in a row</label>
			</p>
			<p>
				<b><i>
				Hold down SHIFT to remove prefabs
				<br/>Push R to randomize preview
			</p>
			<p align="center">
				<label><input type="checkbox" id="enableBrush" style="margin-right: 5px;"/> Enable Brush</label>
			</p>

		</div>
		').appendTo(props);

		var repeat = options.find("#repeatPrefab");
		repeat.on("change", function() {
			currentConfig.dontRepeatPrefab = repeat.is(":checked");
		}).prop("checked", currentConfig.dontRepeatPrefab);

		var enableBrush = options.find("#enableBrush");
		enableBrush.on("change", function() {
			currentConfig.enableBrush = enableBrush.is(":checked");
			sceneEditor.setLock([this], currentConfig.enableBrush, false);
			removeInteractiveBrush();
			if (currentConfig.enableBrush)
				createInteractiveBrush(ectx);
			else {
				interactive.cancelEvents = true;
			}

		}).prop("checked", currentConfig.enableBrush);

		options.find("#select").click(function(_) {
			var options = selectElement.children().elements();
			for (opt in options) {
				opt.prop("selected", true);
			}
		});
		options.find("#add").click(function(_) {
			hide.Ide.inst.chooseFiles(["prefab", "l3d"], function(paths) {
				for( path in paths ) {
					addPrefabPath(path);
					createPrefabElement(path);
				}
			});
		});

		options.find("#toground").click(function(_) {
			var ctx = ectx.getContext(this);
			var mso = cast(ctx.local3d,PrefabSprayObject);
			undo.change(Custom(function(undo) {
			}));
			for( c in this.children ) {
				var obj = c.to(Object3D);
				if( obj == null ) continue;
				setGroundPos(ectx, obj);
				var ctx = ectx.getContext(obj);
				if( ctx != null ) obj.applyTransform(ctx.local3d);
				wasEdited = true;
			}
			mso.redraw();
		});

		options.find("#remove").click(function(_) {
			var options = selectElement.children().elements();
			for (opt in options) {
				if (opt.prop("selected")) {
					removePrefabPath(opt.val());
					opt.remove();
				}
			}
		});
		options.find("#clean").click(function(_) {
			if (hide.Ide.inst.confirm("Are you sure to remove all prefabs for this PrefabSpray ?")) {
				var prefabs = [];
				for( c in children ) {
					prefabs.push(c);
				}
				sceneEditor.deleteElements(prefabs);
			}
		});


		ectx.properties.add(props, this, function(pname) {});

		var optionsGroup = new hide.Element('<div class="group" id="groupConfig" name="Options"><dl></dl></div>');
		optionsGroup.append(hide.comp.PropsEditor.makePropsList([
				{ name: "density", t: PInt(1, 25), def: currentConfig.density },
				{ name: "step", t: PFloat(0, 50), def: currentConfig.step },
				{ name: "densityOffset", t: PInt(0, 10), def: currentConfig.densityOffset },
				{ name: "radius", t: PFloat(0, 50), def: currentConfig.radius },
				{ name: "deleteRadius", t: PFloat(0, 50), def: currentConfig.deleteRadius },
				{ name: "scale", t: PFloat(0, 10), def: currentConfig.scale },
				{ name: "scaleOffset", t: PFloat(0, 1), def: currentConfig.scaleOffset },
				{ name: "rotation", t: PFloat(0, 180), def: currentConfig.rotation },
				{ name: "rotationOffset", t: PFloat(0, 30), def: currentConfig.rotationOffset },
				{ name: "zOffset", t: PFloat(0, 10), def: currentConfig.zOffset },
				{ name: "orientTerrain", t: PFloat(0, 1), def: currentConfig.orientTerrain },
				{ name: "tiltAmount", t: PFloat(0, 1), def: currentConfig.tiltAmount },
			]));
		ectx.properties.add(optionsGroup, this, function(pname) {
			var value = sceneEditor.properties.element.find("input[field="+ pname + "]").val();
			Reflect.setField(currentConfig, pname, Std.parseFloat(value));
		});

		sceneEditor.setLock([this], currentConfig.enableBrush, false);
		removeInteractiveBrush();
		if (currentConfig.enableBrush)
			createInteractiveBrush(ectx);
		super.edit(ectx);
	}

	function createInteractiveBrush(ectx : EditContext) {
		if (!enabled) return;
		var ctx = ectx.getContext(this);
		var s2d = ctx.shared.root2d.getScene();
		interactive = new h2d.Interactive(10000, 10000, s2d);
		interactive.propagateEvents = true;
		interactive.cancelEvents = false;
		interactive.enableRightButton = true;

		interactive.onWheel = function(e) {

		};

		interactive.onKeyUp = function(e) {
			if (e.keyCode == hxd.Key.R) {
				lastPrefabId = -1;
				if (lastSpray < Date.now().getTime() - 100) {
					if( !K.isDown( K.SHIFT) ) {
						clearPreview();
						var worldPos = ectx.screenToGround(s2d.mouseX, s2d.mouseY);
						previewPrefabsAround(ectx, ctx, worldPos);
					}
					lastSpray = Date.now().getTime();
					lastPrefabPos = null;
				}
			}
		}
		interactive.onClick = function(e) {
			if (e.button == K.MOUSE_RIGHT) {
				e.propagate = false;
				currentConfig.rotation += 10 * (K.isDown(K.CTRL) ? -1 : 1);
				currentConfig.rotation = currentConfig.rotation % 360;
				clearPreview();
				var worldPos = ectx.screenToGround(s2d.mouseX, s2d.mouseY);
				previewPrefabsAround(ectx, ctx, worldPos);
			}
		}

		interactive.onPush = function(e) {
			e.propagate = false;
			if (e.button == K.MOUSE_RIGHT) {
				return;
			}
			sprayEnable = true;
			var worldPos = ectx.screenToGround(s2d.mouseX, s2d.mouseY);
			if( K.isDown( K.SHIFT) )
				removePrefabsAround(ctx, worldPos);
			else {
				lastPrefabPos = worldPos.clone();
				addPrefabs(ctx);
			}
		};

		interactive.onRelease = function(e) {
			e.propagate = false;
			sprayEnable = false;
			var addedPrefabs = sprayedPrefabs.copy();
			if (sprayedPrefabs.length > 0) {
				undo.change(Custom(function(undo) {
					if(undo) {
						sceneEditor.deleteElements(addedPrefabs, () -> removeInteractiveBrush(), true, false);
						clearPreview();
					}
					else {
						sceneEditor.addElements(addedPrefabs, false, true, false);
					}
					cast(ctx.local3d,PrefabSprayObject).redraw();
				}));
				sprayedPrefabs = [];
			}
			clearPreview();
		};

		interactive.onMove = function(e) {
			var worldPos = ectx.screenToGround(s2d.mouseX, s2d.mouseY);

			var shiftPressed = K.isDown( K.SHIFT);

			if( worldPos == null ) {
				clearBrushes();
				return;
			}

			drawCircle(ctx, worldPos.x, worldPos.y, worldPos.z, (shiftPressed) ? currentConfig.deleteRadius : currentConfig.radius, 5, (shiftPressed) ? 9830400 : 38400);

			if (lastSpray < Date.now().getTime() - 100) {
				clearPreview();
				if( !shiftPressed ) {
					previewPrefabsAround(ectx, ctx, worldPos);
				}

				if( K.isDown( K.MOUSE_LEFT) ) {
					e.propagate = false;

					if (sprayEnable) {
						if( shiftPressed ) {
							removePrefabsAround(ctx, worldPos);
						} else {
							if (currentConfig.density == 1) {
								if(lastPrefabPos.distance(worldPos) > currentConfig.step) {
									lastPrefabPos = worldPos.clone();
									addPrefabs(ctx);
								}
							}
							else {
								lastPrefabPos = worldPos.clone();
								addPrefabs(ctx);
							}
						}
					}
				}
				lastSpray = Date.now().getTime();
			}
		};

	}

	function updateConfig() {
		var CONFIG = currentConfig;
		var defaultConfig = getDefaultConfig();
		var fields = Reflect.fields(defaultConfig);
		for (fieldName in fields) {
			var fieldValue = Reflect.field(CONFIG, fieldName);
			if (fieldValue == null) {
				fieldValue = Reflect.field(defaultConfig, fieldName);
				Reflect.setField(CONFIG, fieldName, fieldValue);
			}
			var input = sceneEditor.properties.element.find("input[field="+ fieldName + "]");
			input.val(fieldValue);
			input.change();
		}

		sceneEditor.properties.element.find("#repeatPrefab").prop("checked", CONFIG.dontRepeatPrefab);
	}

	override function removeInstance(ctx : Context):Bool {
		removeInteractiveBrush();
		return super.removeInstance(ctx);
	}
	override function setSelected( ctx : Context, b : Bool ) {
		if( !b )
			removeInteractiveBrush();
		return false;
	}

	function removeInteractiveBrush() {
		if( interactive != null ) interactive.remove();
		clearPreview();
		if (wasEdited)
			sceneEditor.refresh(Partial, () -> { });
		wasEdited = false;
		clearBrushes();
	}

	function clearBrushes() {
		if( gBrushes != null ) {
			for (g in gBrushes) g.remove();
			gBrushes = null;
		}
	}

	function addPrefabPath(path : String) {
		var prefab = { path: path };
		if (currentPrefabs.filter(p -> p.path == path).length == 0)
			currentPrefabs.push(prefab);
	}

	function removePrefabPath(path : String) {
		var prefab = currentPrefabs.filter(m -> m.path == path);
		if (prefab.length > 0)
			currentPrefabs.remove(prefab[0]);
	}

	var localMat = new h3d.Matrix();
	var lastPos : h3d.col.Point;
	var lastPrefabId = -1;
	var lastSprayedObj : h3d.scene.Object;
	function previewPrefabsAround(ectx : hide.prefab.EditContext, ctx : Context, point : h3d.col.Point) {
		if (currentPrefabs.length == 0) {
			return;
		}
		var nbPrefabsInZone = 0;
		var vecRelat = point.toVector();
		vecRelat.transform3x4(invParent);
		var point2d = new h2d.col.Point(vecRelat.x, vecRelat.y);

		final CONFIG = currentConfig;

		var computedDensity = CONFIG.density + Std.random(CONFIG.densityOffset+1);

		var minDistanceBetweenPrefabsSq = (CONFIG.radius * CONFIG.radius / computedDensity);

		var currentPivots : Array<h2d.col.Point> = [];
		inline function distance(x1 : Float, y1 : Float, x2 : Float, y2 : Float) return (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2);
		var fakeRadius = CONFIG.radius * CONFIG.radius + minDistanceBetweenPrefabsSq;
		for (child in children) {
			var prefab = child.to(hrt.prefab.Object3D);
			if( prefab == null ) continue;
			if (distance(point2d.x, point2d.y, prefab.x, prefab.y) < fakeRadius) {
				if (previewPrefabs.indexOf(prefab) != -1) continue;
				nbPrefabsInZone++;
				currentPivots.push(new h2d.col.Point(prefab.x, prefab.y));
			}
		}
		var nbPrefabsToPlace = computedDensity - nbPrefabsInZone;
		if (computedDensity == 1)
			clearPreview();
		lastPos = point;
		if (nbPrefabsToPlace > 0) {
			while (nbPrefabsToPlace-- > 0) {
				var nbTry = 5;
				var position : h3d.col.Point;
				do {
					var randomRadius = CONFIG.radius*Math.sqrt(Math.random());
					var angle = Math.random() * 2*Math.PI;

					position = new h3d.col.Point(point.x + randomRadius*Math.cos(angle), point.y + randomRadius*Math.sin(angle), 0);
					var vecRelat = position.toVector();
					vecRelat.transform3x4(invParent);

					var isNextTo = false;
					for (cPivot in currentPivots) {
						if (distance(vecRelat.x, vecRelat.y, cPivot.x, cPivot.y) <= minDistanceBetweenPrefabsSq) {
							isNextTo = true;
							break;
						}
					}
					if (!isNextTo) {
						break;
					}
				} while (nbTry-- > 0);

				var prefabId = 0;
				var prefabUsed = null;
				var options = selectElement.children().elements();
				var selectedPrefabs = [];
				for (opt in options) {
					if (opt.prop("selected")) {
						var findPrefab = currentPrefabs.filter((m) -> m.path == opt.val());
						if (findPrefab.length > 0)
							selectedPrefabs.push(findPrefab[0]);
					}
				}
				if (selectedPrefabs.length > 0) {
					if(selectedPrefabs.length > 1) {
						do
							prefabId = Std.random(selectedPrefabs.length)
						while(CONFIG.dontRepeatPrefab && prefabId == lastPrefabId);
					}
					prefabUsed = selectedPrefabs[prefabId];
				}
				else {
					if(currentPrefabs.length > 1) {
						do
							prefabId = Std.random(currentPrefabs.length)
						while(CONFIG.dontRepeatPrefab && prefabId == lastPrefabId);
					}
					prefabUsed = currentPrefabs[prefabId];
				}
				lastIndexPrefab = prefabId;
				if (computedDensity == 1)
					lastPrefabId = prefabId;
				else
					lastPrefabId = -1;


				var newPrefab : hrt.prefab.Object3D = null;

				var refPrefab = new hrt.prefab.Reference(this);
				refPrefab.source = prefabUsed.path;
				newPrefab = refPrefab;

				newPrefab.name = extractPrefabName(prefabUsed.path);

				localMat.identity();

				var randScaleOffset = Math.random() * CONFIG.scaleOffset;
				if (Std.random(2) == 0) {
					randScaleOffset *= -1;
				}
				var currentScale = hxd.Math.fmt(CONFIG.scale + randScaleOffset);

				localMat.scale(currentScale, currentScale, currentScale);

				position.z = ectx.positionToGroundZ(position.x, position.y) + CONFIG.zOffset;
				localMat.setPosition(new Vector(hxd.Math.fmt(position.x), hxd.Math.fmt(position.y), position.z));
				localMat.multiply(localMat, invParent);

				newPrefab.setTransform(localMat);
				setGroundPos(ectx, newPrefab);

				previewPrefabs.push(newPrefab);
				currentPivots.push(new h2d.col.Point(newPrefab.x, newPrefab.y));
			}

			if (previewPrefabs.length > 0) {
				sceneEditor.addElements(previewPrefabs, false, false, false);
			}
		}
	}

	function addPrefabs(ctx : Context) {
		lastPrefabId = -1;
		if (previewPrefabs.length > 0) {
			wasEdited = true;
			sprayedPrefabs = sprayedPrefabs.concat(previewPrefabs);
			previewPrefabs = [];
			clearBrushes();
			cast(ctx.local3d,PrefabSprayObject).redraw();
		}
	}

	function removePrefabsAround(ctx : Context, point : h3d.col.Point) {
		var vecRelat = point.toVector();
		vecRelat.transform3x4(invParent);
		var point2d = new h2d.col.Point(vecRelat.x, vecRelat.y);

		var childToRemove = [];
		inline function distance(x1 : Float, y1 : Float, x2 : Float, y2 : Float) return (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2);
		var fakeRadius = currentConfig.deleteRadius * currentConfig.deleteRadius;
		for (child in children) {
			var prefab = child.to(hrt.prefab.Object3D);
			if (prefab != null) {
				if (distance(point2d.x, point2d.y, prefab.x, prefab.y) < fakeRadius) {
					childToRemove.push(child);
				}
			}
		}
		var needRedraw = false;
		if (childToRemove.length > 0) {
			wasEdited = true;
			sceneEditor.deleteElements(childToRemove, () -> { }, false);
			needRedraw = true;
		}


		if( needRedraw ) {
			clearBrushes();
			cast(ctx.local3d,PrefabSprayObject).redraw();
		}
	}

	public function drawCircle(ctx : Context, originX : Float, originY : Float, originZ : Float, radius: Float, thickness: Float, color) {
		var newColor = h3d.Vector.fromColor(color);
		if (gBrushes == null || gBrushes.length == 0 || gBrushes[0].scaleX != radius || gBrushes[0].material.color != newColor) {
			clearBrushes();
			gBrushes = [];
			var gBrush = new h3d.scene.Mesh(makePrimCircle(32, 0.95), ctx.local3d);
			gBrush.scaleX = gBrush.scaleY = radius;
			gBrush.ignoreParentTransform = true;
			var pass = gBrush.material.mainPass;
			pass.setPassName("overlay");
			pass.depthTest = Always;
			pass.depthWrite = false;
			gBrush.material.shadows = false;
			gBrush.material.color = newColor;
			gBrushes.push(gBrush);
			gBrush = new h3d.scene.Mesh(new h3d.prim.Sphere(Math.min(radius*0.05, 0.35)), ctx.local3d);
			gBrush.ignoreParentTransform = true;
			var pass = gBrush.material.mainPass;
			pass.setPassName("overlay");
			pass.depthTest = Always;
			pass.depthWrite = false;
			gBrush.material.shadows = false;
			gBrush.material.color = newColor;
			gBrushes.push(gBrush);
		}
		for (g in gBrushes) g.visible = true;
		for (g in gBrushes) {
			g.x = originX;
			g.y = originY;
			g.z = originZ + 0.025;
		}
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		ctx.local3d = new PrefabSprayObject(this, ctx.local3d);
		ctx.local3d.name = name;
		updateInstance(ctx);
		return ctx;
	}

	override function make(ctx:Context):Context {
		if( !enabled )
			return ctx;
		return super.make(ctx);
	}

	override function applyTransform(o : h3d.scene.Object) {
		super.applyTransform(o);
		cast(o, PrefabSprayObject).redraw();
	}


	static public function makePrimCircle(segments: Int, inner : Float = 0, rings : Int = 0) {
		var points = [];
		var uvs = [];
		var indices = [];
		++segments;
		var anglerad = hxd.Math.degToRad(360);
		for(i in 0...segments) {
			var t = i / (segments - 1);
			var a = hxd.Math.lerp(-anglerad/2, anglerad/2, t);
			var ct = hxd.Math.cos(a);
			var st = hxd.Math.sin(a);
			for(r in 0...(rings + 2)) {
				var v = r / (rings + 1);
				var r = hxd.Math.lerp(inner, 1.0, v);
				points.push(new h2d.col.Point(ct * r, st * r));
				uvs.push(new h2d.col.Point(t, v));
			}
		}
		for(i in 0...segments-1) {
			for(r in 0...(rings + 1)) {
				var idx = r + i * (rings + 2);
				var nxt = r + (i + 1) * (rings + 2);
				indices.push(idx);
				indices.push(idx + 1);
				indices.push(nxt);
				indices.push(nxt);
				indices.push(idx + 1);
				indices.push(nxt + 1);
			}
		}

		var verts = [for(p in points) new h3d.col.Point(p.x, p.y, 0.)];
		var idx = new hxd.IndexBuffer();
		for(i in indices)
			idx.push(i);
		var primitive = new h3d.prim.Polygon(verts, idx);
		primitive.normals = [for(p in points) new h3d.col.Point(0, 0, 1.)];
		primitive.tangents = [for(p in points) new h3d.col.Point(0., 1., 0.)];
		primitive.uvs = [for(uv in uvs) new h3d.prim.UV(uv.x, uv.y)];
		primitive.colors = [for(p in points) new h3d.col.Point(1,1,1)];
		return primitive;
	}

	override function flatten<T:hrt.prefab.Prefab>( ?cl : Class<T>, ?arr: Array<T> ) : Array<T> {
		if(arr == null)
			arr = [];
		if( cl == null )
			arr.push(cast this);
		else {
			var i = to(cl);
			if(i != null)
				arr.push(i);
		}
		return arr;
	}

	static var _ = Library.register("prefabSpray", PrefabSpray);

}

#end
