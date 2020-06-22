package hrt.prefab.l3d;

enum abstract HeightMapTextureKind(String) {
	var Albedo = "albedo";
	var Height = "height";
	var Normal = "normal";
	var SplatMap = "splatmap";
}

class HeightMapShader extends hxsl.Shader {
	static var SRC = {
		@:import h3d.shader.BaseMesh;

		@const var hasHeight : Bool;
		@const var hasNormal : Bool;

		@param var heightMap : Sampler2D;
		@param var normalMap : Sampler2D;
		@param var heightScale : Float;
		@param var heightOffset : Vec2;
		@param var normalScale : Float;
		@param var cellSize : Vec2;

		@const var SplatCount : Int;
		@param var splats : Array<Sampler2D,SplatCount>;
		@param var albedos : Array<Sampler2D,SplatCount>;

		@input var input2 : { uv : Vec2 };

		var calculatedUV : Vec2;

		function getPoint( dx : Float, dy : Float ) : Vec3 {
			var v = vec2(dx,dy);
			return vec3( cellSize * v , heightMap.get(calculatedUV + heightOffset * v).r * heightScale - relativePosition.z);
		}

		function vertex() {
			calculatedUV = input2.uv;
			if( hasHeight ) {
				var z = heightMap.get(calculatedUV).x * heightScale;
				relativePosition.z = z;

				// calc normal
				if( !hasNormal ) {
					var px0 = getPoint(-1,0);
					var py0 = getPoint(0, -1);
					var px1 = getPoint(1, 0);
					var py1 = getPoint(0, 1);
					var n = px1.cross(py1) + py1.cross(px0) + px0.cross(py0) + py0.cross(px1);
					n.z *= normalScale;
					transformedNormal = (n.normalize() * global.modelView.mat3()).normalize();
				}
			}
		}

		function __init__fragment() {
			if( hasNormal ) {
				var n = unpackNormal(normalMap.get(calculatedUV));
				n.z *= normalScale;
				transformedNormal = (n * global.modelView.mat3()).normalize();
			}
			if( SplatCount > 0 ) {
				var color = pixelColor;
				for( i in 0...SplatCount )
					color = mix( color, albedos[i].get(calculatedUV), splats[i].get(calculatedUV).rrrr );
				color.a = 1;
				pixelColor = color;
			}
		}

	};
}

class HeightMap extends Object3D {

	var textures : Array<{ path : String, kind : HeightMapTextureKind, enable : Bool }> = [];
	var size = 128.;
	var heightScale = 0.2;
	var normalScale = 1.;
	var tileX = 1;
	var tileY = 1;
	var heightTexturesCache : Array<hxd.Pixels>;

	override function save():{} {
		var o : Dynamic = super.save();
		o.textures = [for( t in textures ) { path : t.path, kind : t.kind }];
		o.size = size;
		o.heightScale = heightScale;
		o.normalScale = normalScale;
		if( o.tileX != 1 || o.tileY != 1 ) {
			o.tileX = tileX;
			o.tileY = tileY;
		}
		return o;
	}

	override function load(obj:Dynamic) {
		super.load(obj);
		textures = [for( o in (obj.textures:Array<Dynamic>) ) { path : o.path, kind : o.kind, enable : true }];
		size = obj.size;
		heightScale = obj.heightScale;
		normalScale = obj.normalScale;
		if( obj.tileX != null ) {
			tileX = obj.tileX;
			tileY = obj.tileY;
		} else {
			tileX = 1;
			tileY = 1;
		}
	}

