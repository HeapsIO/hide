package hrt.ui;

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
		<hui-category("Dynamic Bones")>
		</hui-category>
		<hui-category("Blend Shapes")>
		</hui-category>
	</hui-model-inspector>

	var model : hide.view.Model;

	public function new(obj : h3d.scene.Object, model: hide.view.Model, ?parent: h2d.Object) {
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
			hide.Ide.showInfo("Copied current lod config to the clipboard");
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
				hide.Ide.showError("Couldn't paste config from clipboard (invalid data)");
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
			hide.Ide.showInfo("Pasted config from the clipboard");
		};

		resetLods.onClick = (_) -> {
			var prevConfig = @:privateAccess hmd.lodConfig?.copy();
			@:privateAccess hmd.lodConfig = h3d.prim.ModelDatabase.current.getDefaultLodConfig(hmd.lib.resource.entry.directory);
			hide.Ide.showInfo('Lod config reset for object : ${obj.name}');
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
			precisionEl.parent.visible = collisionModeEl.value == hide.view.Model.CollisionMode.Auto;
			precisionEl.text = '${settings.params?.precision ?? 1.0}';

			maxConvexHullsEl.parent.visible = collisionModeEl.value == hide.view.Model.CollisionMode.Auto;
			maxConvexHullsEl.text = '${settings.params?.maxConvexHulls ?? 1}';

			maxSubdivisionEl.parent.visible = collisionModeEl.value == hide.view.Model.CollisionMode.Auto;
			maxSubdivisionEl.text = '${settings.params?.maxSubdiv ?? 32}';

			meshEl.items = [ { value: null, label: "None" } ];
			if (hmd != null) {
				for (m in hmd.lib.header.models) {
					if (m.geometry >= 0)
						meshEl.items.push({ label: m.name, value: m.name });
				}
			}
			meshEl.parent.visible = collisionModeEl.value == hide.view.Model.CollisionMode.Auto || collisionModeEl.value == hide.view.Model.CollisionMode.Mesh;
			meshEl.value = settings.params?.mesh;

			computeColliderBtn.visible = collisionModeEl.value == hide.view.Model.CollisionMode.Auto;

			shapeEditor.visible = collisionModeEl.value == hide.view.Model.CollisionMode.Shapes;
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
				case hide.view.Model.CollisionMode.Default:
					Reflect.setField(curParams, "useDefault", true);
				case hide.view.Model.CollisionMode.None:
					curParams = null;
				case hide.view.Model.CollisionMode.Auto:
					Reflect.setField(curParams, "precision", Std.parseFloat(precisionEl.text));
					Reflect.setField(curParams, "maxConvexHulls", Std.parseInt(maxConvexHullsEl.text));
					Reflect.setField(curParams, "maxSubdiv", Std.parseInt(maxSubdivisionEl.text));
					Reflect.setField(curParams, "mesh", meshName == "null" ? null : meshName);
				case hide.view.Model.CollisionMode.Mesh:
					Reflect.setField(curParams, "mesh", meshName == "null" ? null : meshName);
				case hide.view.Model.CollisionMode.Shapes:
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
			if (curMode != hide.view.Model.CollisionMode.Auto || curMode != prevMode)
				@:privateAccess model.sceneEditor.updateDebugOverlayVisibility();

			model.undo.record((isUndo) -> {
				var mode = isUndo ? prevMode : curMode;
				var params = isUndo ? prevParams : curParams;
				settings.mode = mode;
				settings.params = params;
				refreshCollisionEdition();
				if (curMode != hide.view.Model.CollisionMode.Auto || curMode != prevMode)
					@:privateAccess model.sceneEditor.updateDebugOverlayVisibility();
				if (settings.mode == hide.view.Model.CollisionMode.Shapes)
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

		collisionModeEl.items = [for(idx in 0...hide.view.Model.CollisionMode.Count) { value: idx, label: cast(idx, hide.view.Model.CollisionMode).toString()}];
		collisionModeEl.value = settings.mode;

		refreshCollisionEdition();
	}
}
#end