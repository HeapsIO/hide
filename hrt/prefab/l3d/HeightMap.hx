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
		@param var cellSize : Vec2;
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
					transformedNormal = (n.normalize() * global.modelView.mat3()).normalize();
				}
			}
		}

		function __init__fragment() {
			if( hasNormal )
				transformedNormal = (unpackNormal(normalMap.get(calculatedUV)) * global.modelView.mat3()).normalize();
		}

	};
}

class HeightMap extends Object3D {

	var textures : Array<{ path : String, kind : HeightMapTextureKind, enable : Bool }> = [];
	var size = 128.;
	var heightScale = 0.2;

	override function save():{} {
		var o : Dynamic = super.save();
		o.textures = [for( t in textures ) { path : t.path, kind : t.kind }];
		o.size = size;
		o.heightScale = heightScale;
		return o;
	}

	override function load(obj:Dynamic) {
		super.load(obj);
		textures = [for( o in (obj.textures:Array<Dynamic>) ) { path : o.path, kind : o.kind, enable : true }];
		size = obj.size;
		heightScale = obj.heightScale;
	}

	function getTextures( ctx : Context, k : HeightMapTextureKind ) {
		return [for( t in textures ) if( t.kind == k && t.path != null && t.enable ) ctx.loadTexture(t.path)];
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

		var mesh = cast(ctx.local3d, h3d.scene.Mesh);
		var grid = cast(mesh.primitive, HeightGrid);

		var hmap = getTextures(ctx,Height)[0];
		var width = hmap == null ? Std.int(size) : hmap.width;
		var height = hmap == null ? Std.int(size) : hmap.height;
		var cw = size/width, ch = size/height;
		if( grid == null || grid.width != width || grid.height != height || grid.cellWidth != cw || grid.cellHeight != ch ) {
			grid = new HeightGrid(width,height,cw,ch);
			grid.addUVs();
			grid.addNormals();
			mesh.primitive = grid;
		}

		var albedo = getTextures(ctx, Albedo);
		mesh.material.texture = albedo.length == 1 ? albedo[0] : null;

		var normal = getTextures(ctx,Normal)[0];

		var shader = mesh.material.mainPass.getShader(HeightMapShader);
		shader.hasHeight = hmap != null;
		shader.heightMap = hmap;
		shader.hasNormal = normal != null;
		shader.normalMap = normal;
		shader.heightScale = heightScale * size;
		shader.cellSize.set(cw,ch);
		if( hmap != null ) shader.heightOffset.set(1 / hmap.width,1 / hmap.height);
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
			</dl>
			<div class="group" name="Textures">
			<ul></ul>
			</div>
		');
		var list = props.find("ul");
		ectx.properties.add(props,this, (_) -> updateInstance(ctx));
		for( tex in textures ) {
			var e = new hide.Element('<li>
				<input type="texturepath" field="path"/>
				<select field="kind" style="width:80px">
					<option value="albedo">Albedo
					<option value="height">Height
					<option value="normal">Normal
					<option value="splatmap">SplatMap
					<option value="delete">-- Delete --
				</select>
				<input type="checkbox" field="enable"/>
			</li>
			');
			e.appendTo(list);
			ectx.properties.build(e, tex, (_) -> {
				if( ""+tex.kind == "delete" ) {
					textures.remove(tex);
					ectx.rebuildProperties();
				}
				updateInstance(ctx);
			});
		}
		var add = new hide.Element('<li><a href="#">[+]</a></li>');
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