	override function localRayIntersection(ctx:Context, ray:h3d.col.Ray):Float {
		if( ray.lz > 0 )
			return -1; // only from top
		var maxZ = getHScale() * 100;
		var b = h3d.col.Bounds.fromValues(0,0,0,size * tileX, size * tileY, maxZ);
		var dist = b.rayIntersection(ray, false);
		if( dist < 0 )
			return -1;
		var prim = cast(ctx.local3d.toMesh().primitive, HeightGrid);
		var pt = ray.getPoint(dist);
		var m = hxd.Math.min(prim.cellWidth, prim.cellHeight) * 0.5;
		var isTiled = tileX != 1 || tileY != 1;
		var curX = -1, curY = -1, curMap = null, offX = 0., offY = 0., cw = 0., ch = 0.;
		if( !isTiled ) {
			curX = 0;
			curY = 0;
			curMap = getHeightMap(0,0);
			cw = curMap.width / size;
			ch = curMap.height / size;
		}
		var prevH = pt.z;
		var hscale = getHScale();
		while( true ) {
			pt.x += ray.lx * m;
			pt.y += ray.ly * m;
			pt.z += ray.lz * m;
			if( !b.contains(pt) )
				break;
			if( isTiled ) {
				var px = Std.int(pt.x / size);
				var py = Std.int(pt.y / size);
				if( px != curX || py != curY ) {
					curX = px;
					curY = py;
					offX = -px * size;
					offY = -py * size;
					curMap = getHeightMap(px, py);
					cw = curMap.width / size;
					ch = curMap.height / size;
				}
			}
			var ix = Std.int((pt.x + offX)*cw);
			var iy = Std.int((pt.y + offY)*ch);
			var h = curMap.bytes.getFloat( (ix + iy * curMap.width) << 2 );
			h *= hscale;
			if( pt.z < h ) {
				// todo : fix interpolation using getZ dichotomy
				var k = 1 - (prevH - (pt.z - ray.lz * m)) / (ray.lz * m - (h - prevH));
				pt.x -= k * ray.lx * m;
				pt.y -= k * ray.ly * m;
				pt.z -= k * ray.lz * m;
				return pt.sub(ray.getPos()).length();
			}
			prevH = h;
		}
		return -1;
	}

	function getHeightMap( x : Int, y : Int ) {
		var id = x + y * tileX;
		if( heightTexturesCache == null )
			heightTexturesCache = [];
		else {
			var b = heightTexturesCache[id];
			if( b != null ) return b;
		}
		var pix : hxd.Pixels = null;
		for( t in textures )
			if( t.kind == Height && t.enable && t.path != null ) {
				var path = resolveTexturePath(t.path, x, y);
				pix = try hxd.res.Loader.currentInstance.load(path).toImage().getPixels() catch( e : hxd.res.NotFound ) null;
				break;
			}
		if( pix == null ) pix = hxd.Pixels.alloc(1, 1, R32F);
		pix.convert(R32F);
		heightTexturesCache[id] = pix;
		return pix;
	}

	function resolveTexturePath( path : String, x : Int, y : Int ) {
		if( x != 0 && y != 0 ) {
			var parts = path.split("0");
			switch( parts.length ) {
			case 2:
				path = x + parts[0] + y + parts[1];
			case 3:
				path = parts[0] + x + parts[1] + y + parts[2];
			default:
				// pattern not recognized - should contain 2 zeroes
			}
		}
		return path;
	}

	function getTextures( ctx : Context, k : HeightMapTextureKind, x : Int, y : Int ) {
		var tl = [];
		for( t in textures )
			if( t.kind == k && t.path != null && t.enable ) {
				var path = resolveTexturePath(t.path,x,y);
				tl.push(ctx.loadTexture(path));
			}
		return tl;
	}

	override function makeInstance(ctx:Context):Context {
		ctx = ctx.clone(this);
		var mesh = new h3d.scene.Mesh(null, ctx.local3d);
		mesh.material.mainPass.addShader(new HeightMapShader());
		ctx.local3d = mesh;
		ctx.local3d.name = name;
		updateInstance(ctx);
		return ctx;
	}

