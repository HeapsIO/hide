package hrt.prefab.l3d;

#if (hl_ver >= version("1.13.0")) @:struct #end
class TrailPoint {
	public var x : Float = 0;
	public var y : Float = 0;
	public var z : Float = 0;
	public var w : Float = 0;
	public var tx : Float = 0;
	public var ty : Float = 0;
	public var tz : Float = 0;
	public var speed : Float = 0;
	public var len : Float = 0;
	public var lifetime : Float = 0;
	public var next : TrailPoint = null;

	public function new(){};
}

#if (hl_ver >= version("1.13.0")) @:struct #end
class TrailHead {
	public var firstPoint : TrailPoint = null;
	public var totalLength : Float = 0;
	public var numPoints : Int = 0;
	public var generation : Int = 0;
	public var nextTrail : TrailHead = null;

	public function new(){};
}

enum TrailOrientation {
	Camera;
	Up(x : Float, y : Float, z : Float);
	Right(x : Float, y : Float, z : Float);
}

enum UVMode {
	@display("Stretch", "Stretch the UV between the head (u=0) and the tail (u=1) of the trails")
	EStretch;
	@display("Tile Fixed", "Tile the texture through the trail, but the texture stay fixed in world space")
	ETileFixed;
	@display("Tile Follow", "Tile the texture throught the tail, and the texture follow the head of the tail (u=0 at the head)")
	ETileFollow;
	@display("Life", "The value of the U is equal to the life of the trail point")
	ELifetime;
}

enum UVRepeat {
	@display("Mod", "U value goes from 0 to 1, then back to 0 again. For textures that tile horizontally")
	EMod;
	@display("Mirror", "U value goes from 0 to 1 then from 1 to 0, repeating. For textures that don't tile horizontally")
	EMirror;
	@display("Clamp", "U value goes from 0 to 1, then stay at 1")
	EClamp;
	@display("None", "No repeat for the UV values")
	ENone;
}


typedef PointsArray = #if (hl_ver >= version("1.14.0")) hl.CArray<TrailPoint> #else Array<TrailPoint> #end;
typedef TrailsArray = #if (hl_ver >= version("1.14.0")) hl.CArray<TrailHead> #else Array<TrailHead> #end;

class TrailObj extends h3d.scene.Mesh {

	var points : PointsArray;
	var trails : TrailsArray;

	var trailsPool : TrailHead = null;
	var firstFreePointID = 0;

	var nextTrailID = 0;

	var dprim : h3d.prim.RawPrimitive;
	var vbuf : hxd.FloatBuffer;
	var ibuf : hxd.IndexBuffer;
	var numVertsIndices : Int = 0;
	var bounds : h3d.col.Bounds;
	var prefab : Trails;

	var xOffset : Float = 0;
	var yOffset : Float = 0;
	var zOffset : Float = 0;

	public var timeScale : Float = 1.0;

	#if editor
	var icon : hrt.impl.EditorTools.EditorIcon;
	#end

	var cooldown : Float;

	// Sets whenever we check the position of this object to automaticaly add points to the 0th trail.
	// If set to false, trail can be created by manually calling addPoint()
	public var autoTrackPosition : Bool = true;

	var currentAllocatedVertexCount = 0;
	var currentAllocatedIndexCount = 0;

	public var numTrails(default, set) : Int = -1;
	var subTrailChildIndices : Array<Int> = [];

	static var tmpHead = new TrailPoint();
	static var tmpNormal = new h3d.Vector();
	static var tmpBinormal = new h3d.Vector();

	public function set_numTrails(new_value : Int) : Int {
		if (numTrails != new_value) {
			numTrails = new_value;
			allocBuffers();
			if (dprim != null)
				dprim.alloc(null);
		}
		return numTrails;
	}

	// How many frame we wait before adding a new point
	static final maxFramerate : Float = 30.0;

	var shader : hrt.shader.BaseTrails;

	public function calcMaxTrailPoints() : Int {
		return std.Math.ceil( prefab.lifetime * maxFramerate ) + 2; // Segment count + head and tail
	}

	function calcMaxVertexes() : Int {
		var pointsPerTrail = calcMaxTrailPoints();
		var vertsPerTrail = pointsPerTrail << 1;
		var num = vertsPerTrail * numTrails;
		if (num > 65534)
			num = 65534;
		return num;
	}

