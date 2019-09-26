package hrt.prefab.l3d;

import h3d.Vector;
import hxd.Key as K;

class MeshSpray extends Object3D {

	#if editor

	var meshes : Array<String> = [];
	var sceneEditor : hide.comp.SceneEditor;

	var density : Int = 10;
	var densityOffset : Int = 0;
	var radius : Float = 10.0;
	var scale : Float = 1.0;
	var scaleOffset : Float = 0.1;
	var rotation : Float = 0.0;
	var rotationOffset : Float = 0.0;

	var sprayEnable : Bool = false;
	var interactive : h2d.Interactive;
	var gBrush : h3d.scene.Graphics;

	var timerCicle : haxe.Timer;

	var lastSpray : Float = 0;

	#end

	public function new( ?parent ) {
		super(parent);
		type = "meshBatch";
	}

	#if editor

	override function save() {
		var obj : Dynamic = super.save();
		obj.meshes = meshes;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		if (obj.meshes != null)
			meshes = obj.meshes;
	}


	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		ctx.local3d = new SprayObject(ctx.local3d);
		ctx.local3d.name = name;
		updateInstance(ctx);
		return ctx;
	}

	override function getHideProps() : HideProps {
		return { icon : "paint-brush", name : "MeshSpray" };
	}

	function extractMeshName( path : String ) : String {
		if( path == null ) return "None";
		var childParts = path.split("/");
		return childParts[childParts.length - 1].split(".")[0];
	}

	override function edit( ectx : EditContext ) {
		sceneEditor = ectx.scene.editor;
		var ctx = ectx.getContext(this);
		var s2d = @:privateAccess ctx.local2d.getScene();
		interactive = new h2d.Interactive(10000, 10000, s2d);
		interactive.propagateEvents = true;
		interactive.cancelEvents = false;
		interactive.onWheel = function(e) {

		};
		interactive.onPush = function(e) {
			e.propagate = false;
			sprayEnable = true;

		};
		interactive.onRelease = function(e) {
			e.propagate = false;
			sprayEnable = false;
		};
		interactive.onMove = function(e) {
			var worldPos = screenToWorld(s2d.mouseX, s2d.mouseY);
			worldPos.z = getZ(worldPos.x, worldPos.y);
			drawCircle(ctx, worldPos.x, worldPos.y, worldPos.z, radius, 2, 16711680);
			if( K.isDown( K.MOUSE_LEFT) ) {
				e.propagate = false;
				if (sprayEnable) {
					if (lastSpray < Date.now().getTime() - 50) {
						if( K.isDown( K.SHIFT) ) {
							removeMeshesAround(ctx, worldPos);
						} else {
							addMeshesAround(ctx, worldPos);
						}
						lastSpray = Date.now().getTime();
					}
				}
			}
		};

		var props = new hide.Element('<div class="group" name="Meshes"></div>');
		var selectElement = new hide.Element('<select multiple size="6" style="width: 300px" ></select>').appendTo(props);
		for (m in meshes) {
			addMeshPath(m);
			selectElement.append(new hide.Element('<option value="${m}">${extractMeshName(m)}</option>'));
		}
		var options = new hide.Element('<div class="btn-list" align="center" ></div>').appendTo(props);

		var selectAllBtn = new hide.Element('<input type="button" value="Select all" />').appendTo(options);
		var addBtn = new hide.Element('<input type="button" value="Add" >').appendTo(options);
		var removeBtn = new hide.Element('<input type="button" value="Remove" />').appendTo(options);
		var cleanBtn = new hide.Element('<input type="button" value="Remove all meshes" />').appendTo(options);
		new hide.Element('<br /><b><i>Hold down SHIFT to remove meshes</i></b>').appendTo(options);

		selectAllBtn.on("click", function() {
			var options = selectElement.children().elements();
			for (opt in options) {
				opt.prop("selected", true);
			}
		});
		addBtn.on("click", function () {
			hide.Ide.inst.chooseFiles(["fbx"], function(path) {
				for( m in path ) {
					addMeshPath(m);
					selectElement.append(new hide.Element('<option value="$m">${extractMeshName(m)}</option>'));
				}
			});
		});
		removeBtn.on("click", function () {
			var options = selectElement.children().elements();
			for (opt in options) {
				if (opt.prop("selected")) {
					removeMeshPath(opt.val());
					opt.remove();
				}
			}
		});
		cleanBtn.on("click", function() {
			if (hide.Ide.inst.confirm("Are you sure to remove all meshes for this MeshSpray ?")) {
				sceneEditor.deleteElements(children.copy());
				sceneEditor.selectObjects([this]);
			}
		});

		ectx.properties.add(props, this, function(pname) {});

		var optionsGroup = new hide.Element('<div class="group" name="Options"><dl></dl></div>');
		optionsGroup.append(hide.comp.PropsEditor.makePropsList([
				{ name: "density", t: PInt(1, 25), def: density },
				{ name: "densityOffset", t: PInt(0, 10), def: densityOffset },
				{ name: "radius", t: PFloat(0, 50), def: radius },
				{ name: "scale", t: PFloat(0, 10), def: scale },
				{ name: "scaleOffset", t: PFloat(0, 1), def: scaleOffset },
				{ name: "rotation", t: PFloat(0, 180), def: rotation },
				{ name: "rotationOffset", t: PFloat(0, 30), def: rotationOffset }
			]));
		ectx.properties.add(optionsGroup, this, function(pname) {  });
	}

	override function setSelected( ctx : Context, b : Bool ) {

		if (timerCicle != null) {
			timerCicle.stop();
		}
		if( !b ) {
			if( interactive != null ) interactive.remove();
			timerCicle = new haxe.Timer(100);
			timerCicle.run = function() {
				timerCicle.stop();
				if (gBrush != null) gBrush.remove();
			};
		}
	}

	function addMeshPath(path : String) {
		if (meshes.indexOf(path) == -1)
			meshes.push(path);
	}

	function removeMeshPath(path : String) {
		meshes.remove(path);
	}

	function addMeshesAround(ctx : Context, point : h3d.col.Point) {
		if (meshes.length == 0) {
			throw "There is no meshes";
		}
		var nbMeshesInZone = 0;
		var vecRelat = point.toVector();
		var transform = this.getTransform().clone();
		transform.invert();
		vecRelat.transform3x4(transform);
		var point2d = new h2d.col.Point(vecRelat.x, vecRelat.y);
		var computedDensity = density + Std.random(densityOffset+1);
		var minDistanceBetweenMeshesSq = (radius * radius / computedDensity);
		var currentPivots : Array<h2d.col.Point> = [];
		inline function distance(x1 : Float, y1 : Float, x2 : Float, y2 : Float) return (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2);
		var fakeRadius = radius * radius + minDistanceBetweenMeshesSq;
		for (child in children) {
			var model = child.to(hrt.prefab.Object3D);
			if (distance(point2d.x, point2d.y, model.x, model.y) < fakeRadius) {
				nbMeshesInZone++;
				currentPivots.push(new h2d.col.Point(model.x, model.y));
			}
		}
		var nbMeshesToPlace = computedDensity - nbMeshesInZone;
		if (nbMeshesToPlace > 0) {
			var models : Array<hrt.prefab.Prefab> = [];
			var random = new hxd.Rand(Std.random(0xFFFFFF));
			while (nbMeshesToPlace-- > 0) {
				var nbTry = 5;
				var position : h3d.col.Point;
				do {
					var randomRadius = radius*Math.sqrt(random.rand());
					var angle = random.rand() * 2*Math.PI;
					position = new h3d.col.Point(point.x + randomRadius*Math.cos(angle), point.y + randomRadius*Math.sin(angle), 0);
					var vecRelat = position.toVector();
					vecRelat.transform3x4(transform);
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
				var randRotationOffset = random.rand() * rotationOffset;
				if (Std.random(2) == 0) {
					randRotationOffset *= -1;
				}
				var rotationZ = ((rotation  + randRotationOffset) % 360)/360 * 2*Math.PI;
				var model = new hrt.prefab.Model(this);
				model.source = meshes[Std.random(meshes.length)];
				model.name = extractMeshName(model.source);
				var localMat = new h3d.Matrix();
				localMat.initRotationZ(rotationZ);
				var randScaleOffset = random.rand() * scaleOffset;
				if (Std.random(2) == 0) {
					randScaleOffset *= -1;
				}
				var currentScale = (scale + randScaleOffset);
				localMat.scale(currentScale, currentScale, currentScale);
				position.z = getZ(position.x, position.y);
				localMat.setPosition(new Vector(position.x, position.y, position.z));
				var invParent = getTransform().clone();
				invParent.invert();
				localMat.multiply(localMat, invParent);
				model.setTransform(localMat);
				models.push(model);
				currentPivots.push(new h2d.col.Point(model.x, model.y));
			}
			sceneEditor.addObject(models);
			sceneEditor.selectObjects([this]);
			@:privateAccess Std.downcast(ctx.local3d, SprayObject).blockHead = null;
		}
	}

	function removeMeshesAround(ctx : Context, point : h3d.col.Point) {
		var vecRelat = point.toVector();
		var transform = this.getTransform().clone();
		transform.invert();
		vecRelat.transform3x4(transform);
		var point2d = new h2d.col.Point(vecRelat.x, vecRelat.y);
		var childToRemove = [];
		inline function distance(x1 : Float, y1 : Float, x2 : Float, y2 : Float) return (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2);
		var fakeRadius = radius * radius;
		for (child in children) {
			var model = child.to(hrt.prefab.Object3D);
			if (distance(point2d.x, point2d.y, model.x, model.y) < fakeRadius) {
				childToRemove.push(child);
			}
		}
		sceneEditor.deleteElements(childToRemove);
		sceneEditor.selectObjects([this]);
	}

	public function drawCircle(ctx : Context, originX : Float, originY : Float, originZ : Float, radius: Float, thickness: Float, color) {
		if (gBrush != null) gBrush.remove();
		gBrush = new h3d.scene.Graphics(sceneEditor.scene.s3d);
		gBrush.material.props = h3d.mat.MaterialSetup.current.getDefaults("fx");
		gBrush.material.mainPass.setPassName("overlay");
		gBrush.material.shadows = false;
		gBrush.setPosition(originX, originY, originZ + 0.15);
		gBrush.lineStyle(thickness, color, 1.0);
		gBrush.moveTo(radius, 0, 0);
		var nsegments = 32;
		for(i in 0...nsegments) {
			var theta = Math.PI * 2 * (i+1)/nsegments;
			gBrush.lineTo(Math.cos(theta) * radius, Math.sin(theta) * radius, 0);
		}
		gBrush.lineStyle();
	}

	// GET Z with TERRAIN

	public function getZ( x : Float, y : Float ) {
		var z = this.z;

		@:privateAccess var terrain = sceneEditor.sceneData.find(p -> Std.downcast(p, hrt.prefab.terrain.Terrain));

		if(terrain != null){
			var pos = new h3d.Vector(x, y, 0);
			pos.transform3x4(this.getTransform());
			z = terrain.terrain.getHeight(pos.x, pos.y);
		}

		return z;
	}

	public function screenToWorld(sx: Float, sy: Float) {
		var camera = sceneEditor.scene.s3d.camera;
		var ray = camera.rayFromScreen(sx, sy);
		return ray.intersect(h3d.col.Plane.Z());
	}

	function projectToGround( ray: h3d.col.Ray ) {
		var minDist = -1.;
		@:privateAccess var terrainPrefab = sceneEditor.sceneData.find(p -> Std.downcast(p, hrt.prefab.terrain.Terrain));
		if (terrainPrefab != null) {
			var normal = terrainPrefab.terrain.getAbsPos().up();
			var plane = h3d.col.Plane.fromNormalPoint(normal.toPoint(), new h3d.col.Point(terrainPrefab.terrain.getAbsPos().tx, terrainPrefab.terrain.getAbsPos().ty, terrainPrefab.terrain.getAbsPos().tz));
			var pt = ray.intersect(plane);
			if(pt != null) { minDist = pt.sub(ray.getPos()).length();}
		}
		return minDist;
	}

	#end

	static var _ = Library.register("meshSpray", MeshSpray);
}