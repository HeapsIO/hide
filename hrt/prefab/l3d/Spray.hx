package hrt.prefab.l3d;

import h3d.Vector;
import hxd.Key as K;

typedef Source = {
	var path: String;
	var isRef: Bool;
}

#if !editor

class SprayObject extends h3d.scene.Object {
}

class Spray extends Object3D {

	@:s var sources : Array<{ path : String }> = [];

	override function createObject( ctx : Context ) {
		var spray = new SprayObject(ctx.local3d);
		return spray;
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
}

#else

typedef Set = {
	var name: String;
	var sources: Array<Source>;
	var config: SprayConfig;
}

typedef SetGroup = {
	var name: String;
	var sets: Array<Set>;
}

typedef SprayConfig = {
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
	var dontRepeatItem : Bool;
	var enableBrush : Bool;
	var orientTerrain : Float;
	var tiltAmount : Float;
}


@:access(hrt.prefab.l3d.MeshSpray)
class SprayObject extends h3d.scene.Object {

	var spray : Spray;

	public function new(spray,?parent) {
		this.spray = spray;
		super(parent);
	}


	public function redraw(updateShaders=false) {
		getBounds(); // force absBos calculus on children
		for( c in children ) {
			c.culled = false;
			if( c.alwaysSyncAnimation ) continue;
		}
	}

}

class Spray extends Object3D {

	@:s var sources : Array<Source> = []; // specific set for this spray
	@:s var defaultConfig: SprayConfig;
	@:s var currentPresetName : String = null;
	@:s var currentSetName : String = null;

	var sceneEditor : hide.comp.SceneEditor;

	var undo(get, null):hide.ui.UndoHistory;
	function get_undo() { return sceneEditor.view.undo; }

	var lastIndexItem = -1;
	var allSetGroups : Array<SetGroup>;
	var setGroup : SetGroup;
	var currentSet : Set;

	var currentSources(get, null) : Array<Source>;
	function get_currentSources() {
		if (currentSet != null)
			return currentSet.sources;
		else
			return sources;
	}

	var currentConfig(get, null) : SprayConfig;
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
	var lastItemPos : h3d.col.Point;
	var invParent : h3d.Matrix;

	var shared : ContextShared;

	function clearPreview() {
		// prevent saving preview
		if( previewItems.length > 0 ) {
			sceneEditor.deleteElements(previewItems, () -> { }, false, false);
			previewItems = [];
		}
	}

	function getDefaultConfig() : SprayConfig {
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
			dontRepeatItem: true,
			enableBrush: true,
			orientTerrain : 0,
			tiltAmount : 0,
		};
	}

