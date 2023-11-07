package hrt.prefab.l3d;

import hrt.prefab.l3d.Spray;
#if !editor

typedef BatchData = {
	batch : h3d.scene.MeshBatch,
	pivot : h3d.Matrix,
	emitCountTip : Int,
	init : Bool
};

class MeshSprayObject extends Spray.SprayObject {
	public var batches : Array<h3d.scene.MeshBatch> = [];
	public var batchesMap : Map<Int,Map<String,BatchData>> = [];
}

class MeshSpray extends Spray {

	@:s var split : Int;
	@:s var binaryStorage : Bool = false;

	var binaryMeshes : Array<{ path : String, x : Float, y : Float, z : Float, rotX : Float, rotY : Float, rotZ : Float, scale : Float }>;
	var clearBinaryMeshes : Bool = true;

	inline function getSplitID( x : Float, y : Float ) {
		return (Math.floor(x/split) * 39119 + Math.floor(y/split)) % 0x7FFFFFFF;
	}

	override function load(obj : Dynamic) {
		super.load(obj);
		//backward compatibility
		if(Reflect.hasField(obj, "meshes")) {
			var oldSources : Array<Spray.Source> = Reflect.field(obj, "meshes");
			for (source in oldSources) {
				sources.push(source);
			}
		}
	}

	override function createObject( ctx : Context ) {
		var mspray = new MeshSprayObject(ctx.local3d);
		// preallocate batches so their materials can be resolved
		var curID = 0, curMap = mspray.batchesMap.get(0);
		if( curMap == null ) {
			curMap = new Map();
			mspray.batchesMap.set(0, curMap);
		}
		inline function switchMap(x,y) {
			var sid = getSplitID(x, y);
			if( sid != curID ) {
				curID = sid;
				curMap = mspray.batchesMap.get(sid);
				if( curMap == null ) {
					curMap = new Map();
					mspray.batchesMap.set(sid, curMap);
				}
			}
		}
		inline function loadBatchMesh( source : String, mesh : h3d.scene.Mesh ) {
			var batch = new h3d.scene.MeshBatch(cast(mesh.primitive,h3d.prim.MeshPrimitive), mesh.material, mspray);
			batch.name = '${this.name}_${mesh.name}_${curID}';
			batch.cullingCollider = @:privateAccess batch.instanced.bounds;
			var multi = Std.downcast(mesh, h3d.scene.MultiMaterial);
			if( multi != null ) batch.materials = multi.materials;
			curMap.set(source, { batch : batch, pivot : mesh.defaultTransform.isIdentity() ? null : mesh.defaultTransform, emitCountTip : 1, init : false });
			mspray.batches.push(batch);
		}
		var tmp = new h3d.Matrix();
		inline function loadBatch( source : String ) {
			var batch = curMap.get(source);
			if( batch != null ) {
				batch.emitCountTip++;
				return;
			}
			var obj = ctx.loadModel(source);
			if ( obj.isMesh() ) {
				loadBatchMesh( source, obj.toMesh() );
			} else {
				var mesh = obj.find(o -> o.isMesh() ? o : null);
				if ( !obj.defaultTransform.isIdentity() ) {
					tmp.multiply(obj.defaultTransform, mesh.defaultTransform);
					mesh.defaultTransform = tmp;
				}
				if ( mesh != null ) loadBatchMesh(source, mesh.toMesh());
			}
		}
		for( c in children ) {
			if( !c.enabled || c.type != "model" ) continue;
			if( split > 0 ) {
				var obj = c.to(Object3D);
				switchMap(obj.x, obj.y);
			}
			loadBatch(c.source);
		}
		if( binaryMeshes != null ) {
			for( c in binaryMeshes ) {
				if( split > 0 ) switchMap(c.x, c.y);
				loadBatch(c.path);
			}
		}
		return mspray;
	}

