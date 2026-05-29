package hide.view;
import hrt.ui.*;

private enum abstract CollisionMode(Int) from Int to Int {
	var Default = 0;
	var None    = 1;
	var Auto    = 2;
	var Mesh    = 3;
	var Shapes  = 4;
	var Count   = 5;

	public function toString() {
		return switch (this) {
			case Default: "Default";
			case None: "None";
			case Auto: "Auto";
			case Mesh: "Mesh";
			case Shapes: "Shapes";
			default: "Undefined";
		}
	}
}

class CollisionSettings {
	public var mode : Int;
	public var params : hxd.fmt.fbx.HMDOut.CollideParams;

	public function new( mode : Int, params : hxd.fmt.fbx.HMDOut.CollideParams ) {
		this.mode = mode;
		this.params = params;
	}

	public function getDebugCollider(mesh : h3d.scene.Mesh, convertRule : hxd.fs.FileConverter.ConvertRule) : h3d.scene.Object {
		var hmd = Std.downcast(mesh.primitive, h3d.prim.HMDModel);
		if (hmd == null)
			return null;
		var model : hxd.fmt.hmd.Data.Model = null;
		if (params != null) {
			for (m in hmd.lib.header.models)
				if (m.getObjectName() == params.mesh || m.getObjectName() == mesh.name)
					model = m;
		}

		if (model == null)
			return null;

		var defaultParams : hxd.fmt.fbx.HMDOut.CollideParams = null;
		#if ((sys || nodejs) && !macro)
		var fs : hxd.fs.LocalFileSystem = Std.downcast(hxd.res.Loader.currentInstance.fs, hxd.fs.LocalFileSystem);
		if (fs != null) {
			var convertRule = @:privateAccess fs.convert.getConvertRule(hmd.lib.resource.entry.path);
			var collide = convertRule.cmd?.params?.collide;
			if (collide != null) {
				defaultParams = {
					precision : collide.precision,
					maxConvexHulls : collide.maxConvexHulls,
					maxSubdiv : collide.maxSubdiv,
				};
			}
		}
		#end

		var collisionThresholdHeight = Reflect.field(convertRule.cmd.params, "collisionThresholdHeight");
		var collisionUseLowLod = Reflect.field(convertRule.cmd.params, "collisionUseLowLod");
		var noCollision = Reflect.field(convertRule.cmd.params, "noCollision");
		var isDefaultParams = params == null || (params != null && params.useDefault);
		var params = isDefaultParams ? defaultParams : params;
		var colliderType = hxd.fmt.hmd.Data.Collider.resolveColliderType(hmd.lib.header, model, params, isDefaultParams, collisionThresholdHeight, collisionUseLowLod, noCollision);
		if (colliderType == null)
			return null;

		return switch (colliderType) {
			case Mesh(colliderModel):
				var g = hmd.lib.header.geometries[colliderModel.geometry];
				var buffers = hmd.lib.getBuffers(g, hxd.BufferFormat.POS3D);
				var polygonBuffer = new h3d.col.PolygonBuffer();
				polygonBuffer.setData(buffers.vertexes, buffers.indexes);
				var obj = polygonBuffer.makeDebugObj();
				obj.defaultTransform = colliderModel.position.toMatrix();
				if (colliderModel.skin != null)
					obj.defaultTransform.multiply(obj.defaultTransform, colliderModel.skin.joints[0].position.toMatrix());
				obj.defaultTransform.multiply(obj.defaultTransform, model.position.toMatrix().getInverse());
				return obj;

			case ConvexHulls(colliderModel):
				var hmd = Std.downcast(mesh.primitive, h3d.prim.HMDModel);

				var dim = hmd.getBounds().dimension();
				var prec = hxd.Math.min(dim, params.precision);
				var subdiv = hxd.Math.ceil(dim / prec);
				subdiv = hxd.Math.imin(subdiv, params.maxSubdiv);
				var p = { maxConvexHulls: params.maxConvexHulls, maxResolution: subdiv * subdiv * subdiv };

				var vertices : Array<Float> = [];
				var indexes : Array<Int> = [];
				for (idx => m in mesh.getMaterials()) {
					if (Reflect.field(m.props, "ignoreCollide"))
						continue;

					var bufs = hmd.lib.getBuffers(hmd.lib.header.geometries[colliderModel.geometry], hxd.BufferFormat.POS3D, null, idx);
					for (v in bufs.vertexes)
						vertices.push(v);
					for (i in bufs.indexes)
						indexes.push(i);
				}

				var convexHulls = hxd.fmt.hmd.Data.ConvexHullsCollider.buildConvexHulls(vertices, indexes, p);
				if (convexHulls == null)
					return null;

				var parentObj = new h3d.scene.Object();
				for (convexHull in convexHulls) {
					var polygonBuffer = new h3d.col.PolygonBuffer();
					var vbuf = new haxe.ds.Vector<hxd.impl.Float32>(convexHull.vertices.length);
					for (vIdx => v in convexHull.vertices)
						vbuf[vIdx] = v;
					var ibuf = new haxe.ds.Vector<Int>(convexHull.indexes.length);
					for (i => idx in convexHull.indexes)
						ibuf[i] = idx;
					polygonBuffer.setData(vbuf, ibuf, true);
					var obj = polygonBuffer.makeDebugObj();
					obj.defaultTransform = colliderModel.position.toMatrix();
					if (colliderModel.skin != null)
						obj.defaultTransform.multiply(obj.defaultTransform, colliderModel.skin.joints[0].position.toMatrix());
					parentObj.addChild(obj);
				}

				parentObj.defaultTransform = model.position.toMatrix().getInverse();
				return parentObj;

			case Shapes:
				var root = new h3d.scene.Object();
				for (s in toShapeEditor())
					hrt.ui.HuiShapeEditor.getInteractive(s, false, root);

				return root;

			default:
				null;
		}
	}

