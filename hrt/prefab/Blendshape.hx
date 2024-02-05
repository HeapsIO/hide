package hrt.prefab;

@:access(h3d.prim.HMDModel)
class BlendedPrimitive extends h3d.prim.HMDModel {
	public var weights : Array<Float> = [];
	public var index : Int;
	public var amount : Float;

	var debug : h3d.scene.Graphics;

	public function new(original : h3d.scene.Object) {
		debug = new h3d.scene.Graphics(original);

		var originalPrim = getPrim(original);
		super(originalPrim.data, originalPrim.dataPosition, originalPrim.lib);
		if ( originalPrim.data.vertexFormat.hasLowPrecision )
			throw "Blend shape doesn't support low precision";
	}

	public function update() {
		dispose();
	}

	function getPrim(o : h3d.scene.Object) {
		var originalMesh = Std.downcast(o, h3d.scene.Mesh);
		if ( originalMesh == null )
			throw "Should create Blend shape with mesh";
		var prim = Std.downcast(originalMesh.primitive, h3d.prim.HMDModel);
		if ( prim == null )
			throw "Can't create Blend shape if primitive is not an HMDModel";
		return prim;
	}

	override function alloc( engine : h3d.Engine ) {
		debug.clear();

		dispose();
		var is32 = data.vertexCount > 0x10000;
		var vertexFormat = data.vertexFormat;
		buffer = new h3d.Buffer(data.vertexCount, vertexFormat);

		var size = data.vertexCount * vertexFormat.strideBytes;
		var originalBytes = haxe.io.Bytes.alloc(size);
		lib.resource.entry.readBytes(originalBytes, 0, dataPosition + data.vertexPosition, size);

		var shapesBytes = [];
		var shapes = this.lib.header.shapes;
		weights = [];
		var inputMapping : Array<Map<String, Int>> = [];
		for ( s in 0...shapes.length ) {
			weights[s] = s == index ? amount : 0.0;
			var s = shapes[s];
			var size = s.vertexCount * s.vertexFormat.strideBytes;
			var vertexBytes = haxe.io.Bytes.alloc(size);
			lib.resource.entry.readBytes(vertexBytes, 0, dataPosition + s.vertexPosition, size);
			size = s.vertexCount << (is32 ? 2 : 1);
			var indexBytes = haxe.io.Bytes.alloc(size);
			lib.resource.entry.readBytes(indexBytes, 0, dataPosition + s.indexPosition, size);
			size = data.vertexCount << 2;
			var remapBytes = haxe.io.Bytes.alloc(size);
			lib.resource.entry.readBytes(remapBytes, 0, dataPosition + s.remapPosition, size);
			shapesBytes.push({ vertexBytes : vertexBytes, indexBytes : indexBytes, remapBytes : remapBytes});
			inputMapping.push(new Map());
		}
		for ( input in vertexFormat.getInputs() ) {
			for ( s in 0...shapes.length ) {
				var offset = 0;
				for ( i in shapes[s].vertexFormat.getInputs() ) {
					if ( i.name == input.name )
						inputMapping[s].set(i.name, offset);
					offset += i.type.getSize();
				}
			}
		}
		var p = 0;
		var blendIndexes = [];
		for ( i in 0...shapes.length ) {
			var idx = [];
			if ( is32 ) {
				for ( id in 0...shapesBytes[i].indexBytes.length >> 2 ) {
					idx.push(shapesBytes[i].indexBytes.getInt32(id << 2));
				}
			} else {
				for ( id in 0...shapesBytes[i].indexBytes.length >> 1 ) {
					idx.push(shapesBytes[i].indexBytes.getUInt16(id << 1));
				}
			}
			blendIndexes.push(idx);
		}
		var indexRemap = [for ( i in shapes ) 0];
		var bytes = haxe.io.Bytes.alloc(originalBytes.length);
		var count = 0;
		var countN = 0;
		var pos = new h3d.col.Point(0,0,0);
		var normal = new h3d.col.Point(0,0,0);

		for ( vid in 0...data.vertexCount ) {
			for ( i in 0...shapes.length ) {
				var remap = shapesBytes[i].remapBytes.getInt32(vid << 2) - 1;
				if ( remap < 0 )
					indexRemap[i] = -1;
				else {
					indexRemap[i] = blendIndexes[i].contains(remap) ? blendIndexes[i].indexOf(remap) : -1;
				}
			}
			for ( input in data.vertexFormat.getInputs() ) {
				for ( k in 0...input.type.getSize() ) {
					var k = k;
					var original = originalBytes.getFloat(p << 2);
					var f = original;
					var e = original;

					for ( i in 0...shapes.length ) {
						var indexBlendShape = indexRemap[i];

						if ( indexBlendShape < 0 )
							continue;

						var mapping = inputMapping[i].get(input.name);
						if ( mapping == null )
							continue;

						var floatId = indexBlendShape * shapes[i].vertexFormat.stride + k + mapping;
						var shapeFloat = shapesBytes[i].vertexBytes.getFloat(floatId << 2);
						if (weights[i] != 0)
							trace(shapeFloat);
						f = hxd.Math.lerp(f, original + shapeFloat, weights[i]);
					}
					bytes.setFloat(p << 2, f);

					// Normals debug
					if (input.name == "position") {
						if (count == 0)
							pos.x = f - 3;
						else if (count == 1)
							pos.y = f;
						else if (count == 2)
							pos.z = f;

						count++;

						if (count == 3)
							count = 0;
					}

					if (input.name == "normal") {
						if (countN == 0)
							normal.x = f;
						else if (countN == 1)
							normal.y = f;
						else if (countN == 2)
							normal.z = f;

						countN++;

						if (countN == 3) {
							countN = 0;
							drawDebugNormal(pos, normal.normalized() * 0.1);
						}
					}

					p++;
				}
			}
		}
		buffer.uploadBytes(bytes, 0, data.vertexCount);

		indexCount = 0;
		indexesTriPos = [];
		for( n in data.indexCounts ) {
			indexesTriPos.push(Std.int(indexCount/3));
			indexCount += n;
		}
		indexes = new h3d.Indexes(indexCount, is32);
		var size = (is32 ? 4 : 2) * indexCount;
		var bytes = lib.resource.entry.fetchBytes(dataPosition + data.indexPosition, size);
		indexes.uploadBytes(bytes, 0, indexCount);
	}