	function calcMaxIndexes() : Int {
		var pointsPerTrail = calcMaxTrailPoints();
		var indicesPerTrail = (pointsPerTrail - 1) * 6;
		return indicesPerTrail * numTrails;
	}

	function allocBuffers() {
		var alloc = hxd.impl.Allocator.get();
		if (vbuf != null)
			alloc.disposeFloats(vbuf);
		currentAllocatedVertexCount = calcMaxVertexes();
		vbuf = new hxd.FloatBuffer(currentAllocatedVertexCount * 8);
		if (ibuf != null)
			alloc.disposeIndexes(ibuf);
		currentAllocatedIndexCount = calcMaxIndexes();
		ibuf = new hxd.IndexBuffer(currentAllocatedIndexCount);

		pool = null;
		firstFreePointID = 0;

		maxNumPoints = calcMaxTrailPoints() * numTrails;
		if (maxNumPoints <= 0)
			maxNumPoints = 1;

		points = #if (hl_ver >= version("1.14.0")) hl.CArray.alloc(TrailPoint, maxNumPoints) #else [for(i in 0...maxNumPoints) new TrailPoint()] #end;
		trails = #if (hl_ver >= version("1.14.0")) hl.CArray.alloc(TrailHead, numTrails) #else [for(i in 0...numTrails) new TrailHead()] #end;

		for (i in 0...numTrails-1)
			trails[i].nextTrail = trails[i+1];
		trailsPool = trails[0];

		reset();
	}

	var maxNumPoints : Int = 0;

	var pool : TrailPoint = null;

	public var materialData = {};

	function allocPoint() : TrailPoint {
		var r = null;
		if (pool != null) {
			r = pool;
			pool = r.next;
		} else {
			if (firstFreePointID >= maxNumPoints)
				return null;
			r = points[firstFreePointID++];
		}

		r.next = null;
		r.len = 0.0;
		return r;
	}

	public function allocTrail() : TrailHead {
		if (trailsPool == null)
			throw "assert";
		var r = trailsPool;
		trailsPool = trailsPool.nextTrail;
		return r;
	}

	function disposeTrail(t : TrailHead) {
		t.firstPoint = null;
		t.totalLength = 0;
		t.numPoints = 0;
		t.generation++;
		t.nextTrail = trailsPool;
		trailsPool = t;
	}

	function disposePoint(p : TrailPoint) {
		p.next = pool;
		pool = p;
	}

	override function onRemove() {
		super.onRemove();
		var p = parent;
		var fxAnim : Array<hrt.prefab.fx.FX.FXAnimation> = [];
		while ( p != null ) {
			var fx = Std.downcast(p, hrt.prefab.fx.FX.FXAnimation);
			if ( fx != null )
				fxAnim.push(fx);
			p = p.parent;
		}
		for ( fx in fxAnim )
			fx.trails.remove(this);
		dprim.dispose();
	}

	override function onAdd() {
		super.onAdd();
		dprim.alloc(null);
	}

	public function reset() {
		for (i in 0...numTrails) {
			var t = trails[i];
			var p = t.firstPoint;
			while (p != null) {
				var n = p.next;
				disposePoint(p);
				p = n;
			}
			disposeTrail(t);
		}
	}

	public function updateShader() {
		shader.uvRepeat = prefab.uvRepeat.getIndex();
	}

	var ux : Float = 0.0;
	var uy : Float = 0.0;
	var uz : Float = 0.0;

	function computeOrientation() {
		switch (prefab.orientation) {
			case Camera: {
				var cam = getScene().camera.pos;
				var target = getScene().camera.target;

				var vcamx = cam.x - target.x;
				var vcamy = cam.y - target.y;
				var vcamz = cam.z - target.z;

				var len = hxd.Math.distance(vcamx, vcamy, vcamz);

				if (len == 0) {
					vcamx = 0;
					vcamy = 0;
					vcamz = 1.0;
					len = 1.0;
				}

				len = 1.0 / len;

				ux = vcamx * len;
				uy = vcamy * len;
				uz = vcamz * len;
			}
			case Up(x, y, z), Right(x, y ,z): {
				ux = x;
				uy = y;
				uz = z;
			}
		}
	}

