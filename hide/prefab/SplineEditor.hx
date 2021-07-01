package hide.prefab;
import hxd.Key as K;
import hrt.prefab.l3d.Spline;

#if editor

class NewSplinePointViewer extends h3d.scene.Object {

	var pointViewer : h3d.scene.Mesh;
	var connectionViewer : h3d.scene.Graphics;
	var tangentViewer : h3d.scene.Graphics;

	public function new( parent : h3d.scene.Object ) {
		super(parent);
		name = "SplinePointViewer";
		pointViewer = new h3d.scene.Mesh(h3d.prim.Sphere.defaultUnitSphere(), null, this);
		pointViewer.name = "pointViewer";
		pointViewer.material.setDefaultProps("ui");
		pointViewer.material.color.set(1,1,0,1);
		pointViewer.material.mainPass.depthTest = Always;

		connectionViewer = new h3d.scene.Graphics(this);
		connectionViewer.name = "connectionViewer";
		connectionViewer.lineStyle(3, 0xFFFF00);
		connectionViewer.material.mainPass.setPassName("ui");
		connectionViewer.material.mainPass.depthTest = Always;
		connectionViewer.clear();

		tangentViewer = new h3d.scene.Graphics(this);
		tangentViewer.name = "tangentViewerViewer";
		tangentViewer.lineStyle(3, 0xFFFF00);
		tangentViewer.material.mainPass.setPassName("ui");
		tangentViewer.material.mainPass.depthTest = Always;
		tangentViewer.clear();
	}

	override function sync( ctx : h3d.scene.RenderContext ) {
		var cam = ctx.camera;
		var gpos = getAbsPos().getPosition();
		var distToCam = cam.pos.sub(gpos).length();
		var engine = h3d.Engine.getCurrent();
		var ratio = 18 / engine.height;
		var correctionFromParents =  1.0 / getAbsPos().getScale().x;
		pointViewer.setScale(correctionFromParents * ratio * distToCam * Math.tan(cam.fovY * 0.5 * Math.PI / 180.0));
		calcAbsPos();
		super.sync(ctx);
	}

	public function update( spd : SplinePointData ) {

		pointViewer.setPosition(spd.pos.x, spd.pos.y, spd.pos.z);

		tangentViewer.clear();
		tangentViewer.visible = spd.tangent != null;
		if( spd.tangent != null ) {
			var scale = 1.0;
			if( spd.prev != null && spd.next != null ) scale = (spd.prev.scaleX + spd.next.scaleX) * 0.5;
			else if( spd.prev != null ) scale = spd.prev.scaleX;
			else if( spd.next != null ) scale = spd.next.scaleX;
			tangentViewer.moveTo(spd.pos.x - spd.tangent.x * scale, spd.pos.y - spd.tangent.y * scale, spd.pos.z - spd.tangent.z * scale);
			tangentViewer.lineTo(spd.pos.x + spd.tangent.x * scale, spd.pos.y + spd.tangent.y * scale, spd.pos.z + spd.tangent.z * scale);
		}

		// Only display the connection if we are adding the new point at the end or the beggining fo the spline
		connectionViewer.clear();
		connectionViewer.visible = spd.prev == null || spd.next == null;
		if( connectionViewer.visible ) {
			var startPos = spd.prev == null ? spd.next.getPoint() : spd.prev.getPoint();
			connectionViewer.moveTo(startPos.x, startPos.y, startPos.z);
			connectionViewer.lineTo(spd.pos.x, spd.pos.y, spd.pos.z);
		}
	}
}

class SplinePointViewer extends h3d.scene.Object {

	var pointViewer : h3d.scene.Mesh;
	var controlPointsViewer : h3d.scene.Graphics;
	var indexText : h2d.ObjectFollower;
	var spline : Spline;
	var splinePoint : SplinePoint;

