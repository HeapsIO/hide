package hrt.prefab.l3d;

#if !editor

class MeshSprayObject extends h3d.scene.Object {
	public var batches : Array<h3d.scene.MeshBatch> = [];
	public var batchesMap : Map<String,{ batch : h3d.scene.MeshBatch, pivot : h3d.Matrix }> = [];
	override function getMaterials( ?arr : Array<h3d.mat.Material>, recursive=true ) {
		if( !recursive ) {
			// batches materials are considered local materials
			if( arr == null ) arr = [];
			for( b in batches )
				arr = b.getMaterials(arr, false);
		}
		return super.getMaterials(arr,recursive);
	}
}

class MeshSpray extends Object3D {

	override function createObject( ctx : Context ) {
		var mspray = new MeshSprayObject(ctx.local3d);
		// preallocate batches so their materials can be resolved
		for( c in children ) {
			if( !c.enabled || c.type != "model" ) continue;
			var batch = mspray.batchesMap.get(c.source);
			if( batch == null ) {
				var obj = ctx.loadModel(c.source).toMesh();
				var batch = new h3d.scene.MeshBatch(cast(obj.primitive,h3d.prim.MeshPrimitive), obj.material, mspray);
				var multi = Std.downcast(obj, h3d.scene.MultiMaterial);
				if( multi != null ) batch.materials = multi.materials;
				mspray.batchesMap.set(c.source, { batch : batch, pivot : obj.defaultTransform.isIdentity() ? null : obj.defaultTransform });
				mspray.batches.push(batch);
			}
		}
		return mspray;
	}

	override function make( ctx : Context ) {
		if( !enabled )
			return ctx;
		ctx = super.make(ctx);
		var mspray = Std.downcast(ctx.local3d, MeshSprayObject);
		var pos = mspray.getAbsPos();
		var tmp = new h3d.Matrix();
		for( b in mspray.batches ) {
			b.begin();
			b.worldPosition = tmp;
		}
		for( c in children ) {
			if( !c.enabled || c.type != "model" )
				continue;
			var inf = mspray.batchesMap.get(c.source);
			tmp.multiply3x4(c.to(Object3D).getTransform(), pos);
			if( inf.pivot != null ) tmp.multiply3x4(inf.pivot, tmp);
			inf.batch.emitInstance();
		}
		for( b in mspray.batches )
			b.worldPosition = null;
		return ctx;
	}

	override function makeChildren( ctx : Context, p : hrt.prefab.Prefab ) {
		if( p.type == "model" )
			return;
		super.makeChildren(ctx, p);
	}

	static var _ = Library.register("meshSpray", MeshSpray);

}

#else

import h3d.Vector;
import hxd.Key as K;

typedef Mesh = {
	var path: String;
	var isRef: Bool;
}

typedef Set = {
	var name: String;
	var meshes: Array<Mesh>;
	var config: MeshSprayConfig;
}

typedef SetGroup = {
	var name: String;
	var sets: Array<Set>;
}

typedef MeshSprayConfig = {
	var density : Int;
	var densityOffset : Int;
	var radius : Float;
	var deleteRadius : Float;
	var scale : Float;
	var scaleOffset : Float;
	var rotation : Float;
	var rotationOffset : Float;
	var zOffset: Float;
	var dontRepeatMesh : Bool;
	var orientTerrain : Float;
	var tiltAmount : Float;
}


@:access(hrt.prefab.l3d.MeshSpray)
class MeshSprayObject extends h3d.scene.Object {

	var childCount : Int = -1;
	var batches : Array<h3d.scene.MeshBatch> = [];
	var blookup : Map<h3d.prim.Primitive, h3d.scene.MeshBatch> = new Map();
	var mp : MeshSpray;
	var currentChk : Float = 0;

	public function new(mp,?parent) {
		this.mp = mp;
		super(parent);
	}

	override function getMaterials( ?arr : Array<h3d.mat.Material>, recursive=true ) {
		if( !recursive ) {
			// batches materials are considered local materials
			if( arr == null ) arr = [];
			for( b in batches )
				arr = b.getMaterials(arr, false);
		}
		return super.getMaterials(arr,recursive);
	}

