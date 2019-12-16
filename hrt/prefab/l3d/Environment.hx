package hrt.prefab.l3d;


@:access(h3d.scene.pbr.Environment)
class Environment extends Object3D {

	var sourceMapPath : String;
	var env : h3d.scene.pbr.Environment;

	public var power : Float = 1.0;
	public var threshold : Float = 1.0;
	public var scale : Float = 1.0;
	public var rotation : Float = 0.0;
	public var sampleBits : Int = 12;
	public var diffSize : Int = 64;
	public var specSize : Int = 512;
	public var ignoredSpecLevels : Int = 1;

	public function new( ?parent ) {
		super(parent);
		type = "environment";
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
	 	power = obj.power != null ? obj.power : 1.0;
		threshold = obj.threshold != null ? obj.threshold : 1.0;
		scale = obj.scale != null ? obj.scale : 1.0;
		rotation = obj.rotation != null ? obj.rotation : 0.0;
		sampleBits = obj.sampleBits != null ? obj.sampleBits : 12;
		diffSize = obj.diffSize != null ? obj.diffSize : 64;
		specSize = obj.specSize != null ? obj.specSize : 512;
		ignoredSpecLevels = obj.ignoredSpecLevels != null ? obj.ignoredSpecLevels : 1;
		sourceMapPath = obj.sourceMapPath != null ? obj.sourceMapPath : null;
	}

	override function save() {
		var obj : Dynamic = super.save();
		obj.power = power;
		obj.threshold = threshold;
		obj.scale = scale;
		obj.rotation = rotation;
		obj.sampleBits = sampleBits;
		obj.diffSize = diffSize;
		obj.specSize = specSize;
		obj.ignoredSpecLevels = ignoredSpecLevels;
		obj.sourceMapPath = sourceMapPath;
		return obj;
	}

	function saveAsBinary( ctx : Context ) {
		if( env == null || env.diffuse == null || env.specular == null || env.lut == null )
			return;
		var bytes = convertToBinary();
		ctx.shared.savePrefabDat("environment", "bake", name, bytes);
	}

	function loadFromBinary( ctx : Context ) : Bool {
		if( env == null || env.diffuse == null || env.specular == null || env.lut == null )
			return false;
		var res = ctx.shared.loadPrefabDat("environment", "bake", name);
		return res != null ? convertFromBinary(res.entry.getBytes()) : false;
	}

