package hrt.prefab.l3d;

import h3d.scene.MeshBatch;
import h3d.scene.Mesh;
import hrt.prefab.l3d.Spline.SplinePoint;

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
			var t = (pos - (s1 * stepSize)) / stepSize;
			t.saturate();
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

class SplineMesh extends Spline {

	var meshPath : String;
	var meshes : Array<h3d.scene.Mesh> = [];

	var splineUVx : Bool = false;
	var splineUVy : Bool = false;

	var spacing: Float = 0.0;
	var meshScale = new h3d.Vector(1,1,1);
	var meshRotation = new h3d.Vector(0,0,0);
	var modelMat = new h3d.Matrix();

	var meshBatch : h3d.scene.MeshBatch = null;
	var meshPrimitive : h3d.prim.MeshPrimitive = null;
	var meshMaterial : h3d.mat.Material = null;
	var customPass : String;

	override function save() {
		var obj : Dynamic = super.save();
		obj.meshPath = meshPath;
		obj.spacing = spacing;
		obj.meshScale = meshScale;
		obj.meshRotation = meshRotation;
		obj.splineUVx = splineUVx;
		obj.splineUVy = splineUVy;
		obj.customPass = customPass;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		meshPath = obj.meshPath;
		spacing = obj.spacing == null ? 0.0 : obj.spacing;
		meshScale = obj.meshScale == null ? new h3d.Vector(1,1,1) : new h3d.Vector(obj.meshScale.x, obj.meshScale.y, obj.meshScale.z);
		meshRotation = obj.meshRotation == null ? new h3d.Vector(0,0,0) : new h3d.Vector(obj.meshRotation.x, obj.meshRotation.y, obj.meshRotation.z);
		splineUVx = obj.splineUVx == null ? false : obj.splineUVx;
		splineUVy = obj.splineUVy == null ? false : obj.splineUVy;
		customPass = obj.customPass;
	}

	override function make(ctx: Context) {
		// Don't make children, which are used to setup the material
		return makeInstance(ctx);
	}

	override function makeInstance( ctx : hrt.prefab.Context ) : hrt.prefab.Context {
		var ctx = ctx.clone(this);
		ctx.local3d = new h3d.scene.Object(ctx.local3d);
		ctx.local3d.name = name;

		for( pd in pointsData ) {
			var sp = new SplinePoint(0, 0, 0, ctx.local3d);
			sp.setTransform(pd);
			sp.getAbsPos();
			points.push(sp);
		}
		pointsData = [];

		if( points == null || points.length == 0 )
			points.push(new SplinePoint(0,0,0, ctx.local3d));

		updateInstance(ctx);
		return ctx;
	}

	override function updateInstance( ctx : hrt.prefab.Context , ?propName : String ) {
		super.updateInstance(ctx, propName);

		var rot = new h3d.Matrix();
		rot.initRotation(hxd.Math.degToRad(meshRotation.x), hxd.Math.degToRad(meshRotation.y), hxd.Math.degToRad(meshRotation.z));
		var scale = new h3d.Matrix();
		scale.initScale(meshScale.x, meshScale.y, meshScale.z);
		modelMat.multiply(scale, rot);

		createMeshPrimitive(ctx);
		createMeshBatch(ctx);
		createBatches(ctx);

		// Remake the material
		if( meshBatch != null ) {
			var emptyCtx = new hrt.prefab.Context();
			emptyCtx.local3d = meshBatch;
			emptyCtx.shared = ctx.shared;
			for( c in @:privateAccess children ) {
				var mat = Std.downcast(c, Material);
				if( mat != null && mat.enabled )
					@:privateAccess mat.makeInstance(emptyCtx);
				var shader = Std.downcast(c, Shader);
				if( shader != null && shader.enabled )
					shader.makeInstance(emptyCtx);
			}
		}
	}

	function createMeshPrimitive( ctx : Context ) {
		meshPrimitive = null;
		meshMaterial = null;
		if( meshPath != null ) {
			var meshTemplate : h3d.scene.Mesh = ctx.loadModel(meshPath).toMesh();
			if( meshTemplate != null ) {
				meshPrimitive = cast meshTemplate.primitive;
				meshMaterial = cast meshTemplate.material.clone();
			}
		}
	}

	function createMeshBatch( ctx : Context ) {

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
					if( ctx.local3d.getScene().renderer.getPassByName(p) != null )
						splineMaterial.allocPass(p);
				}
			}

			meshBatch = new MeshBatch(meshPrimitive, splineMaterial, ctx.local3d);
			meshBatch.ignoreParentTransform = true;
		}
	}

	function createBatches( ctx : Context ) {

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

	function createMultiMeshes( ctx : Context ) {

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
			ctx.local3d.addChild(m);
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

	override function setSelected( ctx : hrt.prefab.Context , b : Bool ) {
		super.setSelected(ctx, b);
	}

	override function edit( ctx : EditContext ) {
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

	override function getHideProps() : HideProps {
		return { icon : "arrows-v", name : "SplineMesh" };
	}

	#end

	static var _ = hrt.prefab.Library.register("splineMesh", SplineMesh);
}