	public function toShapeEditor() {
		if (params == null || mode != Shapes || params.shapes == null)
			return [];
		var arr : Array<hrt.ui.HuiShapeEditor.Shape> = [];
		inline function makeVector(dyn) {
			return new h3d.Vector(dyn.x, dyn.y, dyn.z);
		}
		for (s in params.shapes) {
			var position = makeVector(s.position);
			switch( s.type ) {
			case Sphere:
				arr.push(Sphere(position, s.radius));
			case Box:
				var halfExtent = makeVector(s.halfExtent);
				var rotation = makeVector(s.rotation);
				arr.push(Box(position, rotation, halfExtent.x * 2, halfExtent.y * 2, halfExtent.z * 2));
			case Capsule:
				var halfExtent = makeVector(s.halfExtent);
				var qrot = new h3d.Quat();
				qrot.initMoveTo(new h3d.Vector(0.0, 0.0, 1.0), halfExtent.normalized());
				arr.push(Capsule(position, qrot.toEuler(), s.radius, halfExtent.length() * 2));
			case Cylinder:
				var halfExtent = makeVector(s.halfExtent);
				var qrot = new h3d.Quat();
				qrot.initMoveTo(new h3d.Vector(0.0, 0.0, 1.0), halfExtent.normalized());
				arr.push(Cylinder(position, qrot.toEuler(), s.radius, halfExtent.length() * 2));
			default:
				Ide.showError("Don't know how to handle shape type " + s.type);
			}
		}
		return arr;
	}

	public function fromShapeEditor(arr : Array<hrt.ui.HuiShapeEditor.Shape>) {
		var shapes : Array<hxd.fmt.fbx.HMDOut.ShapeColliderParams> = [];
		for( s in arr ) {
			switch(s) {
			case Sphere(center, radius):
				shapes.push({ type : Sphere, position : center, radius : radius });
			case Box(center, rotation, sizeX, sizeY, sizeZ):
				var halfExtent = new h3d.Vector(sizeX * 0.5, sizeY * 0.5, sizeZ * 0.5);
				shapes.push({ type : Box, position : center, rotation : rotation, halfExtent: halfExtent });
			case Capsule(center, rotation, radius, height):
				var rmat = h3d.Matrix.R(rotation.x, rotation.y, rotation.z);
				var halfExtent = new h3d.Vector(0.0, 0.0, 1.0);
				halfExtent.transform3x3(rmat);
				halfExtent.normalize();
				halfExtent.scale(height * 0.5);
				shapes.push({ type : Capsule, position: center, halfExtent : halfExtent, radius : radius });
			case Cylinder(center, rotation, radius, height):
				var rmat = h3d.Matrix.R(rotation.x, rotation.y, rotation.z);
				var halfExtent = new h3d.Vector(0.0, 0.0, 1.0);
				halfExtent.transform3x3(rmat);
				halfExtent.normalize();
				halfExtent.scale(height * 0.5);
				shapes.push({ type : Cylinder, position: center, halfExtent : halfExtent, radius : radius });
			}
		}
		return shapes;
	}
}

