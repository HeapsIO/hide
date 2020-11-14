package hrt.prefab.vlm;

import hrt.prefab.l3d.Level3D;
import h3d.scene.pbr.Environment;

@:enum abstract ProbeMode(String) {
	var Texture = "Texture";
	var Capture = "Capture";
}

@:enum abstract ProbeFadeMode(String) {
	var Linear = "Linear";
	var Smoothstep = "Smoothstep";
	var Pow2 = "Pow2";
}

class DebugView extends hxsl.Shader {

	static var SRC = {

		var pixelColor : Vec4;
		@param var source : SamplerCube;
		var transformedNormal : Vec3;

		function fragment() {
			var color = source.get(transformedNormal).rgb;
			pixelColor = vec4(color, 1);
		}

	}
}

class BoundsFade extends hxsl.Shader {

	static var SRC = {

		@const var SMOOTHSTEP : Bool;
		@const var POWER2 : Bool;

		@param var scale : Vec3;
		@param var fadeDist : Float;

		var pixelRelativePosition : Vec3;
		var pixelColor : Vec4;

		function fragment() {
			var normalizedPos = abs(pixelRelativePosition) * 2.0;
			var maxDist = min(min(scale.x - normalizedPos.x * scale.x, scale.y - normalizedPos.y * scale.y), scale.z - normalizedPos.z * scale.z);
			var fadeAmount = saturate(maxDist / fadeDist);
			if( SMOOTHSTEP )
				fadeAmount = smoothstep(0.0, 1.0, fadeAmount);
			else if( POWER2 )
				fadeAmount = fadeAmount * fadeAmount;
			pixelColor.a *= fadeAmount;
		}
	};

}

class BoundsClipping extends hxsl.Shader {

	static var SRC = {

		@global var global : {
			@perObject var modelViewInverse : Mat4;
		};

		var transformedPosition : Vec3;
		var pixelRelativePosition : Vec3;

		function fragment() {
			pixelRelativePosition = (transformedPosition * global.modelViewInverse.mat3x4()).xyz;
			if( abs(pixelRelativePosition.x) > 0.5 || abs(pixelRelativePosition.y) > 0.5 || abs(pixelRelativePosition.z) > 0.5 )
				discard;
		}
	};

}

class LightProbeObject extends h3d.scene.Mesh {

	public var env : Environment;
	public var indirectShader : h3d.shader.pbr.Lighting.Indirect;
	public var boundClippingShader : BoundsClipping;
	public var boundFadeShader : BoundsFade;
	public var fadeDist : Float;
	public var fadeMode : ProbeFadeMode;
	public var priority : Int;

	public function new(?parent) {
		var probeMaterial = h3d.mat.MaterialSetup.current.createMaterial();
		super(h3d.prim.Cube.defaultUnitCube(), probeMaterial, parent);
		material.castShadows = false;
		material.mainPass.setPassName("lightProbe");
		boundClippingShader = new BoundsClipping();
		material.mainPass.addShader(boundClippingShader);
		indirectShader = new h3d.shader.pbr.Lighting.Indirect();
		indirectShader.drawIndirectDiffuse = true;
		indirectShader.drawIndirectSpecular = true;
		indirectShader.showSky = false;
		indirectShader.gammaCorrect = false;
		material.mainPass.addShader(indirectShader);
		material.mainPass.setBlendMode(Alpha);
		material.mainPass.depthTest = GreaterEqual;
		material.mainPass.culling = Front;
		material.mainPass.depthWrite = false;

		var r : h3d.scene.pbr.Renderer = cast getScene().renderer;
		if( r != null ) {
			@:privateAccess material.mainPass.addShader(r.pbrProps);
			var props : h3d.scene.pbr.Renderer.RenderProps = r.props;
			indirectShader.emissivePower = props.emissive;
		}

		boundFadeShader = new BoundsFade();
		material.mainPass.addShader(boundFadeShader);
	}

	public function clear() {
		if( env.env != null )
			env.env.clear(0);
		if( env.diffuse != null )
			env.diffuse.clear(0);
		if( env.specular != null ) {
			env.specular.dispose();
		 	env.specular.alloc();
		}
	}

	override function emit( ctx : h3d.scene.RenderContext ) {
		if( env == null )
			return;
		indirectShader.cameraPosition = ctx.camera.pos;
		indirectShader.irrLut = env.lut;
		indirectShader.irrDiffuse = env.diffuse;
		indirectShader.irrSpecular = env.specular;
		indirectShader.irrSpecularLevels = env.specLevels;
		indirectShader.irrPower = env.power * env.power;
		indirectShader.irrRotation.set(Math.cos(env.rot), Math.sin(env.rot));
		super.emit(ctx);
	}