	function extractItemName( path : String ) : String {
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
	var previewItems : Array<hrt.prefab.Prefab> = [];
	var sprayedItems : Array<hrt.prefab.Prefab> = [];
	var selectElement : hide.Element;

	function createInteractiveBrush(ectx : EditContext) {
		if (!enabled) return;
		var ctx = ectx.getContext(this);
		var s2d = ctx.shared.root2d.getScene();
		interactive = new h2d.Interactive(10000, 10000, s2d);
		interactive.propagateEvents = true;
		interactive.cancelEvents = false;

		interactive.onWheel = function(e) {

		};

		interactive.onKeyUp = function(e) {
			if (e.keyCode == K.R) {
				lastItemId = -1;
				if (lastSpray < Date.now().getTime() - 100) {
					if( !K.isDown( K.SHIFT) ) {
						clearPreview();
						var worldPos = ectx.screenToGround(s2d.mouseX, s2d.mouseY);
						previewItemsAround(ectx, ctx, worldPos);
					}
					lastSpray = Date.now().getTime();
					lastItemPos = null;
				}
			}
			if (e.keyCode == K.Q) {
				e.propagate = false;
				currentConfig.rotation -= 10;
				currentConfig.rotation = currentConfig.rotation % 360;
				clearPreview();
				var worldPos = ectx.screenToGround(s2d.mouseX, s2d.mouseY);
				previewItemsAround(ectx, ctx, worldPos);
			}

			if (e.keyCode == K.D) {
				e.propagate = false;
				currentConfig.rotation += 10;
				currentConfig.rotation = currentConfig.rotation % 360;
				clearPreview();
				var worldPos = ectx.screenToGround(s2d.mouseX, s2d.mouseY);
				previewItemsAround(ectx, ctx, worldPos);
			}
		}

		interactive.onPush = function(e) {
			e.propagate = false;
			sprayEnable = true;
			var worldPos = ectx.screenToGround(s2d.mouseX, s2d.mouseY);
			if( K.isDown( K.SHIFT) )
				removeItemsAround(ctx, worldPos);
			else {
				lastItemPos = worldPos.clone();
				addItems(ctx);
			}
		};

		interactive.onRelease = function(e) {
			e.propagate = false;
			sprayEnable = false;
			var addedModels = sprayedItems.copy();
			if (sprayedItems.length > 0) {
				undo.change(Custom(function(undo) {
					if(undo) {
						sceneEditor.deleteElements(addedModels, () -> removeInteractiveBrush(), true, false);
						clearPreview();
					}
					else {
						sceneEditor.addElements(addedModels, false, true, false);
					}
					cast(ctx.local3d,SprayObject).redraw();
				}));
				sprayedItems = [];
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
					previewItemsAround(ectx, ctx, worldPos);
				}

				if( K.isDown( K.MOUSE_LEFT) ) {
					e.propagate = false;

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

	function addSourcePath(path : String) {
	}

	function removeSourcePath(path : String) {
		var source = currentSources.filter(m -> m.path == path);
		if (source.length > 0)
			currentSources.remove(source[0]);
	}

	var localMat = new h3d.Matrix();
	var lastPos : h3d.col.Point;
	var lastItemId = -1;
	var lastSprayedObj : h3d.scene.Object;
	function previewItemsAround(ectx : hide.prefab.EditContext, ctx : Context, point : h3d.col.Point) {
		if (currentSources.length == 0) {
			return;
		}
		var nbItemsInZone = 0;
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
			var item = child.to(hrt.prefab.Object3D);
			if( item == null ) continue;
			if (distance(point2d.x, point2d.y, item.x, item.y) < fakeRadius) {
				if (previewItems.indexOf(item) != -1) continue;
				nbItemsInZone++;
				currentPivots.push(new h2d.col.Point(item.x, item.y));
			}
		}
		var nbItemsToPlace = computedDensity - nbItemsInZone;
		if (computedDensity == 1)
			clearPreview();
		lastPos = point;
		if (nbItemsToPlace > 0) {
			while (nbItemsToPlace-- > 0) {
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

				var itemId = 0;
				var itemUsed = null;
				var options = selectElement.children().elements();
				var selectedItems = [];
				for (opt in options) {
					if (opt.prop("selected")) {
						var findItem = currentSources.filter((m) -> m.path == opt.val());
						if (findItem.length > 0)
							selectedItems.push(findItem[0]);
					}
				}
				if (selectedItems.length > 0) {
					if(selectedItems.length > 1) {
						do
							itemId = Std.random(selectedItems.length)
						while(CONFIG.dontRepeatItem && itemId == lastItemId);
					}
					itemUsed = selectedItems[itemId];
				}
				else {
					if(currentSources.length > 1) {
						do
							itemId = Std.random(currentSources.length)
						while(CONFIG.dontRepeatItem && itemId == lastItemId);
					}
					itemUsed = currentSources[itemId];
				}
				lastIndexItem = itemId;
				if (computedDensity == 1)
					lastItemId = itemId;
				else
					lastItemId = -1;


				var newPrefab : hrt.prefab.Object3D = null;

				if (itemUsed.isRef) {
					var refPrefab = new hrt.prefab.Reference(this);
					refPrefab.source = itemUsed.path;
					newPrefab = refPrefab;
				} else {
					var model = new hrt.prefab.Model(this);
					model.source = itemUsed.path;
					newPrefab = model;
				}

				newPrefab.name = extractItemName(itemUsed.path);

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

				previewItems.push(newPrefab);
				currentPivots.push(new h2d.col.Point(newPrefab.x, newPrefab.y));
			}

			if (previewItems.length > 0) {
				sceneEditor.addElements(previewItems, false, false, false);
			}
		}
	}

	function addItems(ctx : Context) {
		lastItemId = -1;
		if (previewItems.length > 0) {
			wasEdited = true;
			sprayedItems = sprayedItems.concat(previewItems);
			previewItems = [];
			clearBrushes();
			cast(ctx.local3d,SprayObject).redraw();
		}
	}

	function removeItemsAround(ctx : Context, point : h3d.col.Point) {
		var vecRelat = point.toVector();
		vecRelat.transform3x4(invParent);
		var point2d = new h2d.col.Point(vecRelat.x, vecRelat.y);

		var childToRemove = [];
		inline function distance(x1 : Float, y1 : Float, x2 : Float, y2 : Float) return (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2);
		var fakeRadius = currentConfig.deleteRadius * currentConfig.deleteRadius;
		for (child in children) {
			var item = child.to(hrt.prefab.Object3D);
			if (item != null) {
				if (distance(point2d.x, point2d.y, item.x, item.y) < fakeRadius) {
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
			cast(ctx.local3d,SprayObject).redraw();
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
		ctx.local3d = new SprayObject(this, ctx.local3d);
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
		cast(o, SprayObject).redraw();
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

}

#end