#if hui
class HuiModelInspector extends HuiElement {
	static var SRC = <hui-model-inspector>
		<hui-category("Info")>
			<hui-element class="horizontal"><hui-text("Objects") class="label"/><hui-text("1") class="value" id="obj-count"/></hui-element>
			<hui-element class="horizontal"><hui-text("Meshes") class="label"/><hui-text("1") class="value" id="meshes-count"/></hui-element>
			<hui-element class="horizontal"><hui-text("Materials") class="label"/><hui-text("1") class="value" id="mats-count"/></hui-element>
			<hui-element class="horizontal"><hui-text("Draws") class="label"/><hui-text("1") class="value" id="draws-count"/></hui-element>
			<hui-element class="horizontal"><hui-text("Bones") class="label"/><hui-text("1") class="value" id="bones-count"/></hui-element>
			<hui-element class="horizontal"><hui-text("Vertexes") class="label"/><hui-text("1") class="value" id="vertices-count"/></hui-element>
			<hui-element class="horizontal"><hui-text("Triangles") class="label"/><hui-text("1") class="value" id="triangles-count"/></hui-element>
			<hui-element class="horizontal"><hui-text("Vertex Format") class="label"/><hui-text("1") class="value" id="vertex-format"/></hui-element>
			<hui-element class="horizontal"><hui-text("Collider Vertices") class="label"/><hui-text("1") class="value" id="collider-vertices"/></hui-element>
			<hui-element class="horizontal"><hui-text("Collider Triangle") class="label"/><hui-text("1") class="value" id="collider-triangles"/></hui-element>
			<hui-element class="horizontal"><hui-text("Local Pos") class="label"/><hui-text("1") class="value" id="local-pos"/></hui-element>
			<hui-element class="horizontal"><hui-text("Local Rot") class="label"/><hui-text("1") class="value" id="local-rot"/></hui-element>
			<hui-element class="horizontal"><hui-text("Local Scale") class="label"/><hui-text("1") class="value" id="local-scale"/></hui-element>
			<hui-element class="horizontal"><hui-text("Total Size") class="label"/><hui-text("1") class="value" id="total-size"/></hui-element>
			<hui-element class="horizontal"><hui-text("Mesh Size") class="label"/><hui-text("1") class="value" id="mesh-size"/></hui-element>
		</hui-category>
		<hui-category("Collision")>
			<hui-element class="horizontal"><hui-text("Collision Mode") class="label"/><hui-select class="value" id="collision-mode-el"/></hui-element>
			<hui-element class="horizontal"><hui-text("Precision") class="label"/><hui-input-box class="value" id="precision-el"/></hui-element>
			<hui-element class="horizontal"><hui-text("Max Convex Hulls") class="label"/><hui-input-box class="value" id="max-convex-hulls-el"/></hui-element>
			<hui-element class="horizontal"><hui-text("Max Subdivision") class="label"/><hui-input-box class="value" id="max-subdivision-el"/></hui-element>
			<hui-element class="horizontal"><hui-text("Mesh") class="label"/><hui-select class="value" id="mesh-el"/></hui-element>
			<hui-button class="full" id="compute-collider-btn"><hui-text("Compute Collider")></hui-text></hui-button>
			<hui-shape-editor(obj) id="shape-editor"></hui-shape-editor>
		</hui-category>
		<hui-category("LODs")>
			<hui-element class="horizontal"><hui-text("LOD Count") class="label"/><hui-text("1") class="value" id="lod-count"/></hui-element>
			<hui-element class="horizontal"><hui-text("LOD Vertices") class="label"/><hui-text("1") class="value" id="lod-vertices-count"/></hui-element>
			<hui-element class="horizontal"><hui-text("Force Display LOD") class="label"/><hui-select id="force-display-lod" class="value"></hui-select></hui-element>
			<hui-element class="horizontal"><hui-text("Max LOD") class="label"/><hui-input-box id="max-lod" class="value"></hui-input-box></hui-element>
			<hui-lod-line id="lod-line"></hui-lod-line>
			<hui-button class="full" id="copy-lods"><hui-text("Copy")></hui-text></hui-button>
			<hui-button class="full" id="paste-lods"><hui-text("Paste")></hui-text></hui-button>
			<hui-button class="full" id="reset-lods"><hui-text("Reset Defaults")></hui-text></hui-button>
		</hui-category>
		<hui-category("Material Library")>
		</hui-category>
		<hui-category("Textures")>
		</hui-category>
		<hui-category("Material")>
		</hui-category>
		<hui-category("Dynamic Bones")>
		</hui-category>
		<hui-category("Blend Shapes")>
		</hui-category>
	</hui-model-inspector>

	var model : Model;

	public function new(obj : h3d.scene.Object, model: Model, ?parent: h2d.Object) {
		super(parent);
		this.model = model;

		initComponent();

		updateInfosInspector(obj);
		updateLODsInspector(obj);
		updateCollisionInspector(obj);
	}