	public function new( sp : SplinePoint, spline : Spline, ctx : hrt.prefab.Context) {
		super(sp.obj);
		this.spline = spline;
		this.splinePoint = sp;
		name = "SplinePointViewer";
		pointViewer = new h3d.scene.Mesh(h3d.prim.Sphere.defaultUnitSphere(), null, this);
		pointViewer.name = "pointViewer";
		pointViewer.material.setDefaultProps("ui");
		pointViewer.material.color.set(1,1,1,1);
		pointViewer.material.mainPass.depthTest = Always;

		controlPointsViewer = new h3d.scene.Graphics(this);
		controlPointsViewer.name = "controlPointsViewer";
		controlPointsViewer.lineStyle(4, 0xffffff);
		controlPointsViewer.material.mainPass.setPassName("ui");
		controlPointsViewer.material.mainPass.depthTest = Always;
		controlPointsViewer.ignoreParentTransform = false;
		controlPointsViewer.clear();
		controlPointsViewer.moveTo(1, 0, 0);
		controlPointsViewer.lineTo(-1, 0, 0);

		indexText = new h2d.ObjectFollower(pointViewer,  @:privateAccess ctx.local2d.getScene());
		var t = new h2d.Text(hxd.res.DefaultFont.get(), indexText);
		t.textColor = 0xff00ff;
		t.textAlign = Center;
		t.dropShadow = { dx : 0.5, dy : 0.5, color : 0x202020, alpha : 1.0 };
		t.setScale(2.5);
	}

	override function sync( ctx : h3d.scene.RenderContext ) {
		var cam = ctx.camera;
		var gpos = getAbsPos().getPosition();
		var distToCam = cam.pos.sub(gpos).length();
		var engine = h3d.Engine.getCurrent();
		var ratio = 18 / engine.height;
		var correctionFromParents =  1.0 / getAbsPos().getScale().x;
		pointViewer.setScale(correctionFromParents * ratio * distToCam * Math.tan(cam.fovY * 0.5 * Math.PI / 180.0));
		calcAbsPos();

		var t = Std.downcast(indexText.getChildAt(0), h2d.Text);
		t.text = "" + spline.points.indexOf(splinePoint);

		super.sync(ctx);
	}

	public function interset( ray : h3d.col.Ray ) : Bool {
		return pointViewer.getCollider().rayIntersection(ray, false) != -1;
	}

	public function setColor( color : Int ) {
		controlPointsViewer.setColor(color);
		pointViewer.material.color.setColor(color);
	}

	override function onRemove() {
		super.onRemove();
		indexText.remove();
	}
}

@:access(hrt.prefab.l3d.Spline)
class SplineEditor {

	public var prefab : Spline;
	public var editContext : EditContext;
	var editMode = false;
	var undo : hide.ui.UndoHistory;

	var interactive : h2d.Interactive;

	 // Easy way to keep track of viewers
	var splinePointViewers : Array<SplinePointViewer> = [];
	var gizmos : Array<hide.view.l3d.Gizmo> = [];
	var newSplinePointViewer : NewSplinePointViewer;

	public function new( prefab : Spline, undo : hide.ui.UndoHistory ){
		this.prefab = prefab;
		this.undo = undo;
	}

	public function update( ctx : hrt.prefab.Context , ?propName : String ) {
		if( editMode ) {
			showViewers(ctx);
		}
	}

	function reset() {
		removeViewers();
		removeGizmos();
		if( interactive != null ) {
			interactive.remove();
			interactive = null;
		}
		if( newSplinePointViewer != null ) {
			newSplinePointViewer.remove();
			newSplinePointViewer = null;
		}
	}

	inline function getContext() {
		return editContext.getContext(prefab);
	}

	function getClosestSplinePointFromMouse( mouseX : Float, mouseY : Float, ctx : hrt.prefab.Context ) : SplinePoint {
		if( ctx == null || ctx.local3d == null || ctx.local3d.getScene() == null )
			return null;

		var mousePos = new h3d.Vector( mouseX / h3d.Engine.getCurrent().width, 1.0 - mouseY / h3d.Engine.getCurrent().height, 0);
		var minDist = -1.0;
		var result : SplinePoint = null;
		for( sp in prefab.points ) {
			var screenPos = sp.getPoint().toVector();
			screenPos.project(ctx.local3d.getScene().camera.m);
			screenPos.z = 0;
			screenPos.scale3(0.5);
			screenPos = screenPos.add(new h3d.Vector(0.5,0.5));
			var dist = screenPos.distance(mousePos);
			if( dist < minDist || minDist == -1 ) {
				minDist = dist;
				result = sp;
			}
		}
		return result;
	}