	function convertToBinary() : haxe.io.Bytes {
		var lutPixels = env.lut.capturePixels();
		var diffusePixels : Array<hxd.Pixels.PixelsFloat> = [ for( i in 0 ... 6) env.diffuse.capturePixels(i) ];

		var specularPixels : Array<hxd.Pixels.PixelsFloat> =
		 [
			for( i in 0 ... 6 ) {
				for( m in 0 ... env.specLevels ) {
					env.specular.capturePixels(i, m);
				}
			}
		];

		var totalBytes = 0;
		totalBytes += 4 + 4 + 4 + 4 + 8 + 8; // diffSize + specSize + ignoredSpecLevels + sampleBits + threshold + scale
		totalBytes += lutPixels.bytes.length;
		for( p in diffusePixels )
			totalBytes += p.bytes.length;
		for( p in specularPixels )
			totalBytes += p.bytes.length;
		var bytes = haxe.io.Bytes.alloc(totalBytes);
		var curPos = 0;
		bytes.setInt32(curPos, sampleBits);
		curPos += 4;
		bytes.setInt32(curPos, diffSize);
		curPos += 4;
		bytes.setInt32(curPos, specSize);
		curPos += 4;
		bytes.setInt32(curPos, ignoredSpecLevels);
		curPos += 4;
		bytes.setDouble(curPos, threshold);
		curPos += 8;
		bytes.setDouble(curPos, scale);
		curPos += 8;
		bytes.blit(curPos, lutPixels.bytes, 0, lutPixels.bytes.length);
		curPos += lutPixels.bytes.length;
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

	function convertFromBinary( bytes : haxe.io.Bytes ) {
		var curPos = 0;

		var headerSize = 4 + 4 + 4 + 4 + 8 + 8;
		if( headerSize > bytes.length )
			return false;

		var bakedSampleBits = bytes.getInt32(curPos);
		curPos += 4;
		var bakedDiffSize = bytes.getInt32(curPos);
		curPos += 4;
		var bakedSpecSize = bytes.getInt32(curPos);
		curPos += 4;
		var bakedIgnoredSpecLevels = bytes.getInt32(curPos);
		curPos += 4;
		var bakedThreshold = bytes.getDouble(curPos);
		curPos += 8;
		var bakedScale = bytes.getDouble(curPos);
		curPos += 8;

		if( bakedDiffSize != diffSize || bakedSpecSize != specSize || bakedIgnoredSpecLevels != ignoredSpecLevels || bakedSampleBits != sampleBits || bakedThreshold != threshold || bakedScale != scale )
			return false;
		
		var lutSize = hxd.Pixels.calcStride(env.lut.width, env.lut.format) * env.lut.height;
		if( curPos + lutSize > bytes.length ) return false;
		var lutBytes = bytes.sub(curPos, lutSize);
		curPos += lutBytes.length;
		if( curPos > bytes.length ) return false;
		var lutPixels : hxd.Pixels.PixelsFloat = new hxd.Pixels(env.lut.width, env.lut.height, lutBytes, env.lut.format);
		env.lut.uploadPixels(lutPixels);

		var diffSize = hxd.Pixels.calcStride(env.diffuse.width, env.diffuse.format) * env.diffuse.height;
		for( i in 0 ... 6 ) {
			if( curPos + diffSize > bytes.length ) return false;
			var diffByte = bytes.sub(curPos, diffSize);
			curPos += diffByte.length;
			if( curPos > bytes.length ) return false;
			var diffPixels : hxd.Pixels.PixelsFloat = new hxd.Pixels(env.diffuse.width, env.diffuse.height, diffByte, env.diffuse.format);
			env.diffuse.uploadPixels(diffPixels, 0, i);
		}

		var mipLevels = env.getMipLevels();
		env.specLevels = mipLevels - ignoredSpecLevels;
		for( i in 0 ... 6 ) {
			for( m in 0 ... env.specLevels ) {
				var mipMapSize = hxd.Pixels.calcStride(env.specular.width >> m, env.specular.format) * env.specular.height >> m;
				if( curPos + mipMapSize > bytes.length ) return false;
				var specByte = bytes.sub(curPos, mipMapSize);
				curPos += specByte.length;
				if( curPos > bytes.length ) return false;
				var specPixels : hxd.Pixels.PixelsFloat = new hxd.Pixels(env.specular.width >> m, env.specular.height >> m, specByte, env.specular.format);
				env.specular.uploadPixels(specPixels, m, i);
			}
		}

		return true;
	}

	function compute( ctx: Context ) {
		trace("compute");
		env.compute();
		#if editor
		saveAsBinary(ctx);
		#end
	}

	override function makeInstance( ctx : Context ) : Context {
		ctx = ctx.clone(this);
		var obj = new h3d.scene.Object(ctx.local3d);
		ctx.local3d = obj;
		ctx.local3d.name = name;
		updateInstance(ctx);
		return ctx;
	}

	override function updateInstance( ctx : Context, ?propName : String ) {
		super.updateInstance(ctx, propName);

		var sourceMap = sourceMapPath != null ? ctx.loadTexture(sourceMapPath) : null;
		if( sourceMap == null )
			return;

		var needCompute = false;

		if( env == null ) {
			env = new h3d.scene.pbr.Environment(sourceMap);
			needCompute = true;
		}

		if( sourceMap != env.source ) {
			env.source = sourceMap;
			needCompute = true;
		}

		if( env.specSize != specSize ) {
			if( env.specular != null ) env.specular.dispose();
			env.specular = null;
			needCompute = true;
		}
		env.specSize = specSize;

		if( env.diffSize != diffSize ) {
			if( env.diffuse != null ) env.diffuse.dispose();
			env.diffuse = null;
			needCompute = true;
		}
		env.diffSize = diffSize;

		if( propName == null || propName == "sampleBits" || propName == "ignoredSpecLevels" || propName == "threshold" || propName == "scale" ) {
			env.sampleBits = sampleBits;
			env.ignoredSpecLevels = ignoredSpecLevels;
			env.threshold = threshold;
			env.scale = scale;
			needCompute = true;
		}

		env.rot = rotation;
		env.power = power;

		env.createTextures();

		if( needCompute ) {
			var loadFromBinarySucces = loadFromBinary(ctx);
			if( !loadFromBinarySucces )
				compute(ctx);
		}

		applyToRenderer(ctx);
	}

	function applyToRenderer( ctx : Context ) {
		var pbrRenderer = Std.downcast(ctx.local3d.getScene().renderer, h3d.scene.pbr.Renderer);
		if( pbrRenderer != null ) {
			pbrRenderer.env = env;
		}
	}

	#if editor

	override function getHideProps() : HideProps {
		return { icon : "sun-o", name : "Environment" };
	}

	override function edit( ctx : EditContext ) {
		// super.edit(ctx);

		var props = new hide.Element('
			<div class="group" name="Environment">
				<div align="center" >
					<input type="button" value="Set Current" class="apply" />
				</div>
				<dl>
					<dt>SkyBox</dt><dd><input type="texturepath" field="sourceMapPath"/></dd>
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
			</div>
			');

			var applyButton = props.find(".apply");
			applyButton.click(function(_) {
				applyToRenderer(ctx.rootContext);
			});

			ctx.properties.add(props, this, function(pname) { ctx.onChange(this, pname); });
	}

	#end

	static var _ = Library.register("environment", Environment);
}