	override function updateInstance( ctx : Context, ?propName : String ) {
		super.updateInstance(ctx, propName);

		heightTexturesCache = null;

		var mesh = cast(ctx.local3d, h3d.scene.Mesh);
		var grid = cast(mesh.primitive, HeightGrid);

		var hmap = getTextures(ctx,Height, 0, 0)[0];
		var width = hmap == null ? Std.int(size) : hmap.width;
		var height = hmap == null ? Std.int(size) : hmap.height;
		var cw = size/width, ch = size/height;
		if( grid == null || grid.width != width || grid.height != height || grid.cellWidth != cw || grid.cellHeight != ch ) {
			grid = new HeightGrid(width,height,cw,ch);
			grid.addUVs();
			grid.addNormals();
			mesh.primitive = grid;
		}
		updateMesh(ctx, mesh, 0, 0);
		var prev = new Map();
		for( c in mesh )
			if( c.name != null && c.name.charCodeAt(0) == '$'.code )
				prev.set(c.name, c.toMesh());
		for( x in 0...tileX ) {
			for( y in 0...tileY ) {
				var name = "$h_"+x+"_"+y;
				var sub = prev.get(name);
				if( sub == null ) {
					sub = new h3d.scene.Mesh(mesh.primitive, mesh);
					sub.name = name;
					sub.material.mainPass.addShader(new HeightMapShader());
				} else
					prev.remove(name);
				sub.x = x * (width * cw);
				sub.y = y * (height * ch);
				updateMesh(ctx, sub, x, y);
			}
		}
		for( p in prev ) p.remove();
	}

	function getHScale() {
		return heightScale * size * 0.1;
	}

	function updateMesh( ctx : Context, mesh : h3d.scene.Mesh, x : Int, y : Int ) {
		inline function getTextures(k) return this.getTextures(ctx,k,x,y);

		var prim = cast(mesh.primitive, HeightGrid);
		var hmap = getTextures(Height)[0];
		var splat = getTextures(SplatMap);
		var albedo = getTextures(Albedo);
		var normal = getTextures(Normal)[0];
		mesh.material.texture = albedo.shift();

		var shader = mesh.material.mainPass.getShader(HeightMapShader);
		shader.hasHeight = hmap != null;
		shader.heightMap = hmap;
		shader.hasNormal = normal != null;
		shader.normalMap = normal;
		shader.heightScale = getHScale();
		shader.normalScale = 1 / normalScale;
		shader.cellSize.set(prim.cellWidth,prim.cellHeight);
		if( hmap != null ) shader.heightOffset.set(1 / hmap.width,1 / hmap.height);

		var scount = hxd.Math.imin(splat.length, albedo.length);
		shader.SplatCount = scount;
		shader.splats = [for( i in 0...scount ) splat[i]];
		shader.albedos = [for( i in 0...scount ) albedo[i]];
	}

