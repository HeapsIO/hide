package hrt.prefab2.l3d;

import h3d.scene.MeshBatch;
import h3d.scene.Mesh;
import hrt.prefab2.l3d.Spline.SplinePoint;

class SplineMeshShader extends hxsl.Shader {

	static var SRC = {
		@:import h3d.shader.BaseMesh;

		// Spline Infos
		@const(4096) var POINT_COUNT : Int;
		@const var SPLINE_UV_X : Bool;
		@const var SPLINE_UV_Y : Bool;
		@param var stepSize : Float;
		@param var points : Buffer<Vec4, POINT_COUNT>;

		// Instance Infos
		@param var modelMat : Mat4;
		@param var splinePos : Float;

		var calculatedUV : Vec2;

		function vertex() {

			var modelPos = relativePosition * modelMat.mat3x4();
			var pos = splinePos + modelPos.y;
			pos = clamp(pos, 0.0, POINT_COUNT * stepSize);
			var offsetY = pos - splinePos;

			// Linear Interpolation between two samples
			var s1 = clamp(floor(pos / stepSize), 0.0, POINT_COUNT - 1.0).int();
			var s2 = clamp(ceil(pos / stepSize), 0.0, POINT_COUNT - 1.0).int();
			var t = saturate((pos - (s1 * stepSize)) / stepSize);
			var point = mix(points[s1 * 2], points[s2 * 2], t).xyz;
			var tangent = mix(points[s1 * 2 + 1], points[s2 * 2 + 1], t).xyz;

			// Construct the new transform
			var worldUp = vec3(0,0,1);
			var front = -tangent;
			var right = -front.cross(worldUp).normalize();
			var up = front.cross(right).normalize();

			var rotation = mat4(	vec4(right.x, front.x, up.x, 0),
									vec4(right.y, front.y, up.y, 0),
									vec4(right.z, front.z, up.z, 0),
									vec4(0,0,0,1));

			var translation = mat4(	vec4(1,0,0, point.x ),
									vec4(0,1,0, point.y ),
									vec4(0,0,1, point.z ),
									vec4(0,0,0,1));

			var transform = rotation * translation;
			var localPos = (modelPos - vec3(0, offsetY, 0));
			transformedPosition = localPos * transform.mat3x4();
			transformedNormal = transformedNormal * modelMat.mat3x4() * rotation.mat3x4();

			if( SPLINE_UV_X )
				calculatedUV.x = pos;
			if( SPLINE_UV_Y )
				calculatedUV.y = pos;
		}
	}
}

enum SplineMeshMode {
	MultiMesh;
	Instanced;
	BigGeometry;
}

// Need to dipose the GPU buffer manually
class SplineMeshBatch extends h3d.scene.MeshBatch {

	public var splineData : Spline.SplineData;

	override function onRemove() {
		super.onRemove();
		var splinemeshShader = material.mainPass.getShader(SplineMeshShader);
		if( splinemeshShader != null ) {
			splinemeshShader.points.dispose();
		}
	}

	override function sync(ctx) {
		super.sync(ctx);
		var s = material.mainPass.getShader(SplineMeshShader);
		if( s != null && s.points == null || s.points.isDisposed() ) {
			var bufferData = new hxd.FloatBuffer(s.POINT_COUNT * 4 * 2);
			for( i in 0 ... splineData.samples.length ) {
				var index = i * 2 * 4;
				var s = splineData.samples[i];
				bufferData[index] = s.pos.x; bufferData[index + 1] = s.pos.y; bufferData[index + 2] = s.pos.z; bufferData[index + 3] = 0.0;
				bufferData[index + 4] = s.tangent.x; bufferData[index + 5] = s.tangent.y; bufferData[index + 6] = s.tangent.z; bufferData[index + 7] = 0.0;
			}
			s.points = new h3d.Buffer(s.POINT_COUNT * 2, 4, [UniformBuffer,Dynamic]);
			s.points.uploadVector(bufferData, 0, s.points.vertices, 0);
		}
	}

}

class SplineMesh extends Spline {

	@:s var meshPath : String;
	var meshes : Array<h3d.scene.Mesh> = [];

	@:s var splineUVx : Bool = false;
	@:s var splineUVy : Bool = false;

