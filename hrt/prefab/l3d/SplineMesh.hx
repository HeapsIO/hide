package hrt.prefab.l3d;
import h3d.scene.MeshBatch;
import h3d.scene.Mesh;
import hrt.prefab.l3d.Spline.SplinePoint;

class SplineMeshShader extends hxsl.Shader {

	static var SRC = {
		@:import h3d.shader.BaseMesh;

		// Spline Infos
		@const(4096) var POINT_COUNT : Int;
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
			var s1 = floor(pos / stepSize).int();
			var s2 = ceil(pos / stepSize).int();
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
		}

		function fragment() {
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

	var spacing: Float = 0.0;
	var meshScale = new h3d.Vector(1,1,1);
	var meshRotation = new h3d.Vector(0,0,0);
	var modelMat = new h3d.Matrix();

	var meshBatch : h3d.scene.MeshBatch = null;
	var meshPrimitive : h3d.prim.MeshPrimitive = null;
	var meshMaterial : h3d.mat.Material = null;

	override function save() {
		var obj : Dynamic = super.save();
		obj.meshPath = meshPath;
		obj.spacing = spacing;
		obj.meshScale = meshScale;
		obj.meshRotation = meshRotation;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		meshPath = obj.meshPath;
		spacing = obj.spacing == null ? 0.0 : obj.spacing;
		meshScale = obj.meshScale == null ? new h3d.Vector(1,1,1) : obj.meshScale;
		meshRotation = obj.meshRotation == null ? new h3d.Vector(0,0,0) : obj.meshRotation;
	}

	override function makeInstance( ctx : hrt.prefab.Context ) : hrt.prefab.Context {

		var ctx = ctx.clone(this);
		ctx.local3d = new h3d.scene.Object(ctx.local3d);
		ctx.local3d.name = name;
		
		for( pd in pointsData ) {
			var sp = new SplinePoint(0, 0, 0, ctx.local3d);
			sp.setTransform(pd);
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

		// Remake the material
		for( c in @:privateAccess children ) {
			var mat = Std.downcast(c, Material);
			if( mat != null && mat.enabled ) 
				@:privateAccess mat.updateObject(ctx, meshBatch);
			var shader = Std.downcast(c, Shader);
			if( shader != null && shader.enabled ) 
				shader.makeInstance(ctx);
		}

		//createMultiMeshes(ctx);
	}

	function createMeshPrimitive( ctx : Context  ) {
		meshPrimitive = null;
		meshMaterial = null;
		if( meshPath != null ) {	
			var meshTemplate : h3d.scene.Mesh = ctx.loadModel(meshPath).toMesh();
			if( meshTemplate != null ) {
				meshPrimitive = cast meshTemplate.primitive;
				meshMaterial = meshTemplate.material;
			}
		}
	}

	function createMeshBatch( ctx : Context ) {

		if( meshPrimitive == null ) {
			if( meshBatch != null ) {
				meshBatch.remove();
				meshBatch = null;
			}
			return;
		}

		if( meshBatch != null /*&& meshBatch.primitive != meshPrimitive*/ ) {
			meshBatch.remove();
			meshBatch = null;
		}
	
		if( meshBatch == null ) {
			var material : h3d.mat.Material = cast meshMaterial.clone();
			var splinemeshShader = createShader();
			material.mainPass.addShader(splinemeshShader);
			material.castShadows = false;
			meshBatch = new MeshBatch(meshPrimitive, material, ctx.local3d);
			meshBatch.ignoreParentTransform = true;
		}

		var localBounds = meshPrimitive.getBounds().clone();
		localBounds.transform(modelMat);
		var minOffset = hxd.Math.abs(localBounds.yMin);
		var step = (hxd.Math.abs(localBounds.yMax) + hxd.Math.abs(localBounds.yMin)) + spacing;
		var stepCount = hxd.Math.ceil((getLength() - minOffset) / step);

		var splinemeshShader = meshBatch.material.mainPass.getShader(SplineMeshShader);
		
		meshBatch.begin(stepCount);
		for( i in 0 ... stepCount ) {
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
		for( s in data.samples ) {
			bufferData.push(s.pos.x); bufferData.push(s.pos.y); bufferData.push(s.pos.z); bufferData.push(0.0);
			bufferData.push(s.tangent.x); bufferData.push(s.tangent.y); bufferData.push(s.tangent.z); bufferData.push(0.0);
		}
		s.points = new h3d.Buffer(s.POINT_COUNT, 4 * 2, [UniformBuffer]);
		s.points.uploadVector(bufferData, 0, s.points.vertices, 0);
		return s;
	}

	#if editor

	override function setSelected( ctx : hrt.prefab.Context , b : Bool ) {
		super.setSelected(ctx, b);
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		ctx.properties.add( new hide.Element('
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
			'), this, function(pname) { ctx.onChange(this, pname); });
	}

	override function getHideProps() : HideProps {
		return { icon : "arrows-v", name : "SplineMesh" };
	}

	static var _ = hrt.prefab.Library.register("splineMesh", SplineMesh);
	#end
}