	override function emitRec(ctx:h3d.scene.RenderContext) {
		for( b in batches ) {
			var p = b.material.getPass("highlight");
			if( p != null ) b.material.removePass(p);
		}

		var count = children.length;
		count -= batches.length;
		count -= mp.previewModels.length;
		if( mp.gBrushes != null ) count -= mp.gBrushes.length;
		var redraw = false;
		if( childCount != count ) {
			childCount = count;
			redraw = true;
		}

		var chk = 0.;
		for( c in children ) {
			if( c.alwaysSync ) continue;
			chk += c.x - c.y + c.z * 1.5456 + c.scaleX + c.scaleY + c.scaleZ + c.qRot.x + c.qRot.y + c.qRot.z;
		}
		if( chk != currentChk ) {
			currentChk = chk;
			redraw = true;
		}

		if( redraw ) this.redraw();
		super.emitRec(ctx);
	}

	public function redraw(updateShaders=false) {
		for( b in batches ) {
			if( updateShaders ) b.shadersChanged = true;
			b.begin();
		}
		for( c in children ) {
			c.culled = false;
			if( c.alwaysSync ) continue;
			var m = Std.downcast(c, h3d.scene.Mesh);
			if( m == null ) continue;
			var prim = Std.downcast(m.primitive, h3d.prim.MeshPrimitive);
			if( prim == null ) continue;

			var batch = blookup.get(m.primitive);
			if( batch == null ) {
				batch = new h3d.scene.MeshBatch(prim, m.material, this);
				var multi = Std.downcast(m, h3d.scene.MultiMaterial);
				if( multi != null ) batch.materials = multi.materials;
				batch.alwaysSync = true;
				batch.begin();
				batches.push(batch);
				blookup.set(m.primitive, batch);
			}
			batch.worldPosition = c.absPos;
			batch.emitInstance();
			c.culled = true;
		}
		for( b in batches )
			b.worldPosition = null;
	}

}

class MeshSpray extends Object3D {

	@:s var meshes : Array<Mesh> = []; // specific set for this mesh spray
	@:s var defaultConfig: MeshSprayConfig;
	@:s var currentPresetName : String = null;
	@:s var currentSetName : String = null;

	var sceneEditor : hide.comp.SceneEditor;

	var undo(get, null):hide.ui.UndoHistory;
	function get_undo() { return sceneEditor.view.undo; }

	var lastIndexMesh = -1;
	var allSetGroups : Array<SetGroup>;
	var setGroup : SetGroup;
	var currentSet : Set;

	var currentMeshes(get, null) : Array<Mesh>;
	function get_currentMeshes() {
		if (currentSet != null)
			return currentSet.meshes;
		else
			return meshes;
	}

	var currentConfig(get, null) : MeshSprayConfig;
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
	var invParent : h3d.Matrix;

	var MESH_SPRAY_CONFIG_FILE = "meshSprayProps.json";
	var MESH_SPRAY_CONFIG_PATH(get, null) : String;
	function get_MESH_SPRAY_CONFIG_PATH() {
		return hide.Ide.inst.resourceDir + "/" + MESH_SPRAY_CONFIG_FILE;
	}

	override function save() {
		// prevent saving preview
		if( previewModels.length > 0 )
			sceneEditor.deleteElements(previewModels, () -> { }, false);
		return super.save();
	}

	function getDefaultConfig() : MeshSprayConfig {
		return {
			density: 1,
			densityOffset: 0,
			radius: 0.1,
			deleteRadius: 5,
			scale: 1,
			scaleOffset: 0.1,
			rotation: 184,
			rotationOffset: 0,
			zOffset: 0,
			dontRepeatMesh: true,
			orientTerrain : 0,
			tiltAmount : 0,
		};
	}

	override function getHideProps() : HideProps {
		return { icon : "paint-brush", name : "MeshSpray", hideChildren : p -> return Std.is(p, Model) };
	}

	function extractMeshName( path : String ) : String {
		if( path == null ) return "None";
		var childParts = path.split("/");
		return childParts[childParts.length - 1].split(".")[0];
	}

	function saveConfigMeshBatch() {
		sys.io.File.saveContent(MESH_SPRAY_CONFIG_PATH, hide.Ide.inst.toJSON(allSetGroups));
	}