	function updateInfosInspector(obj : h3d.scene.Object) {
		var meshes = obj.getMeshes();
		var vertCount = 0, triCount = 0, materialDraws = 0, materialCount = 0, jointsCount = 0;
		var uniqueMats = new Map();
		for (m in obj.getMaterials()) {
			if( uniqueMats.exists(m.name) ) continue;
			uniqueMats.set(m.name, true);
			materialCount++;
		}
		for (m in meshes) {
			var p = m.primitive;
			triCount += p.triCount();
			vertCount += p.vertexCount();
			var multi = Std.downcast(m, h3d.scene.MultiMaterial);
			var skin = Std.downcast(m, h3d.scene.Skin);
			if( skin != null )
				jointsCount += skin.getSkinData().allJoints.length;
			var count = if( skin != null && skin.getSkinData().splitJoints != null )
				skin.getSkinData().splitJoints.length;
			else if( multi != null )
				multi.materials.length
			else
				1;
			materialDraws += count;
		}

		var mesh = Std.downcast(obj, h3d.scene.Mesh);
		var hmd = mesh != null ? Std.downcast(mesh.primitive, h3d.prim.HMDModel) : null;
		var vFormat = '';
		if (mesh != null && mesh.primitive.buffer != null) {
			for ( i in mesh.primitive.buffer.format.getInputs() )
				vFormat += ' ' + i.name;
		}

		var colVertices = 0;
		var colTriangles = 0;
		if (hmd != null && @:privateAccess hmd.colliderData != null) {
			var col = hmd.getCollider();
			function recCol(c : h3d.col.Collider) {
				var optimized = Std.downcast(c, h3d.col.Collider.OptimizedCollider);
				if ( optimized != null ) {
					recCol(optimized.b);
					return;
				}
				var list = Std.downcast(c, h3d.col.Collider.GroupCollider);
				if ( list != null ) {
					for ( l in list.colliders )
						recCol(l);
					return;
				}
				var polygonBuffer = Std.downcast(c, h3d.col.PolygonBuffer);
				if ( polygonBuffer != null ) {
					colTriangles += @:privateAccess polygonBuffer.triCount;
					colVertices += @:privateAccess Std.int(polygonBuffer.buffer.length / 3);
					return;
				}
				var polygon = Std.downcast(c, h3d.col.Polygon);
				if ( polygon != null ) {
					var t = @:privateAccess polygon.triPlanes;
					while ( t != null ) {
						colTriangles += 1;
						colVertices += 3;
						t = t.next;
					}
					return;
				}
			}
			recCol(col);
		}

		objCount.text = ""+(1 + obj.getObjectsCount());
		meshesCount.text = ""+meshes.length;
		matsCount.text = ""+materialCount;
		drawsCount.text = ""+materialDraws;
		bonesCount.text = ""+jointsCount;
		verticesCount.text = ""+vertCount;
		trianglesCount.text = ""+triCount;
		vertexFormat.text = vFormat;
		colliderVertices.text = ""+colVertices;
		colliderTriangles.text = ""+colTriangles;

		function round(n : Float) { return hxd.Math.round(n * 100) / 100; }

		var transform = obj.defaultTransform;
		if (transform != null) {
			var p = transform.getPosition();
			localPos.text = 'X: ${round(p.x)}  Y: ${round(p.y)}  Z: ${round(p.z)}';
			var r = transform.getEulerAngles();
			localRot.text = 'X: ${round(hxd.Math.radToDeg(r.x))}  Y: ${round(hxd.Math.radToDeg(r.y))}  Z: ${round(hxd.Math.radToDeg(r.z))}';
			var s = transform.getScale();
			localScale.text = 'X: ${round(s.x)}  Y: ${round(s.y)}  Z: ${round(s.z)}';
		}
	}

	function updateLODsInspector(obj : h3d.scene.Object) {
		var mesh = Std.downcast(obj, h3d.scene.Mesh);
		var hmd = Std.downcast(mesh?.primitive, h3d.prim.HMDModel);

		if (hmd == null || hmd.lodCount() <= 1)
			return;

		lodCount.text = '${hmd.lodCount()}';
		lodVerticesCount.text = '${@:privateAccess hmd.lods[mesh.getLodIndex()].vertexCount}';

		var options = [];
		options.push({ label: 'None', value: -1 });
		for (idx in 0...hmd.lodCount())
			options.push({ label: 'LOD ${idx}', value: idx });
		forceDisplayLod.items = options;
		forceDisplayLod.value = mesh.forcedLod;
		forceDisplayLod.onValueChanged = () -> { mesh.forcedLod = forceDisplayLod.value; updateLODsInspector(obj); };

		lodLine.mesh = mesh;

		maxLod.text = '${lodLine.maxLodRatio * 100}';
		maxLod.onChange = (isTempChange) -> {
			if (isTempChange)
				return;
			var v = Std.parseFloat(maxLod.text) / 100;
			if (hxd.Math.isNaN(v)) {
				maxLod.text = '${lodLine.maxLodRatio * 100}';
				return;
			}

			var oldVal = lodLine.maxLodRatio;
			var newVal = v;
			newVal = Math.max(@:privateAccess lodLine.getLodRatio(0), newVal);

			var exec = function(undo) {
				var m = undo ? oldVal : newVal;
				maxLod.text = '${m * 100}';
				lodLine.maxLodRatio = m;
				@:privateAccess lodLine.updateAreas();
			};

			getView().undo.record(exec, false);
			exec(false);
		}

		copyLods.onClick = (_) -> {
			var config = @:privateAccess hmd.lodConfig?.copy();
			hxd.System.setClipboardText(hide.Ide.inst.toJSON(config));
			Ide.showInfo("Copied current lod config to the clipboard");
		}

		pasteLods.onClick = (_) -> {
			var prevConfig = @:privateAccess hmd.lodConfig?.copy();
			var newConfig = try haxe.Json.parse(hxd.System.getClipboardText()) catch(e) null;

			if (newConfig is Array) {
				for (value in (newConfig:Array<Dynamic>)) {
					if (value is Float || value is Int) {
						continue;
					}
					newConfig = null;
					break;
				}
			}

			if (newConfig == null) {
				Ide.showError("Couldn't paste config from clipboard (invalid data)");
				return;
			}

			var exec = function(undo) {
				if (undo) {
					@:privateAccess hmd.lodConfig = prevConfig;
				} else {
					@:privateAccess hmd.lodConfig = cast newConfig;
				}
				@:privateAccess lodLine.updateAreas();
			}

			getView().undo.record(exec, true);
			exec(false);
			Ide.showInfo("Pasted config from the clipboard");
		};

		resetLods.onClick = (_) -> {
			var prevConfig = @:privateAccess hmd.lodConfig?.copy();
			@:privateAccess hmd.lodConfig = h3d.prim.ModelDatabase.current.getDefaultLodConfig(hmd.lib.resource.entry.directory);
			Ide.showInfo('Lod config reset for object : ${obj.name}');
			@:privateAccess lodLine.updateAreas();

			getView().undo.record((isUndo) -> {
				if (isUndo) {
					@:privateAccess hmd.lodConfig = prevConfig;
				} else {
					@:privateAccess hmd.lodConfig = null;
				}

				@:privateAccess lodLine.updateAreas();
			}, true);
		}
	}

