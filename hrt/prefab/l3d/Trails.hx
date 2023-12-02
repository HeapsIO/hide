package hrt.prefab.l3d;

#if (hl_ver >= version("1.13.0")) @:struct #end
class TrailPoint {
	public var x : Float = 0;
	public var y : Float = 0;
	public var z : Float = 0;
	public var nx : Float = 0;
	public var ny : Float = 0;
	public var nz : Float = 0;
	public var ux : Float = 0;
	public var uy : Float = 0;
	public var uz : Float = 0;
	public var w : Float = 0;
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
	ECamera;
	EUp(x : Float, y : Float, z : Float);
	EBasis(m : h3d.Matrix);
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


typedef PointsArray = #if (hl_ver >= version("1.13.0")) hl.CArray<TrailPoint> #else Array<TrailPoint> #end;
typedef TrailsArray = #if (hl_ver >= version("1.13.0")) hl.CArray<TrailHead> #else Array<TrailHead> #end;


class TrailObj extends h3d.scene.Mesh {

	var points : PointsArray;
	var trails : TrailsArray;
	var lastAddTime : Array<Float>;

	var trailsPool : TrailHead = null;
	var firstFreePointID = 0;

	var nextTrailID = 0;

	var dprim : h3d.prim.RawPrimitive;
	var vbuf : hxd.FloatBuffer;
	var ibuf : hxd.IndexBuffer;
	var numVertsIndices : Int = 0;
	var numVerts : Int = 0;
	var bounds : h3d.col.Bounds;
	var prefab : Trails;

	public var timeScale : Float = 1.0;

	#if editor
	var icon : hrt.impl.EditorTools.EditorIcon;
	#end


	// Sets whenever we check the position of this object to automaticaly add points to the 0th trail.
	// If set to false, trail can be created by manually calling addPoint()
	public var autoTrackPosition : Bool = true;

	var currentAllocatedVertexCount = 0;
	var currentAllocatedIndexCount = 0;


	public var numTrails(default, set) : Int = -1;

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
		return Std.int(std.Math.ceil(prefab.lifetime * maxFramerate));
	}

	function calcMaxVertexes() : Int {
		var pointsPerTrail = calcMaxTrailPoints();
		var vertsPerTrail = std.Math.ceil(pointsPerTrail * 2);
		var num = vertsPerTrail * numTrails;
		if (num > 65534) {
			num = 65534;
		}
		return num;
	}

	function calcMaxIndexes() : Int {
		var pointsPerTrail = calcMaxTrailPoints();
		var indicesPerTrail = (pointsPerTrail-1) * 6;
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
		if (maxNumPoints <= 0) maxNumPoints = 1;
		points = #if (hl_ver >= version("1.13.0")) hl.CArray.alloc(TrailPoint, maxNumPoints) #else [for(i in 0...maxNumPoints) new TrailPoint()] #end;

		trails = #if (hl_ver >= version("1.13.0")) hl.CArray.alloc(TrailHead, numTrails) #else [for(i in 0...numTrails) new TrailHead()] #end;

		lastAddTime = [for (i in 0...numTrails) 0.0];

		for (i in 0...numTrails-1) {
			trails[i].nextTrail = trails[i+1];
		}
		trailsPool = trails[0];

		reset();
	}

	var maxNumPoints : Int = 0;

	var pool : TrailPoint = null;

	#if editor
	var debugPointViz : h3d.scene.Graphics = null;
	#end

	public var materialData = {};

	public  function updateParams() {
		updateShader();
	}