	function setGroundPos( ectx : EditContext, obj : Object3D ) {
		var pos = obj.getAbsPos();
		var config = currentConfig;
		var tz = ectx.positionToGroundZ(pos.tx, pos.ty);
		var mz = config.zOffset + tz - pos.tz;
		obj.z += mz;
		var orient = config.orientTerrain;
		var tilt = config.tiltAmount;

		var r = config.radius * 0.2;
		inline function getPoint(dx,dy) {
			var dz = ectx.positionToGroundZ(pos.tx + r * dx, pos.ty + r * dy) - tz;
			return new h3d.col.Point(r * dx, r * dy, dz * orient);
		}

		var px0 = getPoint(-1,0);
		var py0 = getPoint(0, -1);
		var px1 = getPoint(1, 0);
		var py1 = getPoint(0, 1);
		var n = px1.cross(py1).add(py1.cross(px0)).add(px0.cross(py0)).add(py0.cross(px1)).normalized();
		var q = new h3d.Quat();
		q.initNormal(n);
		var m = q.toMatrix();
		m.prependRotation(Math.random()*tilt*Math.PI/8,0,  (config.rotation + (Std.random(2) == 0 ? -1 : 1) * Math.round(Math.random() * config.rotationOffset)) * Math.PI / 180);
		var a = m.getEulerAngles();
		obj.rotationX = hxd.Math.fmt(a.x * 180 / Math.PI);
		obj.rotationY = hxd.Math.fmt(a.y * 180 / Math.PI);
		obj.rotationZ = hxd.Math.fmt(a.z * 180 / Math.PI);
	}

