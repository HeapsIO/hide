package hide.prefab2;
import hxd.Key as K;
import hrt.prefab.Context;

using hrt.prefab2.Object3D; // GetLocal3D

enum ColorState{
	None;
	Overlapped;
	OverlappedForDelete;
	Selected;
}

class Edge{
	public var p1 : h2d.col.Point;
	public var p2 : h2d.col.Point;
	public function new(p1, p2){
		this.p1 = p1;
		this.p2 = p2;
	}
}

class SphereHandle extends h3d.scene.Mesh {
	public function new(prim, mat, parent) {
		super(prim, mat, parent);
	}

	override function sync(ctx:h3d.scene.RenderContext) {
		var cam = ctx.camera;
		var gpos = getAbsPos().getPosition();
		var distToCam = cam.pos.sub(gpos).length();
		var engine = h3d.Engine.getCurrent();
		var ratio = 18 / engine.height;
		// Ignore parent scale
		var tmp = parent.getAbsPos().getScale();
		var scale = ratio * distToCam * Math.tan(cam.fovY * 0.5 * Math.PI / 180.0);
		scaleX = scale / tmp.x;
		scaleY = scale / tmp.y;
		scaleZ = scale / tmp.z;
		calcAbsPos();
		super.sync(ctx);
	}
}

class MovablePoint {

	public var showDebug : Bool;
	public var point : h2d.col.Point;
	var mesh: h3d.scene.Mesh;
	public var colorState = None;
	var localPosText : h2d.ObjectFollower;
	var worldPosText : h2d.ObjectFollower;

	public function new(point : h2d.col.Point, ctx : Context){
		this.point = point;
		mesh = new SphereHandle(h3d.prim.Cube.defaultUnitCube(), null, ctx.local3d);
		mesh.name = "_movablePoint";
		mesh.material.setDefaultProps("ui");
		mesh.material.mainPass.depthTest = Always;
		mesh.scale(0.1);
		mesh.setPosition(point.x, point.y, 0);
		localPosText = createText(ctx);
		worldPosText = createText(ctx);
		worldPosText.offsetZ = (0.3);
		localPosText.offsetZ = (0.6);
		updateText(ctx);
	}

	function createText(ctx : Context){
		var o = new h2d.ObjectFollower(mesh, ctx.shared.root2d.getScene());
		var t = new h2d.Text(hxd.res.DefaultFont.get(), o);
		t.textColor = 0xFFFFFF;
		t.textAlign = Center;
		t.dropShadow = { dx : 1.5, dy : 1.5, color : 0x202020, alpha : 1.0 };
		return o;
	}

	public function dispose(){
		mesh.remove();
		worldPosText.remove();
		localPosText.remove();
	}

	function worldToScreen(wx: Float, wy: Float, wz: Float, ctx : Context) {
		var s2d = ctx.shared.root2d.getScene();
		var camera = @:privateAccess ctx.local3d.getScene().camera;
		camera.update();
		var pt = camera.project(wx, wy, wz, s2d.width, s2d.height);
		return new h2d.col.Point( pt.x, pt.y);
	}

	public function updateText(ctx : Context){
		inline function getText(o) : h2d.Text{
			return Std.downcast(o.getChildAt(0), h2d.Text);
		}
		getText(localPosText).visible = showDebug;
		getText(worldPosText).visible = showDebug;
		var pointWorldPos = new h3d.col.Point(point.x, point.y, 0.);
		ctx.local3d.localToGlobal(pointWorldPos);
		getText(localPosText).text = "Local : " + untyped point.x.toFixed(3) + " / " + untyped point.y.toFixed(3);
		getText(worldPosText).text = "World : " + untyped pointWorldPos.x.toFixed(3) + " / " + untyped pointWorldPos.y.toFixed(3) + " / " + untyped pointWorldPos.z.toFixed(3);
	}

	public function updateColor(){
		switch(colorState){
			case None : mesh.material.color.set(0,0,0);
			case Overlapped : mesh.material.color.set(1,1,0);
			case OverlappedForDelete : mesh.material.color.set(1,0,0);
			case Selected : mesh.material.color.set(0,0,1);
		}
	}

	public function interset(ray : h3d.col.Ray) : Bool{
		return mesh.getCollider().rayIntersection(ray, false) != -1;
	}

