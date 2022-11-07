package hrt.prefab.l3d;

class BaseTrails extends hxsl.Shader {

	static var SRC = {

        @param var uvStretch : Float;
        @const @param var uvRepeat : Int = 0;

        @input var input2 : {
			var uv : Vec2;
        };

		var calculatedUV : Vec2;

        function __init__() {
            calculatedUV = input2.uv;
        }

        function fragment() {
            calculatedUV = calculatedUV * vec2(uvStretch, 1.0);

            switch(uvRepeat) {
                case 0: // Modulo
                    calculatedUV.x = calculatedUV.x % 1.0;
                case 1: // Mirror
                    calculatedUV.x = calculatedUV.x % 2.0;
                    if (calculatedUV.x > 1.0) {
                        calculatedUV.x = 2.0-calculatedUV.x;
                    }
                case 3: // Clamp
                    calculatedUV.x = saturate(calculatedUV.x);
                case 4: {};// None
                default: {};
            }
        }
	};

}

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

class TrailHead {
    public var firstPoint : TrailPoint = null;
    public var totalLength : Float = 0; 

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

typedef TrailID = haxe.Int32;

typedef TrailParameters = {
    var uvMode : UVMode;
    var startWidth : Float;
    var endWidth : Float;
    var lifetime : Float;
    var minLen : Float;
    var uvStretch: Float;
    var uvRepeat : UVRepeat;
    var maxTriangles : Int;
}

class TrailObj extends h3d.scene.Mesh {
    var trailHeads : Map<TrailID, TrailHead> = new Map();

    var nextTrailID = 0;

    var dprim : h3d.prim.RawPrimitive;
    var vbuf : hxd.FloatBuffer;
    var ibuf : hxd.IndexBuffer;
    var num_verts_indices : Int = 0;
    var num_verts : Int = 0;
    var bounds : h3d.col.Bounds;
    var prefab : Trails;

    public var num_trails : Int = 1;

    // How many frame we wait before adding a new point
    var pointFrameskip : Int = 2;

    var shader : BaseTrails;


    public function getTheoricalMaxPoints() : Int {
        return Std.int(std.Math.ceil(prefab.lifetime * 60.0 / pointFrameskip));
    }

    function getTheoricalMaxVertexes() : Int {
        var pointsPerTrail = getTheoricalMaxPoints();
        var vertsPerTrail = std.Math.ceil(pointsPerTrail * 2);
        return vertsPerTrail * num_trails;
    }

    function getTheoricalMaxIndices() : Int {
        var pointsPerTrail = getTheoricalMaxPoints();
        var indicesPerTrail = (pointsPerTrail-1) * 6;
        return indicesPerTrail * num_trails;
    }

    var lastMaxVertexesSize = 0;
    var lastMaxIndicesSize = 0;

    function refreshBufferSize() {
        if (lastMaxVertexesSize != getTheoricalMaxVertexes() || lastMaxIndicesSize != getTheoricalMaxIndices()) {
            lastMaxVertexesSize = getTheoricalMaxVertexes();
            lastMaxIndicesSize = getTheoricalMaxIndices();

            initOrResizeInternalBuffers();
            dprim.alloc(null);
        }
    }

    function initOrResizeInternalBuffers() {
        var alloc = hxd.impl.Allocator.get();
        if (vbuf != null)
            alloc.disposeFloats(vbuf);
        vbuf = new hxd.FloatBuffer(getTheoricalMaxVertexes() * 8);
        if (ibuf != null)
            alloc.disposeIndexes(ibuf);
        ibuf = new hxd.IndexBuffer(getTheoricalMaxIndices());
    }


    var pool : TrailPoint = null;

    var debugPointViz : h3d.scene.Graphics = null;

	public var materialData = {};

    public function getNextTrailID() : TrailID {
        return nextTrailID++;
    }

    public  function updateParams() {
        updateShader();
    }

    function alloc() : TrailPoint {
        if (pool != null)
        {
            var r = pool;
            pool = r.next;
            r.next = null;
            r.len = 0.0;
            return r;
        }
        return new TrailPoint();
    }

    function disposePoint(p : TrailPoint) {
        p.next = null;
        if (pool != null)
            p.next = pool;
        pool = p;
    }

    override function onRemove() {
        dprim.dispose();
    }

    public function reset() {
        for (k => v in trailHeads) {
            var p = v.firstPoint;
            while (p != null) {
                var n = p.next;
                disposePoint(p);
                p = n;
            }
        }
        trailHeads.clear();
    }

    public function updateShader() {
        shader.uvRepeat = prefab.uvRepeat.getIndex();
    }

    static var showDebugLines = false;

    var statusText : h2d.Text;
    