	function updateCollisionInspector(obj : h3d.scene.Object) {
		var mesh = Std.downcast(obj, h3d.scene.Mesh);
		var hmd = Std.downcast(mesh?.primitive, h3d.prim.HMDModel);

		if (hmd == null)
			return;

		var settings = @:privateAccess model.collisionSettings.get(obj.name);
		function refreshCollisionEdition() {
			precisionEl.parent.visible = collisionModeEl.value == CollisionMode.Auto;
			precisionEl.text = '${settings.params?.precision ?? 1.0}';

			maxConvexHullsEl.parent.visible = collisionModeEl.value == CollisionMode.Auto;
			maxConvexHullsEl.text = '${settings.params?.maxConvexHulls ?? 1}';

			maxSubdivisionEl.parent.visible = collisionModeEl.value == CollisionMode.Auto;
			maxSubdivisionEl.text = '${settings.params?.maxSubdiv ?? 32}';

			meshEl.items = [ { value: null, label: "None" } ];
			if (hmd != null) {
				for (m in hmd.lib.header.models) {
					if (m.geometry >= 0)
						meshEl.items.push({ label: m.name, value: m.name });
				}
			}
			meshEl.parent.visible = collisionModeEl.value == CollisionMode.Auto || collisionModeEl.value == CollisionMode.Mesh;
			meshEl.value = settings.params?.mesh;

			computeColliderBtn.visible = collisionModeEl.value == CollisionMode.Auto;

			shapeEditor.visible = collisionModeEl.value == CollisionMode.Shapes;
			shapeEditor.refresh(settings.toShapeEditor());
			shapeEditor.rootDebugObj = obj;
		}

		function applyCollisionEdition() {
			var prevMode = settings.mode;
			var prevParams = settings.params;
			var meshName = meshEl.value;
			var curMode = collisionModeEl.value;
			var curParams = {};
			switch (curMode) {
				case Default:
					Reflect.setField(curParams, "useDefault", true);
				case None:
					curParams = null;
				case Auto:
					Reflect.setField(curParams, "precision", Std.parseFloat(precisionEl.text));
					Reflect.setField(curParams, "maxConvexHulls", Std.parseInt(maxConvexHullsEl.text));
					Reflect.setField(curParams, "maxSubdiv", Std.parseInt(maxSubdivisionEl.text));
					Reflect.setField(curParams, "mesh", meshName == "null" ? null : meshName);
				case Mesh:
					Reflect.setField(curParams, "mesh", meshName == "null" ? null : meshName);
				case Shapes:
					var shapes = settings.fromShapeEditor(shapeEditor.getValue());
					if (shapes.length == 0)
						curParams = null;
					else
						Reflect.setField(curParams, "shapes", shapes);
				default:
					throw "Unknown collision mode";
			}
			settings.mode = curMode;
			settings.params = curParams;
			refreshCollisionEdition();
			if (curMode != Auto || curMode != prevMode)
				@:privateAccess model.sceneEditor.updateDebugOverlayVisibility();

			model.undo.record((isUndo) -> {
				var mode = isUndo ? prevMode : curMode;
				var params = isUndo ? prevParams : curParams;
				settings.mode = mode;
				settings.params = params;
				refreshCollisionEdition();
				if (curMode != Auto || curMode != prevMode)
					@:privateAccess model.sceneEditor.updateDebugOverlayVisibility();
				if (settings.mode == Shapes)
					shapeEditor.refresh(settings.toShapeEditor());
			}, true);
		}

		collisionModeEl.onValueChanged = () -> applyCollisionEdition();
		shapeEditor.onChange = () -> applyCollisionEdition();
		precisionEl.onChange = (_) -> applyCollisionEdition();
		maxConvexHullsEl.onChange = (_) -> applyCollisionEdition();
		maxSubdivisionEl.onChange = (_) -> applyCollisionEdition();
		meshEl.onValueChanged = () -> applyCollisionEdition();
		computeColliderBtn.onClick = (_) -> {
			applyCollisionEdition();
			@:privateAccess model.sceneEditor.updateDebugOverlayVisibility();
		}

		collisionModeEl.items = [for(idx in 0...CollisionMode.Count) { value: idx, label: cast(idx, CollisionMode).toString()}];
		collisionModeEl.value = settings.mode;

		refreshCollisionEdition();
	}
}

