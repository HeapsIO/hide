package hrt.prefab.l3d;


@:access(h3d.scene.pbr.Environment)
class Environment extends Object3D {

	var sourceMapPath : String;
	var configName : String;
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
		configName = obj.configName;
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
		if( configName != null ) obj.configName = configName;
		return obj;
	}

	function loadFromBinary() {
		var path = new haxe.io.Path(sourceMapPath);
		try {
			env.dispose();
			if( configName != null )
				path.file += "-" + configName;
			path.ext = "envd.dds";
			env.diffuse = hxd.res.Loader.currentInstance.load(path.toString()).toImage().toTexture();
			path.ext = "envs.dds";
			env.specular = hxd.res.Loader.currentInstance.load(path.toString()).toImage().toTexture();
			return true;
		} catch( e : hxd.res.NotFound ) {
			return false;
		}
	}

	function saveToBinary() {
		#if (hl || hxnodejs)
		var fs = cast(hxd.res.Loader.currentInstance.fs, hxd.fs.LocalFileSystem);
		if( fs == null ) return;
		var path = new haxe.io.Path(fs.baseDir+sourceMapPath);
		if( configName != null )
			path.file += "-" + configName;
		var diffuse = hxd.Pixels.toDDS([for( i in 0...6 ) env.diffuse.capturePixels(i)],true);
		path.ext = "envd.dds";
		sys.io.File.saveBytes(path.toString(), diffuse);
		var specular = hxd.Pixels.toDDS([for( i in 0...6 ) for( mip in 0...env.getMipLevels() ) env.specular.capturePixels(i,mip)],true);
		path.ext = "envs.dds";
		sys.io.File.saveBytes(path.toString(), specular);
		#end
	}

	override function makeInstance( ctx : Context ) : Context {
		super.makeInstance(ctx);
		updateInstance(ctx);
		return ctx;
	}

	override function updateInstance( ctx : Context, ?propName : String ) {
		super.updateInstance(ctx, propName);

		var sourceMap = sourceMapPath != null ? ctx.loadTexture(sourceMapPath) : null;
		if( sourceMap == null )
			return;

		#if editor
		if( sourceMap.flags.has(Loading) ) {
			haxe.Timer.delay(function() {
				ctx.setCurrent();
				if( h3d.Engine.getCurrent().driver == null ) return; // was disposed
				updateInstance(ctx,propName);
			},100);
			return;
		}
		#end

		var needLoad = false;
		if( env == null )
			env = new h3d.scene.pbr.Environment(null);

		if( configName != null ) {
			configName = StringTools.trim(configName);
			if( configName == "" ) configName = null;
		}

		if( env.source != sourceMap ) {
			env.source = sourceMap;
			needLoad = true;
		}

		env.specSize = specSize;
		env.diffSize = diffSize;
		env.sampleBits = sampleBits;
		env.ignoredSpecLevels = ignoredSpecLevels;
		env.threshold = threshold;
		env.scale = scale;

		env.rot = rotation;
		env.power = power;

		if( propName == "force" || (needLoad && !loadFromBinary()) ) {
			env.dispose();
			env.specular = null;
			env.diffuse = null;
			env.compute();
			saveToBinary();
		}

		var scene = ctx.local3d.getScene();
		// Auto Apply on change
		if( scene != null )
			applyToRenderer(scene.renderer);
	}

	public function applyToRenderer( r : h3d.scene.Renderer) {
		var r = Std.downcast(r, h3d.scene.pbr.Renderer);
		if( r != null )
			r.env = env;
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
			<div class="group closed" name="Generation">
				<dl>
					<dt>Diffuse</dt><dd><input type="range" min="1" max="512" step="1" field="diffSize"/></dd>
					<dt>Specular</dt><dd><input type="range" min="1" max="2048" step="1" field="specSize"/></dd>
					<dt>Sample Count</dt><dd><input type="range" min="1" max="12" step="1" field="sampleBits"/></dd>
					<dt>Ignored Spec Levels</dt><dd><input type="range" min="0" max="3" step="1" field="ignoredSpecLevels"/></dd>
					<dt>HDR Threshold</dt><dd><input type="range" min="0" max="1" step="0.1" field="threshold"/></dd>
					<dt>HDR Scale</dt><dd><input type="range" min="0" max="10" field="scale"/></dd>
					<dt>Config Name</dt><dd><input type="text" field="configName"/></dd>
					<dt>&nbsp;</dt><dd><input type="button" class="compute" value="Compute"/></dd>
				</dl>
			</div>
		');

		var applyButton = props.find(".apply");
		applyButton.click(function(_) {
			applyToRenderer(ctx.rootContext.local3d.getScene().renderer);
		});

		props.find(".compute").click(function(_) {
			ctx.onChange(this,"force");
		});

		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	#end

	static var _ = Library.register("environment", Environment);
}