	public function addPoint( head : TrailHead, x : Float, y : Float, z : Float ) {
		var prev = head.firstPoint;

		var len = 0.0;
		if (prev != null) {
			var lenSq = (x - prev.x) * (x - prev.x) +
			(y - prev.y) * (y - prev.y) +
			(z - prev.z) * (z - prev.z);
			len = Math.sqrt(lenSq);
			if ( len < 0.0001 ) {
				prev.lifetime = prefab.lifetime;
				return;
			}
		}

		var point = allocPoint();
		point.x = x;
		point.y = y;
		point.z = z;

		var tangent = inline new h3d.Vector();
		if ( prev != null ) {
			tangent.x = x - prev.x;
			tangent.y = y - prev.y;
			tangent.z = z - prev.z;
		}
		tangent.normalize();
		point.tx = tangent.x;
		point.ty = tangent.y;
		point.tz = tangent.z;

		point.lifetime = prefab.lifetime;
		point.w = prefab.startWidth;
		point.len = len;
		point.speed = prev != null ? len / ( point.lifetime - prev.lifetime ) : 0;
		point.next = prev;

		head.firstPoint = point;
		head.totalLength += point.len;
		head.numPoints++;
	}

	public function getMaterialProps() {
		var name = h3d.mat.MaterialSetup.current.name;
		var p = Reflect.field(materialData, name);
		if( p == null ) {
			p = h3d.mat.MaterialSetup.current.getDefaults("trail3D");
			Reflect.setField(materialData, name, p);
		}
		return p;
	}

	function onDprimContextLost() {
		return {
			vbuf : vbuf,
			ibuf : ibuf,
			format : hxd.BufferFormat.POS3D_NORMAL_UV,
			bounds : bounds,
		};
	}

	public function new(parentPrefab: Trails, ?parent : h3d.scene.Object, ?numTrails : Int) {
		bounds = new h3d.col.Bounds();
		prefab = parentPrefab;
		bounds.addPos(0,0,0);

		var nTrails = numTrails != null ? numTrails : 1;
		if ( nTrails == 1 && parentPrefab.children.length > 1 )
			nTrails = parentPrefab.children.length;

		this.numTrails = nTrails;

		dprim = new h3d.prim.RawPrimitive(onDprimContextLost(), true);
		dprim.onContextLost = onDprimContextLost;

		super(dprim,parent);

		#if editor
		icon = hrt.impl.EditorTools.create3DIcon(this, hide.Ide.inst.getHideResPath("icons/icon-trails.png"), 0.75, Trails);
		#end

		material.props = getMaterialProps();
		material.mainPass.dynamicParameters = true;

		shader = new hrt.shader.BaseTrails();
		material.mainPass.addShader(shader);

		shader.setPriority(-999);

		updateShader();

		cooldown = 0.0;
	}

	var lastUpdateDuration = 0.0;

	override function sync(ctx) {
		var t = haxe.Timer.stamp();
		super.sync(ctx);

		if (timeScale > 0.0)
			update(ctx.elapsedTime * timeScale);

		lastUpdateDuration = haxe.Timer.stamp() - t;
	}