	@:s var spacing: Float = 0.0;
	@:c var meshScale = new h3d.Vector(1,1,1);
	@:c var meshRotation = new h3d.Vector(0,0,0);
	var modelMat = new h3d.Matrix();

	var meshBatch : SplineMeshBatch = null;
	var meshPrimitive : h3d.prim.MeshPrimitive = null;
	var meshMaterial : h3d.mat.Material = null;
	@:s var customPass : String;

	override function save(obj:Dynamic) : Dynamic {
		super.save(obj);
		obj.meshScale = meshScale;
		obj.meshRotation = meshRotation;
		return obj;
	}

	override function copy( obj : Dynamic ) {
		super.copy(obj);
		meshScale = obj.meshScale == null ? new h3d.Vector(1,1,1) : new h3d.Vector(obj.meshScale.x, obj.meshScale.y, obj.meshScale.z);
		meshRotation = obj.meshRotation == null ? new h3d.Vector(0,0,0) : new h3d.Vector(obj.meshRotation.x, obj.meshRotation.y, obj.meshRotation.z);
	}

	override function makeInstanceRec() : Void{
		if (!enabled) return;

		var old2d = shared.current2d;
		var old3d = shared.current3d;

		makeInstance();

		var new2d = Object2D.getLocal2d(this);
		if (new2d != null)
			shared.current2d = new2d;
		var new3d = Object3D.getLocal3d(this);
		if (new3d != null)
			shared.current3d = new3d;

		shared.current2d = old2d;
		shared.current3d = old3d;

		postMakeInstance();

		shared.current2d = old2d;
		shared.current3d = old3d;
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);

		var rot = new h3d.Matrix();
		rot.initRotation(hxd.Math.degToRad(meshRotation.x), hxd.Math.degToRad(meshRotation.y), hxd.Math.degToRad(meshRotation.z));
		var scale = new h3d.Matrix();
		scale.initScale(meshScale.x, meshScale.y, meshScale.z);
		modelMat.multiply(scale, rot);

		createMeshPrimitive();
		createMeshBatch();
		createBatches();