@:access(hrt.ui.HuiSceneEditor)
class Model extends HuiView<{path: String}> {
	static var SRC =
		<model>
			<hui-scene-editor id="scene-editor"/>
		</model>

	static var _ = HuiView.register("model", Model);

	var obj : h3d.scene.Object;
	var selectedObjects: Array<Dynamic> = [];
	var collisionSettings : Map<String, CollisionSettings>;
	var modelInspector : HuiModelInspector;

	public function new(_state: Dynamic, ?parent) {
		super(_state, parent);
		initComponent();

		var path = Ide.inst.getRelPath(state.path);
		sceneEditor.load = () -> load(path);
		sceneEditor.onScenePush = (e) -> {
			if (e.button == 0)
				setSelection(sceneEditor.getObjectsAt(cast e.relX, cast e.relY, obj, (o) -> Std.isOfType(o, h3d.scene.Mesh)));
		}
		sceneEditor.setColliderDebugVisibility = setColliderDebugVisibility;

		undo.onAfterChange = () -> {
			hasUnsavedChanges = undo.isDirty();
		}

		registerCommand(HuiCommands.save, View, () -> { save();});

		buildToolbar();

		sceneEditor.load();
		sceneEditor.tree.getItemChildren = (item: Dynamic) -> {
			if (item == null)
				return obj.name == null ? @:privateAccess obj.children : [obj];

			var skin = Std.downcast(item, h3d.scene.Skin);
			var obj = Std.downcast(item, h3d.scene.Object);
			var join = Std.downcast(item, h3d.scene.Skin.Joint);
			var children : Array<Dynamic> = [];

			if (obj != null && @:privateAccess obj.children != null) {
				for (c in @:privateAccess obj.children)
					if (!Std.isOfType(c, h3d.scene.Graphics))
						children.push(c);
			}

			if (skin != null) {
				var joints = skin.getSkinData().rootJoints;
				for (j in joints)
					children.push(skin.getObjectByName(j.name));
			}

			if (obj != null) {
				var mats = item.getMaterials(null, false);
				children = children.concat(mats);
			}

			if (join != null) {
				var sObj : h3d.scene.Object = join;
				while (!Std.isOfType(sObj, h3d.scene.Skin))
					sObj = sObj.parent;
				var skin : h3d.scene.Skin = cast sObj;
				for (j in @:privateAccess skin.getSkinData().allJoints[join.index].subs)
					children.push(skin.getObjectByName(j.name));
			}

			return children;
		};
		sceneEditor.tree.getItemName = (item: Dynamic) -> {
			var obj = Std.downcast(item, h3d.scene.Object);
			if (obj != null) return obj.name;

			var mat = Std.downcast(item, h3d.mat.Material);
			if (mat != null) return mat.name;

			var join = Std.downcast(item, h3d.scene.Skin.Joint);
			if (join != null) return join.name;

			return "";
		};
		sceneEditor.tree.getItemIcon = (item : Dynamic) -> {
			if (Std.isOfType(item, h3d.scene.Object))
				return HuiRes.icons.cube;
			if (Std.isOfType(item, h3d.mat.Material))
				return HuiRes.icons.material;
			if (Std.isOfType(item, h3d.scene.Skin.Joint))
				return HuiRes.icons.bone;
			return HuiRes.icons.file_blank;
		}
		sceneEditor.tree.getIdentifier = (item: Dynamic) -> {
			var o = Std.downcast(item, h3d.scene.Object);
			if (o == null) return item.name;
			var path = o.name;
			var parent = o.parent;
			while (parent != null) {
				path = '${parent.name}/${path}';
				parent = parent.parent;
			}
			return path;
		};
		sceneEditor.tree.onUserSelectionChanged = () -> {
			setSelection(cast sceneEditor.tree.getSelectedItems());
		}
		sceneEditor.tree.onItemDoubleClick = (_, el) -> {
			var obj = Std.downcast(el, h3d.scene.Object);
			if (obj != null)
				sceneEditor.focusObjects([obj]);
		};
		sceneEditor.tree.revealItem(obj);

		// Load collision settings
		collisionSettings = [];
		for (o in obj.getMeshes()) {
			var mesh = Std.downcast(obj, h3d.scene.Mesh);
			var hmd = Std.downcast(mesh?.primitive, h3d.prim.HMDModel);
			if (hmd == null) continue;

			var dirPath = @:privateAccess hmd.lib.resource.entry.directory;
			var resName = @:privateAccess hmd.lib.resource.name;
			var props = @:privateAccess h3d.prim.ModelDatabase.current.getModelData(dirPath, resName, obj.name);
			var settings = new CollisionSettings(Default, { useDefault : true });
			if (props != null && Reflect.hasField(props, h3d.prim.ModelDatabase.COLLIDE_CONFIG)) {
				var collideFields = Reflect.field(props, h3d.prim.ModelDatabase.COLLIDE_CONFIG);
				if (collideFields == null)
					settings = new CollisionSettings(None, null);
				else if(collideFields != null && Std.isOfType(collideFields, Array) ) {
					for (cf in (collideFields:Array<Dynamic>)) {
						var mode = Default;
						if (cf == null)
							mode = None;
						else if (Reflect.field(cf, "useDefault"))
							mode = Default;
						else if (Reflect.hasField(cf, "precision"))
							mode = Auto;
						else if (Reflect.hasField(cf, "mesh"))
							mode = Mesh;
						else if (Reflect.hasField(cf, "shapes"))
							mode = Shapes;
						settings = new CollisionSettings(mode, cf);
					}
				}
			}

			collisionSettings.set(o.name, settings);
		}
		sceneEditor.updateDebugOverlayVisibility();
	}

