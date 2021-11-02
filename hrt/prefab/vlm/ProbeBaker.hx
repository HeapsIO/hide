package hrt.prefab.vlm;

import hrt.prefab.vlm.LightProbe.LightProbeObject;

class ProbeBaker {

	public var useGPU = false;

	// Tmp cube texture for rendring environment
	var envMap : h3d.mat.Texture;

	// Params for CubeMap rendering
	var customCamera : h3d.Camera;
	var cubeDir = [ h3d.Matrix.L([0,0,-1,0, 0,1,0,0, -1,-1,1,0]),
					h3d.Matrix.L([0,0,1,0, 0,1,0,0, 1,-1,-1,0]),
	 				h3d.Matrix.L([-1,0,0,0, 0,0,1,0, 1,-1,-1,0]),
	 				h3d.Matrix.L([-1,0,0,0, 0,0,-1,0, 1,1,1,0]),
				 	h3d.Matrix.L([-1,0,0,0, 0,1,0,0, 1,-1,1,0]),
				 	h3d.Matrix.L([1,0,0,0, 0,1,0,0, -1,-1,-1,0]) ];

	// Output for SH computation on GPU
	var computeSH : h3d.pass.ScreenFx<hrt.shader.ComputeSH>;
	var output0 : h3d.mat.Texture;
	var output1 : h3d.mat.Texture;
	var output2 : h3d.mat.Texture;
	var output3 : h3d.mat.Texture;
	var output4 : h3d.mat.Texture;
	var output5 : h3d.mat.Texture;
	var output6 : h3d.mat.Texture;
	var output7 : h3d.mat.Texture;
	var textureArray: Array<h3d.mat.Texture>;

	// Tmp Buffer
	var pixels : hxd.Pixels = null;
	var prim : h3d.prim.Plane2D;

	var emissive : Float = 1.0;

	public function new(){
		customCamera = new h3d.Camera();
		customCamera.screenRatio = 1.0;
		customCamera.fovY = 90;
		customCamera.zNear = 0.01;
		customCamera.zFar = 4000;
	}

	public function dispose() {
		if( envMap != null ) {
			envMap.dispose();
			envMap = null;
		}
		if(output0 != null) output0.dispose();
		if(output1 != null) output1.dispose();
		if(output2 != null) output2.dispose();
		if(output3 != null) output3.dispose();
		if(output4 != null) output4.dispose();
		if(output5 != null) output5.dispose();
		if(output6 != null) output6.dispose();
		if(output7 != null) output7.dispose();
		if(prim != null) prim.dispose();
	}

	public function captureEnvironment( position : h3d.Vector, resolution : Int, scene : h3d.scene.Scene, output : h3d.mat.Texture ) {
		var pbrRenderer = Std.downcast(scene.renderer, h3d.scene.pbr.Renderer);

		var prevCam = scene.camera;
		var prevRenderMode = pbrRenderer.renderMode;
		pbrRenderer.renderMode = LightProbe;
		scene.camera = customCamera;

		var renderProps : h3d.scene.pbr.Renderer.RenderProps = pbrRenderer.props;
		var prevEmissive = renderProps.emissive;
		renderProps.emissive = emissive * prevEmissive;

		// Bake a Probe
		var engine = h3d.Engine.getCurrent();
		for( f in 0 ... 6 ) {
			engine.begin();
			customCamera.setCubeMap(f, position);
			customCamera.update();
			scene.camera = customCamera;
			engine.pushTarget(output, f);
			engine.clear(0,1,0);
			scene.render(engine);
			engine.popTarget();
		}

		scene.camera = prevCam;
		pbrRenderer.renderMode = prevRenderMode;
		@:privateAccess renderProps.emissive = prevEmissive;
	}

	function setupEnvMap( resolution : Int ) {
		if( envMap == null || resolution != envMap.width || resolution != envMap.height ) {
			if( envMap != null ) envMap.dispose();
			envMap = new h3d.mat.Texture(resolution, resolution, [Cube, Target], RGBA32F);
		}
	}