	override function sync( ctx : h3d.scene.RenderContext ) {
		super.sync(ctx);
		getAbsPos().getScale(boundFadeShader.scale);
		getAbsPos()._44 = priority;
		boundFadeShader.fadeDist = fadeDist;
		switch fadeMode {
			case Linear:
				boundFadeShader.POWER2 = false;
				boundFadeShader.SMOOTHSTEP = false;
			case Smoothstep:
				boundFadeShader.POWER2 = false;
				boundFadeShader.SMOOTHSTEP = true;
			case Pow2:
				boundFadeShader.POWER2 = true;
				boundFadeShader.SMOOTHSTEP = false;
		}
	}

}

@:access(h3d.scene.pbr.Environment)
class LightProbe extends Object3D {

	// Probe
	public var mode : ProbeMode = Texture;
	public var priority : Int = 0;

	// Fade
	public var fadeDist : Float = 0.0;
	public var fadeMode : ProbeFadeMode = Linear;

	// Texture Mode
	public var texturePath : String = null;
	public var threshold : Float = 1.0;
	public var scale : Float = 1.0;
	public var rotation : Float = 0.0;

	// Capture Mode
	public var bounce : Int = 1;

	// Shared
	public var power : Float = 1.0;
	public var sampleBits : Int = 12;
	public var diffSize : Int = 16;
	public var specSize : Int = 64;
	public var ignoredSpecLevels : Int = 2;

	// Debug
	public var debugDisplay : Bool = true;
	public var sphereRadius : Float = 0.5;

	public function new( ?parent : Prefab ) {
		super(parent);
		type = "lightProbe";

		// Duplicate Name Fix - Prevent baked data conflict
		var root : Prefab = this;
		while( root.parent != null ) {
			root = root.parent;
		}
		var probeList : Array<LightProbe> = cast root.findAll( p -> Std.is(p, LightProbe) ? p : null );
		var curIndex = 0;
		var needCheck = true;
		while( needCheck ) {
			needCheck = false;
			for( p in probeList ) {
				if( p.name != null && p.name.indexOf("_" + curIndex) != -1 ) {
					curIndex++;
					needCheck = true;
					continue;
				}
			}
		}
		name = "lightProbe_" + curIndex;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		if( obj.mode != null ) mode = obj.mode;
		if( obj.bounce != null ) bounce = obj.bounce;
		if( obj.priority != null ) priority = obj.priority;
		if( obj.texturePath != null) texturePath = obj.texturePath;
		if( obj.fadeDist != null ) fadeDist = obj.fadeDist;
		if( obj.fadeMode != null ) fadeMode = obj.fadeMode;
		if( obj.power != null ) power = obj.power;
		if( obj.threshold != null ) threshold = obj.threshold;
		if( obj.scale != null ) scale = obj.scale;
		if( obj.rotation != null ) rotation = obj.rotation;
		if( obj.sampleBits != null ) sampleBits = obj.sampleBits;
		if( obj.diffSize != null ) diffSize = obj.diffSize;
		if( obj.specSize != null ) specSize = obj.specSize;
		if( obj.ignoredSpecLevels != null ) ignoredSpecLevels = obj.ignoredSpecLevels;
		if( obj.debugDisplay != null ) debugDisplay = obj.debugDisplay;
		if( obj.sphereRadius != null ) sphereRadius = obj.sphereRadius;
	}

	override function save() {
		var o : Dynamic = super.save();
		o.mode = mode;
		o.bounce = bounce;
		o.priority = priority;
		o.texturePath = texturePath;
		o.fadeDist = fadeDist;
		o.fadeMode = fadeMode;
		o.power = power;
		o.threshold = threshold;
		o.scale = scale;
		o.rotation = rotation;
		o.sampleBits = sampleBits;
		o.diffSize = diffSize;
		o.specSize = specSize;
		o.ignoredSpecLevels = ignoredSpecLevels;
		o.debugDisplay = debugDisplay;
		o.sphereRadius = sphereRadius;
		return o;
	}

