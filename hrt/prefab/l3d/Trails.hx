package hrt.prefab.l3d;

typedef TrailPoint = {
    var x : Float;
    var y : Float;
    var z : Float;
    var nx : Float;
    var ny : Float;
    var nz : Float;
    var ux : Float;
    var uy : Float;
    var uz : Float;
    var w : Float;
    var lifetime : Float;
    var next : TrailPoint;
};


class TrailObj extends h3d.scene.Mesh {
    var trailHeads : Map<Int, TrailPoint> = new Map();

    var dprim : h3d.prim.DynamicPrimitive;

    var pool : TrailPoint = null;

    var debugPointViz : h3d.scene.Graphics = null;

	public var materialData = {};

    function alloc() : TrailPoint {
        if (pool != null)
        {
            var r = pool;
            pool = pool.next;
            r.next = null;
            return r;
        }
        return {
            x : 0,
            y : 0,
            z : 0,
            nx : 0,
            ny : 0,
            nz : 0,
            ux : 0,
            uy : 0,
            uz : 0,
            w : 0,
            lifetime : 0,
            next : null
        };
    }

    function dispose(p : TrailPoint) {
        if (pool != null)
            p.next = pool;
        pool = p;
    }

    public function addPoint(?id : Int, x : Float, y : Float, z : Float, ux : Float, uy : Float, uz : Float, w : Float) {
        id = id != null ? id : 0;

        var prev = trailHeads[id];

        var new_pt = alloc();

        new_pt.lifetime = 0.0;
        new_pt.w = w;

        new_pt.x = x;
        new_pt.y = y;
        new_pt.z = z;

        if (prev != null) {
            var len = (x - prev.x) * (x - prev.x) +
            (y - prev.y) * (y - prev.y) +
            (z - prev.z) * (z - prev.z);
            len = Math.sqrt(len);
    
            var nx = (prev.x - x) / len;
            var ny = (prev.y - y) / len;
            var nz = (prev.z - z) / len;
    
            new_pt.nx = ny * uz - nz * uy;
            new_pt.ny = nz * ux - nx * uz;
            new_pt.nz = nx * uy - ny * ux;

            new_pt.ux = new_pt.ny * nz - new_pt.nz * ny;
            new_pt.uy = new_pt.nz * nx - new_pt.nx * nz;
            new_pt.uz = new_pt.nx * ny - new_pt.ny * nx;
        } else {
            new_pt.nx = 0;
            new_pt.ny = 0;
            new_pt.nz = 0;
        }


        if (prev != null)
            new_pt.next = prev;
        trailHeads.set(id, new_pt);
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

    public function new(?parent : h3d.scene.Object) {
        dprim = new h3d.prim.DynamicPrimitive(8);
        super(dprim,parent);

        debugPointViz = new h3d.scene.Graphics(parent);

        material.props = getMaterialProps();
		material.mainPass.dynamicParameters = true;
    }

    static var pointA = new h3d.col.Point();
    static var pointB = new h3d.col.Point();

    var prev_x : Float = 0;
    var prev_y : Float = 0;
    var prev_z : Float = 0;

    override function sync(ctx) {
        //x = Math.sin(hxd.Timer.frameCount/60*2.0*5.0) * 5.0;
        //y = Math.cos(hxd.Timer.frameCount/60 * 5.0) * 5.0;
        calcAbsPos();


		super.sync(ctx);
        trace(absPos._41, absPos._42, absPos._43);

        var x = absPos._41;
        var y = absPos._42;
        var z = absPos._43;

        var spdSqr = 
            (x - prev_x) * (x - prev_x) +
            (y - prev_y) * (y - prev_y) +
            (z - prev_z) * (z - prev_z);

        var minSpd = 0.0;
        if (spdSqr > minSpd * minSpd) {
            addPoint(0, x,y,z, 0, 0, 1, 1);
        }

        prev_x = x;
        prev_y = y;
        prev_z = z;


        debugPointViz.clear();

        var buffer = dprim.getBuffer(10000); // yolo
        var indices = dprim.getIndexes(10000); // yolo

        var count = 0;
        var num_tris = 0;
        var num_verts = 0;

        // render
        for (k => trail in trailHeads) {
            var prev = null;
            var cur = trail;
            while (cur != null) {
                cur.lifetime += hxd.Timer.elapsedTime*2.0;
                if (cur.lifetime > 10.0) {
                    if (prev != null) {
                        prev.next = null;
                    } else {
                        trailHeads.remove(k);
                    }
                    dispose(cur);
                    break;
                }
                if (prev != null) {
                    pointA.set(prev.x, prev.y, prev.z);
                    pointB.set(cur.x, cur.y, cur.z);
                    debugPointViz.drawLine(pointA, pointB);
                }
                    
                var nx = 0.0;
                var ny = 0.0;
                var nz = 0.0;

                if (cur.next != null) {
                    pointA.set(cur.x, cur.y, cur.z);
                    
                    nx = (cur.nx + cur.next.nx) / 2.0;
                    ny = (cur.ny + cur.next.ny) / 2.0;
                    nz = (cur.nz + cur.next.nz) / 2.0;

                    pointB.set( cur.x+nx, 
                                cur.y+ny, 
                                cur.z+nz);

                    debugPointViz.drawLine(pointA, pointB);
                }

                buffer[count++] = cur.x+nx * cur.w;
                buffer[count++] = cur.y+ny * cur.w;
                buffer[count++] = cur.z+nz * cur.w;
                buffer[count++] = cur.ux;
                buffer[count++] = cur.uy;
                buffer[count++] = cur.uz;
                buffer[count++] = 0;
                buffer[count++] = 0;


                buffer[count++] = cur.x+ (nx * -cur.w);
                buffer[count++] = cur.y+ (ny * -cur.w);
                buffer[count++] = cur.z+ (nz * -cur.w);
                buffer[count++] = cur.ux;
                buffer[count++] = cur.uy;
                buffer[count++] = cur.uz;
                buffer[count++] = 1;
                buffer[count++] = 1;

                if (prev != null) {
                    indices[num_tris] = num_verts;
                    indices[num_tris+1] = num_verts+1;
                    indices[num_tris+2] = num_verts+2;

                    num_tris += 3;

                    indices[num_tris] = num_verts+1;
                    indices[num_tris+1] = num_verts+3;
                    indices[num_tris+2] = num_verts+2;

                    num_tris += 3;
                    num_verts += 2;
                }

                prev = cur;
                cur = cur.next;
            }
        }

        dprim.flush();
    }

    override function draw(ctx:h3d.scene.RenderContext) {
		//if( points.length >= 2 ) {
			absPos.identity();
			posChanged = true;
			ctx.uploadParams();
			super.draw(ctx);
		//}
	}
}


class Trails extends Object3D {
	function new(?parent) {
		super(parent);
	}

	public function create( ?parent : h3d.scene.Object ) {
		var tr = new TrailObj(parent);
		//tr.load(data);
		applyTransform(tr);
		tr.name = name;
		return tr;
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		var tr = create(ctx.local3d);
		ctx.local3d = tr;
		return ctx;
	}

	static var _ = Library.register("trails", Trails);
}