	function getNewPointPosition( mouseX : Float, mouseY : Float, ctx : hrt.prefab.Context ) : SplinePointData {
		if( prefab.points.length == 0 ) {
			return { pos : ctx.local3d.getAbsPos().getPosition().toPoint(), tangent : ctx.local3d.getAbsPos().right().toPoint() , prev : null, next : null };
		}

		var closestPt = getClosestPointFromMouse(mouseX, mouseY, ctx);

		// If we are are adding a new point at the beginning/end, just make a raycast 'cursor -> plane' with the transform of the first/last SplinePoint
		if( !prefab.loop && (closestPt.next == null || closestPt.prev == null) ) {
			var camera = @:privateAccess ctx.local3d.getScene().camera;
			var ray = camera.rayFromScreen(mouseX, mouseY);
			var normal = closestPt.next == null ? closestPt.prev.getAbsPos().up().toPoint() : closestPt.next.getAbsPos().up().toPoint();
			var point = closestPt.next == null ? closestPt.prev.getAbsPos().getPosition().toPoint() : closestPt.next.getAbsPos().getPosition().toPoint();
			var plane = h3d.col.Plane.fromNormalPoint(normal, point);
			var pt = ray.intersect(plane);
			return { pos : pt, tangent : closestPt.tangent, prev : closestPt.prev, next : closestPt.next };
		}
		else
			return closestPt;
	}

	function getClosestPointFromMouse( mouseX : Float, mouseY : Float, ctx : hrt.prefab.Context ) : SplinePointData {

		if( ctx == null || ctx.local3d == null || ctx.local3d.getScene() == null )
			return null;

		var result : SplinePointData = null;
		var mousePos = new h3d.Vector( mouseX / h3d.Engine.getCurrent().width, 1.0 - mouseY / h3d.Engine.getCurrent().height, 0);
		var minDist = -1.0;
		for( s in prefab.data.samples ) {
			var screenPos = s.pos.toVector();
			screenPos.project(ctx.local3d.getScene().camera.m);
			screenPos.z = 0;
			screenPos.scale3(0.5);
			screenPos = screenPos.add(new h3d.Vector(0.5,0.5));
			var dist = screenPos.distance(mousePos);
			if( (dist < minDist || minDist == -1) && dist < 0.1 ) {
				minDist = dist;
				result = s;
			}
		}

		if( result == null ) {
			result = { pos : null, tangent : null, prev : null, next : null };

			var firstSp = prefab.points[0];
			var firstPt = firstSp.getPoint();
			var firstPtScreenPos = firstPt.toVector();
			firstPtScreenPos.project(ctx.local3d.getScene().camera.m);
			firstPtScreenPos.z = 0;
			firstPtScreenPos.scale3(0.5);
			firstPtScreenPos = firstPtScreenPos.add(new h3d.Vector(0.5,0.5));
			var distToFirstPoint = firstPtScreenPos.distance(mousePos);

			var lastSp = prefab.points[prefab.points.length - 1];
			var lastPt = lastSp.getPoint();
			var lastPtSreenPos = lastPt.toVector();
			lastPtSreenPos.project(ctx.local3d.getScene().camera.m);
			lastPtSreenPos.z = 0;
			lastPtSreenPos.scale3(0.5);
			lastPtSreenPos = lastPtSreenPos.add(new h3d.Vector(0.5,0.5));
			var distTolastPoint = lastPtSreenPos.distance(mousePos);

			if( distTolastPoint < distToFirstPoint ) {
				result.pos = lastPt;
				result.tangent = lastSp.getAbsPos().right().toPoint();
				result.prev = prefab.points[prefab.points.length - 1];
				result.next = null;
			}
			else {
				result.pos = firstPt;
				result.tangent = firstSp.getAbsPos().right().toPoint();
				result.prev = null;
				result.next = prefab.points[0];
			}
		}

		return result;
	}

