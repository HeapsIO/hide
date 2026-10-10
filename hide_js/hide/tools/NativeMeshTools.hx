package hide.tools;

#if dx12
import hlemu.Native in M;

/**
	The mesh processing of the FBX to HMD conversion with the heaps natives of HashLink (libs/heaps, compiled
	unmodified in bin/jsdx/dx12.node) instead of the meshTools executable : the HL code of hxd.tools.MeshTools,
	with the memory of hlemu.Native.
**/
class NativeMeshTools {

	static var prims : Dynamic;

	public static function init() {
		prims = js.Syntax.code("globalThis.__dx12");
		if( prims == null || prims.compute_mikkt_tangents == null ) return;
		hxd.tools.MeshTools.mikktspace = mikktspace;
		hxd.tools.MeshTools.optimize = optimize;
		hxd.tools.MeshTools.convexHulls = convexHulls;
	}

	static inline function addr( b : haxe.io.Bytes ) {
		return M.mem_address(b.getData());
	}

	static function mikktspace( vertices : haxe.io.Bytes, count : Int, stride : Int, xPos : Int, normalPos : Int, uvPos : Int, threshold = 180. ) {
		var tangents = haxe.io.Bytes.alloc(count << 4);
		for( i in 0...count )
			tangents.setFloat(i << 4, 1);
		var indexes = haxe.io.Bytes.alloc(count << 2);
		for( i in 0...count )
			indexes.setInt32(i << 2, i);
		// user_info of mikkt.c
		var m = haxe.io.Bytes.alloc(64);
		M.mem_set_i64(addr(m) + 8, addr(vertices));
		m.setInt32(16, stride);
		m.setInt32(20, xPos);
		m.setInt32(24, normalPos);
		m.setInt32(28, uvPos);
		M.mem_set_i64(addr(m) + 32, addr(tangents));
		m.setInt32(40, 4);
		m.setInt32(44, 0);
		M.mem_set_i64(addr(m) + 48, addr(indexes));
		m.setInt32(56, count);
		if( !prims.compute_mikkt_tangents(addr(m), threshold) )
			throw "assert";
		return tangents;
	}

	static function optimize( vertices : haxe.io.Bytes, vertexCount : Int, vertexSize : Int, indexes : haxe.io.Bytes, indexCount : Int, targetIndexCount = -1, targetError = 0. ) {
		var v = addr(vertices);
		var idx = addr(indexes);
		var remap = haxe.io.Bytes.alloc(vertexCount << 2);
		var uniqueVertexCount : Int = prims.generate_vertex_remap(addr(remap), idx, indexCount, v, vertexCount, vertexSize);
		prims.remap_index_buffer(idx, idx, indexCount, addr(remap));
		prims.remap_vertex_buffer(v, v, vertexCount, vertexSize, addr(remap));
		vertexCount = uniqueVertexCount;
		if( targetIndexCount >= 0 )
			indexCount = prims.simplify(idx, idx, indexCount, v, vertexCount, vertexSize, targetIndexCount, targetError, 1 | 8 /* LockBorder | Prune */, null);
		prims.optimize_vertex_cache(idx, idx, indexCount, vertexCount);
		prims.optimize_overdraw(idx, idx, indexCount, v, vertexCount, vertexSize, 1.05);
		vertexCount = prims.optimize_vertex_fetch(v, idx, indexCount, v, vertexCount, vertexSize);
		return { vertexCount : vertexCount, indexCount : indexCount };
	}

	static function convexHulls( vertices : haxe.io.Bytes, vertexCount : Int, indexes : haxe.io.Bytes, triangleCount : Int, maxConvexHulls : Int, resolution : Int ) : Array<hxd.tools.MeshTools.ConvexHullData> {
		// VHACD::IVHACD::Parameters, with the values of hxd.tools.VHACD.Parameters
		var p = haxe.io.Bytes.alloc(72);
		p.setInt32(24, maxConvexHulls);
		p.setInt32(28, resolution);
		p.setDouble(32, 1);
		p.setInt32(40, 10);
		p.set(44, 1);
		p.setInt32(48, 0);
		p.setInt32(52, 64);
		p.set(56, 0);
		p.setInt32(60, 2);
		p.set(64, 0);
		var vhacd = prims.create_vhacd();
		prims.vhacd_compute(vhacd, addr(vertices), vertexCount, addr(indexes), triangleCount, addr(p));
		var count : Int = prims.vhacd_get_n_convex_hulls(vhacd);
		var out = count == 0 ? null : [];
		// convex_hull of vhacd.cpp
		var hull = haxe.io.Bytes.alloc(112);
		for( i in 0...count ) {
			prims.vhacd_get_convex_hull(vhacd, i, addr(hull));
			var points = new js.lib.Float64Array(hull.getInt32(16) * 3);
			M.mem_copy(M.mem_address(points), M.mem_get_i64(addr(hull)), points.byteLength);
			var triangles = new js.lib.Int32Array(hull.getInt32(20) * 3);
			M.mem_copy(M.mem_address(triangles), M.mem_get_i64(addr(hull) + 8), triangles.byteLength);
			out.push({ vertices : [for( f in points ) f], indexes : [for( i in triangles ) i] });
		}
		prims.vhacd_release(vhacd);
		return out;
	}

}
#end