	public function updateTrail( t : TrailHead, dt : Float, x : Float, y : Float, z : Float) {
		var cur = t.firstPoint;
		if ( cur == null )
			return;

		var lastPointAlive : TrailPoint = null;
		var totalLength = 0.0;
		while ( cur != null ) {
			cur.lifetime -= dt;
			var t = 1.0 - cur.lifetime / prefab.lifetime;
			cur.w = hxd.Math.lerp(prefab.startWidth, prefab.endWidth, t);
			if ( cur.lifetime > 0.0 ) {
				totalLength += cur.len;
				lastPointAlive = cur;
			}
			cur = cur.next;
		}

		t.totalLength = totalLength;

		if ( lastPointAlive == null ) {
			if ( t.firstPoint != null ) {
				var dyingPoint = t.firstPoint;
				while (dyingPoint != null) {
					var n = dyingPoint.next;
					disposePoint(dyingPoint);
					t.numPoints--;
					dyingPoint = n;
				}
				t.firstPoint = null;
			}
			return;
		}

		if ( lastPointAlive.next == null )
			return;

		var dyingPoint = lastPointAlive.next;
		var alivePointLifetime = lastPointAlive.lifetime;
		var alpha = -dyingPoint.lifetime / ( alivePointLifetime - dyingPoint.lifetime );

		if ( -dyingPoint.lifetime > alivePointLifetime ) {
			while (dyingPoint != null) {
				var n = dyingPoint.next;
				disposePoint(dyingPoint);
				t.numPoints--;
				dyingPoint = n;
			}
			lastPointAlive.next = null;
			return;
		}

		var lastX = lastPointAlive.x;
		var lastY = lastPointAlive.y;
		var lastZ = lastPointAlive.z;

		var xDelta = ( lastX - dyingPoint.x );
		var yDelta = ( lastY - dyingPoint.y );
		var zDelta = ( lastZ - dyingPoint.z );

		dyingPoint.x = xDelta * alpha + dyingPoint.x;
		dyingPoint.y = yDelta * alpha + dyingPoint.y;
		dyingPoint.z = zDelta * alpha + dyingPoint.z;
		dyingPoint.len = 0;

		var len = Math.sqrt(xDelta * xDelta + yDelta * yDelta + zDelta * zDelta);
		t.totalLength -= lastPointAlive.len - len;
		lastPointAlive.len = len;

		var tangent = new h3d.Vector( lastX - dyingPoint.x, lastY - dyingPoint.y, lastZ - dyingPoint.z );
		tangent.normalize();
		dyingPoint.tx = tangent.x;
		dyingPoint.ty = tangent.y;
		dyingPoint.tz = tangent.z;

		dyingPoint.w = prefab.endWidth;
		dyingPoint.lifetime = 0.0;

		if ( dyingPoint.next != null ) {
			var p = dyingPoint.next;
			dyingPoint.next = null;
			while (p != null) {
				var n = p.next;
				disposePoint(p);
				t.numPoints--;
				t.totalLength -= p.len;
				p = n;
			}
		}
	}

	function updateSubTrails(dt : Float) {
		for (i => childIndex in subTrailChildIndices) {
			var c = children[childIndex];
			var t = trails[i];
			var absPos = c.getAbsPos();
			updateTrail(t, dt, absPos.tx, absPos.ty, absPos.tz);
		}
	}

	public function update(dt: Float) {
		cooldown -= dt;

		// Recompute some values of those were based on previous s3d positions
		var sceneAbs = getScene().absPos.getPosition();
		if (xOffset != sceneAbs.x || yOffset != sceneAbs.y || zOffset != sceneAbs.z) {
			var xDelta = sceneAbs.x - xOffset;
			var yDelta = sceneAbs.y - yOffset;
			var zDelta = sceneAbs.z - zOffset;

			for (i in 0...numTrails) {
				var trail = trails[i];
				var cur = trail.firstPoint;

				while (cur != null) {
					cur.x = cur.x + xDelta;
					cur.y = cur.y + yDelta;
					cur.z = cur.z + zDelta;

					cur = cur.next;
				}
			}

			xOffset = sceneAbs.x;
			yOffset = sceneAbs.y;
			zOffset = sceneAbs.z;
		}

		computeOrientation();

		var numObj = 0;
		for ( i => child in children) {
			if (Std.downcast(child, TrailsSubTailObj) == null)
				continue;
			subTrailChildIndices[numObj] = i;
			numObj++;
		}

		if (numObj > 0) {
			subTrailChildIndices.resize(numObj);
			autoTrackPosition = false;
			numTrails = numObj;
			updateSubTrails(dt);
		} else {
			subTrailChildIndices = null;
			numTrails = 1;
			syncPos();
			calcAbsPos();
			updateTrail(trails[0], dt, absPos.tx, absPos.ty, absPos.tz);
		}

		#if editor
		icon.color.a = (numObj > 0) ? 0.50 : 1.0;
		#end

		if ( cooldown > 0.0 )
			return;
		cooldown = 1.0 / maxFramerate;

		if ( numObj > 0) {
			for (i => childIndex in subTrailChildIndices) {
				var c = children[childIndex];
				var t = trails[i];
				var pos = c.getAbsPos();
				addPoint(t, pos.tx, pos.ty, pos.tz);
			}
		} else if (autoTrackPosition)
			addPoint(trails[0], absPos.tx, absPos.ty, absPos.tz);
	}

