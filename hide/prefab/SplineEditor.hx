package hide.prefab;
import hxd.Key as K;
import hrt.prefab.l3d.Spline;

#if editor

class SplinePointViewer extends h3d.scene.Object {

	var pointViewer : h3d.scene.Mesh;
	var controlPointsViewer : h3d.scene.Graphics;

	public function new( sp : SplinePoint ) {
		super(sp);
		name = "SplinePointViewer";
		pointViewer = new h3d.scene.Mesh(h3d.prim.Sphere.defaultUnitSphere(), null, this);
		pointViewer.name = "sphereHandle";
		pointViewer.material.setDefaultProps("ui");

		controlPointsViewer = new h3d.scene.Graphics(this);
		controlPointsViewer.lineStyle(4, 0xffffff);
		controlPointsViewer.material.mainPass.setPassName("overlay");
		controlPointsViewer.material.mainPass.depth(false, LessEqual);
		controlPointsViewer.ignoreParentTransform = false;
		controlPointsViewer.clear();
		controlPointsViewer.moveTo(1, 0, 0);
		controlPointsViewer.lineTo(-1, 0, 0);
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

	public function interset( ray : h3d.col.Ray ) : Bool {
		return pointViewer.getCollider().rayIntersection(ray, false) != -1;
	}
}

class SplineEditor {

	public var prefab : Spline;
	public var editContext : EditContext;
	var editMode = false;
	var undo : hide.ui.UndoHistory;

	var interactive : h2d.Interactive;

	 // Easy way to keep track of viewers
	var splinePointViewers : Array<SplinePointViewer> = [];
	var gizmos : Array<hide.view.l3d.Gizmo> = [];

	public function new( prefab : Spline, undo : hide.ui.UndoHistory ){
		this.prefab = prefab;
		this.undo = undo;
	}

	public function update( ctx : hrt.prefab.Context , ?propName : String ) {
		if( editMode )
			showViewers(ctx);
		else 
			removeViewers();

	}

	function reset() {
		removeViewers();
		removeGizmos();
		if( interactive != null )
			interactive.remove();
	}

	function trySelectPoint( ray: h3d.col.Ray ) : SplinePointViewer {
		for( spv in splinePointViewers )
			if( spv.interset(ray) )
				return spv;
		return null;
	}

	inline function getContext() {
		return editContext.getContext(prefab);
	}

	function removeViewers() {
		for( v in splinePointViewers )
			v.remove();
		splinePointViewers = [];
	}