	function loadBinary( ctx : Context ) {
		binaryMeshes = [];
		var bytes = new haxe.io.BytesInput(ctx.shared.loadPrefabDat("content","dat",name).entry.getBytes());
		try {
			while( true ) {
				binaryMeshes.push({
					path : sources[bytes.readByte() - 1].path,
					x : bytes.readFloat(),
					y : bytes.readFloat(),
					z : bytes.readFloat(),
					scale : bytes.readFloat(),
					rotX : bytes.readFloat(),
					rotY : bytes.readFloat(),
					rotZ : bytes.readFloat(),
				});
				if( bytes.readByte() != "\n".code ) throw "assert";
			}
		} catch( e : haxe.io.Eof ) {
		}
	}

	function emitCondition(m : h3d.Matrix ) {
		return true;
	}

	override function make( ctx : Context ) {
		if( !enabled )
			return ctx;
		if( binaryStorage )
			loadBinary(ctx);
		ctx = super.make(ctx);
		var mspray = Std.downcast(ctx.local3d, MeshSprayObject);
		var pos = mspray.getAbsPos();
		var tmp = new h3d.Matrix();
		var curID = 0, curMap = mspray.batchesMap.get(0);
		function emitInstance( batchData : BatchData ) {
			var batch = batchData.batch;
			if( !batchData.init ) {
				batchData.init = true;
				var emitCountTip = batchData.emitCountTip;
				if( emitCountTip < 10 )
					emitCountTip = 10;
				else {
					var STEP_TIP = 25;
					emitCountTip = (Math.floor(emitCountTip / STEP_TIP) + 1) * STEP_TIP;
				}
				batch.begin(emitCountTip);
				batch.worldPosition = tmp;
			}
			batch.emitInstance();
		}
		for( c in children ) {
			if( !c.enabled || c.type != "model" )
				continue;
			if( split > 0 ) {
				var obj = c.to(Object3D);
				var sid = getSplitID(obj.x, obj.y);
				if( sid != curID ) {
					curMap = mspray.batchesMap.get(sid);
					curID = sid;
				}
			}
			var inf = curMap.get(c.source);
			// if ( inf == null ) {
			// 	var obj = ctx.loadModel(c.source);
			// 	for ( m in obj.findAll(o -> o.isMesh() ? o.toMesh() : null) )
			// 		inf = curMap.get(c.source);
			// }
			tmp.multiply3x4(c.to(Object3D).getTransform(), pos);
			if( inf.pivot != null ) tmp.multiply3x4(inf.pivot, tmp);
			if ( !emitCondition(tmp) )
				continue;
			emitInstance(inf);
		}
		if( binaryMeshes != null ) {
			var degToRad = Math.PI / 180;
			for( c in binaryMeshes ) {
				if( split > 0 ) {
					var sid = getSplitID(c.x, c.y);
					if( sid != curID ) {
						curMap = mspray.batchesMap.get(sid);
						curID = sid;
					}
				}
				var inf = curMap.get(c.path);
				tmp.initRotation(c.rotX * degToRad, c.rotY * degToRad, c.rotZ * degToRad);
				tmp.prependScale(c.scale, c.scale, c.scale);
				tmp.tx = c.x;
				tmp.ty = c.y;
				tmp.tz = c.z;
				tmp.multiply3x4(tmp, pos);
				if( inf.pivot != null ) tmp.multiply3x4(inf.pivot, tmp);
				if ( !emitCondition(tmp) )
					continue;
				emitInstance(inf);
			}
		}
		for( b in mspray.batches )
			b.worldPosition = null;
		if ( clearBinaryMeshes )
			binaryMeshes = null;
		return ctx;
	}

	override function makeChild( ctx : Context, p : hrt.prefab.Prefab ) {
		if( p.type == "model" )
			return;
		super.makeChild(ctx, p);
	}

	static var _ = Library.register("meshSpray", MeshSpray);

}

#else

import h3d.Vector;
import hxd.Key as K;


@:access(hrt.prefab.l3d.Spray)
class MeshSprayObject extends Spray.SprayObject {

	var batches : Array<h3d.scene.MeshBatch> = [];
	var blookup : Map<h3d.prim.Primitive, h3d.scene.MeshBatch> = new Map();
	var mlookup : Map<String, h3d.scene.Mesh> = [];
	public var editChildren : Bool;

	override function emitRec(ctx:h3d.scene.RenderContext) {
		for( b in batches ) {
			var p = b.material.getPass("highlight");
			if( p != null ) b.material.removePass(p);
		}
		super.emitRec(ctx);
	}