	override function emit(ctx) {
		super.emit(ctx);

		var buffer = vbuf;
		var indices = ibuf;

		var count = 0;
		numVertsIndices = 0;

		var baseScale = new h3d.Vector(1, 1, 1);
		if ( prefab.useScale ) {
			var scale = absPos.getScale();
			baseScale.x = scale.x;
			baseScale.y = scale.y;
			baseScale.z = scale.z;
		}

		inline function addEdge( p : h3d.Vector, u : Float, w : Float, normal : h3d.Vector, binormal : h3d.Vector ) {
			buffer[count++] = p.x + binormal.x * w * baseScale.x;
			buffer[count++] = p.y + binormal.y * w * baseScale.y;
			buffer[count++] = p.z + binormal.z * w * baseScale.z;
			buffer[count++] = normal.x;
			buffer[count++] = normal.y;
			buffer[count++] = normal.z;
			buffer[count++] = u;
			buffer[count++] = 0;

			buffer[count++] = p.x + (binormal.x * -w * baseScale.x);
			buffer[count++] = p.y + (binormal.y * -w * baseScale.y);
			buffer[count++] = p.z + (binormal.z * -w * baseScale.z);
			buffer[count++] = ux;
			buffer[count++] = uy;
			buffer[count++] = uz;
			buffer[count++] = u;
			buffer[count++] = 1;
		}

		inline function addSegment( segmentIndex : Int ) {
			var currentIndex = segmentIndex * 2;

			indices[numVertsIndices + 0] = currentIndex + 2;
			indices[numVertsIndices + 1] = currentIndex + 1;
			indices[numVertsIndices + 2] = currentIndex;

			indices[numVertsIndices + 3] = currentIndex + 2;
			indices[numVertsIndices + 4] = currentIndex + 3;
			indices[numVertsIndices + 5] = currentIndex + 1;

			numVertsIndices += 6;
		}

		var segmentIndex = 0;

		var orientRight = prefab.orientation.match(Right(_,_,_));
		var customAxis = ( orientRight ) ? tmpBinormal : tmpNormal;
		var computedAxis = ( orientRight ) ? tmpNormal : tmpBinormal;
		customAxis.set(ux, uy, uz);
		customAxis.normalize();

		for (i in 0...numTrails) {
			var trail = trails[i];
			if ( trail.firstPoint == null )
				continue;

			var cur = trail.firstPoint;
			var totalLen = trail.totalLength;

			var absPos = subTrailChildIndices == null ? this.absPos : children[subTrailChildIndices[i]].absPos;
			var curToHead = new h3d.Vector(absPos.tx - cur.x, absPos.ty - cur.y, absPos.tz - cur.z);
			var curToHeadSq = curToHead.lengthSq();

			if ( curToHeadSq > 0.01 ) {
				tmpHead.x = absPos.tx;
				tmpHead.y = absPos.ty;
				tmpHead.z = absPos.tz;

				var tangent = curToHead.normalized();
				tmpHead.tx = tangent.x;
				tmpHead.ty = tangent.y;
				tmpHead.tz = tangent.z;

				tmpHead.w = prefab.startWidth;
				tmpHead.next = cur;
				tmpHead.lifetime = prefab.lifetime;
				tmpHead.len = Math.sqrt(curToHeadSq);
				tmpHead.speed = cur.speed;

				totalLen += tmpHead.len;
				cur = tmpHead;
			}

			if (cur.next == null )
				continue;

			var len = 0.0;
			while (	cur != null ) {
				var u = switch (prefab.uvMode) {
					case ETileFixed:
						totalLen - len;
					case EStretch:
						(totalLen - len) / totalLen;
					case ETileFollow:
						len;
					case ELifetime:
						1 - cur.lifetime / prefab.lifetime;
				}

				var tangent = new h3d.Vector(cur.tx, cur.ty, cur.tz);
				computedAxis.load( customAxis.cross(tangent) );
				computedAxis.normalize();

				var p = new h3d.Vector(cur.x, cur.y, cur.z);
				addEdge( p, u, cur.w, tmpNormal, tmpBinormal );

				if ( cur.next != null && cur.speed < prefab.maxSpeed && cur.speed > prefab.minSpeed )
					addSegment( segmentIndex );

				len += cur.len;
				segmentIndex++;
				cur = cur.next;
			}
		}

		var numVerts = Std.int(count/8);

		shader.uvStretch = prefab.uvStretch;

		dprim.buffer.uploadFloats(vbuf, 0, numVerts, 0);
		dprim.indexes.uploadIndexes(ibuf, 0, numVertsIndices);
	}