	var wasEdited = false;
	var previewModels : Array<hrt.prefab.Prefab> = [];
	var sprayedModels : Array<hrt.prefab.Prefab> = [];
	override function edit( ectx : EditContext ) {

		invParent = getAbsPos().clone();
		invParent.invert();

		if (defaultConfig == null) defaultConfig = getDefaultConfig();
		if (sceneEditor == null) {
			allSetGroups = if( sys.FileSystem.exists(MESH_SPRAY_CONFIG_PATH) )
				try hide.Ide.inst.parseJSON(sys.io.File.getContent(MESH_SPRAY_CONFIG_PATH)) catch( e : Dynamic ) throw e+" (in "+MESH_SPRAY_CONFIG_PATH+")";
			else
				[];
		}
		sceneEditor = ectx.scene.editor;


		var ctx = ectx.getContext(this);
		var s2d = @:privateAccess ctx.local2d.getScene();
		reset();
		interactive = new h2d.Interactive(10000, 10000, s2d);
		interactive.propagateEvents = true;
		interactive.cancelEvents = false;

		interactive.onWheel = function(e) {

		};

		interactive.onKeyUp = function(e) {
			if (e.keyCode == hxd.Key.R) {
				lastMeshId = -1;
				if (lastSpray < Date.now().getTime() - 100) {
					if( !K.isDown( K.SHIFT) ) {
						if (previewModels.length > 0) {
							sceneEditor.deleteElements(previewModels, () -> { }, false);
							sceneEditor.selectElements([this]);
							previewModels = [];
						}
						var worldPos = ectx.screenToGround(s2d.mouseX, s2d.mouseY);
						previewMeshesAround(ectx, ctx, worldPos);
					}
					lastSpray = Date.now().getTime();
				}
			}
		}

		interactive.onPush = function(e) {
			e.propagate = false;
			sprayEnable = true;
			var worldPos = ectx.screenToGround(s2d.mouseX, s2d.mouseY);
			if( K.isDown( K.SHIFT) )
				removeMeshesAround(ctx, worldPos);
			else {
				addMeshes(ctx);
			}
		};

		interactive.onRelease = function(e) {
			e.propagate = false;
			sprayEnable = false;
			var addedModels = sprayedModels.copy();
			if (sprayedModels.length > 0) {
				undo.change(Custom(function(undo) {
					if(undo) {
						sceneEditor.deleteElements(addedModels, () -> reset(), true, false);
					}
					else {
						sceneEditor.addElements(addedModels, false, true, true);
					}
				}));
				sprayedModels = [];
			}
			

			if (previewModels.length > 0) {
				sceneEditor.deleteElements(previewModels, () -> { }, false);
				sceneEditor.selectElements([this], Nothing);
				previewModels = [];
			}
		};

		interactive.onMove = function(e) {
			var worldPos = ectx.screenToGround(s2d.mouseX, s2d.mouseY);

			var shiftPressed = K.isDown( K.SHIFT);

			drawCircle(ctx, worldPos.x, worldPos.y, worldPos.z, (shiftPressed) ? currentConfig.deleteRadius : currentConfig.radius, 5, (shiftPressed) ? 9830400 : 38400);

			if (lastSpray < Date.now().getTime() - 100) {
				if (previewModels.length > 0) {
					sceneEditor.deleteElements(previewModels, () -> { }, false, false);
					previewModels = [];
				}
				if( !shiftPressed ) {
					previewMeshesAround(ectx, ctx, worldPos);
				}

				if( K.isDown( K.MOUSE_LEFT) ) {
					e.propagate = false;

					if (sprayEnable) {
						if( shiftPressed ) {
							removeMeshesAround(ctx, worldPos);
						} else {
							if (currentConfig.density == 1) sprayEnable = false;
							else addMeshes(ctx);
						}
					}
				}
				lastSpray = Date.now().getTime();
			}
		};

		var props = new hide.Element('<div class="group" name="Meshes"></div>');

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

		var selectElement = new hide.Element('<select multiple size="6" style="width: 300px" ></select>').appendTo(props);

		function onChangeSet() {
			selectElement.empty();
			for (m in currentMeshes.copy()) {
				var path : String = null;
				if (Std.is(m, String)) { // retro-compatibility
					path = cast m;
					currentMeshes.remove(m);
					addMeshPath(path);
				} else {
					path = m.path;
				}
				selectElement.append(new hide.Element('<option value="${path}">${extractMeshName(path)}</option>'));
			}
			updateConfig();
		}

		var selectedSetElt : hide.Element = null;
		function setSet(set: Set, setElt : hide.Element) {
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
							saveConfigMeshBatch();
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
						meshes: [],
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
						meshes: [],
						config: getDefaultConfig()
					}]
				});
				currentPresetName = name;
				currentSetName = "SetName";
				saveConfigMeshBatch();
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
			saveConfigMeshBatch();
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
				saveConfigMeshBatch();
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
				<input type="button" value="Remove all meshes" id="clean"/>
				<input type="button" value="Set to Ground" id="toground"/>
			</div>
			<p align="center">
				<label><input type="checkbox" id="repeatMesh" style="margin-right: 5px;"/> Don\'t repeat same mesh in a row</label>
			</p>
			<p>
				<b><i>
				Hold down SHIFT to remove meshes
				<br/>Push R to randomize preview
			</p>
		</div>
		').appendTo(props);

		var repeat = options.find("#repeatMesh");
		repeat.on("change", function() {
			currentConfig.dontRepeatMesh = repeat.is(":checked");
		}).prop("checked", currentConfig.dontRepeatMesh);

		options.find("#select").click(function(_) {
			var options = selectElement.children().elements();
			for (opt in options) {
				opt.prop("selected", true);
			}
		});
		options.find("#add").click(function(_) {
			hide.Ide.inst.chooseFiles(["fbx", "l3d"], function(paths) {
				for( path in paths ) {
					addMeshPath(path);
					selectElement.append(new hide.Element('<option value="$path">${extractMeshName(path)}</option>'));
				}
			});
		});

		options.find("#toground").click(function(_) {
			for( c in children ) {
				var obj = c.to(Object3D);
				if( obj == null ) continue;
				setGroundPos(ectx, obj);
				var ctx = ectx.getContext(obj);
				if( ctx != null ) obj.applyTransform(ctx.local3d);
			}
		});

		options.find("#remove").click(function(_) {
			var options = selectElement.children().elements();
			for (opt in options) {
				if (opt.prop("selected")) {
					removeMeshPath(opt.val());
					opt.remove();
				}
			}
		});
		options.find("#clean").click(function(_) {
			if (hide.Ide.inst.confirm("Are you sure to remove all meshes for this MeshSpray ?")) {
				var meshes = [];
				for( c in children ) {
					if( Std.is(c, Model) ) {
						meshes.push(c);
					}
				}
				sceneEditor.deleteElements(meshes);
				sceneEditor.selectElements([this], Nothing);
			}
		});


		ectx.properties.add(props, this, function(pname) {});

		var optionsGroup = new hide.Element('<div class="group" id="groupConfig" name="Options"><dl></dl></div>');
		optionsGroup.append(hide.comp.PropsEditor.makePropsList([
				{ name: "density", t: PInt(1, 25), def: currentConfig.density },
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
			saveConfigMeshBatch();
		});

		super.edit(ectx);
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

		sceneEditor.properties.element.find("#repeatMeshBtn").prop("checked", CONFIG.dontRepeatMesh);
	}

	override function removeInstance(ctx : Context):Bool {
		reset();
		return super.removeInstance(ctx);
	}
	override function setSelected( ctx : Context, b : Bool ) {
		if( !b ) {
			reset();
			if( gBrushes != null ) {
				for (g in gBrushes) g.remove();
				gBrushes = null;
			}
		}
		return false;
	}

	function reset() {
		if( interactive != null ) interactive.remove();
		if (previewModels != null && previewModels.length > 0) {
			sceneEditor.deleteElements(previewModels, () -> { }, false, false);
			previewModels = [];
		}
		if (wasEdited)
			sceneEditor.refresh(Partial, () -> { });
		wasEdited = false;
		if( gBrushes != null ) {
			for (g in gBrushes) g.remove();
			gBrushes = null;
		}
	}

	function addMeshPath(path : String) {
		var mesh = { path: path, isRef: path.toLowerCase().indexOf(".fbx") == -1 };
		if (currentMeshes.filter(m -> m.path == path).length == 0)
			currentMeshes.push(mesh);
		if (currentSet != null)
			saveConfigMeshBatch();
	}

	function removeMeshPath(path : String) {
		var mesh = currentMeshes.filter(m -> m.path == path);
		if (mesh.length > 0)
			currentMeshes.remove(mesh[0]);
		if (currentSet != null)
			saveConfigMeshBatch();
	}

	var localMat = new h3d.Matrix();
	var lastPos : h3d.col.Point;
	var lastMeshId = -1;
	function previewMeshesAround(ectx : hide.prefab.EditContext, ctx : Context, point : h3d.col.Point) {
		if (currentMeshes.length == 0) {
			return;
		}
		var nbMeshesInZone = 0;
		var vecRelat = point.toVector();
		vecRelat.transform3x4(invParent);
		var point2d = new h2d.col.Point(vecRelat.x, vecRelat.y);

		final CONFIG = currentConfig;

		var computedDensity = CONFIG.density + Std.random(CONFIG.densityOffset+1);

		var minDistanceBetweenMeshesSq = (CONFIG.radius * CONFIG.radius / computedDensity);

		var currentPivots : Array<h2d.col.Point> = [];
		inline function distance(x1 : Float, y1 : Float, x2 : Float, y2 : Float) return (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2);
		var fakeRadius = CONFIG.radius * CONFIG.radius + minDistanceBetweenMeshesSq;
		for (child in children) {
			var model = child.to(hrt.prefab.Object3D);
			if( model == null ) continue;
			if (distance(point2d.x, point2d.y, model.x, model.y) < fakeRadius) {
				if (previewModels.indexOf(model) != -1) continue;
				nbMeshesInZone++;
				currentPivots.push(new h2d.col.Point(model.x, model.y));
			}
		}
		var nbMeshesToPlace = computedDensity - nbMeshesInZone;
		if (computedDensity == 1)
		if (previewModels.length > 0) {
			sceneEditor.deleteElements(previewModels, () -> { }, false);
			sceneEditor.selectElements([this], Nothing);
			previewModels = [];
		}
		lastPos = point;
		if (nbMeshesToPlace > 0) {
			while (nbMeshesToPlace-- > 0) {
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
						if (distance(vecRelat.x, vecRelat.y, cPivot.x, cPivot.y) <= minDistanceBetweenMeshesSq) {
							isNextTo = true;
							break;
						}
					}
					if (!isNextTo) {
						break;
					}
				} while (nbTry-- > 0);

				var meshId = 0;
				if(currentMeshes.length > 1) {
					do
						meshId = Std.random(currentMeshes.length)
					while(CONFIG.dontRepeatMesh && meshId == lastMeshId);
				}
				lastIndexMesh = meshId;
				if (computedDensity == 1)
					lastMeshId = meshId;
				else
					lastMeshId = -1;

				var meshUsed = currentMeshes[meshId];

				var newPrefab : hrt.prefab.Object3D = null;

				if (meshUsed.isRef) {
					var refPrefab = new hrt.prefab.Reference(this);
					refPrefab.source = meshUsed.path;
					newPrefab = refPrefab;
				} else {
					var model = new hrt.prefab.Model(this);
					model.source = meshUsed.path;
					newPrefab = model;
				}

				newPrefab.name = extractMeshName(meshUsed.path);

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

				previewModels.push(newPrefab);
				currentPivots.push(new h2d.col.Point(newPrefab.x, newPrefab.y));
			}

			if (previewModels.length > 0) {
				sceneEditor.addElements(previewModels, false, false, true);
			}
		}
	}

	function addMeshes(ctx : Context) {
		lastMeshId = -1;
		if (previewModels.length > 0) {
			wasEdited = true;
			sprayedModels = sprayedModels.concat(previewModels);
			previewModels = [];
		}
	}

	function removeMeshesAround(ctx : Context, point : h3d.col.Point) {
		var vecRelat = point.toVector();
		vecRelat.transform3x4(invParent);
		var point2d = new h2d.col.Point(vecRelat.x, vecRelat.y);

		var childToRemove = [];
		inline function distance(x1 : Float, y1 : Float, x2 : Float, y2 : Float) return (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2);
		var fakeRadius = currentConfig.deleteRadius * currentConfig.deleteRadius;
		for (child in children) {
			var model = child.to(hrt.prefab.Object3D);
			if (distance(point2d.x, point2d.y, model.x, model.y) < fakeRadius) {
				childToRemove.push(child);
			}
		}
		if (childToRemove.length > 0) {
			wasEdited = true;
			sceneEditor.deleteElements(childToRemove, () -> { }, false);
			sceneEditor.selectElements([this], Nothing);
		}
	}

	public function drawCircle(ctx : Context, originX : Float, originY : Float, originZ : Float, radius: Float, thickness: Float, color) {
		var newColor = h3d.Vector.fromColor(color);
		if (gBrushes == null || gBrushes.length == 0 || gBrushes[0].scaleX != radius || gBrushes[0].material.color != newColor) {
			if (gBrushes != null) {
				for (g in gBrushes) g.remove();
			}
			gBrushes = [];
			var gBrush = new h3d.scene.Mesh(makePrimCircle(32, 0.95), ctx.local3d);
			gBrush.scaleX = gBrush.scaleY = radius;
			gBrush.ignoreParentTransform = true;
			gBrush.material.mainPass.setPassName("overlay");
			gBrush.material.shadows = false;
			gBrush.material.color = newColor;
			gBrushes.push(gBrush);
			gBrush = new h3d.scene.Mesh(new h3d.prim.Sphere(Math.min(radius*0.05, 0.35)), ctx.local3d);
			gBrush.ignoreParentTransform = true;
			gBrush.material.mainPass.setPassName("overlay");
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
		ctx.local3d = new MeshSprayObject(this, ctx.local3d);
		ctx.local3d.name = name;
		updateInstance(ctx);
		return ctx;
	}

	override function make(ctx:Context):Context {
		if( !enabled )
			return ctx;
		ctx = makeInstance(ctx);
		// add all children then build meshspray
		for( c in children )
			if( c.type == "model" )
				makeChildren(ctx, c);
		cast(ctx.local3d, MeshSprayObject).redraw();
		// then add other children (shaders etc.)
		for( c in children )
			if( c.type != "model" )
				makeChildren(ctx, c);
		// rebuild to apply per instance shaders
		cast(ctx.local3d, MeshSprayObject).redraw(true);
		return ctx;
	}

	override function applyTransform(o : h3d.scene.Object) {
		super.applyTransform(o);
		cast(o, MeshSprayObject).redraw();
	}


	function makePrimCircle(segments: Int, inner : Float = 0, rings : Int = 0) {
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
		primitive.incref();
		return primitive;
	}

	static var _ = Library.register("meshSpray", MeshSpray);

}

#end