	override function sync(ctx) {
		super.sync(ctx);
	}

	override function getContextMenuContent(content: Array<hide.comp.ContextMenu.MenuItem>) {
		// content.push({label: "Save", click: () -> execCommand(HuiCommands.save)});
		// content.push({label: "Rebuild", click: () -> @:privateAccess prefabEditor.tryMake(prefabEditor.prefab)});
		// content.push({isSeparator: true});
		// content.push({label: "Debug dump", click: () -> {
		// 	var ser = @:privateAccess prefabEditor.prefab.serialize();
		// 	trace(haxe.Json.stringify(ser, "\t"));
		// }});
	}

	override function getViewName():String {
		return state.path.split("/").splice(-1, 2).join("/");
	}

	override function requestClose(cb: (canClose:Bool) -> Void) {
		if (hasUnsavedChanges) {
			uiBase.confirm("Save change before closing ?", Save | DontSave | Cancel, (choice: hrt.ui.HuiConfirmPopup.ConfirmButton) -> {
				switch (choice) {
					case Save:
						execCommand(HuiCommands.save);
						cb(true);
					case DontSave:
						cb(true);
					case Cancel:
						cb(false);
					default:
						throw "???";
				}
			});
		} else {
			cb(true);
		}
	}

	override function getToolbarWidgets() : Array<HuiElement> {
		var widgets : Array<HuiElement> = [];

		var cameraBtn = new HuiButton();
		new HuiIcon("camera", cameraBtn);
		cameraBtn.onClick = (_) -> {
			uiBase.addPopup(new hrt.ui.HuiToolbar.HuiCameraSettingsPopup(sceneEditor), { object: Element(cameraBtn), directionX: StartInside, directionY: EndOutside });
		}
		widgets.push(cameraBtn);

		var helpBtn = new HuiButton();
		helpBtn.onClick = (_) -> {
			uiBase.addPopup(new hrt.ui.HuiToolbar.HuiHelpPopup(this.registeredCommands), { object: Element(helpBtn), directionX: StartInside, directionY: EndOutside });
		};
		new HuiIcon("question_mark", helpBtn);
		widgets.push(helpBtn);

		widgets.push(new hrt.ui.HuiToolbar.HuiVisibilityWidget(sceneEditor));
		widgets.push(new hrt.ui.HuiToolbar.HuiViewModesWidget(sceneEditor.scene.s3d));
		widgets.push(new hrt.ui.HuiToolbar.HuiSceneFiltersWidget(sceneEditor));
		widgets.push(new hrt.ui.HuiToolbar.HuiRenderPropsWidget(sceneEditor));

		return widgets;
	}

	function save() {
		if (!hasUnsavedChanges)
			return;

		undo.markClean();
		hasUnsavedChanges = false;

		// Save model props
		for (o in obj.findAll(o -> Std.downcast(o, h3d.scene.Mesh))) {
			var hmd = Std.downcast(o.primitive, h3d.prim.HMDModel);
			if (hmd == null)
				continue;

			var settings = collisionSettings.get(o.name);
			var collide = {};
			if (settings != null) {
				switch (settings.mode) {
					case Default: collide = {};
					case None: collide = { collide : null };
					case Auto, Mesh, Shapes: collide = { collide : [settings.params] };
					default: throw "Unexpected collision mode";
				}
			}

			var input : h3d.prim.ModelDatabase.ModelDataInput = {
				resourceDirectory : @:privateAccess hmd.lib.resource.entry.directory,
				resourceName : @:privateAccess hmd.lib.resource.name,
				objectName : o.name,
				hmd : hmd,
				skin : o.find((o) -> Std.downcast(o, h3d.scene.Skin)),
				collide : collide
			}

			h3d.prim.ModelDatabase.current.saveModelProps(input);
			var lfs = cast(hxd.res.Loader.currentInstance.fs, hxd.fs.LocalFileSystem);
			lfs.removePathFromCache(state.path);
			@:privateAccess hxd.res.Loader.currentInstance.cache.remove(state.path);
		}
	}