	function showViewers( ctx : hrt.prefab.Context ) {
		removeViewers(); // Security, avoid duplication
		for( sp in prefab.points ) {
			var spv = new SplinePointViewer(sp);
			splinePointViewers.push(spv);
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
			var worldPos = ctx.local3d.localToGlobal(new h3d.Vector(sp.x, sp.y, sp.z));
			gizmo.setPosition(worldPos.x, worldPos.y, worldPos.z);
			@:privateAccess sceneEditor.updates.push( gizmo.update );
			gizmos.push(gizmo);

			gizmo.onStartMove = function(mode) {
				/**/
				var sceneObj = sp;
				var pivotPt = sceneObj.getAbsPos().getPosition();
				var pivot = new h3d.Matrix();
				pivot.initTranslation(pivotPt.x, pivotPt.y, pivotPt.z);
				var invPivot = pivot.clone();
				invPivot.invert();
				var worldMat : h3d.Matrix = sceneEditor.worldMat(sceneObj);
				var localMat : h3d.Matrix = worldMat.clone();
				localMat.multiply(localMat, invPivot);

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

				var rot = sceneObj.getRotationQuat().toEuler();
				var prevState = { 	x : sceneObj.x, y : sceneObj.y, z : sceneObj.z, 
									scaleX : sceneObj.scaleX, scaleY : sceneObj.scaleY, scaleZ : sceneObj.scaleZ, 
									rotationX : rot.x, rotationY : rot.y, rotationZ : rot.z };

				gizmo.onMove = function(translate: h3d.Vector, rot: h3d.Quat, scale: h3d.Vector) {
					var transf = new h3d.Matrix();
					transf.identity();

					if(rot != null)
						rot.toMatrix(transf);

					if(translate != null)
						transf.translate(translate.x, translate.y, translate.z);

					var newMat = localMat.clone();
					newMat.multiply(newMat, transf);
					newMat.multiply(newMat, pivot);
					var invParent = sceneObj.parent.getAbsPos().clone();
					invParent.invert();
					newMat.multiply(newMat, invParent);
					if(scale != null) {
						newMat.prependScale(scale.x, scale.y, scale.z);
					}

					var rot = newMat.getEulerAngles();
					sceneObj.x = quantize(newMat.tx, posQuant);
					sceneObj.y = quantize(newMat.ty, posQuant);
					sceneObj.z = quantize(newMat.tz, posQuant);
					sceneObj.setRotation(hxd.Math.degToRad(quantize(hxd.Math.radToDeg(rot.x), rotQuant)), hxd.Math.degToRad(quantize(hxd.Math.radToDeg(rot.y), rotQuant)), hxd.Math.degToRad(quantize(hxd.Math.radToDeg(rot.z), rotQuant)));
					if(scale != null) {
						inline function scaleSnap(x: Float) {
							if(K.isDown(K.CTRL)) {
								var step = K.isDown(K.SHIFT) ? 0.5 : 1.0;
								x = Math.round(x / step) * step;
							}
							return x;
						}
						var s = newMat.getScale();
						sceneObj.scaleX = quantize(scaleSnap(s.x), scaleQuant);
						sceneObj.scaleY = quantize(scaleSnap(s.y), scaleQuant);
						sceneObj.scaleZ = quantize(scaleSnap(s.z), scaleQuant);
					}	

					prefab.updateInstance(ctx);	
				}

				gizmo.onFinishMove = function() {
					//var newState = [for(o in objects3d) o.saveTransform()];
					/*undo.change(Custom(function(undo) {
						if( undo ) {
							for(i in 0...objects3d.length) {
								objects3d[i].loadTransform(prevState[i]);
								objects3d[i].applyPos(sceneObjs[i]);
							}
						}
						else {
							for(i in 0...objects3d.length) {
								objects3d[i].loadTransform(newState[i]);
								objects3d[i].applyPos(sceneObjs[i]);
							}
						}
					}));*/
				}/**/
			}
		}
	}

	public function setSelected( ctx : hrt.prefab.Context , b : Bool ) {
		reset();

		if( !editMode )
			return;

		if( b ) {
			@:privateAccess editContext.scene.editor.gizmo.visible = false;
			@:privateAccess editContext.scene.editor.curEdit = null;
			createGizmos(ctx);
			/*var s2d = @:privateAccess ctx.local2d.getScene();
			interactive = new h2d.Interactive(10000, 10000, s2d);
			interactive.propagateEvents = true;
			interactive.cancelEvents = false;

			interactive.onKeyDown =
				function(e) {
					e.propagate = false;
				};

			interactive.onKeyUp =
				function(e) {
					e.propagate = false;
				};

			interactive.onPush =
				function(e) {
					if( K.isDown( K.MOUSE_LEFT ) ) {
						e.propagate = false;
						var ray = @:privateAccess ctx.local3d.getScene().camera.rayFromScreen(s2d.mouseX, s2d.mouseY);
						var p = trySelectPoint(ray);
					}
				};

			interactive.onRelease =
				function(e) {

				};

			interactive.onMove =
				function(e) {

				};*/
		}
		else {
			editMode = false;
		}
	}

	public function edit( ctx : EditContext ) {

		var props = new hide.Element('
		<div class="spline-editor">
			<div class="group" name="Description">
				<div class="description">
					<i>Ctrl + Left Click</i> Destroy the world
				</div>
			</div>
			<div class="group" name="Tool">
				<div align="center">
					<input type="button" value="Edit Mode : Disabled" class="editModeButton" />
				</div>
			</div>
		</div>');

		var editModeButton = props.find(".editModeButton");
		editModeButton.click(function(_) {
			editMode = !editMode;
			editModeButton.val(editMode ? "Edit Mode : Enabled" : "Edit Mode : Disabled");
			editModeButton.toggleClass("editModeEnabled", editMode);
			setSelected(getContext(), true);
			ctx.onChange(prefab, null);
		});

		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(prefab, pname);
		});

		return props;
	}

}

#end