	public function setColorState(s : ColorState){
		colorState = s;
	}
}

class PolygonEditor {

	public var editContext : hide.prefab2.EditContext;
	public var showDebug : Bool;
	public var gridSize = 1;
	public var showTriangles : Bool = false;
	public var worldSnap = false;

	var polygonPrefab : hrt.prefab2.l3d.Polygon;
	var undo : hide.ui.UndoHistory;
	var interactive : h2d.Interactive;
	var lineGraphics : h3d.scene.Graphics;
	var triangleGraphics : h3d.scene.Graphics;
	var movablePoints : Array<MovablePoint> = [];
	var selectedPoints : Array<h2d.col.Point> = [];
	var lastPointSelected : h2d.col.Point;
	var lastPos : h3d.col.Point;
	var selectedEdge : Edge;
	var selectedEdgeGraphic : h3d.scene.Graphics;
	//var lastClickStamp = 0.0;
	var editMode = false;

	// Temp container for Undo
	var beforeMoveList : Array<h2d.col.Point> = [];
	var afterMoveList : Array<h2d.col.Point> = [];

	public function new( polygonPrefab , undo : hide.ui.UndoHistory ){
		this.polygonPrefab = polygonPrefab;
		this.undo = undo;
	}

	public function dispose(){
		reset();
	}

	function removeGraphics(g : h3d.scene.Graphics){
		if(g != null){
			g.clear();
			g.remove();
		}
	}

	public function reset(){
		clearMovablePoints();
		clearSelectedPoint();
		if(interactive != null) interactive.remove();
		removeGraphics(lineGraphics);
		removeGraphics(selectedEdgeGraphic);
		removeGraphics(triangleGraphics);
	}

	inline function getContext(){
		// TODO(ces) : restore
		return null;
		//return editContext.getContext(polygonPrefab);
	}

	inline function refreshInteractive() {
		// TODO(ces) : restore
		//editContext.scene.editor.refreshInteractive(polygonPrefab);
	}

	public function update( ?propName : String) {
		if(propName == "showDebug"){
			for(mp in movablePoints){
				mp.showDebug = showDebug;
				mp.updateText(getContext());
			}
		}
		else if(propName == "showTriangles") {
			drawTriangles(showTriangles);
		}
		else if(propName == "editMode") {
			setSelected(true);
		} else {
			refreshInteractive();
		}
	}

	function copyArray(array : Array<h2d.col.Point>){
		var copy : Array<h2d.col.Point> = [];
		for(p in array)
		copy.push(p.clone());
		return copy;
	}

	function addUndo( prev : Array<h2d.col.Point>, next : Array<h2d.col.Point>){
		undo.change(Custom(function(undo) {
			var prevList = prev;
			var newList = next;
			if(undo)
				polygonPrefab.points = prevList;
			else
				polygonPrefab.points = newList;
			refreshPolygon();
		}));
	}

	function refreshPolygon(withProps=false) {
		if(!polygonPrefab.points.isClockwise())
			polygonPrefab.points.reverse();  // Ensure poly is always clockwise

		var polyPrim = polygonPrefab.generateCustomPolygon();
		var mesh : h3d.scene.Mesh = cast getContext().local3d;
		mesh.primitive = polyPrim;
		refreshEditorDisplay(withProps);
	}

	function refreshDebugDisplay(){
		for(mp in movablePoints)
			mp.updateText(getContext());
	}

	function clearSelectedPoint(){
		selectedPoints.splice(0, selectedPoints.length);
		lastPointSelected = null;
	}

	function isAlreadySelected( p : h2d.col.Point ) : Bool {
		if( p == null) return false;
		for( point in selectedPoints )
			if( point == p ) return true;
		return false;
	}

	function addSelectedPoint( p : h2d.col.Point ){
		if( p == null) return;
		for( point in selectedPoints )
			if( point == p ) return;
		selectedPoints.push(p);
	}

	function removePoint( p : h2d.col.Point) {
		polygonPrefab.points.remove(p);
		refreshPolygon();
	}