	function addSplinePoint( spd : SplinePointData, ctx : hrt.prefab.Context ) : SplinePoint {

		var invMatrix = new h3d.Matrix();
		invMatrix.identity();
		var o : hrt.prefab.Object3D = prefab;
		while(o != null) {
			invMatrix.multiply(invMatrix, o.getTransform());
			o = o.parent.to(hrt.prefab.Object3D);
		}
		invMatrix.initInverse(invMatrix);

		var pos = spd.pos.toVector();
		pos.project(invMatrix);

		var index = 0;
		var scale = 1.0;
		if( spd.prev == null && spd.next == null ) {
			scale = 1.0;
			index = 0;
		}
		else if( spd.prev == null ) {
			index = 0;
			scale = prefab.points[0].getAbsPos().getScale().x;
		}
		else if( spd.next == null ) {
			index = prefab.points.length;
			scale = prefab.points[prefab.points.length - 1].getAbsPos().getScale().x;
		}
		else {
			index = prefab.points.indexOf(spd.next);
			scale = (spd.prev.scaleX + spd.next.scaleX) * 0.5;
		}

		var sp = new SplinePoint(prefab);
		sp.x = pos.x;
		sp.y = pos.y;
		sp.z = pos.z;
		prefab.points.insert(index, sp);
		if( spd.tangent != null ) {
			var dir = spd.tangent.toVector();
			dir.transform3x3(invMatrix); // Don't take the translation
			dir.scale3(-1);
			sp.rotationX = h3d.Matrix.lookAtX(dir).getFloats()[0];
			sp.rotationY = h3d.Matrix.lookAtX(dir).getFloats()[1];
			sp.rotationZ = h3d.Matrix.lookAtX(dir).getFloats()[2];
			
		}
		sp.scaleX = scale;
		sp.scaleY = scale;
		sp.scaleZ = scale;
		editContext.scene.editor.addElements([sp], false, false);
		@:privateAccess editContext.scene.editor.refresh(Partial);

		prefab.updateInstance(ctx);
		showViewers(ctx);
		return sp;
	}

	function removeViewers() {
		for( v in splinePointViewers )
			v.remove();
		splinePointViewers = [];
	}

	function showViewers( ctx : hrt.prefab.Context) {
		removeViewers(); // Security, avoid duplication
		for( sp in prefab.points ) {
			var spv = new SplinePointViewer(sp, prefab, ctx);
			splinePointViewers.insert(splinePointViewers.length, spv);
		}
	}

	function removeGizmos() {
		for( g in gizmos ) {
			g.remove();
			@:privateAccess editContext.scene.editor.updates.remove(g.update);
		}
		gizmos = [];
	}