	#if editor
	override function edit(ectx:EditContext) {
		super.edit(ectx);
		var ctx = ectx.getContext(this);
		var props = new hide.Element('
			<div class="group" name="View">
			<dl>
				<dt>Size</dt><dd><input type="range" min="0" max="1000" value="128" field="size"/></dd>
				<dt>Height Scale</dt><dd><input type="range" min="0" max="1" field="heightScale"/></dd>
				<dt>Normal Scale</dt><dd><input type="range" min="0" max="2" field="normalScale"/></dd>
			</dl>
			<div class="group" name="Textures">
			<ul></ul>
			</div>
			<div class="group" name="Tiling">
			<dl>
				<dt>X</dt><dd><input type="range" min="1" max="16" step="1" field="tileX"/></dd>
				<dt>Y</dt><dd><input type="range" min="1" max="16" step="1" field="tileY"/></dd>
			</dl>
			</div>
		');
		var list = props.find("ul");
		ectx.properties.add(props,this, (_) -> updateInstance(ctx));
		for( tex in textures ) {
			var prevTex = tex.path;
			var e = new hide.Element('<li style="position:relative">
				<input type="checkbox" field="enable"/>
				<input type="texturepath" style="width:165px" field="path"/>
				<select field="kind" style="width:70px">
					<option value="albedo">Albedo
					<option value="height">Height
					<option value="normal">Normal
					<option value="splatmap">SplatMap
					<option value="delete">-- Delete --
				</select>
				<a href="#" class="up">🡅</a>
				<a href="#" class="down">🡇</a>
			</li>
			');
			e.find(".up").click(function(_) {
				var index = textures.indexOf(tex);
				if( index <= 0 ) return;
				textures.remove(tex);
				textures.insert(index-1, tex);
				ectx.rebuildProperties();
				updateInstance(ctx);
			});
			e.find(".down").click(function(_) {
				var index = textures.indexOf(tex);
				textures.remove(tex);
				textures.insert(index+1, tex);
				ectx.rebuildProperties();
				updateInstance(ctx);
			});
			e.appendTo(list);
			ectx.properties.build(e, tex, (_) -> {
				if( tex.path != prevTex ) {
					tex.enable = true; // enable on change texture !
					prevTex = tex.path;
				}
				if( ""+tex.kind == "delete" ) {
					textures.remove(tex);
					ectx.rebuildProperties();
				}
				updateInstance(ctx);
			});
		}
		var add = new hide.Element('<li><p><a href="#">[+]</a></p></li>');
		add.appendTo(list);
		add.find("a").click(function(_) {
			textures.push({ path : null, kind : Albedo, enable: true });
			ectx.rebuildProperties();
		});
	}
	#end

	static var _ = Library.register("heightmap", HeightMap);

}


class HeightGrid extends h3d.prim.MeshPrimitive {

	/**
		The number of cells in width
	**/
	public var width (default, null) : Int;

	/**
		The number of cells in height
	**/
	public var height (default, null)  : Int;

	/**
		The width of a cell
	**/
	public var cellWidth (default, null) : Float;

	/**
		The height of a cell
	**/
	public var cellHeight (default, null)  : Float;

	var hasNormals : Bool;
	var hasUVs : Bool;

	public function new( width : Int, height : Int, cellWidth = 1., cellHeight = 1. ) {
		this.width = width;
		this.height = height;
		this.cellWidth = cellWidth;
		this.cellHeight = cellHeight;
	}

	public function addNormals() {
		hasNormals = true;
	}

	public function addUVs() {
		hasUVs = true;
	}

	override function getBounds():h3d.col.Bounds {
		return h3d.col.Bounds.fromValues(0,0,0,width*cellWidth,height*cellHeight,0);
	}

	override function alloc(engine:h3d.Engine) {
		dispose();
		var size = 3;
		var names = ["position"];
		var positions = [0];
		if( hasNormals ) {
			names.push("normal");
			positions.push(size);
			size += 3;
		}
		if( hasUVs ) {
			names.push("uv");
			positions.push(size);
			size += 2;
		}

		var buf = new hxd.FloatBuffer((width + 1) * (height +  1) * size);
		var p = 0;
		for( y in 0...height + 1 )
			for( x in 0...width + 1 ) {
				buf[p++] = x * cellWidth;
				buf[p++] = y * cellHeight;
				buf[p++] = 0;
				if( hasNormals ) {
					buf[p++] = 0;
					buf[p++] = 0;
					buf[p++] = 1;
				}
				if( hasUVs ) {
					buf[p++] = x / width;
					buf[p++] = y / height;
				}
			}
		var flags : Array<h3d.Buffer.BufferFlag> = [LargeBuffer];
		buffer = h3d.Buffer.ofFloats(buf, size, flags);

		for( i in 0...names.length )
			addBuffer(names[i], buffer, positions[i]);

		indexes = new h3d.Indexes(width * height * 6, true);
		var b = haxe.io.Bytes.alloc(indexes.count * 4);
		var p = 0;
		for( y in 0...height )
			for( x in 0...width ) {
				var s = x + y * (width + 1);
				b.setInt32(p++ << 2, s);
				b.setInt32(p++ << 2, s + 1);
				b.setInt32(p++ << 2, s + width + 1);
				b.setInt32(p++ << 2, s + 1);
				b.setInt32(p++ << 2, s + width + 2);
				b.setInt32(p++ << 2, s + width + 1);
			}
		indexes.uploadBytes(b,0,indexes.count);
	}

}