	function load(path : String) {
		var scene = @:privateAccess sceneEditor.scene;
		var lib = hxd.res.Loader.currentInstance.load(path).toModel().toHmd();
		obj = lib.makeObject();
		sceneEditor.scene.s3d.addChild(obj);
	}

	function setSelection(selection: Array<Dynamic>) {
		var oldSelection = selectedObjects.copy();
		if (selection.length == oldSelection.length) {
			var same = true;
			for (p in selection) {
				if (!selectedObjects.contains(p)) {
					same = false;
					break;
				}
			}
			if (same)
				return;
		}

		for (s in selectedObjects) {
			var obj = Std.downcast(s, h3d.scene.Object);
			if (obj == null)
				continue;
			for (m in obj.getMaterials()) {
				var p = m.getPass("highlight");
				if (p == null) continue;
				m.removePass(p);
			}
		}

		selectedObjects = [];

		var objs : Array<h3d.scene.Object> = [];
		for (o in selection) {
			selectedObjects.push(o);
			var obj = Std.downcast(o, h3d.scene.Object);
			if (obj != null) {
				objs.push(obj);
				for (m in obj.getMaterials()) {
					var p = m.allocPass("highlight");
					p.culling = None;
					p.depthWrite = false;
					p.depthTest = Always;
				}
			}
		}

		refreshInspector();
	}

	function refreshInspector() {
		sceneEditor.inspectorPanel.removeChildElements();

		// TODO: manage multi-edit for objects
		if (selectedObjects.length != 1)
			return;

		var el = selectedObjects[0];
		var o = Std.downcast(el, h3d.scene.Object);
		if (o != null)
			modelInspector = new HuiModelInspector(o, this, sceneEditor.inspectorPanel);
	}

	function setColliderDebugVisibility(visible : Bool) {
		if (visible) {
			if (collisionSettings == null || sceneEditor.scene == null)
				return;

			if (sceneEditor.rootDebugCollider == null) {
				sceneEditor.rootDebugCollider = new h3d.scene.Object(sceneEditor.scene.s3d);
				sceneEditor.rootDebugCollider.name = "rootDebugCollider";
			}

			sceneEditor.rootDebugCollider.removeChildren();

			for (k in collisionSettings.keys()) {
				var obj = obj.getObjectByName(k);
				if (obj == null)
					continue;

				var debugCollider = new h3d.scene.Object(sceneEditor.rootDebugCollider);
				debugCollider.name = 'debug collider (${obj.name})';
				debugCollider.follow = obj;

				var fs : hxd.fs.LocalFileSystem = Std.downcast(hxd.res.Loader.currentInstance.fs, hxd.fs.LocalFileSystem);
				var convertRule = @:privateAccess fs.convert.getConvertRule(state.path);
				var c = collisionSettings.get(k);
				var debugCreated = false;

				// If user is currently using the shape editor, use the shape editors debug as debug colliders
				var shapeEditor = @:privateAccess modelInspector?.shapeEditor;
				if (shapeEditor != null && shapeEditor.visible == true && c.mode == Shapes) {
					shapeEditor.removeAllInteractives();
					shapeEditor.rootDebugObj = debugCollider;
					shapeEditor.createAllInteractives();
					debugCreated = true;
				}

				if (debugCreated)
					continue;

				var debug = c.getDebugCollider(cast obj, convertRule);
				if (debug == null)
					continue;

				debugCollider.addChild(debug);

				var colliderColor = 0x55FFFFFF;
				var intersectionColor = 0x55FF0000;

				for (m in debug.getMeshes()) {
					m.material.castShadows = false;
					m.material.blendMode = Alpha;
					m.material.name = "$collider";
					m.material.color.setColor(colliderColor);
					m.material.mainPass.setPassName("afterTonemapping");

					var debugWireframe = new h3d.scene.Mesh(m.primitive, null, m);
					debugWireframe.forcedLod = m.forcedLod;
					debugWireframe.name = "debugWireframe";
					debugWireframe.material.name = "$collider";
					debugWireframe.material.mainPass.wireframe = true;
					debugWireframe.material.castShadows = false;
					debugWireframe.material.color.setColor(colliderColor);
					debugWireframe.material.mainPass.setPassName("afterTonemapping");

					var debugIntersection = new h3d.scene.Mesh(m.primitive, null, m);
					debugIntersection.forcedLod = m.forcedLod;
					debugIntersection.name = "debugIntersection";
					debugIntersection.material.name = "$collider";
					debugIntersection.material.castShadows = false;
					debugIntersection.material.blendMode = Alpha;
					debugIntersection.material.mainPass.culling = Front;
					debugIntersection.material.mainPass.depth(false, GreaterEqual);
					debugIntersection.material.color.setColor(intersectionColor);
					debugIntersection.material.mainPass.setPassName("afterTonemapping");
				}
			}
		}
		else if (sceneEditor.rootDebugCollider != null) {
			sceneEditor.rootDebugCollider.remove();
			sceneEditor.rootDebugCollider = null;
		}
	}
}

#end