	function createGizmos( ctx : hrt.prefab.Context  ) {
		removeGizmos(); // Security, avoid duplication
		var sceneEditor = @:privateAccess editContext.scene.editor;
		for( sp in prefab.points ) {
			var gizmo = new hide.view.l3d.Gizmo(editContext.scene);
			gizmo.getRotationQuat().identity();
			gizmo.visible = true;
			var worldPos = ctx.local3d.localToGlobal(new h3d.col.Point(sp.x, sp.y, sp.z));
			gizmo.setPosition(worldPos.x, worldPos.y, worldPos.z);
			@:privateAccess sceneEditor.updates.push( gizmo.update );
			gizmos.insert(gizmos.length, gizmo);
			gizmo.visible = false; // Not visible by default, only show the closest in the onMove of interactive

			var posQuant = @:privateAccess sceneEditor.view.config.get("sceneeditor.xyzPrecision");
			var scaleQuant = @:privateAccess sceneEditor.view.config.get("sceneeditor.scalePrecision");
			var rotQuant = @:privateAccess sceneEditor.view.config.get("sceneeditor.rotatePrecision");

			inline function quantize(x: Float, step: Float) {
				if(step > 0) {
					x = Math.round(x / step) * step;
					x = untyped parseFloat(x.toFixed(5)); // Snap to closest nicely displayed float :cold_sweat:
				}
				return x;
			}

			gizmo.onStartMove = function(mode) {

				var sceneObj = sceneEditor.getContext(sp).local3d;
				var obj3d = sp.to(hrt.prefab.Object3D);
				var pivotPt = sceneObj.getAbsPos().getPosition();
				var pivot = new h3d.Matrix();
				pivot.initTranslation(pivotPt.x, pivotPt.y, pivotPt.z);
				var invPivot = pivot.clone();
				invPivot.invert();

				var localMat : h3d.Matrix = sceneEditor.worldMat(sceneObj).clone();
				localMat.multiply(localMat, invPivot);

				var prevState = obj3d.saveTransform();
				gizmo.onMove = function(translate: h3d.Vector, rot: h3d.Quat, scale: h3d.Vector) {
					var transf = new h3d.Matrix();
					transf.identity();

					if(rot != null) rot.toMatrix(transf);
					if(translate != null) transf.translate(translate.x, translate.y, translate.z);

					var newMat = localMat.clone();
					newMat.multiply(newMat, transf);
					newMat.multiply(newMat, pivot);

					var parentInvMat = sceneObj.parent.getAbsPos().clone();
					parentInvMat.initInverse(parentInvMat);
					newMat.multiply(newMat, parentInvMat);
					if(scale != null) newMat.prependScale(scale.x, scale.y, scale.z);

					var rot = newMat.getEulerAngles();
					obj3d.x = quantize(newMat.tx, posQuant);
					obj3d.y = quantize(newMat.ty, posQuant);
					obj3d.z = quantize(newMat.tz, posQuant);
					obj3d.rotationX = quantize(hxd.Math.radToDeg(rot.x), rotQuant);
					obj3d.rotationY = quantize(hxd.Math.radToDeg(rot.y), rotQuant);
					obj3d.rotationZ = quantize(hxd.Math.radToDeg(rot.z), rotQuant);
					if(scale != null) {
						inline function scaleSnap(x: Float) {
							if(K.isDown(K.CTRL)) {
								var step = K.isDown(K.SHIFT) ? 0.5 : 1.0;
								x = Math.round(x / step) * step;
							}
							return x;
						}
						var s = newMat.getScale();
						obj3d.scaleX = quantize(scaleSnap(s.x), scaleQuant);
						obj3d.scaleY = quantize(scaleSnap(s.y), scaleQuant);
						obj3d.scaleZ = quantize(scaleSnap(s.z), scaleQuant);
					}
					obj3d.applyTransform(sceneObj);
				}

				gizmo.onFinishMove = function() {
					var newState = obj3d.saveTransform();
					trace("obj3d rotationZ : " + hxd.Math.radToDeg(obj3d.rotationZ));
					undo.change(Custom(function(undo) {
						if( undo ) {
							sceneObj.setTransform(prevState);
							prefab.updateInstance(ctx);
							showViewers(ctx);
							createGizmos(ctx);
						}
						else {
							sceneObj.setTransform(newState);
							prefab.updateInstance(ctx);
							showViewers(ctx);
							createGizmos(ctx);
						}
					}));
				}
			}
		}
	}