	override function getDataBuffers(fmt, ?defaults, ?material) {
		throw "";
		return null;
	}

	function drawDebugNormal(origin : h3d.Vector, normal : h3d.Vector) {
		debug.lineStyle(1.0, 0xE600DA, 1);

		var pointA = new h3d.col.Point(origin.x, origin.y, origin.z);
		var pointB = new h3d.col.Point(origin.x + normal.x, origin.y + normal.y, origin.z + normal.z);

		debug.drawLine(pointA, pointB);
	}
}

class BlendShape extends hrt.prefab.Model {

	@:s var shape : String;
	@:s var amount : Float = 1.0;
	@:s var index : Int = 0;

	public function new(parent, shared: ContextShared) {
		super(parent, shared);
	}

	override function makeObject(parent3d:h3d.scene.Object):h3d.scene.Object {
		return super.makeObject(parent3d);
	}

	override function updateInstance(?propName : String) {
		super.updateInstance();

		local3d.removeChildren();

		var blendedPrim = new BlendedPrimitive(local3d);
		blendedPrim.amount = amount;
		blendedPrim.index = index;
		blendedPrim.update();
		//var parentMesh = cast(ctx.local3d, h3d.scene.Mesh);
		var blended = new h3d.scene.Mesh(null, null, local3d);
		blended.x += -3;
		blended.primitive = blendedPrim;
		for ( m in local3d.getMaterials() )
			for ( p in m.getPasses() )
				p.culling = None;
	}

	#if editor
	override function edit( ectx : hide.prefab.EditContext ) {
		super.edit(ectx);
		var props = ectx.properties.add(new hide.Element('
		<div class="group" name="Shapes">
			<dt>Amount</dt><dd><input type="range" min="0" max="1" field="amount"/></dd>
			<dt>Index</dt><dd><input type="range" min="0" max="3" step="1" field="index"/></dd>
		</div>
		'), this, function(pname) {
			ectx.onChange(this, pname);
		});
	}

	override function getHideProps() : hide.prefab.HideProps {
		return {
			icon : "cube", name : "BlendShape", fileSource : ["fbx","hmd"],
			onResourceRenamed : function(f) animation = f(animation),
		};
	}
	#end

	static var _ = Prefab.register("blendShape", BlendShape);
}