	function setupShaderOutput( order : Int, probeCount: Int ) {

		if( order > 3 || order <= 0 ){ throw "Not Supported"; return; }

		if( !useGPU )
			probeCount = 1;

		if( order >= 1 && (output0 == null || output0.width != probeCount)){
			if(output0 != null) output0.dispose();
			output0 = new h3d.mat.Texture(probeCount, 1, [Target], RGBA32F);
		}
		if( order >= 2 && (output1 == null || output1.width != probeCount)){
			if(output1 != null) output1.dispose();
			if(output2 != null) output2.dispose();
			if(output3 != null) output3.dispose();
			output1 = new h3d.mat.Texture(probeCount, 1, [Target], RGBA32F);
			output2 = new h3d.mat.Texture(probeCount, 1, [Target], RGBA32F);
			output3 = new h3d.mat.Texture(probeCount, 1, [Target], RGBA32F);
		}
		if( order >= 3 && (output4 == null || output4.width != probeCount)){
			if(output4 != null) output4.dispose();
			if(output5 != null) output5.dispose();
			if(output6 != null) output6.dispose();
			if(output7 != null) output7.dispose();
			output4 = new h3d.mat.Texture(probeCount, 1, [Target], RGBA32F);
			output5 = new h3d.mat.Texture(probeCount, 1, [Target], RGBA32F);
			output6 = new h3d.mat.Texture(probeCount, 1, [Target], RGBA32F);
			output7 = new h3d.mat.Texture(probeCount, 1, [Target], RGBA32F);
		}

		switch(order){
			case 1:
				textureArray = [output0];
				computeSH = new h3d.pass.ScreenFx(new hrt.shader.ComputeSH(),[
								Vec4([Value("out.coefL00", 3), Const(0)])]);
			case 2:
				textureArray = [output0, output1, output2, output3];
				computeSH = new h3d.pass.ScreenFx(new hrt.shader.ComputeSH(),[
							Vec4([Value("out.coefL00", 3), Const(0)]),
							Vec4([Value("out.coefL1n1", 3), Const(0)]),
							Vec4([Value("out.coefL10", 3), Const(0)]),
							Vec4([Value("out.coefL11", 3), Const(0)])]);

			case 3:
				function getSwiz(name,comp) : hxsl.Output { return Swiz(Value(name,3),[comp]); }
				textureArray = [output0, output1, output2, output3, output4, output5, output6, output7];
				computeSH = new h3d.pass.ScreenFx(new hrt.shader.ComputeSH(),[
							Vec4([Value("out.coefL00", 3), getSwiz("out.coefL22",X) ]),
							Vec4([Value("out.coefL1n1", 3), getSwiz("out.coefL22",Y) ]),
							Vec4([Value("out.coefL10", 3), getSwiz("out.coefL22",Z) ]),
							Vec4([Value("out.coefL11", 3), Const(0)]),
							Vec4([Value("out.coefL2n2", 3), Const(0)]),
							Vec4([Value("out.coefL2n1", 3), Const(0)]),
							Vec4([Value("out.coefL20", 3), Const(0)]),
							Vec4([Value("out.coefL21", 3), Const(0)])]);
		}
	}

	function drawSHIntoTexture(renderer : h3d.scene.Renderer, env : h3d.mat.Texture, order : Int, probeIndex: Int) {
		if( prim == null ){
			prim = new h3d.prim.Plane2D();
		}

		function setPrimPos( index : Int ){
			var v = new hxd.FloatBuffer();
			var pixelSize = (1.0 / output0.width);
			var translation =  pixelSize * index * 2;
			var posX = -1.0 + translation;
			v.push( posX ) ; v.push( -1 ); v.push(0); v.push(0);
			v.push( posX ); v.push( 1 ); v.push(0); v.push(0);
			v.push( posX + pixelSize * 2 ); v.push( -1 ); v.push(0); v.push(0);
			v.push( posX + pixelSize * 2 ); v.push( 1 ); v.push(0); v.push(0);
			prim.buffer = h3d.Buffer.ofFloats(v, 4, [Quads, RawFormat]);
		}
		setPrimPos(probeIndex);

		@:privateAccess renderer.ctx.engine = h3d.Engine.getCurrent();
		@:privateAccess renderer.setTargets(textureArray);
		computeSH.shader.ORDER = order;
		computeSH.shader.width = env.width;
		computeSH.shader.environment = env;
		computeSH.shader.cubeDir = cubeDir;
		computeSH.primitive = prim;
		computeSH.render();
		@:privateAccess renderer.resetTarget();
		@:privateAccess renderer.ctx.engine.flushTarget();
	}