	function addPointOnEdge( pos: h2d.col.Point, e : Edge) {
		if(e == null){
			polygonPrefab.points.points.push(pos);
			return;
		}
		function findIndex(p) : Int {
			for(i in 0 ... polygonPrefab.points.length)
				if( p == polygonPrefab.points[i])
					return i;
			return -1;
		}
		var i1 = findIndex(e.p1);
		var i2 = findIndex(e.p2);
		if( hxd.Math.abs(i1 - i2) > 1 )
			polygonPrefab.points.points.push(pos);
		else
			polygonPrefab.points.points.insert(Std.int(hxd.Math.max(i1,i2)), pos);
		refreshPolygon();
	}

	function projectToGround( ray: h3d.col.Ray) {
		var minDist = -1.;
		var normal = getContext().local3d.getAbsPos().up();
		var plane = h3d.col.Plane.fromNormalPoint(normal.toPoint(), new h3d.col.Point(getContext().local3d.getAbsPos().tx, getContext().local3d.getAbsPos().ty, getContext().local3d.getAbsPos().tz));
		var pt = ray.intersect(plane);
		if(pt != null) { minDist = pt.sub(ray.getPos()).length();}
		return minDist;
	}

	function screenToWorld( u : Float, v : Float ) {
		var camera = @:privateAccess getContext().local3d.getScene().camera;
		var ray = camera.rayFromScreen(u, v);
		var dist = projectToGround(ray);
		return dist >= 0 ? ray.getPoint(dist) : null;
	}

	function trySelectPoint( ray: h3d.col.Ray ) : MovablePoint {
		for(mp in movablePoints)
			if(mp.interset(ray))
				return mp;
		return null;
	}

	function trySelectEdge( pos : h2d.col.Point ) : Edge {
		inline function crossProduct( a : h2d.col.Point, b : h2d.col.Point ){
			return a.x * b.y - a.y * b.x;
		}
		inline function dist(s1 : h2d.col.Point, s2 : h2d.col.Point, p : h2d.col.Point){
			var l = s2.distance(s1);
			l = l * l;
			if(l == 0) return p.distance(s1);
			var t = hxd.Math.max(0, hxd.Math.min(1, p.sub(s1).dot(s2.sub(s1)) / l));
			var proj = s1.add((s2.sub(s1).multiply(t)));
			return p.distance(proj);
		}
		if(polygonPrefab.points.length < 2) return null;
		var minDist = dist(polygonPrefab.points[0], polygonPrefab.points[polygonPrefab.points.length - 1], pos);
		var edge : Edge = new Edge(polygonPrefab.points[0],polygonPrefab.points[polygonPrefab.points.length - 1]);
		for(i in 1 ... polygonPrefab.points.length){
			var p1 = polygonPrefab.points[i-1];
			var p2 = polygonPrefab.points[i];
			var dist = dist(p1, p2, pos);
			if(dist < minDist){
				edge.p1 = p1;
				edge.p2 = p2;
				minDist = dist;
			}
		}
		return edge;
	}

	function getFinalPos( mouseX, mouseY ){
		var worldPos = screenToWorld(mouseX, mouseY);
		var localPos = getContext().local3d.globalToLocal(worldPos);
		if( K.isDown( K.CTRL ) ){ // Snap To Grid with Ctrl
			var gridPos = new h3d.col.Point();
			if( worldSnap ){
				var absPos = getContext().local3d.getAbsPos();
				worldPos = getContext().local3d.localToGlobal(worldPos);
				gridPos.x = hxd.Math.round(localPos.x / gridSize) * gridSize;
				gridPos.y = hxd.Math.round(localPos.y / gridSize) * gridSize;
				gridPos.z = hxd.Math.round(localPos.z / gridSize) * gridSize;
				gridPos = getContext().local3d.globalToLocal(gridPos);
			}
			else{
				gridPos.x = hxd.Math.round(worldPos.x / gridSize) * gridSize;
				gridPos.y = hxd.Math.round(worldPos.y / gridSize) * gridSize;
				gridPos.z = hxd.Math.round(worldPos.z / gridSize) * gridSize;
			}
			localPos = gridPos;
		}
		return localPos;
	}