	function allocPoint() : TrailPoint {
		var r = null;
		if (pool != null)
		{
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
		if (trailsPool == null) throw "assert";
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
		if (pool != null)
			p.next = pool;
		else
			p.next = null;
		pool = p;
	}

	override function onRemove() {
		super.onRemove();
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

	static var showDebugLines = false;

	var statusText : h2d.Text;

	public function addPoint(t : TrailHead, x : Float, y : Float, z : Float, orient : TrailOrientation, w : Float) {

		var ux : Float = 0.0;
		var uy : Float = 0.0;
		var uz : Float = 0.0;
		var nx : Float = 0.0;
		var ny : Float = 0.0;
		var nz : Float = 0.0;

		switch (orient) {
			case ECamera: {
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
			case EUp(x,y,z): {
				ux = x;
				uy = y;
				uz = z;
			}
			case EBasis(m): {
				var up = m.up();
				ux = up.x;
				uy = up.y;
				uz = up.z;

				var right = m.right();
				nx = right.x;
				ny = right.y;
				nz = right.z;
			}
		}

		var head = t;

		var prev = head.firstPoint;
		var new_pt : TrailPoint = null;

		var added_point = true;

		// If we haven't moved far enought from the previous point, reuse the head instead of creating a new point
		if (prev != null && prev.next != null) {
			var len = (x - prev.next.x) * (x - prev.next.x) +
			(y - prev.next.y) * (y - prev.next.y) +
			(z - prev.next.z) * (z - prev.next.z);
			len = Math.sqrt(len);

			var len2 = hxd.Math.distance(x-prev.x, y-prev.y, z-prev.z);

			if (prev.lifetime < 1.0/maxFramerate-0.001 ||
				head.numPoints >= calcMaxTrailPoints() // Don't allocate points if we have the max numPoints
				|| len < 0.01 || len2 < 0.01
				) {
				new_pt = prev;
				prev = prev.next;
				added_point = false;
			} else {
				head.totalLength += prev.len;
			}
		}

		if (new_pt == null)
		{
			new_pt = allocPoint();
			if (new_pt == null)
				return;
			head.numPoints ++;
			new_pt.lifetime = 0.0;
		}

		new_pt.w = w;

		new_pt.x = x;
		new_pt.y = y;
		new_pt.z = z;

		var len = 0.0;

		if (prev != null) {
			var lenSq = (x - prev.x) * (x - prev.x) +
			(y - prev.y) * (y - prev.y) +
			(z - prev.z) * (z - prev.z);
			len = Math.sqrt(lenSq);

			new_pt.len = len;

			if (nx == 0 && ny == 0 && nz == 0 && len != 0) {
				var nlen = 1.0/len;


				var dx = (prev.x - x) * nlen;
				var dy = (prev.y - y) * nlen;
				var dz = (prev.z - z) * nlen;

				new_pt.nx = dy * uz - dz * uy;
				new_pt.ny = dz * ux - dx * uz;
				new_pt.nz = dx * uy - dy * ux;

				nlen = 1.0/hxd.Math.distance(new_pt.nx, new_pt.ny, new_pt.nz);

				new_pt.nx *= nlen;
				new_pt.ny *= nlen;
				new_pt.nz *= nlen;


				new_pt.ux = new_pt.ny * dz - new_pt.nz * dy;
				new_pt.uy = new_pt.nz * dx - new_pt.nx * dz;
				new_pt.uz = new_pt.nx * dy - new_pt.ny * dx;

				if (prev.nx == 0 && prev.ny == 0 && prev.nz == 0) {
					prev.nx = new_pt.nx;
					prev.ny = new_pt.ny;
					prev.nz = new_pt.nz;

					prev.ux = new_pt.ux;
					prev.uy = new_pt.uy;
					prev.uz = new_pt.uz;
				}
			}
			else {
				new_pt.nx = nx;
				new_pt.ny = ny;
				new_pt.nz = nz;

				new_pt.ux = ux;
				new_pt.uy = uy;
				new_pt.uz = uz;
			}
		} else {
			new_pt.nx = nx;
			new_pt.ny = ny;
			new_pt.nz = nz;

			new_pt.ux = ux;
			new_pt.uy = uy;
			new_pt.uz = uz;

			new_pt.len = 0;
		}

		if (prev != null)
			new_pt.next = prev;
		head.firstPoint = new_pt;
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
		if (nTrails == 1) {
			if (parentPrefab.children.length > 1) {
				nTrails = parentPrefab.children.length;
			}
		}

		this.numTrails = nTrails;

		dprim = new h3d.prim.RawPrimitive(onDprimContextLost(), true);
		dprim.onContextLost = onDprimContextLost;

		super(dprim,parent);

		#if editor
		debugPointViz = new h3d.scene.Graphics(parent.getScene());
		icon = hrt.impl.EditorTools.create3DIcon(this, hide.Ide.inst.getHideResPath("icons/icon-trails.png"), 0.75, Trails);
		#end

		material.props = getMaterialProps();
		material.mainPass.dynamicParameters = true;

		shader = new hrt.shader.BaseTrails();
		material.mainPass.addShader(shader);

		shader.setPriority(-999);

		updateParams();
	}

	#if editor
	static var pointA = new h3d.col.Point();
	static var pointB = new h3d.col.Point();
	#end

	var prev_x : Float = 0;
	var prev_y : Float = 0;
	var prev_z : Float = 0;

	var lastUpdateDuration = 0.0;

	override function sync(ctx) {
		var t = haxe.Timer.stamp();
		super.sync(ctx);

		if (timeScale > 0.0) {
			update(ctx.elapsedTime * timeScale);
		}

		lastUpdateDuration = haxe.Timer.stamp() - t;
	}

	public function update(dt: Float) {

		var numObj = 0;
		for (child in children) {
			if (Std.downcast(child, TrailsSubTailObj) == null)
				continue;
			numObj ++;
		}

		if (numObj > 0) {
			set_numTrails(numObj);
		}

		#if editor
			if (numObj > 0) {
				icon.color.a = 0.50;
			}
			else {
				icon.color.a = 1.0;
			}
		#end

		var childObjCount = 0;
		for (child in children) {
			if (Std.downcast(child, TrailsSubTailObj) == null)
				continue;
			autoTrackPosition = false;
			var c = child;
			var t = trails[childObjCount];
			var pos = c.getAbsPos();
			addPoint(t, pos.tx, pos.ty, pos.tz, ECamera, 1.0);
			childObjCount ++;
		}

		if (autoTrackPosition) {
			calcAbsPos();

			var x = absPos.tx;
			var y = absPos.ty;
			var z = absPos.tz;

			var spdSqr =
				(x - prev_x) * (x - prev_x) +
				(y - prev_y) * (y - prev_y) +
				(z - prev_z) * (z - prev_z);

			var shouldAddPoint : Bool = false;

			if (spdSqr > prefab.minSpeed * prefab.minSpeed || true) {
				shouldAddPoint = true;
			}

			if (shouldAddPoint) {
				addPoint(trails[0], x,y,z, ECamera, 1);
				//addPoint(0, x,y,z, EUp(0,0,1), 1);
				//addPoint(0, x,y,z, EBasis(absPos), 1);
			}
		}

		prev_x = x;
		prev_y = y;
		prev_z = z;


		#if editor
		debugPointViz.clear();
		#end

		var buffer = vbuf;
		var indices = ibuf;

		var count = 0;
		numVertsIndices = 0;
		var currentIndex = 0;
		var num_segments = 0;

		// render

		for (i in 0...numTrails) {
			var trail = trails[i];
			var prev : TrailPoint = null;
			var cur = trail.firstPoint;
			var len = 0.0;

			var totalLen = trail.totalLength + (cur != null ? cur.len : 0.0);
			while (cur != null) {
				num_segments += 1;
				cur.lifetime += dt;
				var t = cur.lifetime / prefab.lifetime;
				cur.w = hxd.Math.lerp(prefab.startWidth, prefab.endWidth, t);
				if (cur.lifetime > prefab.lifetime) {
					if (prefab.uvMode != ETileFixed)
						trail.totalLength -= cur.len;
					if (prev != null) {
						prev.next = null;
					} else {
						disposeTrail(trail);
					}
					var dp = cur;
					while(dp != null) {
						var next = dp.next;
						disposePoint(dp);
						dp = next;
						trail.numPoints--;
					}
					break;
				}

				#if editor
				if (cur.next != null) {
					if (showDebugLines) {
						debugPointViz.setColor(0xFFFFFF, 1.0);
						debugPointViz.lineStyle(8.0);

						/*pointA.set(cur.next.x, cur.next.y, cur.next.z);
						pointB.set(cur.x, cur.y, cur.z);
						debugPointViz.drawLine(pointA, pointB);*/

						debugPointViz.lineStyle(4.0);

						pointA.set((cur.x+cur.next.x) / 2.0,
									(cur.y+cur.next.y) / 2.0,
									(cur.z+cur.next.z) / 2.0);

						pointB.set(pointA.x + cur.nx * 2.0,
									pointA.y + cur.ny * 2.0,
									pointA.z + cur.nz * 2.0);

						debugPointViz.setColor(0xFF0000, 1.0);
						debugPointViz.drawLine(pointA, pointB);

						pointB.set(pointA.x + cur.ux * 2.0,
							pointA.y + cur.uy * 2.0,
							pointA.z + cur.uz * 2.0);
						debugPointViz.setColor(0x0000FF, 1.0);
						debugPointViz.drawLine(pointA, pointB);
					}
				}
				#end


				var nx = 0.0;
				var ny = 0.0;
				var nz = 0.0;

				if (prev != null) {
					nx = (cur.nx + prev.nx) * 0.5;
					ny = (cur.ny + prev.ny) * 0.5;
					nz = (cur.nz + prev.nz) * 0.5;
				} else {
					nx = cur.nx;
					ny = cur.ny;
					nz = cur.nz;
				}

				#if editor
				if (showDebugLines) {
					debugPointViz.setColor(0xFFFFFF, 1.0);

					pointA.set(cur.x, cur.y, cur.z);
					pointB.set( cur.x+nx,
						cur.y+ny,
						cur.z+nz);

					debugPointViz.drawLine(pointA, pointB);

					pointA.set(cur.x, cur.y, cur.z);
					pointB.set( cur.x-nx,
							cur.y-ny,
							cur.z-nz);

					debugPointViz.drawLine(pointA, pointB);
				}
				#end


				if (count+16 > currentAllocatedVertexCount * 8) {
					break;
				}

				var u = switch (prefab.uvMode) {
					case ETileFixed:
						totalLen - len;
					case EStretch:
						(totalLen - len) / totalLen;
					case ETileFollow:
						len;
					case ELifetime:
						t;
				}

				buffer[count++] = cur.x+nx * cur.w;
				buffer[count++] = cur.y+ny * cur.w;
				buffer[count++] = cur.z+nz * cur.w;
				buffer[count++] = cur.ux;
				buffer[count++] = cur.uy;
				buffer[count++] = cur.uz;
				buffer[count++] = u;
				buffer[count++] = 0;


				buffer[count++] = cur.x+ (nx * -cur.w);
				buffer[count++] = cur.y+ (ny * -cur.w);
				buffer[count++] = cur.z+ (nz * -cur.w);
				buffer[count++] = cur.ux;
				buffer[count++] = cur.uy;
				buffer[count++] = cur.uz;
				buffer[count++] = u;
				buffer[count++] = 1;


				if (prev != null ) {
					var spd = cur.len / hxd.Math.max((cur.lifetime - prev.lifetime), 1.0/maxFramerate);
					if (spd < prefab.maxSpeed && spd > prefab.minSpeed) {
						if (numVertsIndices + 6 > currentAllocatedIndexCount) break;

						indices[numVertsIndices] = currentIndex;
						indices[numVertsIndices+1] = currentIndex-1;
						indices[numVertsIndices+2] = currentIndex-2;

						numVertsIndices += 3;

						indices[numVertsIndices] = currentIndex;
						indices[numVertsIndices+1] = currentIndex+1;
						indices[numVertsIndices+2] = currentIndex-1;

						numVertsIndices += 3;
					}

				}

				currentIndex += 2;

				len += cur.len;

				prev = cur;
				cur = cur.next;

			}
		}

		numVerts = Std.int(count/8);

		shader.uvStretch = prefab.uvStretch;

		dprim.buffer.uploadFloats(vbuf, 0, numVerts, 0);
		dprim.indexes.upload(ibuf, 0, numVertsIndices);


	}

	override function draw(ctx:h3d.scene.RenderContext) {
		absPos.identity();
		posChanged = true;
		ctx.uploadParams();

		var triToDraw : Int = Std.int(numVertsIndices/3);
		if (triToDraw < 0) triToDraw = 0;
		ctx.engine.renderIndexed(dprim.buffer, dprim.indexes, 0, triToDraw);

	}
}

// Empty class just for casting purposes
class TrailsSubTailObj extends h3d.scene.Object {

	public function new(?parent) {
		super(parent);
		#if editor
		var icon = hrt.impl.EditorTools.create3DIcon(this, "icons/icon-trails.png", 1.0, Trails);
		icon.scale(0.33);
		#end
	}
}

class TrailsSubTrail extends Object3D {

	function new(?parent) {
		super(parent);
		name = "SubTrail";
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		var obj = new TrailsSubTailObj(ctx.local3d);
		applyTransform(obj);
		obj.name = name;
		ctx.local3d = obj;
		return ctx;
	}

	#if editor
	override function getHideProps():HideProps {
		return { icon : "toggle-on", name : "Sub Trail" , allowChildren: (name) -> name == "Trails"};
	}
	#end

	static var _ = Library.register("SubTrail", TrailsSubTrail);

}


class Trails extends Object3D {

	@:s public var startWidth : Float = 1.0;
	@:s public var endWidth : Float = 0.0;
	@:s public var lifetime : Float = 1.0;

	@:s public var minSpeed : Float = 10.0;
	@:s public var maxSpeed : Float = 1000.0;


	@:s public var uvMode : UVMode = EStretch;
	@:s public var uvStretch: Float = 1.0;
	@:s public var uvRepeat : UVRepeat = EMod;

	function new(?parent) {
		super(parent);
		name = "Trails";

	}

	public function create( ?parent : h3d.scene.Object, ?numTrails : Int ) {
		var tr = new TrailObj(this, parent, numTrails);
		applyTransform(tr);
		tr.name = name;
		tr.updateShader();
		return tr;
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		var tr = create(ctx.local3d, ctx.custom != null ? ctx.custom.numTrails : 1);
		ctx.local3d = tr;
		return ctx;
	}

	#if editor

	override function getHideProps():HideProps {
		return { icon : "toggle-on", name : "Trails" };
	}

	override public function edit(ctx:EditContext) {
		super.edit(ctx);

		var trailContext = ctx.getContext(this);
		var trailObj = trailContext == null ? null : Std.downcast(trailContext.local3d, TrailObj);
		var props = ctx.properties.add(new hide.Element('
		<div class="group" name="Trail Properties">
			<dl>
				<dt>Lifetime</dt><dd><input type="range" field="lifetime" min="0" max="1"/></dd>
				<dt>Width Start</dt><dd><input type="range" field="startWidth" min="0" max="10"/></dd>
				<dt>Width End</dt><dd><input type="range" field="endWidth" min="0" max="10"/></dd>
				<dt>Min Speed</dt><dd><input type="range" field="minSpeed" min="0" max="1000"/></dd>
				<dt>Max Speed</dt><dd><input type="range" field="maxSpeed" min="0" max="1000"/></dd>
			</dl>
		</div>

		<div class="group" name="UV">
		<dl>
			<dt>UV Mode</dt><dd><select field="uvMode"></select></dd>
			<dt>UV Repeat</dt><dd><select field="uvRepeat"></select></dd>
			<dt>UV Scale</dt><dd><input type="range" field="uvStretch" min="0" max="5" title="Hey look at me i\'m a comment"/></dd>
		</dl>
	</div>
		'),this, function(name:String) {
			if(trailObj == null)
				return;
			if (name == "uvRepeat") {
				trailObj.updateShader();
			}
			if (name == "uvMode") {
				trailObj.reset();
			}
			if (name == "maxTriangles") {
				trailObj.updateParams();
			}
		});
		//ctx.properties.addMaterial( trail.material, props.find("[name=Material] > .content"), function(_) data = trail.save());
	}

	#end

	static var _ = Library.register("trails", Trails);
}