	function convertOuputTexturesIntoSH( volumetricLightMap : hrt.prefab.vlm.VolumetricMesh, pixelsOut : hxd.Pixels ) {

		var order = volumetricLightMap.shOrder;
		var sh = new hrt.prefab.vlm.SphericalHarmonic(order);
		var coefCount = order * order;
		var maxCoef : Int = Std.int(Math.min(8, coefCount));

		for(coef in 0 ... maxCoef){
			var pixels = textureArray[coef].capturePixels();
			for( index in 0 ... pixels.width){
				var coefs : h3d.Vector = pixels.getPixelF(index, 0);
				var coords = volumetricLightMap.getProbeCoords(index);
				var u = coords.x + volumetricLightMap.probeCount.x * coef;
				var v = coords.y + coords.z * volumetricLightMap.probeCount.y;
				pixelsOut.setPixelF(u, v, new h3d.Vector(coefs.r, coefs.g, coefs.b, 0));

				// Last coefs is inside the alpha channel
				if( order == 3 ){
					var u = coords.x + volumetricLightMap.probeCount.x * 8;
					var v = coords.y + coords.z * volumetricLightMap.probeCount.y;
					var prev = pixelsOut.getPixelF(u, v);
					if( coef == 0 ){ prev.r = coefs.a; }
					if( coef == 1 ){ prev.g = coefs.a; }
					if( coef == 2 ){ prev.b = coefs.a; }
					pixelsOut.setPixelF(u, v, prev);
				}
			}
		}
	}

	function convertEnvIntoSH_CPU( env : h3d.mat.Texture, order : Int ) : hrt.prefab.vlm.SphericalHarmonic {
		var coefCount = order * order;
		var sphericalHarmonic = new hrt.prefab.vlm.SphericalHarmonic(order);
		var face : hxd.Pixels;
		var weightSum = 0.0;
		var invWidth = 1.0 / env.width;
		var shData : Array<Float> = [for ( value in 0...coefCount ) 0];

		for( f in 0...6 ) {
			face = env.capturePixels(f, 0);
			for (u in 0...face.width) {
				var fU : Float = (u / face.width ) * 2 - 1;// Texture coordinate U in range [-1 to 1]
				fU *= fU;
				var uCoord = 2.0 * u * invWidth + invWidth;
				for (v in 0...face.width) {
        			var fV : Float = (v / face.height ) * 2 - 1;// Texture coordinate V in range [-1 to 1]
					fV *= fV;
					var vCoord = 2.0 * v * invWidth + invWidth;
					var dir = getDir(uCoord, vCoord, f);// Get direction from center of cube texture to current texel
           			var diffSolid = 4.0 / ((1.0 + fU + fV) * Math.sqrt(1.0 + fU + fV));	// Scale factor depending on distance from center of the face
					weightSum += diffSolid;
					var color = face.getPixelF(u,v);// Get color from the current face
					evalSH(order, dir, shData);// Calculate coefficients of spherical harmonics for current direction
					for(i in 0...coefCount){
						sphericalHarmonic.coefR[i] += shData[i] * color.r * diffSolid;
						sphericalHarmonic.coefG[i] += shData[i] * color.g * diffSolid;
						sphericalHarmonic.coefB[i] += shData[i] * color.b * diffSolid;
					}
				}
			}
		}
		// Final scale for coefficients
		var normProj = (4.0 * Math.PI) / weightSum;
		for( i in 0...coefCount ){
			sphericalHarmonic.coefR[i] *= normProj;
			sphericalHarmonic.coefG[i] *= normProj;
			sphericalHarmonic.coefB[i] *= normProj;
		}
		return sphericalHarmonic;
	}

	inline function evalSH( order : Int, dir : h3d.Vector, shData : Array<Float> ) {
		for (l in 0...order) {
       		for (m in -l...l+1) {
				shData[getIndex(l, m)] = evalCoef(l, m, dir);
			}
		}
	}

	inline function getIndex( l : Int, m :Int ) : Int {
		return l * (l + 1) + m;
	}

	inline function getDir( u : Float, v : Float, face : Int ) : h3d.Vector {
		var dir = new h3d.Vector();
		switch( face ) {
			case 0: dir.x = -1.0; dir.y = -1.0 + v; dir.z = 1.0 - u;
			case 1: dir.x = 1.0; dir.y = -1.0 + v; dir.z = -1.0 + u;
			case 2: dir.x = 1.0 - u; dir.y = -1.0; dir.z = -1.0 + v;
			case 3: dir.x = 1.0 - u; dir.y = 1.0; dir.z = 1.0 - v;
			case 4: dir.x = 1.0 - u;  dir.y = -1.0 + v; dir.z = 1.0;
			case 5: dir.x = -1.0 + u; dir.y = -1.0 + v;  dir.z = -1.0;
			default:
		}
		dir.normalizeFast();
		return dir;
	}

