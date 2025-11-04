package hrt.prefab.l3d;

class LocalVolumetricShader extends hxsl.Shader {

	static var SRC = {

		final EPSILON = 1e-4;
		final FLT_MAX = 3.402823466e+38;

		@global var depthMap : Channel;

		@global var camera : {
			var position : Vec3;
			var inverseViewProj : Mat4;
		};

		@global var global : {
			@perObject var modelView : Mat4;
			@perObject var modelViewInverse : Mat4;
		};

		@param var shape : Int;

		@param var obH : Vec3;

		@param var fogColor : Vec4;
		@param var fogDensity : Float;

		@param var cubeCornerRound : Float;
		@param var coneTipRadius : Float;

		var screenUV : Vec2;
		var transformedPosition : Vec3;
		var transformedNormal : Vec3;
		var pixelColor : Vec4;

		function maxComp(a : Vec3) : Float { return max(a.x, max(a.y, a.z)); }
		function minComp(a : Vec3) : Float { return min(a.x, min(a.y, a.z)); }

		function getPositionAt( uv: Vec2 ) : Vec3 {
			var depth = depthMap.get(uv);
			var uv2 = uvToScreen(uv);
			var temp = vec4(uv2, depth, 1) * camera.inverseViewProj;
			var originWS = temp.xyz / temp.w;
			return originWS;
		}

		function getPosition() : Vec3 {
			return getPositionAt(screenUV);
		}

		function rayBoxIntersection( o : Vec3, d : Vec3) : Vec3 {
			var m = 1.0/d;
			var n = m*o;
			var k = abs(m)*obH;
			var t1 = -n - k;
			var t2 = -n + k;
			var tN = maxComp(t1);
			var tF = minComp(t2);
			var hit = vec3(tN, tF, 1.0);
			if(tN>tF || tF<0.0) {
				hit = vec3(-1.0);
			}
			return hit;
		}

		function dot2(v : Vec3) : Float {
			return dot(v, v);
		}

		function rayCappedConeIntersection( o : Vec3, d : Vec3, he : Float, ra : Float, rb : Float) : Float {
			var ob = o - vec3(0.0, 0.0,he);

			var res = 0.0;
			var hit = false;
			//caps
			if( o.z<0.0 ) {
				if( dot2(o*d.z-d*o.z)<(ra*ra*d.z*d.z) ){
					res = -o.z/d.z;
					hit = true;
				}
			} else if( o.z>he ) {
				if( dot2(ob*d.z-d*ob.z)<(rb*rb*d.z*d.z) ) {
					res = -ob.z/d.z;
					hit = true;
				}
			}

			if(!hit) {
				// body
				var m4 = dot(d,o);
				var m5 = dot(o,o);
				var rr = ra - rb;
				var hz = he*he + rr*rr;

				var k2 = he*he    - d.z*d.z*hz;
				var k1 = he*he*m4 - o.z*d.z*hz + ra*(rr*he*d.z*1.0 );
				var k0 = he*he*m5 - o.z*o.z*hz + ra*(rr*he*o.z*2.0 - he*he*ra);

				var h = k1*k1 - k2*k0;
				if( h<0.0 ) {
					res = -1.0;
					hit = true;
				} else {
					var t = (-k1-sqrt(h))/k2;

					var z = o.z + t*d.z;
					if( z>0.0 && z<he )
					{
						res = t;
						hit = true;
					}
				}
			}

			return hit ? res : -1.0;
		}

		function intersectCone( o : Vec3, d : Vec3) : Vec3 {
			o.z += 0.5;
			var res = vec3(-1.0);
			var tN = rayCappedConeIntersection(o, d, 1.0, 0.5, coneTipRadius + 1e-4);

			var offset = max(tN,0.0) + 1.5;
			var oF = o + d * offset;
			var tF = rayCappedConeIntersection(oF, -d, 1.0, 0.5, coneTipRadius);
			if(tF > 0.0){
				tF = offset - tF;
			}

			if(tN > 0.0){
				res = vec3(tN, tF, 1.0);
			} else if(tF > 0.0){
				res = vec3(-1.0, tF, 1.0);
			} else {
				res = vec3(-1.0);
			}

			return res;
		}

		function getPath(o : Vec3, d : Vec3) : Vec4 {
			var dir = normalize(d);
			var hit = vec3(0.0);
			if(shape == 1){
				hit = intersectCone(o, dir);
			} else {
				hit = rayBoxIntersection(o, dir);
			}
			var path = vec4(o, -1.0);
			if(hit.z > 0.0){
				if(hit.x > 0.0){
					path = vec4(o+hit.x*dir, hit.y - hit.x);
				} else {
					path.w = hit.y;
				}
			}

			var backgroundLocalPosition = (vec4(getPosition(), 1.0) * global.modelViewInverse).xyz;
			var backgroundDist = length(backgroundLocalPosition-path.xyz);
			if(dot(dir, backgroundLocalPosition - path.xyz) < 0.0){
				backgroundDist = 0.0;
			}
			path.w = min(path.w, backgroundDist);
			return path;
		}

		function boxDistance(p : Vec3) : Float {
			var d = abs(p) - obH;
			return length(max(d,0.0)) + min(maxComp(d),0.0);
		}

		function boxDensity( o : Vec3, d : Vec3, t : Float) : Float{
			var ir2 = 1.0/(obH*obH);
			var a = 1.0 - (o*o)*ir2;
			var b =	    - 2.0*(o*d)*ir2;
			var c =     - (d*d)*ir2;

			var t1 = t;
			var t2 = t1*t1;
			var t3 = t2*t1;
			var t4 = t2*t2;
			var t5 = t2*t3;
			var t6 = t3*t3;
			var t7 = t3*t4;

			var f = (t1/1.0) *(a.x*a.y*a.z) +
					  (t2/2.0) *(a.x*a.y*b.z + a.x*b.y*a.z + b.x*a.y*a.z) +
					  (t3/3.0) *(a.x*a.y*c.z + a.x*b.y*b.z + a.x*c.y*a.z + b.x*a.y*b.z + b.x*b.y*a.z + c.x*a.y*a.z) +
					  (t4/4.0) *(a.x*b.y*c.z + a.x*c.y*b.z + b.x*a.y*c.z + b.x*b.y*b.z + b.x*c.y*a.z + c.x*a.y*b.z + c.x*b.y*a.z) +
					  (t5/5.0) *(a.x*c.y*c.z + b.x*b.y*c.z + b.x*c.y*b.z + c.x*a.y*c.z + c.x*b.y*b.z + c.x*c.y*a.z) +
					  (t6/6.0) *(b.x*c.y*c.z + c.x*b.y*c.z + c.x*c.y*b.z) +
					  (t7/7.0) *(c.x*c.y*c.z);

			return f;
		}

		function sampleFog(pos : Vec3, dir : Vec3, dist : Float) : Float {
			var density = fogDensity;
			if(shape == 0){
				density = clamp(fogDensity * boxDensity(pos, dir, dist) / cubeCornerRound, 0.0, fogDensity);
			}
			return density;
		}

		function integrateShape(pos : Vec3, dir: Vec3, dist : Float, integrationValues : Vec4) : Vec4 {
			var extinction = sampleFog(pos, dir, dist/length(dir));
			var clampedExtinction = max(extinction, 1e-5);
			var transmittance = exp(-extinction*dist);
			var integScatt = fogColor.rgb;

			integrationValues.rgb += integrationValues.a * integScatt;
			integrationValues.a *= transmittance;

			return integrationValues;
		}

		function evaluate() : Vec4 {
			var dir = normalize(transformedPosition - camera.position);
			var pos = camera.position;

			dir = dir * global.modelViewInverse.mat3();
			pos = (vec4(pos, 1) * global.modelViewInverse).xyz;

			var path = getPath(pos, dir);

			var integrationValues = vec4(0.0,0.0,0.0,1.0);
			return integrateShape(path.xyz, dir, path.w, integrationValues);
		}

		function fragment() {
			var volumetric = evaluate();
			volumetric.a = saturate(1.0 - volumetric.a);
			volumetric.a = volumetric.a > 1.0 - 1e-3 ? 1.0 : volumetric.a;
			pixelColor = volumetric;
		}
	}
}