	override function getMaterials( ?arr : Array<h3d.mat.Material>, recursive=true ) {
		// Allows hrt.prefab.Shader if editChildren
		return super.getMaterials(arr,editChildren ? true : recursive);
	}

	function getBatch( m : h3d.scene.Mesh ) {
		var batch = blookup.get(m.primitive);
		if( batch == null ) {
			batch = new h3d.scene.MeshBatch(cast(m.primitive,h3d.prim.MeshPrimitive), m.material, this);
			var multi = Std.downcast(m, h3d.scene.MultiMaterial);
			if( multi != null ) batch.materials = multi.materials;
			batch.alwaysSyncAnimation = true;
			batch.begin();
			batches.push(batch);
			blookup.set(m.primitive, batch);
		}
		return batch;
	}

	function loadMesh( path : String ) {
		var mesh = mlookup.get(path);
		if( mesh == null ) {
			var obj = spray.shared.loadModel(path);
			if( !obj.isMesh() ) throw path+" is not a mesh";
			mesh = obj.toMesh();
			mlookup.set(path, mesh);
		}
		return mesh;
	}

	override public function redraw(updateShaders=false) {
		if ( editChildren )
			return;
		getBounds(); // force absBos calculus on children
		for( b in batches ) {
			if( updateShaders ) b.shadersChanged = true;
			b.begin();
		}
		for( c in children ) {
			c.culled = false;
			if( c.alwaysSyncAnimation ) continue;
			var m = Std.downcast(c, h3d.scene.Mesh);
			if( m == null || !Std.isOfType(m.primitive, h3d.prim.MeshPrimitive) ) continue;

			var batch = getBatch(m);
			batch.worldPosition = c.absPos;
			if ( !emitCondition(c.absPos) )
				continue;
			batch.emitInstance();
			c.culled = true;
		}
		if( Std.downcast(spray, MeshSpray).binaryMeshes != null ) {
			var tmp = new h3d.Matrix();
			var absPos = getAbsPos();
			var degToRad = Math.PI / 180;
			for( c in Std.downcast(spray, MeshSpray).binaryMeshes ) {
				var mesh = loadMesh(c.path);
				var batch = getBatch(mesh);
				tmp.initRotation(c.rotX * degToRad, c.rotY * degToRad, c.rotZ * degToRad);
				tmp.prependScale(c.scale, c.scale, c.scale);
				tmp.tx = c.x;
				tmp.ty = c.y;
				tmp.tz = c.z;
				tmp.multiply3x4(tmp, absPos);
				tmp.multiply3x4(mesh.defaultTransform, tmp);
				batch.worldPosition = tmp;
				if ( !emitCondition(tmp) )
					continue;
				batch.emitInstance();
			}
		}
		for( b in batches )
			b.worldPosition = null;
	}

	dynamic function emitCondition(m : h3d.Matrix ) {
		return true;
	}

}

class MeshSpray extends Spray {

	@:s var split : Int = 0;
	@:s var binaryStorage = false;
	@:s var editChildren = false;

	var binaryMeshes : Array<{ path : String, x : Float, y : Float, z : Float, rotX : Float, rotY : Float, rotZ : Float, scale : Float }>;
	var binaryChanged : Bool = false;

	var MESH_SPRAY_CONFIG_FILE = "meshSprayProps.json";
	var MESH_SPRAY_CONFIG_PATH(get, null) : String;
	function get_MESH_SPRAY_CONFIG_PATH() {
		return hide.Ide.inst.resourceDir + "/" + MESH_SPRAY_CONFIG_FILE;
	}

	override function save() {
		clearPreview();
		if( binaryStorage ) saveToBinary();
		return super.save();
	}

	override function load(obj : Dynamic) {
		super.load(obj);
		//backward compatibility
		if(Reflect.hasField(obj, "meshes")) {
			var oldSources : Array<Spray.Source> = Reflect.field(obj, "meshes");
			for (source in oldSources) {
				sources.push(source);
			}
		}
	}


