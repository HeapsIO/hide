package hrt.prefab.pbr;

import h3d.pass.Default;
import hrt.shader.AnisotropicForward;

enum abstract AnisotropyMode(String) {
	var Flat;
	var Texture;
	var Frequency;
}

class Anisotropy extends Prefab {

	@:s public var mode : AnisotropyMode = Flat;

	@:s public var intensity : Float = 0.0;
	@:s public var direction : Float = 0.0;

	@:s public var noiseFrequency : Float = 0.0;
	@:s public var noiseIntensity : Float = 1.0;

	@:s public var intensityFactor = 1.0;
	@:s public var noiseIntensityPath : String = null;
	@:s public var noiseDirectionPath : String = null;
	@:s public var rotationOffset : Float = 0.0;

	public function new(?parent) {
		super(parent);
		type = "anisotropy";
	}

	function getMaterials( ctx : Context ) {
		if( Std.is(parent, Material) ) {
			var material : Material = cast parent;
			return material.getMaterials(ctx);
		}
		else {
			return ctx.local3d.getMaterials();
		}
	}

	override function makeInstance( ctx : Context ):Context {
		ctx = ctx.clone(this);
		refreshShaders(ctx);
		updateInstance(ctx);
		return ctx;
	}

	function refreshShaders( ctx : Context ) {
		var fv = new FlatValue();
		var as = new AnisotropicForward();
		var nt = new NoiseTexture();
		var ff = new FrequencyValue();

		var noiseIntensityTexture = noiseIntensityPath != null ? ctx.loadTexture(noiseIntensityPath) : null;
		var noiseDirectionTexture = noiseDirectionPath != null ? ctx.loadTexture(noiseDirectionPath) : null;

		var mat = getMaterials(ctx);

		for( m in mat ) {
			m.mainPass.removeShader(m.mainPass.getShader(NoiseTexture));
			m.mainPass.removeShader(m.mainPass.getShader(FlatValue));
			m.mainPass.removeShader(m.mainPass.getShader(FrequencyValue));
			m.mainPass.removeShader(m.mainPass.getShader(AnisotropicForward));
		}

		for( m in mat ) {

			if( m.mainPass.name != "forward" )
				continue;

			if( mode == Texture && noiseIntensityTexture != null && noiseDirectionTexture != null ) {
				m.mainPass.addShader(nt);
			}
			else {
				switch mode {
					case Texture,Flat: m.mainPass.addShader(fv);
					case Frequency:	m.mainPass.addShader(ff);
					default:
				}
			}

			m.mainPass.addShader(as);
		}
	}

	override function updateInstance( ctx : Context, ?propName : String ) {
		for( m in getMaterials(ctx) ) {

			var fv = m.mainPass.getShader(FlatValue);
			if( fv != null ) {
				fv.intensity = intensity;
				var angle = hxd.Math.degToRad(direction);
				fv.dirVector.set(hxd.Math.cos(angle), hxd.Math.sin(angle), 0);
			}

			var ff = m.mainPass.getShader(FrequencyValue);
			if( ff != null ) {
				ff.intensity = intensity;
				ff.noiseFrequency = noiseFrequency;
				ff.noiseIntensity = noiseIntensity;
				var angle = hxd.Math.degToRad(direction);
				ff.dirVector.set(hxd.Math.cos(angle), hxd.Math.sin(angle), 0);
			}

			var nt = m.mainPass.getShader(NoiseTexture);
			if( nt != null ) {
				nt.noiseIntensityTexture = noiseIntensityPath != null ? ctx.loadTexture(noiseIntensityPath) : null;
				nt.noiseDirectionTexture = noiseDirectionPath != null ? ctx.loadTexture(noiseDirectionPath) : null;
				nt.intensityFactor = intensityFactor;
				nt.rotationOffset = hxd.Math.degToRad(rotationOffset);
			}
		}
	}

	#if editor
	override function getHideProps() : HideProps {
		return { 	icon : "cube",
					name : "Anisotropy",
					allowParent : function(p) return p.to(Material) != null  };
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		var flatParams = 	'<dt>Intensity</dt><dd><input type="range" min="0" max="1" field="intensity"/></dd>
							<dt>Direction</dt><dd><input type="range" min="0" max="360" field="direction"/></dd>';

		var textureParams = '<dt>Factor</dt><dd><input type="range" min="0" max="1" field="intensityFactor"/></dd>
							<dt>Rotation Offset</dt><dd><input type="range" min="0" max="360" field="rotationOffset"/></dd>
							<dt>Intensity</dt><dd><input type="texturepath" field="noiseIntensityPath"/>
							<dt>Direction</dt><dd><input type="texturepath" field="noiseDirectionPath"/>';

		var frequencyParams =	'<dt>Intensity</dt><dd><input type="range" min="0" max="1" field="intensity"/></dd>
								<dt>Noise Intensity</dt><dd><input type="range" min="0" max="1" field="noiseIntensity"/></dd>
								<dt>Noise Frequency</dt><dd><input type="range" min="0" max="100" field="noiseFrequency"/></dd>
								<dt>Direction</dt><dd><input type="range" min="0" max="360" field="direction"/></dd>';

		var params = switch mode {
			case Flat: flatParams;
			case Texture: textureParams;
			case Frequency: frequencyParams;
		};

		var props = new hide.Element('
			<div class="group" name="Anisotropy">
				<dl>
					<dt>Mode</dt>
						<dd>
							<select field="mode">
								<option value="Flat">Flat</option>
								<option value="Texture">Texture</option>
								<option value="Frequency">Frequency</option>
							</select>
						</dd>
					' + params + '
				</dl>
			</div>
		');

		ctx.properties.add(props, this, function(pname) {
			if( pname == "mode" || pname == "noiseIntensityPath" || pname == "noiseDirectionPath" ) {
				ctx.rebuildProperties();
				refreshShaders(ctx.getContext(this));
			}
			ctx.onChange(this, pname);
		});
	}
	#end

	static var _ = Library.register("anisotropy", Anisotropy);
}