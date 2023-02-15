package hrt.prefab2.l3d;


@:access(h3d.scene.pbr.Environment)
class Environment extends Object3D {

	@:s public var power : Float = 1.0;
	@:s public var hdrMax : Float = 10.0;
	@:s public var rotation : Float = 0.0;
	@:s public var sampleBits : Int = 12;
	@:s public var diffSize : Int = 64;
	@:s public var specSize : Int = 512;
	@:s public var ignoredSpecLevels : Int = 1;

	@:s var sourceMapPath : String;
	@:s var configName : String;
	var env : h3d.scene.pbr.Environment;

	public function new( ?parent ) {
		super(parent);
	}

	function loadFromBinary() {
		try {
			env.dispose();
			env.diffuse = hxd.res.Loader.currentInstance.load(getBinaryPath(true)).toImage().toTexture();
			env.specular = hxd.res.Loader.currentInstance.load(getBinaryPath(false)).toImage().toTexture();
			env.specular.mipMap = Linear;
			env.specLevels = env.getMipLevels() - ignoredSpecLevels;
			return true;
		} catch( e : hxd.res.NotFound ) {
			return false;
		}
	}

	function getBinaryPath( diffuse : Bool ) {
		var path = new haxe.io.Path(sourceMapPath);
		if( configName != null )
			path.file += "-" + configName;
		path.ext = diffuse ? "envd" : "envs";
		return path.toString();
	}

	function saveToBinary() {
		#if (hl || hxnodejs)
		var fs = cast(hxd.res.Loader.currentInstance.fs, hxd.fs.LocalFileSystem);
		if( fs == null ) return;
		var diffuse = hxd.Pixels.toDDSLayers([for( i in 0...6 ) env.diffuse.capturePixels(i)],true);
		sys.io.File.saveBytes(fs.baseDir + getBinaryPath(true), diffuse);
		var specular = hxd.Pixels.toDDSLayers([for( i in 0...6 ) for( mip in 0...env.getMipLevels() ) env.specular.capturePixels(i,mip)],true);
		sys.io.File.saveBytes(fs.baseDir + getBinaryPath(false), specular);
		#end
	}

	override function makeObject3d(parent3d:h3d.scene.Object):h3d.scene.Object {
        return super.makeObject3d(parent3d);
    }

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);

		if( sourceMapPath == null )
			return;

		#if editor
		var sourceMap = loadTexture(sourceMapPath);
		if( sourceMap == null )
			return;
		if( sourceMap.flags.has(Loading) ) {
			haxe.Timer.delay(function() {
				shared.scene.setCurrent();
				if( h3d.Engine.getCurrent().driver == null ) return; // was disposed
				updateInstance(propName);
			},100);
			return;
		}
		#end

		var needLoad = false;
		if( env == null ) {
			env = new h3d.scene.pbr.Environment(null);
			needLoad = true;
		}

		if( configName != null ) {
			configName = StringTools.trim(configName);
			if( configName == "" ) configName = null;
		}

		if( env.source != null && env.source.name != sourceMapPath )
			needLoad = true;

		env.specSize = specSize;
		env.diffSize = diffSize;
		env.sampleBits = sampleBits;
		env.ignoredSpecLevels = ignoredSpecLevels;
		env.hdrMax = hdrMax;

		env.rotation = hxd.Math.degToRad(rotation);
		env.power = power;

		if( propName == "force" || (needLoad && !loadFromBinary()) ) {
			env.dispose();
			env.specular = null;
			env.diffuse = null;
			env.source = loadTexture(sourceMapPath);
			env.compute();
			saveToBinary();
		}

		var scene = local3d.getScene();
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

	override function getHideProps() : hide.prefab2.HideProps {
		return { icon : "sun-o", name : "Environment" };
	}

	override function edit( ctx : hide.prefab2.EditContext ) {
		// super.edit(ctx);

		var props = new hide.Element('
			<div class="group" name="Environment">
				<div align="center" >
					<input type="button" value="Set Current" class="apply" />
				</div>
				<dl>
					<dt>SkyBox</dt><dd><input type="texturepath" field="sourceMapPath"/></dd>
					<dt>Rotation</dt><dd><input type="range" min="0" max="360" field="rotation"/></dd>
					<dt>Power</dt><dd><input type="range" min="0" max="2" field="power"/></dd>
				</dl>
			</div>
			<div class="group closed" name="Generation">
				<dl>
					<dt>Diffuse</dt><dd><input type="range" min="1" max="512" step="1" field="diffSize"/></dd>
					<dt>Specular</dt><dd><input type="range" min="1" max="2048" step="1" field="specSize"/></dd>
					<dt>Sample Count</dt><dd><input type="range" min="1" max="12" step="1" field="sampleBits"/></dd>
					<dt>Ignored Spec Levels</dt><dd><input type="range" min="0" max="3" step="1" field="ignoredSpecLevels"/></dd>
					<dt>HDR Max</dt><dd><input type="range" min="0" max="100" field="hdrMax"/></dd>
					<dt>Config Name</dt><dd><input type="text" field="configName"/></dd>
					<dt>&nbsp;</dt><dd><input type="button" class="compute" value="Compute"/></dd>
					<dt>View</dt><dd>
						<input type="button" style="width:90px" class="showDif" value="Diffuse"/>
						<input type="button" style="width:90px" class="showSpec" value="Specular"/>
					</dd>
				</dl>
			</div>
		');

		var applyButton = props.find(".apply");
		applyButton.click(function(_) {
			applyToRenderer(findFirstLocal3d().getScene().renderer);
		});

		props.find(".compute").click(function(_) {
			ctx.onChange(this,"force");
		});

		props.find(".showDif").click(function(_) {
			ctx.ide.openFile(getBinaryPath(true));
		});

		props.find(".showSpec").click(function(_) {
			ctx.ide.openFile(getBinaryPath(false));
		});

		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
	}

	#end

	static var _ = Prefab.register("environment", Environment);
}