	override function makeInstance( ctx : Context ) : Context {
		ctx = ctx.clone(this);
		var lpo = new LightProbeObject(ctx.local3d);
		lpo.material.castShadows = false;
		lpo.material.mainPass.setPassName("lightProbe");
		lpo.ignoreCollide = true;
		ctx.local3d = lpo;
		ctx.local3d.name = name;

		#if editor
		var wire = new h3d.scene.Box(lpo);
		wire.thickness = 2.0;
		wire.material.mainPass.setPassName("overlay");
		wire.name = "wire_select";
		wire.color = 0xFFFFFF;
		wire.ignoreCollide = true;
		wire.material.shadows = false;
		wire.visible = false;
		wire.material.mainPass.depthTest = Always;

		var previewSphereDiffuse = new h3d.scene.Mesh(h3d.prim.Sphere.defaultUnitSphere(), lpo);
		previewSphereDiffuse.name = "preview_sphere_diffuse";
		previewSphereDiffuse.material.mainPass.setPassName("overlay");
		previewSphereDiffuse.material.mainPass.addShader(new DebugView());
		previewSphereDiffuse.material.castShadows = false;

		var previewSphereSpecular = new h3d.scene.Mesh(h3d.prim.Sphere.defaultUnitSphere(), lpo);
		previewSphereSpecular.name = "preview_sphere_specular";
		previewSphereSpecular.material.mainPass.setPassName("overlay");
		previewSphereSpecular.material.mainPass.addShader(new DebugView());
		previewSphereSpecular.material.castShadows = false;
		#end

		updateInstance(ctx, texturePath == null ? null : "texturePath");
		return ctx;
	}

	override function updateInstance( ctx : Context, ?propName : String ) {
		super.updateInstance(ctx, propName);
		var lpo : LightProbeObject = cast ctx.local3d;
		lpo.fadeDist = fadeDist;
		lpo.fadeMode = fadeMode;
		lpo.priority = priority;

		// Full Reset
		if( propName == "mode" ) {
			if( lpo.env != null ) {
				lpo.env.dispose();
				lpo.env = null;
			}
		}

		switch mode {
			case Texture:
				var needCompute = false;
				if( propName == "texturePath" || propName == "mode" ) {
					var t = texturePath == null ? null : ctx.loadTexture(texturePath);
					if( t != null ) {
						lpo.env = new Environment(t);
						needCompute = true;
					}
				}
				if( lpo.env != null ) {
					lpo.env.power = power;
					lpo.env.threshold = threshold;
					lpo.env.scale = scale;
					lpo.env.rot = hxd.Math.degToRad(rotation);
					lpo.env.sampleBits = sampleBits;
					lpo.env.ignoredSpecLevels = ignoredSpecLevels;
					if( lpo.env.specSize != specSize ) {
						if( lpo.env.specular != null ) lpo.env.specular.dispose();
						lpo.env.specular = null;
						needCompute = true;
					}
					lpo.env.specSize = specSize;
					if( lpo.env.diffSize != diffSize ) {
						if( lpo.env.diffuse != null ) lpo.env.diffuse.dispose();
						lpo.env.diffuse = null;
						needCompute = true;
					}
					lpo.env.diffSize = diffSize;

					if( propName == "threshold" || propName == "scale" ||
						propName == "sampleBits" || propName == "ignoredSpecLevels" )
						needCompute = true;

					if( needCompute ) {
						if( lpo.env.source.flags.has(Loading) )
							lpo.env.source.waitLoad(lpo.env.compute);
						else
							lpo.env.compute();
					}
				}

			case Capture:

				var needCompute = false;

				if( lpo.env == null )
					lpo.env = new Environment(null);

				lpo.env.power = power;
				lpo.env.ignoredSpecLevels = ignoredSpecLevels;

				if( propName == "threshold" || propName == "scale" ||
					propName == "sampleBits" || propName == "ignoredSpecLevels" )
					needCompute = true;

				var res = ctx.shared.loadPrefabDat("probe", "bake", name);
				if( res != null ) {
					loadBinary(lpo.env, res.entry.getBytes());
					needCompute = false; // No Env available with binary load, everything else is already baked
				}

				if( needCompute )
					lpo.env.compute();
		}

		updatePreviewSphere(lpo);
	}