		// Remake the material
		if( meshBatch != null ) {
			for( c in @:privateAccess children ) {
				var mat = Std.downcast(c, Material);
				if( mat != null && mat.enabled )
					@:privateAccess mat.makeInstance();
				var shader = Std.downcast(c, Shader);
				if( shader != null && shader.enabled )
					shader.makeInstance();
			}
		}
	}

	function createMeshPrimitive() {
		meshPrimitive = null;
		meshMaterial = null;
		if( meshPath != null ) {
			var meshTemplate : h3d.scene.Mesh = shared.loadModel(meshPath).toMesh();
			if( meshTemplate != null ) {
				meshPrimitive = cast meshTemplate.primitive;
				meshMaterial = cast meshTemplate.material.clone();
			}
		}
	}

	function createMeshBatch() {

		if( meshBatch != null ) {
			meshBatch.remove();
			meshBatch = null;
		}

		if( meshPrimitive == null || (meshBatch != null && meshBatch.primitive == meshPrimitive) )
			return;

		if( meshBatch == null ) {
			var splineMaterial : h3d.mat.Material = meshMaterial;
			var splineMeshShader = createShader();
			splineMaterial.mainPass.addShader(splineMeshShader);
			splineMaterial.castShadows = false;

			if( customPass != null ) {
				for( p in customPass.split(",") ) {
					if( local3d.getScene().renderer.getPassByName(p) != null )
						splineMaterial.allocPass(p);
				}
			}

			meshBatch = new SplineMeshBatch(meshPrimitive, splineMaterial, local3d);
			meshBatch.ignoreParentTransform = true;
			meshBatch.splineData = this.data;
		}
	}

	function createBatches() {

		if( meshBatch == null )
			return;

		var localBounds = meshPrimitive.getBounds().clone();
		localBounds.transform(modelMat);
		var minOffset = hxd.Math.abs(localBounds.yMin);
		var step = (hxd.Math.abs(localBounds.yMax) + hxd.Math.abs(localBounds.yMin)) + spacing;
		var stepCount = hxd.Math.ceil((getLength() - minOffset) / step);

		if( stepCount > 4096 )
			return;

		meshBatch.begin(stepCount);
		var splinemeshShader = meshBatch.material.mainPass.getShader(SplineMeshShader);
		for( i in 0 ... stepCount ) {
			if( splinemeshShader != null )
				splinemeshShader.splinePos = i * step + minOffset;
			meshBatch.emitInstance();
		}
	}

	function createMultiMeshes() {

		for( m in meshes )
			m.remove();

		meshes = [];

		if( meshPrimitive == null )
			return;

		var localBounds = meshPrimitive.getBounds().clone();
		localBounds.transform(modelMat);
		var minOffset = hxd.Math.abs(localBounds.yMin);
		var step = (hxd.Math.abs(localBounds.yMax) + hxd.Math.abs(localBounds.yMin)) + spacing;

		var length = getLength();
		var stepCount = hxd.Math.ceil((length - minOffset) / step);
		for( i in 0 ... stepCount ) {
			var m = new h3d.scene.Mesh(meshPrimitive, cast meshMaterial.clone());
			m.material.castShadows = false;
			m.ignoreParentTransform = true;
			m.material.mainPass.culling = None;
			var s = createShader();
			m.material.mainPass.addShader(s);
			s.splinePos = i * step + minOffset;
			local3d.addChild(m);
			meshes.push(m);
		}
	}

	function createShader() {
		var s = new SplineMeshShader();
		s.POINT_COUNT = data.samples.length;
		s.stepSize = step;
		s.modelMat = modelMat;
		var bufferData = new hxd.FloatBuffer(s.POINT_COUNT * 4 * 2);
		for( i in 0 ... data.samples.length ) {
			var index = i * 2 * 4;
			var s = data.samples[i];
			bufferData[index] = s.pos.x; bufferData[index + 1] = s.pos.y; bufferData[index + 2] = s.pos.z; bufferData[index + 3] = 0.0;
			bufferData[index + 4] = s.tangent.x; bufferData[index + 5] = s.tangent.y; bufferData[index + 6] = s.tangent.z; bufferData[index + 7] = 0.0;
		}
		s.points = new h3d.Buffer(s.POINT_COUNT * 2, 4, [UniformBuffer,Dynamic]);
		s.points.uploadVector(bufferData, 0, s.points.vertices, 0);
		s.SPLINE_UV_X = splineUVx;
		s.SPLINE_UV_Y = splineUVy;
		return s;
	}

	#if editor

	override function edit( ctx : hide.prefab2.EditContext ) {
		super.edit(ctx);

		var props = new hide.Element('
			<div class="group" name="Material">
				<dl>
					<dt>Use spline UV on X</dt><dd><input type="checkbox" field="splineUVx"/></dd>
					<dt>Use spline UV on Y</dt><dd><input type="checkbox" field="splineUVy"/></dd>
					<dt>Custom Pass</dt><dd><input type="text" field="customPass"/></dd>
					<div align="center"><input type="button" value="Refresh" class="refresh"/></div>
				</dl>
			</div>
			<div class="group" name="Mesh">
				<dl>
					<dt>Mesh</dt><dd><input type="model" field="meshPath"/></dd>
					<dt>Spacing</dt><dd><input type="range" min="0" max="10" field="spacing"/></dd>
					<dt>Scale X</dt><dd><input type="range" min="0" max="5" value="1" field="meshScale.x"/></dd>
					<dt>Scale Y</dt><dd><input type="range" min="0" max="5" value="1" field="meshScale.y"/></dd>
					<dt>Scale Z</dt><dd><input type="range" min="0" max="5" value="1" field="meshScale.z"/></dd>
					<dt>Rotation X</dt><dd><input type="range" min="-180" max="180" value="0" field="meshRotation.x" /></dd>
					<dt>Rotation Y</dt><dd><input type="range" min="-180" max="180" value="0" field="meshRotation.y" /></dd>
					<dt>Rotation Z</dt><dd><input type="range" min="-180" max="180" value="0" field="meshRotation.z" /></dd>
				</dl>
			</div>
			');

		props.find(".refresh").click(function(_) { ctx.onChange(this, null); });
		ctx.properties.add(props, this, function(pname) { ctx.onChange(this, pname); });
	}

	override function getHideProps() : hide.prefab2.HideProps {
		return { icon : "arrows-v", name : "SplineMesh" };
	}

	#end

	static var _ = Prefab.register("splineMesh", SplineMesh);
}