class LocalVolumetricLightingObject extends h3d.scene.Object {

	public var localVolume : LocalVolumetricLighting;
	public var bounds : h3d.col.OrientedBounds;

	public var meshInside : h3d.scene.Mesh;
	public var meshOutside : h3d.scene.Mesh;
	public var boundsDisplay : h3d.scene.Graphics;

	public var shader : LocalVolumetricShader;

	public function new(parent:h3d.scene.Object, localVolume:LocalVolumetricLighting) {
		this.localVolume = localVolume;
		super(parent);
		bounds = new h3d.col.OrientedBounds();

		var prim = new h3d.prim.Cube(1,1,1,true);
		prim.addNormals();

		shader = new LocalVolumetricShader();

		meshInside = new h3d.scene.Mesh(prim, this);
		meshInside.visible = false;
		var materialInside = meshInside.material;
		materialInside.castShadows = false;
		meshInside.material.mainPass.setPassName("volumetricOverlay");
		meshInside.material.mainPass.setBlendMode(h3d.mat.BlendMode.Alpha);
		meshInside.material.mainPass.culling = Front;
		meshInside.material.mainPass.depthTest = Always;
		meshInside.material.mainPass.depthWrite = false;
		materialInside.mainPass.addShader(shader);

		meshOutside = new h3d.scene.Mesh(prim, this);
		var materialOutside = meshOutside.material;
		materialOutside.castShadows = false;
		meshOutside.material.mainPass.setPassName("volumetricOverlay");
		meshOutside.material.mainPass.setBlendMode(h3d.mat.BlendMode.Alpha);
		meshOutside.material.mainPass.culling = Back;
		meshOutside.material.mainPass.depthTest = Less;
		meshOutside.material.mainPass.depthWrite = false;
		materialOutside.mainPass.addShader(shader);

		refresh();
	}