	function updatePreviewSphere( o : h3d.scene.Object ) {
		#if editor
		var lpo : LightProbeObject = cast o;
		var previewSphereDiffuse : h3d.scene.Mesh = Std.downcast(lpo.find( o -> o.name == "preview_sphere_diffuse" ? o : null), h3d.scene.Mesh);
		var previewSphereSpecular : h3d.scene.Mesh = Std.downcast(lpo.find( o -> o.name == "preview_sphere_specular" ? o : null), h3d.scene.Mesh);
		var parentScale = lpo.getAbsPos().getScale();

		// Don't use scale from parent for preview phere
		function updateScale( m : h3d.scene.Mesh ) {
			m.scaleX = sphereRadius / parentScale.x;
			m.scaleY = sphereRadius / parentScale.y;
			m.scaleZ = sphereRadius / parentScale.z;
		}

		if( previewSphereDiffuse != null ) {
			previewSphereDiffuse.visible = debugDisplay;
			previewSphereDiffuse.x = (sphereRadius + (sphereRadius * 0.5)) / parentScale.x;
			var s = previewSphereDiffuse.material.mainPass.getShader(DebugView);
			if( lpo.env != null ) {
				if( lpo.env.source != null && lpo.env.source.flags.has(Loading) )
					lpo.env.source.waitLoad( () ->  s.source = lpo.env.diffuse );
				else
					s.source = lpo.env.diffuse;
			}
			updateScale(previewSphereDiffuse);
		}
		if( previewSphereSpecular != null ) {
			previewSphereSpecular.visible = debugDisplay;
			previewSphereSpecular.x = -(sphereRadius + (sphereRadius * 0.5)) / parentScale.x;
			var s = previewSphereSpecular.material.mainPass.getShader(DebugView);
			if( lpo.env != null ) {
				if( lpo.env.source != null && lpo.env.source.flags.has(Loading) )
					lpo.env.source.waitLoad( () -> s.source = lpo.env.specular );
				else
					s.source = lpo.env.specular;
			}
			updateScale(previewSphereSpecular);
		}
		#end
	}

	override function applyTransform( o : h3d.scene.Object ) {
		super.applyTransform(o);
		updatePreviewSphere(o);
	}

	function serialize( env : Environment ) : haxe.io.Bytes {

		var diffusePixels : Array<hxd.Pixels.PixelsFloat> = [ for( i in 0 ... 6) env.diffuse.capturePixels(i) ];
		var mipLevels = env.getMipLevels();
		var specularPixels : Array<hxd.Pixels.PixelsFloat> =
		 [
			for( i in 0 ... 6 ) {
				for( m in 0 ... mipLevels ) {
					env.specular.capturePixels(i, m);
				}
			}
		];

		var totalBytes = 0;
		totalBytes += 4 + 4 + 4 + 4 + 8 + 8; // diffSize + specSize + ignoredSpecLevels + sampleBits + threshold + scale
		for( p in diffusePixels )
			totalBytes += p.bytes.length;
		for( p in specularPixels )
			totalBytes += p.bytes.length;

		var bytes = haxe.io.Bytes.alloc(totalBytes);

		var curPos = 0;
		bytes.setInt32(curPos, env.sampleBits); 		curPos += 4;
		bytes.setInt32(curPos, env.diffSize); 			curPos += 4;
		bytes.setInt32(curPos, env.specSize); 			curPos += 4;
		bytes.setInt32(curPos, env.ignoredSpecLevels); 	curPos += 4;
		bytes.setDouble(curPos, env.threshold); 		curPos += 8;
		bytes.setDouble(curPos, env.scale);			 	curPos += 8;

		for( p in diffusePixels ) {
			bytes.blit(curPos, p.bytes, 0, p.bytes.length);
			curPos += p.bytes.length;
		}

		for( p in specularPixels ) {
			bytes.blit(curPos, p.bytes, 0, p.bytes.length);
			curPos += p.bytes.length;
		}

		return bytes;
	}