	override function draw(ctx:h3d.scene.RenderContext) {
		absPos.identity();
		posChanged = true;
		ctx.uploadParams();

		var triToDraw : Int = Std.int(numVertsIndices/3);
		if (triToDraw < 0)
			triToDraw = 0;
		ctx.engine.renderIndexed(dprim.buffer, dprim.indexes, 0, triToDraw);
	}
}

// Empty class just for casting purposes
class TrailsSubTailObj extends h3d.scene.Object {

	public function new(?parent) {
		super(parent);
		#if editor
		hrt.impl.EditorTools.create3DIcon(this, hide.Ide.inst.getHideResPath("icons/icon-trails.png"), 0.33, Trails);
		#end
	}
}

class TrailsSubTrail extends Object3D {

	override function makeObject(parent3d: h3d.scene.Object) : h3d.scene.Object {
		var obj = new TrailsSubTailObj(parent3d);
		return obj;
	}

	override function updateInstance(?props: String) {
		applyTransform();
	}

	#if editor
	override function getHideProps():hide.prefab.HideProps {
		return { icon : "toggle-on", name : "Sub Trail" , allowChildren: (name) -> name == Trails};
	}
	#end

	static var _ = Prefab.register("SubTrail", TrailsSubTrail);

}

class Trails extends Object3D {

	@:s public var startWidth : Float = 1.0;
	@:s public var endWidth : Float = 0.0;
	@:s public var lifetime : Float = 1.0;
	@:c public var orientation : TrailOrientation = TrailOrientation.Camera;
	@:s public var useScale : Bool = false;

	@:s public var minSpeed : Float = 10.0;
	@:s public var maxSpeed : Float = 1000.0;

	@:s public var uvMode : UVMode = EStretch;
	@:s public var uvStretch: Float = 1.0;
	@:s public var uvRepeat : UVRepeat = EMod;

	// TODO(ces) : find better way to do that
	// Override this before calling make() to change how many trails are instancied
	public var numTrails : Int = 1;

	function new(parent, shared) {
		super(parent, shared);
		name = "Trails";
	}

	override function load(data : Dynamic) : Void {
		super.load(data);

		if (data.orientation == null)
			return;

		if (data?.orientation >= 1) {
			if( Std.isOfType(data.orientationUpAxisX, String) )
				this.orientation = TrailOrientation.createByIndex(data.orientation, [ Std.parseFloat(data.orientationUpAxisX), Std.parseFloat(data.orientationUpAxisY), Std.parseFloat(data.orientationUpAxisZ) ]);
			else
				this.orientation = TrailOrientation.createByIndex(data.orientation, [ data.orientationUpAxisX, data.orientationUpAxisY, data.orientationUpAxisZ ]);
		}
		else
			this.orientation = TrailOrientation.createByIndex(data.orientation);
	}

	override function copy(data: Prefab) : Void {
		super.copy(data);
	}

	override function save() : Dynamic {
		var obj = super.save();

		switch (this.orientation) {
			case Camera:
			case Up(x, y, z), Right(x, y, z):
				obj.orientation = this.orientation.getIndex();
				obj.orientationUpAxisX = x;
				obj.orientationUpAxisY = y;
				obj.orientationUpAxisZ = z;
			default:
				obj.orientation = this.orientation.getIndex();

		}

		return obj;
	}

	public function create( ?parent : h3d.scene.Object, ?numTrails : Int ) {
		var tr = new TrailObj(this, parent, numTrails);
		applyTransform();
		tr.name = name;
		tr.updateShader();
		return tr;
	}

	override function makeObject(parent3d: h3d.scene.Object) : h3d.scene.Object {
		return create(parent3d, numTrails);
	}