	public function setSelected( ctx : hrt.prefab.Context , b : Bool ) {
		reset();

		if( !b ) {
			editMode = false;
			return;
		}

		if( editMode ) {
			createGizmos(ctx);
			var s2d = @:privateAccess ctx.local2d.getScene();
			interactive = new h2d.Interactive(10000, 10000, s2d);
			interactive.propagateEvents = true;
			interactive.onPush =
				function(e) {
					// Add a new point
					if( K.isDown( K.MOUSE_LEFT ) && K.isDown( K.CTRL )  ) {
						e.propagate = false;
						var pt = getNewPointPosition(s2d.mouseX, s2d.mouseY, ctx);
						var sp = addSplinePoint(pt, ctx);
						showViewers(ctx);
						createGizmos(ctx);

						undo.change(Custom(function(undo) {
							if( undo ) {
								prefab.points.remove(sp);
								prefab.updateInstance(ctx);
								showViewers(ctx);
								createGizmos(ctx);
							}
							else {
								addSplinePoint(pt, ctx);
								showViewers(ctx);
								createGizmos(ctx);
							}
						}));

					}
					// Delete a point
					if( K.isDown( K.MOUSE_LEFT ) && K.isDown( K.SHIFT )  ) {
						e.propagate = false;
						var sp = getClosestSplinePointFromMouse(s2d.mouseX, s2d.mouseY, ctx);
						var index = prefab.points.indexOf(sp);
						editContext.scene.editor.deleteElements([sp]);
						prefab.updateInstance(ctx);
						showViewers(ctx);
						createGizmos(ctx);

						undo.change(Custom(function(undo) {
							if( undo ) {
								prefab.points.insert(index, sp);
								prefab.updateInstance(ctx);
								showViewers(ctx);
								createGizmos(ctx);
							}
							else {
								prefab.points.remove(sp);
								prefab.updateInstance(ctx);
								showViewers(ctx);
								createGizmos(ctx);
							}
						}));
					}
				};

			interactive.onMove =
				function(e) {

					if( prefab.points.length == 0 )
						return;

					// Only show the gizmo of the closest splinePoint
					var closetSp = getClosestSplinePointFromMouse(s2d.mouseX, s2d.mouseY, ctx);
					var index = prefab.points.indexOf(closetSp);
					for( g in gizmos ) {
						g.visible = gizmos.indexOf(g) == index && !K.isDown( K.CTRL ) && !K.isDown( K.SHIFT );
					}

					if( K.isDown( K.CTRL ) ) {
						if( newSplinePointViewer == null )
							newSplinePointViewer = new NewSplinePointViewer(ctx.local3d.getScene());
						newSplinePointViewer.visible = true;

						var npt = getNewPointPosition(s2d.mouseX, s2d.mouseY, ctx);
						newSplinePointViewer.update(npt);
					}
					else {
						if( newSplinePointViewer != null )
							newSplinePointViewer.visible = false;
					}

					if( K.isDown( K.SHIFT ) ) {
						var index = prefab.points.indexOf(getClosestSplinePointFromMouse(s2d.mouseX, s2d.mouseY, ctx));
						for( spv in splinePointViewers ) {
							if( index == splinePointViewers.indexOf(spv) )
								spv.setColor(0xFFFF0000);
							else
								spv.setColor(0xFFFFFFFF);
						}
					}

				};
		}
	}

	public function edit( ctx : EditContext ) {

		var props = new hide.Element('
		<div class="spline-editor">
			<div class="group" name="Utility">
				<div align="center">
					<input type="button" value="Reverse" class="reverse"/>
				</div>
			</div>
			<div class="group" name="Description">
				<div class="description">
					<i>Ctrl + Left Click</i> Add a point on the spline <br>
					<i>Shift + Left Click</i> Delete a point from the spline
				</div>
			</div>
			<div class="group" name="Tool">
				<div align="center">
					<input type="button" value="Edit Mode : Disabled" class="editModeButton" />
				</div>
			</div>
		</div>');

		var reverseButton = props.find(".reverse");
		reverseButton.click(function(_) {
			prefab.points.reverse();
			for( p in prefab.points )
				p.rotationZ += hxd.Math.degToRad(180);

			undo.change(Custom(function(undo) {
				prefab.points.reverse();
				for( p in prefab.points )
					p.rotationZ += hxd.Math.degToRad(180);
			}));
			ctx.onChange(prefab, null);
			removeGizmos();
			createGizmos(getContext());
		});

		var editModeButton = props.find(".editModeButton");
		editModeButton.toggleClass("editModeEnabled", editMode);
		editModeButton.click(function(_) {
			editMode = !editMode;
			prefab.onEdit(editMode);
			editModeButton.val(editMode ? "Edit Mode : Enabled" : "Edit Mode : Disabled");
			editModeButton.toggleClass("editModeEnabled", editMode);
			setSelected(getContext(), true);
			@:privateAccess editContext.scene.editor.showGizmo = !editMode;
			ctx.onChange(prefab, null);
		});

		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(prefab, pname);
		});

		return props;
	}

}

#end