	public function setSelected(b : Bool ) {
		if (!polygonPrefab.enabled) return;
		reset();
		if(!editMode) return;
		if(b){
			var s2d = editContext.scene.s2d;
			interactive = new h2d.Interactive(10000, 10000, s2d);
			interactive.propagateEvents = true;
			interactive.cancelEvents = false;
			lineGraphics = new h3d.scene.Graphics(polygonPrefab.getLocal3d());
			lineGraphics.lineStyle(2, 0xFFFFFF);
			lineGraphics.material.mainPass.setPassName("overlay");
			lineGraphics.material.mainPass.depth(false, LessEqual);
			selectedEdgeGraphic = new h3d.scene.Graphics(polygonPrefab.getLocal3d());
			selectedEdgeGraphic.lineStyle(3, 0xFFFF00, 0.5);
			selectedEdgeGraphic.material.mainPass.setPassName("overlay");
			selectedEdgeGraphic.material.mainPass.depth(false, LessEqual);
			triangleGraphics = new h3d.scene.Graphics(polygonPrefab.getLocal3d());
			triangleGraphics.lineStyle(2, 0xFF0000);
			triangleGraphics.material.mainPass.setPassName("overlay");
			triangleGraphics.material.mainPass.depth(false, LessEqual);

			refreshEditorDisplay();
			drawTriangles(showTriangles);

			interactive.onWheel = function(e) {
				refreshDebugDisplay();
			};
			interactive.onKeyDown =
			function(e) {
				e.propagate = false;
				if( K.isDown( K.SHIFT ) ){
					clearSelectedPoint();
					var ray = @:privateAccess polygonPrefab.getLocal3d().getScene().camera.rayFromScreen(s2d.mouseX, s2d.mouseY);
					refreshMovablePoints(ray);
					if(lastPos == null) lastPos = getFinalPos(s2d.mouseX, s2d.mouseY);
					refreshSelectedEdge(new h2d.col.Point(lastPos.x, lastPos.y));
				}
			}
			interactive.onKeyUp =
			function(e) {
				e.propagate = false;
				var ray = @:privateAccess polygonPrefab.getLocal3d().getScene().camera.rayFromScreen(s2d.mouseX, s2d.mouseY);
				refreshMovablePoints(ray);
				if(lastPos == null) lastPos = getFinalPos(s2d.mouseX, s2d.mouseY);
				refreshSelectedEdge(new h2d.col.Point(lastPos.x, lastPos.y));
			}
			interactive.onPush =
			function(e) {
				var finalPos = getFinalPos(s2d.mouseX, s2d.mouseY);
				var ray = @:privateAccess polygonPrefab.getLocal3d().getScene().camera.rayFromScreen(s2d.mouseX, s2d.mouseY);
				if( K.isDown( K.MOUSE_LEFT ) ){
					e.propagate = false;
					// Shift + Left Click : Remove Point
					if( K.isDown( K.SHIFT ) ){
						var mp = trySelectPoint(ray);
						if(mp != null){
							var prevList = copyArray(polygonPrefab.points.points);
							removePoint(mp.point);
							var newList = copyArray(polygonPrefab.points.points);
							addUndo(prevList, newList);
						}
					}
					else {
						// Left Click : Add/Set selected point / Clear selection
						lastPos = finalPos.clone();
						var mp = trySelectPoint(ray);
						if(mp != null){
							if( K.isDown(K.ALT) && !isAlreadySelected(mp.point))
									addSelectedPoint(mp.point);
							lastPointSelected = mp.point;
							beforeMoveList = copyArray(polygonPrefab.points.points);
						}
						// Double Left Click : Create point
						else{
							clearSelectedPoint();
							if(K.isDown(K.CTRL)) {
							// var curStamp = haxe.Timer.stamp();
							// var diff = curStamp - lastClickStamp;
							// if(diff < 0.2){
								var prevList = copyArray(polygonPrefab.points.points);
								var pt = new h2d.col.Point(finalPos.x, finalPos.y);
								addPointOnEdge(pt, selectedEdge);
								var newList = copyArray(polygonPrefab.points.points);
								addUndo(prevList, newList);
								refreshSelectedEdge(new h2d.col.Point(finalPos.x, finalPos.y));
								// Select new point
								lastPointSelected = pt;
							}
							//lastClickStamp = curStamp;
						}
						refreshMovablePoints();
					}
				}
			};
			interactive.onRelease =
			function(e) {
				//lastPos = null;
				lastPointSelected = null;
				if( beforeMoveList != null ){
					afterMoveList = copyArray(polygonPrefab.points.points);
					addUndo(beforeMoveList, afterMoveList);
					beforeMoveList = null;
					afterMoveList = null;
				}
			};
			interactive.onMove =
			function(e) {
				var ray = @:privateAccess polygonPrefab.getLocal3d().getScene().camera.rayFromScreen(s2d.mouseX, s2d.mouseY);
				var finalPos = getFinalPos(s2d.mouseX, s2d.mouseY);
				refreshMovablePoints(ray);
				refreshSelectedEdge(new h2d.col.Point(finalPos.x, finalPos.y));
				if( K.isDown( K.MOUSE_LEFT )){
					var move : h2d.col.Point = null;
					var pos = new h2d.col.Point(finalPos.x, finalPos.y);
					if(lastPointSelected != null){
						move = pos.sub(lastPointSelected);
						lastPointSelected.load(pos);
						for(p in selectedPoints){
							if(lastPointSelected == p) continue;
							p.x += move.x; p.y += move.y;
						}
					}
					refreshMovablePoints();
					refreshSelectedEdge(new h2d.col.Point(finalPos.x, finalPos.y));
					refreshPolygon(false);
					lastPos = finalPos.clone();
				}
				else
					refreshDebugDisplay();
			};
		}
		else
			editMode = false;
	}