	function isInside(ctx : h3d.scene.RenderContext) : Bool {
		function nearPlaneHalfDiag(cam : h3d.Camera) : Float {
			var v = cam.zNear * Math.tan(cam.fovY * 0.5);
			var h = v * cam.screenRatio;
			return Math.sqrt(v * v + h * h);
		}

		bounds.setMatrix(this.getAbsPos());
		var c = ctx.camera.pos.add(ctx.camera.getForward().scaled(ctx.camera.zNear));
		var s = new h3d.col.Sphere(c.x, c.y, c.z, nearPlaneHalfDiag(ctx.camera));
		return bounds.hasSphere(s);
	}

	override function sync(ctx : h3d.scene.RenderContext) {
		var inside = isInside(ctx);

		if(inside && !meshInside.visible)
		{
			meshOutside.visible = false;
			meshInside.visible = true;
		} else if(!inside && !meshOutside.visible){
			meshOutside.visible = true;
			meshInside.visible = false;
		}
	}

	public function refresh() {
		shader.obH.set(0.5, 0.5, 0.5);

		shader.shape = localVolume.shape;
		shader.coneTipRadius = localVolume.coneTipRadius * 0.5;

		shader.fogColor.setColor(localVolume.color);
		shader.fogDensity = localVolume.fogDensity;
		shader.cubeCornerRound = localVolume.cubeRoundCorner;

		if(localVolume.showBounds){
			boundsDisplay = bounds.makeDebugObj();
			boundsDisplay.lineStyle(2, 0xFFFFFF);
			addChild(boundsDisplay);
		} else if(boundsDisplay != null){
			removeChild(boundsDisplay);
			boundsDisplay = null;
		}
	}
}

class LocalVolumetricLighting extends hrt.prefab.Object3D {

	var localVolumeObject : LocalVolumetricLightingObject;

	@:s public var shape : Int = 0;

	@:s public var coneTipRadius : Float = 0.5;
	@:s public var cubeRoundCorner : Float = 0.0;

	@:s public var fogDensity : Float = 1.0;

	@:s public var color : Int = 0xFFFFFF;

	@:s public var showBounds : Bool = false;

	override public function copy(other:Prefab) {
		super.copy(other);
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		if(obj.fogFade != null){
			cubeRoundCorner = obj.fogFade;
		}
	}

	override function makeObject(parent3d: h3d.scene.Object) : h3d.scene.Object {
		localVolumeObject = new LocalVolumetricLightingObject(parent3d, this);
		return localVolumeObject;
	}

	override function updateInstance(?propName) {
		super.updateInstance(propName);
		localVolumeObject.refresh();
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		ctx.properties.add(new hide.Element('
			<p style="color: red;"> Use new editor </p>
		'), this);
	}
	#end

	override function edit2( ctx : hrt.prefab.EditContext2 ) {
		super.edit2(ctx);

		ctx.build(
			<root>
				<category("Shape")>
					<select([{"label":"Box","value":0},{"label":"Cone","value":1}]) field={shape} onValueChange={(_)->ctx.rebuildInspector()}/>
					<range(0,1) field={cubeRoundCorner} label="Round Corner" if(shape == 0)/>
					<range(0.0, 1.0) field={coneTipRadius} if(shape == 1)/>
				</category>
				<category("Rendering")>
					<range(0,2) label="Density" field={fogDensity}/>
					<color field={color}/>
				</category>
				<category("Debug")>
					<checkbox field={showBounds}/>
				</category>
			</root>);
	}

	static var _ = hrt.prefab.Prefab.register("LocalVolumeLighting", LocalVolumetricLighting);
}