	function loadBinary( env : Environment, bytes : haxe.io.Bytes ) {

		var curPos = 0;

		env.sampleBits = bytes.getInt32(curPos); 		curPos += 4;
		env.diffSize = bytes.getInt32(curPos); 			curPos += 4;
		env.specSize = bytes.getInt32(curPos); 			curPos += 4;
		env.ignoredSpecLevels = bytes.getInt32(curPos); curPos += 4;
		env.threshold = bytes.getDouble(curPos); 		curPos += 8;
		env.scale = bytes.getDouble(curPos); 			curPos += 8;

		env.createTextures();

		var diffSize = hxd.Pixels.calcStride(env.diffuse.width, env.diffuse.format) * env.diffuse.height;
		for( i in 0 ... 6 ) {
			var diffByte = bytes.sub(curPos, diffSize);
			curPos += diffByte.length;
			var diffPixels : hxd.Pixels.PixelsFloat = new hxd.Pixels(env.diffuse.width, env.diffuse.height, diffByte, env.diffuse.format);
			env.diffuse.uploadPixels(diffPixels, 0, i);
		}

		var mipLevels = env.getMipLevels();
		env.specLevels = mipLevels - ignoredSpecLevels;
		for( i in 0 ... 6 ) {
			for( m in 0 ... mipLevels ) {
				var mipMapSize = hxd.Pixels.calcStride(env.specular.width >> m, env.specular.format) * env.specular.height >> m;
				var specByte = bytes.sub(curPos, mipMapSize);
				curPos += specByte.length;
				var specPixels : hxd.Pixels.PixelsFloat = new hxd.Pixels(env.specular.width >> m, env.specular.height >> m, specByte, env.specular.format);
				env.specular.uploadPixels(specPixels, m, i);
			}
		}
	}

	#if editor

	override function getHideProps() : HideProps {
		return { icon : "map-o", name : "LightProbe" };
	}

	override function setSelected( ctx : Context, b : Bool ) {
		var w = ctx.local3d.find( o -> o.name == "wire_select" ? o : null);
		if( w != null )
			w.visible = b;
		return true;
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		var captureModeParams =
		'<div class="group" name="Environment" >
			<dt>Power</dt><dd><input type="range" min="0" max="10" field="power"/></dd>
			<dt>Bounce</dt><dd><input type="range" min="1" max="3" step="1" field="bounce"/></dd>
			<br>
			<div align="center">
				<input type="button" value="Bake" class="bake" />
			</div>
			<div align="center">
				<input type="button" value="Clear" class="clear" />
			</div>
			<br>
			<div align="center">
				<input type="button" value="Export" class="export" />
			</div>
			<div align="center">
				<input type="button" value="Import" class="import" />
			</div>
			<br>
		</div>
		<div class="group" name="Resolution">
			<dl>
				<dt>Diffuse</dt><dd><input type="range" min="1" max="512" step="1" field="diffSize"/></dd>
				<dt>Specular</dt><dd><input type="range" min="1" max="2048" step="1" field="specSize"/></dd>
				<dt>Sample Count</dt><dd><input type="range" min="1" max="12" step="1" field="sampleBits"/></dd>
				<dt>Ignored Spec Levels</dt><dd><input type="range" min="0" max="3" step="1" field="ignoredSpecLevels"/></dd>
			</dl>
		</div>';

		var textureModeParams =
		'<div class="group" name="Environment">
			<dl>
				<dt>Texture</dt><dd><input type="texturepath" field="texturePath"/></dd>
				<dt>Rotation</dt><dd><input type="range" min="0" max="360" field="rotation"/></dd>
				<dt>Power</dt><dd><input type="range" min="0" max="10" field="power"/></dd>
			</dl>
		</div>
		<div class="group" name="Resolution">
			<dl>
				<dt>Diffuse</dt><dd><input type="range" min="1" max="512" step="1" field="diffSize"/></dd>
				<dt>Specular</dt><dd><input type="range" min="1" max="2048" step="1" field="specSize"/></dd>
				<dt>Sample Count</dt><dd><input type="range" min="1" max="12" step="1" field="sampleBits"/></dd>
				<dt>Ignored Spec Levels</dt><dd><input type="range" min="0" max="3" step="1" field="ignoredSpecLevels"/></dd>
			</dl>
		</div>
		<div class="group" name="HDR">
			<dl>
				<dt>Threshold</dt><dd><input type="range" min="0" max="1" step="0.1" field="threshold"/></dd>
				<dt>Scale</dt><dd><input type="range" min="0" max="10" field="scale"/></dd>
			</dl>
		</div>';

		var props = new hide.Element('
			<div class="group" name="Probe">
				<dl>
					<dt>Mode</dt>
					<dd>
						<select field="mode">
							<option value="Texture">Texture</option>
							<option value="Capture">Capture</option>
						</select>
					</dd>
					<dt>Priority</dt><dd><input type="range" min="0" max="10" step="1" field="priority"/></dd>
				</dl>
			</div>
			' + (mode == Texture ? textureModeParams : captureModeParams) + '
			<div class="group" name="Fade">
				<dl>
					<dt>Mode</dt>
						<dd>
							<select field="fadeMode">
								<option value="Linear">Linear</option>
								<option value="Smoothstep">SmoothStep</option>
								<option value="Pow2">Power</option>
							</select>
						</dd>
					<dt>Distance</dt><dd><input type="range" min="0" max="10" field="fadeDist"/></dd>
				</dl>
			</div>
			<div class="group" name="Debug">
				<dl>
					<dt>Debug Display</dt><dd><input type="checkbox" field="debugDisplay"/></dd>
					<dt>Sphere Radius</dt><dd><input type="range" min="0.1" max="4" field="sphereRadius"/></dd>
				</dl>
			</div>
		');
		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
			if( pname == "mode" )
				ctx.rebuildProperties();
		});