	function refreshSelectedEdge( pos : h2d.col.Point ){
		selectedEdge = trySelectEdge(pos);
		selectedEdgeGraphic.clear();
		if(K.isDown( K.SHIFT ) )
			return;
		if(selectedEdge != null){
			selectedEdgeGraphic.moveTo(selectedEdge.p1.x, selectedEdge.p1.y, 0);
			selectedEdgeGraphic.lineTo(selectedEdge.p2.x, selectedEdge.p2.y, 0);
		}
	}

	function drawTriangles( b : Bool ){
		if (triangleGraphics == null)
			return;
		triangleGraphics.clear();
		var prim = polygonPrefab.getPrimitive();
		if(b && prim != null){
			var i = 0;
			while(i < prim.idx.length){
				triangleGraphics.moveTo(prim.points[prim.idx[i]].x, prim.points[prim.idx[i]].y, 0);
				triangleGraphics.lineTo(prim.points[prim.idx[i + 1]].x, prim.points[prim.idx[i + 1]].y, 0);
				triangleGraphics.lineTo(prim.points[prim.idx[i + 2]].x, prim.points[prim.idx[i + 2]].y, 0);
				triangleGraphics.lineTo(prim.points[prim.idx[i]].x, prim.points[prim.idx[i]].y, 0);
				i += 3;
			}
		}
	}

	function clearMovablePoints(){
		for(mp in movablePoints)
			mp.dispose();
		movablePoints.splice(0, movablePoints.length);
	}

	function createMovablePoints(){
		for(p in polygonPrefab.points){
			var mp = new MovablePoint(p, getContext());
			movablePoints.push(mp);
		}
	}

	function refreshMovablePoints( ?ray ){
		for(mp in movablePoints)
			mp.setColorState(None);
		if(ray != null){
			var mp = trySelectPoint(ray);
			if( mp != null && mp.colorState != Selected)
				K.isDown( K.SHIFT ) ? mp.setColorState(OverlappedForDelete) : mp.setColorState(Overlapped);
		}
		for(p in selectedPoints)
			for(mp in movablePoints)
				if(mp.point == p){
					mp.setColorState(Selected);
					break;
				}
		for(mp in movablePoints){
			if( mp.point == lastPointSelected) mp.setColorState(Selected);
			mp.updateColor();
			mp.showDebug = showDebug;
			mp.updateText(getContext());
		}
	}

	function refreshEditorDisplay(withProps=true) {
		lineGraphics.clear();
		clearMovablePoints();
		if(polygonPrefab.points == null || polygonPrefab.points.length == 0) return;
		lineGraphics.moveTo(polygonPrefab.points[polygonPrefab.points.length - 1].x, polygonPrefab.points[polygonPrefab.points.length - 1].y, 0);
		for(p in polygonPrefab.points)
			lineGraphics.lineTo(p.x, p.y, 0);
		createMovablePoints();
		refreshMovablePoints();
		if(withProps)
			refreshPointList(editContext.getCurrentProps(polygonPrefab));
	}