	function saveToBinary() {
		if( binaryMeshes == null )
			binaryMeshes = [];
		var meshes = new Map();
		for( i => m in this.sources )
			meshes.set(m.path, i+1);
		for( c in children.copy() ) {
			if( c.type != "model" || c.children.length != 0 || !meshes.exists(c.source) ) continue;
			var c = c.to(Model);
			binaryMeshes.push({ path : c.source, x : c.x, y : c.y, z : c.z, scale : c.scaleX, rotX : c.rotationX, rotY : c.rotationY, rotZ : c.rotationZ });
			children.remove(c);
			binaryChanged = true;
		}
		if( !binaryChanged )
			return;
		function align(x:Float,y:Float) {
			return y + x * 0.001;
		}
		function key(m:{x:Float,y:Float}) {
			if( split > 0 ) {
				var ix = Math.floor(m.x/split);
				var iy = Math.floor(m.y/split);
				return ix + iy * 65535 + align(m.x/split-ix,m.y/split-iy);
			}
			return align(m.x,m.y);
		}
		binaryMeshes.sort(function(m1,m2) return Reflect.compare(key(m1),key(m2)));
		var bytes = new haxe.io.BytesBuffer();
		for( c in binaryMeshes ) {
			var mid = meshes.get(c.path);
			if( mid == null ) continue;
			if( mid > 255 ) throw "assert";
			bytes.addByte(mid);
			bytes.addFloat(c.x);
			bytes.addFloat(c.y);
			bytes.addFloat(c.z);
			bytes.addFloat(c.scale);
			bytes.addFloat(c.rotX);
			bytes.addFloat(c.rotY);
			bytes.addFloat(c.rotZ);
			bytes.addByte("\n".code);
		}
		shared.savePrefabDat("content","dat",name, bytes.getBytes());
		binaryChanged = false;
	}

	override function getHideProps() : HideProps {
		return { icon : "paint-brush", name : "MeshSpray", hideChildren : p -> return (!editChildren && Std.isOfType(p, Model)) };
	}

	function saveConfigMeshBatch() {
		sys.io.File.saveContent(MESH_SPRAY_CONFIG_PATH, hide.Ide.inst.toJSON(allSetGroups));
	}