	inline function evalCoef( l : Int, m : Int, dir : h3d.Vector ) : Float {
		// Coef from Stupid Spherical Harmonics (SH) Peter-Pike Sloan Microsoft Corporation
		return switch [l,m] {
			case[0,0]:	0.282095; // 0.5 * sqrt(1/pi)
			case[1,-1]:	-0.488603 * dir.y;  // -sqrt(3/(4pi)) * y
			case[1,0]:	0.488603 * dir.z; // sqrt(3/(4pi)) * z
			case[1,1]:	-0.488603 * dir.x; // -sqrt(3/(4pi)) * x
			case[2,-2]:	1.092548 * dir.y * dir.x;// 0.5 * sqrt(15/pi) * y * x
			case[2,-1]:	-1.092548 * dir.y * dir.z; // -0.5 * sqrt(15/pi) * y * z
			case[2,0]:	0.315392 * (-dir.x * dir.x - dir.y * dir.y + 2.0 * dir.z * dir.z);// 0.25 * sqrt(5/pi) * (-x^2-y^2+2z^2)
			case[2,1]:  -1.092548 * dir.x * dir.z; // -0.5 * sqrt(15/pi) * x * z
			case[2,2]:	0.546274 * (dir.x * dir.x - dir.y * dir.y); // 0.25 * sqrt(15/pi) * (x^2 - y^2)
			case[3,-3]:	-0.590044 * dir.y * (3.0 * dir.x * dir.x - dir.y * dir.y);// -0.25 * sqrt(35/(2pi)) * y * (3x^2 - y^2)
			case[3,-2]: 2.890611 * dir.x * dir.y * dir.z; // 0.5 * sqrt(105/pi) * x * y * z
			case[3,-1]: -0.457046 * dir.y * (4.0 * dir.z * dir.z - dir.x * dir.x - dir.y * dir.y); // -0.25 * sqrt(21/(2pi)) * y * (4z^2-x^2-y^2)
			case[3,0]:  0.373176 * dir.z * (2.0 * dir.z * dir.z - 3.0 * dir.x * dir.x - 3.0 * dir.y * dir.y);  // 0.25 * sqrt(7/pi) * z * (2z^2 - 3x^2 - 3y^2)
			case[3,1]:	-0.457046 * dir.x * (4.0 * dir.z * dir.z - dir.x * dir.x - dir.y * dir.y); // -0.25 * sqrt(21/(2pi)) * x * (4z^2-x^2-y^2)
			case[3,2]:  1.445306 * dir.z * (dir.x * dir.x - dir.y * dir.y); // 0.25 * sqrt(105/pi) * z * (x^2 - y^2)
			case[3,3]:	-0.590044 * dir.x * (dir.x * dir.x - 3.0 * dir.y * dir.y); // -0.25 * sqrt(35/(2pi)) * x * (x^2-3y^2)
			case[4,-4]: 2.503343 * dir.x * dir.y * (dir.x * dir.x - dir.y * dir.y);// 0.75 * sqrt(35/pi) * x * y * (x^2-y^2)
			case[4,-3]: -1.770131 * dir.y * dir.z * (3.0 * dir.x * dir.x - dir.y * dir.y); // -0.75 * sqrt(35/(2pi)) * y * z * (3x^2-y^2)
			case[4,-2]: 0.946175 * dir.x * dir.y * (7.0 * dir.z * dir.z - 1.0);// 0.75 * sqrt(5/pi) * x * y * (7z^2-1)
			case[4,-1]: -0.669047 * dir.y * dir.z * (7.0 * dir.z * dir.z - 3.0);// -0.75 * sqrt(5/(2pi)) * y * z * (7z^2-3)
			case[4,0]:  0.105786 * (35.0 * dir.z * dir.z * dir.z * dir.z - 30.0 * dir.z * dir.z + 3.0);// 3/16 * sqrt(1/pi) * (35z^4-30z^2+3)
			case[4,1]:  -0.669047 * dir.x * dir.z * (7.0 * dir.z * dir.z - 3.0);// -0.75 * sqrt(5/(2pi)) * x * z * (7z^2-3)
			case[4,2]:  0.473087 * (dir.x * dir.x - dir.y * dir.y) * (7.0 * dir.z * dir.z - 1.0);// 3/8 * sqrt(5/pi) * (x^2 - y^2) * (7z^2 - 1)
			case[4,3]:  -1.770131 * dir.x * dir.z * (dir.x * dir.x - 3.0 * dir.y * dir.y);// -0.75 * sqrt(35/(2pi)) * x * z * (x^2 - 3y^2)
			case[4,4]:  0.625836 * (dir.x * dir.x * (dir.x * dir.x - 3.0 * dir.y * dir.y) - dir.y * dir.y * (3.0 * dir.x * dir.x - dir.y * dir.y)); // 3/16*sqrt(35/pi) * (x^2 * (x^2 - 3y^2) - y^2 * (3x^2 - y^2))
			default: 0;
		}
	}
}