	public function addProps( ctx : hide.prefab2.EditContext ){
		var props = new hide.Element('
		<div class="poly-editor">
			<div class="group" name="Tool">
				<div align="center">
					<input type="button" value="Edit Mode : Disabled" class="editModeButton" />
				</div>
				<div class="description">
					<i>Ctrl + Left Click</i> : Add point on edge <br>
					<i>Shift + Left Click</i> : Delete selected point <br>
					Drag with <i>Left Click</i> : Move selected points <br>
					Drag with <i>Left Click + Ctrl</i> : Move selected points on grid <br>
					<i>Alt + Left Click</i> : Add point to selection
				</div>
				<dt>Show Debug</dt><dd><input type="checkbox" field="showDebug"/></dd>
				<dt>Show Triangles</dt><dd><input type="checkbox" field="showTriangles"/></dd>
				<dt>Grid Size</dt><dd><input type="range" min="0" max="10" field="gridSize"/></dd>
				<dt>World Snap</dt><dd><input type="checkbox" field="worldSnap"/></dd>
			</div>
			<div align="center">
				<div class="group" name="Points">
					<div class="point-list"> </div>
					<input type="button" value="Reset" class="reset" />
				</div>
			</div>
		</div>');

		var editModeButton = props.find(".editModeButton");
		editModeButton.click(function(_) {
			if (!polygonPrefab.enabled) return;
			editMode = !editMode;
			editModeButton.val(editMode ? "Edit Mode : Enabled" : "Edit Mode : Disabled");
			editModeButton.toggleClass("editModeEnabled", editMode);
			setSelected(true);
			if(!editMode)
				refreshInteractive();
		});

		props.find(".reset").click(function(_) {
			if (!polygonPrefab.enabled) return;
			var prevList = copyArray(polygonPrefab.points.points);
			polygonPrefab.points.points.splice(0, polygonPrefab.points.points.length);
			var nextList = copyArray(polygonPrefab.points.points);
			addUndo(prevList, nextList);
			refreshPolygon();
		});

		refreshPointList(props);

		ctx.properties.add(props, this, function(pname) {ctx.onChange(polygonPrefab, pname); });
		return props;
	}

	function refreshPointList( props : hide.Element){
		var container = props.find(".point-list");
		container.empty();

		function createVector(p : h2d.col.Point){
			var v = new Element('<div class="poly-vector2" >');
			var deleteButton = new Element('<input type="button" value="-" class="deletePoint" />');
			var fieldX = new Element('<input type="text" name="xfield">');
			var fieldY = new Element('<input type="text" name="yfield">');

			fieldX.val(p.x);
			fieldY.val(p.y);

			fieldX.on("input", function(_) {
				if (!polygonPrefab.enabled) return;
				var prevValue = p.x;
				p.x = Std.parseFloat(fieldX.val());
				var nextValue = p.x;
				undo.change(Custom(function(undo) {
					p.x = undo ? prevValue : nextValue;
					refreshPolygon();
				}));
				refreshPolygon();
			});

			fieldY.on("input", function(_) {
				if (!polygonPrefab.enabled) return;
				var prevValue = p.y;
				p.y = Std.parseFloat(fieldY.val());
				var nextValue = p.y;
				undo.change(Custom(function(undo) {
					p.y = undo ? prevValue : nextValue;
					refreshPolygon();
				}));
				refreshPolygon();
			});

			deleteButton.on("click", function(_) {
				if (!polygonPrefab.enabled) return;
				var prevList = copyArray(polygonPrefab.points.points);
				polygonPrefab.points.points.remove(p);
				var nextList = copyArray(polygonPrefab.points.points);
				addUndo(prevList, nextList);
				refreshPolygon();
				refreshPointList(props);
			});

			v.append('<label>X </label>');
			v.append(fieldX);
			v.append('<label> Y </label>');
			v.append(fieldY);
			v.append(deleteButton);
			v.append('</div>');
			container.append(v);
		}

		if(polygonPrefab.points != null) {
			for(p in polygonPrefab.points){
				createVector(p);
			}
		}
	}
}