	override function edit( ectx : EditContext ) {
		#if editor
		this.dirty = true;
		#end
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

		selectElement = new hide.Element('<select multiple size="6" style="width: 300px" ></select>').appendTo(props);
		function createMeshElement(path: String) {
			var elt = new hide.Element('<option value="$path">${extractItemName(path)}</option>');
			elt.contextmenu(function(e) {
				e.preventDefault();
				new hide.comp.ContextMenu([
					{ label : "Swap Model", click : function() hide.Ide.inst.chooseFile(["fbx", "l3d"] , function (newPath) {
						removeSourcePath(elt.val());
						addSourcePath(newPath);
						for (child in children) {
							var model = child.to(hrt.prefab.Object3D);
							if (model != null && model.source == elt.val()) {
								model.source = newPath;
							}
						}
						elt.val(newPath);
						elt.html(extractItemName(newPath));
						sceneEditor.refresh();
						undo.change(Custom(function(undo) {
							if(undo) {
								removeSourcePath(newPath);
								addSourcePath(path);
								for (child in children) {
									var model = child.to(hrt.prefab.Object3D);
									if (model != null && model.source == elt.val()) {
										model.source = path;
									}
								}
								elt.val(path);
								elt.html(extractItemName(path));
								sceneEditor.refresh();
							}
							else {
								removeSourcePath(elt.val());
								addSourcePath(newPath);
								for (child in children) {
									var model = child.to(hrt.prefab.Object3D);
									if (model != null && model.source == elt.val()) {
										model.source = newPath;
									}
								}
								elt.val(newPath);
								elt.html(extractItemName(newPath));
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
			for (m in currentSources.copy()) {
				var path : String = null;
				if (Std.isOfType(m, String)) { // retro-compatibility
					path = cast m;
					currentSources.remove(m);
					addSourcePath(path);
				} else {
					path = m.path;
				}
				createMeshElement(path);
			}
			updateConfig();
		}

		var selectedSetElt : hide.Element = null;
		function setSet(set: Spray.Set, setElt : hide.Element) {
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
						sources: [],
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
						sources: [],
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
			<p align="center">
				<label><input type="checkbox" id="enableBrush" style="margin-right: 5px;"/> Enable Brush</label>
			</p>

		</div>
		').appendTo(props);

		var repeat = options.find("#repeatMesh");
		repeat.on("change", function() {
			currentConfig.dontRepeatItem = repeat.is(":checked");
		}).prop("checked", currentConfig.dontRepeatItem);

		var enableBrush = options.find("#enableBrush");
		enableBrush.on("change", function() {
			currentConfig.enableBrush = enableBrush.is(":checked");
			if ( !editChildren )
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
			hide.Ide.inst.chooseFiles(["fbx", "l3d"], function(paths) {
				for( path in paths ) {
					addSourcePath(path);
					createMeshElement(path);
				}
			});
		});

		options.find("#toground").click(function(_) {
			var ctx = ectx.getContext(this);
			var mso = cast(ctx.local3d,MeshSprayObject);
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
			if ( this.binaryMeshes != null ) {
				var pos = new h3d.col.Point(0,0,0);
				for ( bm in this.binaryMeshes ) {
					var pivot = mso.getAbsPos();
					pos.x = bm.x + pivot.tx;
					pos.y = bm.y + pivot.ty;
					pos.z = bm.z + pivot.tz;
					var ground = setGroundPos(ectx, null, pos);
					bm.z += ground.mz;
					bm.rotX = ground.rotX;
					bm.rotY = ground.rotY;
					bm.rotZ = ground.rotZ;
				}
				if ( this.binaryMeshes.length > 0) {
					wasEdited = true;
					binaryChanged = true;
				}
			}
			mso.redraw();
		});

		options.find("#remove").click(function(_) {
			var options = selectElement.children().elements();
			for (opt in options) {
				if (opt.prop("selected")) {
					removeSourcePath(opt.val());
					opt.remove();
				}
			}
		});
		options.find("#clean").click(function(_) {
			if (hide.Ide.inst.confirm("Are you sure to remove all meshes for this MeshSpray ?")) {
				var meshes = [];
				for( c in children ) {
					if( Std.isOfType(c, Model) ) {
						meshes.push(c);
					}
				}
				sceneEditor.deleteElements(meshes);
				cast(ectx.getContext(this).local3d, MeshSprayObject).redraw();
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
			saveConfigMeshBatch();
		});

		if ( !editChildren )
			sceneEditor.setLock([this], currentConfig.enableBrush, false);
		removeInteractiveBrush();
		if (currentConfig.enableBrush)
			createInteractiveBrush(ectx);
		super.edit(ectx);

		ectx.properties.add(new Element('
		<div class="group" name="Extra">
		<dl>
			<dt>Split</dt><dd><input type="range" min="0" max="2048" field="split"/></dd>
			<dt>Binary Storage</dt><dd><input type="checkbox" field="binaryStorage" ${binaryStorage?"disabled":""}/></dd>
			<dt>Edit children</dt><dd><input type="checkbox" field="editChildren"}/></dd>
		</dl>
		</div>'), this);
	}

	override function createInteractiveBrush(ectx : EditContext) {
		super.createInteractiveBrush(ectx);
		if (!enabled) return;
		var ctx = ectx.getContext(this);

		var s2d = ctx.shared.root2d.getScene();

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
					previewItemsAround(ectx, ctx, worldPos);
				}

				if( K.isDown( K.MOUSE_LEFT) ) {
					e.propagate = false;
					binaryChanged = true;

					if (sprayEnable) {
						if( shiftPressed ) {
							removeItemsAround(ctx, worldPos);
						} else {
							if (currentConfig.density == 1) {
								if(lastItemPos.distance(worldPos) > currentConfig.step) {
									lastItemPos = worldPos.clone();
									addItems(ctx);
								}
							}
							else {
								lastItemPos = worldPos.clone();
								addItems(ctx);
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

		sceneEditor.properties.element.find("#repeatMesh").prop("checked", CONFIG.dontRepeatItem);
	}


	override function addSourcePath(path : String) {
		var mesh = { path: path, isRef: path.toLowerCase().indexOf(".fbx") == -1 };
		if (currentSources.filter(m -> m.path == path).length == 0)
			currentSources.push(mesh);
		if (currentSet != null)
			saveConfigMeshBatch();
	}

	override function removeSourcePath(path : String) {
		var mesh = currentSources.filter(m -> m.path == path);
		if (mesh.length > 0)
			currentSources.remove(mesh[0]);
		if (currentSet != null)
			saveConfigMeshBatch();
	}

	override function removeItemsAround(ctx : Context, point : h3d.col.Point) {
		var vecRelat = point.toVector();
		vecRelat.transform3x4(invParent);
		var point2d = new h2d.col.Point(vecRelat.x, vecRelat.y);

		var childToRemove = [];
		inline function distance(x1 : Float, y1 : Float, x2 : Float, y2 : Float) return (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2);
		var fakeRadius = currentConfig.deleteRadius * currentConfig.deleteRadius;
		for (child in children) {
			var model = child.to(hrt.prefab.Object3D);
			if (model != null) {
				if (distance(point2d.x, point2d.y, model.x, model.y) < fakeRadius) {
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

		if( binaryMeshes != null ) {
			var toDelete = [];
			for( c in binaryMeshes ) {
				if( distance(point2d.x, point2d.y, c.x, c.y) < fakeRadius )
					toDelete.push(c);
			}
			if( toDelete.length > 0 ) {
				for( c in toDelete )
					binaryMeshes.remove(c);
				undo.change(Custom(function(undo) {
					for( c in toDelete ) {
						if( undo ) binaryMeshes.push(c) else binaryMeshes.remove(c);
					}
					cast(ctx.local3d,MeshSprayObject).redraw();
				}));
				needRedraw = true;
			}
		}

		if( needRedraw ) {
			clearBrushes();
			cast(ctx.local3d,MeshSprayObject).redraw();
		}
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		ctx.local3d = new MeshSprayObject(this, ctx.local3d);
		ctx.local3d.name = name;
		updateInstance(ctx);
		return ctx;
	}

	function emitCondition(m: h3d.Matrix) {
		return true;
	}

	override function updateInstance(ctx:Context, ?propName) {
		cast(ctx.local3d, MeshSprayObject).editChildren = editChildren;
		@:privateAccess cast(ctx.local3d, MeshSprayObject).emitCondition = emitCondition;
		if ( editChildren )
			locked = false;
		super.updateInstance(ctx, propName);
	}

	override function make(ctx:Context):Context {
		if( !enabled )
			return ctx;
		if( binaryStorage ) {
			binaryMeshes = [];
			var bytes = new haxe.io.BytesInput(ctx.shared.loadPrefabDat("content","dat",name).entry.getBytes());
			try {
				while( true ) {
					binaryMeshes.push({
						path : sources[bytes.readByte() - 1].path,
						x : bytes.readFloat(),
						y : bytes.readFloat(),
						z : bytes.readFloat(),
						scale : bytes.readFloat(),
						rotX : bytes.readFloat(),
						rotY : bytes.readFloat(),
						rotZ : bytes.readFloat(),
					});
					if( bytes.readByte() != "\n".code ) throw "assert";
				}
			} catch( e : haxe.io.Eof ) {
			}
		}
		shared = ctx.shared;
		ctx = makeInstance(ctx);
		// add all children then build meshspray
		for( c in children )
			if( c.type == "model" )
				makeChild(ctx, c);
		cast(ctx.local3d, MeshSprayObject).redraw();
		// then add other children (shaders etc.)
		for( c in children )
			if( c.type != "model" )
				makeChild(ctx, c);
		// rebuild to apply per instance shaders
		cast(ctx.local3d, MeshSprayObject).redraw(true);
		return ctx;
	}

	override function applyTransform(o : h3d.scene.Object) {
		super.applyTransform(o);
		cast(o, MeshSprayObject).redraw();
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

	override function flatten<T:Prefab>( ?cl : Class<T>, ?arr: Array<T> ) : Array<T> {
		if ( editChildren )
			return super.flatten();
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

	static var _ = Library.register("meshSpray", MeshSpray);

}

#end