		var clearButton = props.find(".clear");
		if( clearButton != null ) {
			clearButton.click(function(_) {
				var lpo : LightProbeObject = cast ctx.getContext(this).local3d;
				lpo.env.createTextures();
				lpo.clear();
				ctx.properties.undo.change(Custom(function(undo) {
					// TO DO
				}));
			});
		}

		var exportButton = props.find(".export");
		if( exportButton != null ) {
			exportButton.click(function(_) {

				var lpo : LightProbeObject = cast ctx.getContext(this).local3d;
				if( lpo.env == null || lpo.env.specular == null || lpo.env.diffuse == null ) {
					hide.Ide.inst.message("Capture is empty.");
					return;
				}

				var data = serialize(lpo.env);
				function saveData( name : String ) {
					var path = ctx.ide.getPath(name)+"/"+this.name+"_export.bake";
					sys.io.File.saveBytes(path, data);
				}
				ctx.ide.chooseDirectory(saveData);

			});
		}

		var importButton = props.find(".import");
		if( importButton != null ) {
			importButton.click(function(_) {

				var lpo : LightProbeObject = cast ctx.getContext(this).local3d;

				function loadData( name : String ) {

					if( name == null || name == "null" )
						return;

					var b = hxd.res.Loader.currentInstance.load(name).entry.getBytes();

					if( lpo.env != null )
						lpo.env.dispose();

					lpo.env = new Environment(null);
					loadBinary(lpo.env, b);

					// Upate the prefab
					sampleBits = lpo.env.sampleBits;
					diffSize = lpo.env.diffSize;
					specSize = lpo.env.specSize;
					ignoredSpecLevels = lpo.env.ignoredSpecLevels;
					threshold = lpo.env.threshold;
					scale = lpo.env.scale;

					// Save the import
					ctx.rootContext.shared.savePrefabDat("probe", "bake", this.name, b);

					ctx.onChange(this, null);
					ctx.rebuildProperties();
				}

				ctx.ide.chooseFile(["bake"], loadData);

				ctx.properties.undo.change(Custom(function(undo) {
					// TO DO
				}));

			});
		}

		var bakeButton = props.find(".bake");
		if( bakeButton != null ) {
			bakeButton.click(function(_) {

				var lpo : LightProbeObject = cast ctx.getContext(this).local3d;
				var captureSize = specSize;

				// Start with a black texture, need to override the default env
				lpo.env.createTextures();
				lpo.clear();

				if( lpo.env.env == null || lpo.env.env.width != captureSize ) {
					if( lpo.env.env != null )
						lpo.env.env.dispose();
					lpo.env.env = new h3d.mat.Texture(captureSize, captureSize, [Cube, Target]);
				}

				var probeBaker = new ProbeBaker();
				if( bounce > 1 ) {
					var tmpTexture = new h3d.mat.Texture(captureSize, captureSize, [Cube, Target]);
					var curCapture : h3d.mat.Texture = tmpTexture;
					for( b in 0 ... bounce ) {
						probeBaker.captureEnvironment(lpo.getAbsPos().getPosition(), captureSize, ctx.scene.s3d, curCapture);
						var tmp = lpo.env.env;
						lpo.env.env = curCapture;
						lpo.env.compute();
						curCapture = tmp;
					}
					curCapture.dispose();
				}
				else {
					probeBaker.captureEnvironment(lpo.getAbsPos().getPosition(), captureSize, ctx.scene.s3d, lpo.env.env);
					lpo.env.compute();
				}

				probeBaker.dispose();

				var bytes = serialize(lpo.env);
				ctx.rootContext.shared.savePrefabDat("probe", "bake", name, bytes);

				ctx.onChange(this, null);
			});
		}
	}

	#end

	static var _ = Library.register("lightProbe", LightProbe);
}