    public function addPoint(?id : Int, x : Float, y : Float, z : Float, orient : TrailOrientation, w : Float) {
        id = id != null ? id : 0;

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

                var len = 1.0/hxd.Math.distance(vcamx, vcamy, vcamz);

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

        var head = getHead(id);

        var prev = head.firstPoint;
        var new_pt : TrailPoint = null;

        var added_point = true;

        // If we haven't moved far enought from the previous point, reuse the head instead of creating a new point
        if (prev != null && prev.next != null) {
            var len = (x - prev.next.x) * (x - prev.next.x) +
            (y - prev.next.y) * (y - prev.next.y) +
            (z - prev.next.z) * (z - prev.next.z);
            len = Math.sqrt(len);

            //if (params.uvMode == EStretch)
            //head.totalLength = prev != null ? prev.len + len : len;

            if (prev.lifetime < pointFrameskip/60.0-0.001) {
                new_pt = prev;
                prev = prev.next;
                added_point = false;
            } else {
                if (prefab.uvMode == ETileFixed) {
                    head.totalLength = prev != null ? prev.len + len : len;
                } else {
                    head.totalLength += prev.len;
                }
            }
        }

        if (new_pt == null)
        {
            new_pt = alloc();
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

            if (prefab.uvMode == ETileFixed) {
                new_pt.len = head.totalLength + len;
            }
            else {
                new_pt.len = len;
            }

            var len = 1.0/len;

            if (nx == 0 && ny == 0 && nz == 0) {
                nx = (prev.x - x) * len;
                ny = (prev.y - y) * len;
                nz = (prev.z - z) * len;
        
                new_pt.nx = ny * uz - nz * uy;
                new_pt.ny = nz * ux - nx * uz;
                new_pt.nz = nx * uy - ny * ux;
    
                var nlen = 1.0/hxd.Math.distance(new_pt.nx, new_pt.ny, new_pt.nz);
                new_pt.nx *= nlen;
                new_pt.ny *= nlen;
                new_pt.nz *= nlen;
    
                new_pt.ux = new_pt.ny * nz - new_pt.nz * ny;
                new_pt.uy = new_pt.nz * nx - new_pt.nx * nz;
                new_pt.uz = new_pt.nx * ny - new_pt.ny * nx;
    
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

    public function getHead(id : TrailID) : TrailHead {
        if (!trailHeads.exists(id))
            trailHeads.set(id, new TrailHead());
        return trailHeads[id];
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
            stride : 8,
            quads : false,
            bounds : bounds,
        };
    }

    public function new(parentPrefab: Trails, ?parent : h3d.scene.Object) {
        bounds = new h3d.col.Bounds();
        prefab = parentPrefab;
        bounds.addPos(0,0,0);

        initOrResizeInternalBuffers();

        dprim = new h3d.prim.RawPrimitive(onDprimContextLost(), true);
        dprim.onContextLost = onDprimContextLost;

        super(dprim,parent);

        debugPointViz = new h3d.scene.Graphics(parent);

        material.props = getMaterialProps();
		material.mainPass.dynamicParameters = true;

        shader = new BaseTrails();
        material.mainPass.addShader(shader);

        shader.setPriority(-999);

        updateParams();
    }

    static var pointA = new h3d.col.Point();
    static var pointB = new h3d.col.Point();

    var prev_x : Float = 0;
    var prev_y : Float = 0;
    var prev_z : Float = 0;

    var lastUpdateDuration = 0.0;

    override function sync(ctx) {
        var t = haxe.Timer.stamp();

        //trace(t, ctx.elapsedTime);

        refreshBufferSize();

        calcAbsPos();


		super.sync(ctx);

        var x = absPos._41;
        var y = absPos._42;
        var z = absPos._43;

        var spdSqr = 
            (x - prev_x) * (x - prev_x) +
            (y - prev_y) * (y - prev_y) +
            (z - prev_z) * (z - prev_z);

        var shouldAddPoint : Bool = false;

        var minSpd = 0.0;
        if (spdSqr > minSpd * minSpd) {
            shouldAddPoint = true;
        }

        if (shouldAddPoint) {
            //addPoint(0, x,y,z, ECamera, 1);
            //addPoint(0, x,y,z, EUp(0,0,1), 1);
            addPoint(0, x,y,z, EBasis(absPos), 1);
        }


        prev_x = x;
        prev_y = y;
        prev_z = z;


        debugPointViz.clear();

        var buffer = vbuf;
        var indices = ibuf;

        var count = 0;
        num_verts_indices = 0;
        var current_index = 0;
        var num_segments = 0;

        // render
        for (k => trail in trailHeads) {
            var prev = null;
            var fix_prev = true;
            var cur = trail.firstPoint;
            var len = 0.0;

            var totalLen = trail.totalLength + (cur != null ? cur.len : 0.0);
            while (cur != null) {
                num_segments += 1;
                cur.lifetime += ctx.elapsedTime;
                var t = cur.lifetime / prefab.lifetime;
                cur.w = hxd.Math.lerp(prefab.startWidth, prefab.endWidth, t);
                if (cur.lifetime > prefab.lifetime) {
                    if (prefab.uvMode != ETileFixed)
                        trail.totalLength -= cur.len;
                    if (prev != null) {
                        prev.next = null;
                    } else {
                        trailHeads.remove(k);
                    }
                    disposePoint(cur);
                    break;
                }
                if (cur.next != null) {
                    if (showDebugLines) {
                        pointA.set(cur.next.x, cur.next.y, cur.next.z);
                        pointB.set(cur.x, cur.y, cur.z);
                        debugPointViz.drawLine(pointA, pointB);
    
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
    
    
                        debugPointViz.setColor(0xFFFFFF, 1.0);
                    }
                }
                    
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
                
                if (showDebugLines) {
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

                if (count+16 > lastMaxVertexesSize * 8) {
                    trace("maxmaxmax");
                    break;
                }

                var u = if (prefab.uvMode == ETileFixed) cur.len else len;
                if (prefab.uvMode == EStretch) u = (totalLen - len) / totalLen;
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

                if (prev != null) {

                    if (num_verts_indices + 6 > lastMaxIndicesSize) break;

                    indices[num_verts_indices] = current_index+2;
                    indices[num_verts_indices+1] = current_index+1;
                    indices[num_verts_indices+2] = current_index;

                    num_verts_indices += 3;

                    indices[num_verts_indices] = current_index+2;
                    indices[num_verts_indices+1] = current_index+3;
                    indices[num_verts_indices+2] = current_index+1;

                    num_verts_indices += 3;
                    current_index += 2;
                }

                len += cur.len;

                prev = cur;
                cur = cur.next;

            }
            
            if (prev != null ){
                current_index +=2;
            }
        }

        num_verts = Std.int(count/8);

        //trace(num_segments, num_verts_indices_indices);

        // debug sanitize
        /*while (count < maxNumTriangles * 8 * 3) {
            buffer[count++] = 1000;
        }*/

        /*var tmp_tris = num_verts_indices;
        while (num_verts_indices < max_buf_size) {
            indices[num_verts_indices++] = max_buf_size - 1;
        }*/

        shader.uvStretch = prefab.uvStretch;

        dprim.buffer.uploadVector(vbuf, 0, num_verts, 0);
        dprim.indexes.upload(ibuf, 0, num_verts_indices);


        lastUpdateDuration = haxe.Timer.stamp() - t;
    }

    override function draw(ctx:h3d.scene.RenderContext) {
		//if( points.length >= 2 ) {
			absPos.identity();
			posChanged = true;
			ctx.uploadParams();

            var triToDraw : Int = Std.int(num_verts_indices/3);
            if (triToDraw < 0) triToDraw = 0;
            ctx.engine.renderIndexed(dprim.buffer, dprim.indexes, 0, triToDraw);
			//super.draw(ctx);
		//}
	}
}


class Trails extends Object3D {
	
    @:s public var startWidth : Float = 1.0;
    @:s public var endWidth : Float = 0.0;
    @:s public var lifetime : Float = 1.0;

    @:s public var uvMode : UVMode = EStretch;
    @:s public var uvStretch: Float = 1.0;
    @:s public var uvRepeat : UVRepeat = EMod;


    function new(?parent) {
		super(parent);
	}

	public function create( ?parent : h3d.scene.Object ) {
		var tr = new TrailObj(this, parent);
		applyTransform(tr);
		tr.name = name;
        tr.updateShader();
		return tr;
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		var tr = create(ctx.local3d);
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
		var trail = trailContext == null ? create(null) : Std.downcast(trailContext.local3d, TrailObj);
		var props = ctx.properties.add(new hide.Element('
		<div class="group" name="Trail Properties">
			<dl>
				<dt>Lifetime</dt><dd><input type="range" field="lifetime" min="0" max="1"/></dd>
				<dt>Width Start</dt><dd><input type="range" field="startWidth" min="0" max="10"/></dd>
				<dt>Width End</dt><dd><input type="range" field="endWidth" min="0" max="10"/></dd>
				<dt title="Minimum distance between 2 points on a trail. More = better performance but a more blockier look">Min Distance</dt><dd><input type="range" field="minLen" min="0" max="1.0"/></dd>
				<dt title="Maximum allocated triangles for this trail system.">Max Triangles</dt><dd><input type="range" field="maxTriangles" min="0" max="65000"/></dd>
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
            if (name == "uvRepeat") {
                trail.updateShader();
            }
            if (name == "uvMode") {
                trail.reset();
            }
            if (name == "maxTriangles") {
                trail.updateParams();
            }
		});
		//ctx.properties.addMaterial( trail.material, props.find("[name=Material] > .content"), function(_) data = trail.save());
	}

	#end

	static var _ = Library.register("trails", Trails);
}