	override function updateInstance(?props: String) {
		super.updateInstance(props);
		var trailObj : TrailObj = cast local3d;
		if ( props == "uvRepeat")
			trailObj.updateShader();

		if ( props == "uvMode")
			trailObj.reset();

		if ( props == "lifetime" ) {
			lifetime = hxd.Math.max(lifetime, 0.00001);
			@:privateAccess trailObj.allocBuffers();
			if ( @:privateAccess trailObj.dprim != null )
				@:privateAccess trailObj.dprim.alloc(null);
		}
	}

	#if editor

	override function getHideProps():hide.prefab.HideProps {
		return { icon : "toggle-on", name : "Trails" };
	}

	override public function edit(ctx:hide.prefab.EditContext) {
		super.edit(ctx);

		var props = ctx.properties.add(new hide.Element('
		<div class="group" name="Trail Properties">
			<dl id="trail-properties">
				<dt>Lifetime</dt><dd><input type="range" field="lifetime" min="0" max="1"/></dd>
				<dt>Width Start</dt><dd><input type="range" field="startWidth" min="0" max="10"/></dd>
				<dt>Width End</dt><dd><input type="range" field="endWidth" min="0" max="10"/></dd>
				<dt>Min Speed</dt><dd><input type="range" field="minSpeed" min="0" max="1000"/></dd>
				<dt>Max Speed</dt><dd><input type="range" field="maxSpeed" min="0" max="1000"/></dd>
				<dt>Use scale</dt><dd><input type="checkbox" field="useScale" /></dd>
			</dl>
		</div>

		<div class="group" name="UV">
		<dl>
			<dt>UV Mode</dt><dd><select field="uvMode"></select></dd>
			<dt>UV Repeat</dt><dd><select field="uvRepeat"></select></dd>
			<dt>UV Scale</dt><dd><input type="range" field="uvStretch" min="0" max="5"/></dd>
		</dl>
	</div>
		'),this, function(name:String) {
			ctx.onChange(this,name);
		});

		var orientationEl = new hide.Element('<dt>Orient</dt><dd>
			<select>
				<option value=0>Camera</option>
				<option value=1>Custom Up</option>
				<option value=2>Custom Right</option>
			</select>
			<div id="up-axis">
				<input id="x" type="number"/><input id="y" type="number"/><input id="z" type="number"/>
			</div>
			</dd>');

		orientationEl.appendTo(props.find("#trail-properties"));

		var select = orientationEl.find("select");
		var upAxisEl = orientationEl.find("#up-axis");

		function updateOrientSelect() {
			switch (this.orientation) {
				case Up(x, y, z), Right(x, y, z):
					select.val(this.orientation.getIndex());
					upAxisEl.css({ display:'flex' });
					upAxisEl.find("#x").val(x);
					upAxisEl.find("#y").val(y);
					upAxisEl.find("#z").val(z);
				default:
					select.val(this.orientation.getIndex());
					upAxisEl.css({ display:'none' });
			}
		}

		function onOrientChange() {
			var newValue = select.val();
			var oldValue = this.orientation.getIndex();

			function exec(undo:Bool) {
				var v = undo ? oldValue : newValue;
				if (v >= 1) {
					var x = Std.parseFloat(upAxisEl.find("#x").val());
					var y = Std.parseFloat(upAxisEl.find("#y").val());
					var z = Std.parseFloat(upAxisEl.find("#z").val());
					this.orientation = TrailOrientation.createByIndex(v, [ Math.isNaN(x) ? 0 : x, Math.isNaN(y) ? 0 : y, Math.isNaN(z) ? 0 : z]);
				}
				else {
					this.orientation = TrailOrientation.createByIndex(v);
				}
				updateOrientSelect();
			}

			exec(false);
			@:privateAccess ctx.scene.editor.undo.change(Custom(exec));
		}

		updateOrientSelect();
		select.on("change", onOrientChange);
		upAxisEl.find("#x").on("change", onOrientChange);
		upAxisEl.find("#y").on("change", onOrientChange);
		upAxisEl.find("#z").on("change", onOrientChange);
	}

	#end

	static var _ = Prefab.register("trails", Trails);
}
