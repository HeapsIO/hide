package hrt.prefab.l3d;

enum abstract DecalMode(String) {
	var Default;
	var BeforeTonemapping;
	var AfterTonemapping;
	var Terrain;
}

class Decal extends Object3D {

	@:s var albedoMap : String;
	@:s var normalMap : String;
	@:s var pbrMap : String;
	@:s var albedoStrength : Float = 1.0;
	@:s var normalStrength: Float = 1.0;
	@:s var pbrStrength: Float = 1.0;
	@:s var fadePower : Float = 1.0;
	@:s var fadeStart : Float = 0;
	@:s var fadeEnd : Float = 1.0;
	@:s var emissive : Float = 0.0;
	@:s var renderMode : DecalMode = Default;
	@:s var centered : Bool = true;
	@:s var autoAlpha : Bool = true;
	@:c var blendMode : h2d.BlendMode = Alpha;

	override function save() {
		var obj : Dynamic = super.save();
		if(blendMode != Alpha) obj.blendMode = blendMode.getIndex();
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		blendMode = obj.blendMode != null ? h2d.BlendMode.createByIndex(obj.blendMode) : Alpha;
	}

	override function makeInstance(ctx:Context) : Context {
		ctx = ctx.clone(this);
		var mesh = new h3d.scene.pbr.Decal(h3d.prim.Cube.defaultUnitCube(), ctx.local3d);

		switch (renderMode) {
			case Default, Terrain:
				var shader = mesh.material.mainPass.getShader(h3d.shader.pbr.VolumeDecal.DecalPBR);
				if( shader == null ) {
					shader = new h3d.shader.pbr.VolumeDecal.DecalPBR();
					mesh.material.mainPass.addShader(shader);
				}
				mesh.material.mainPass.setPassName(renderMode == Default ? "decal" : "terrainDecal");
			case BeforeTonemapping:
				var shader = mesh.material.mainPass.getShader(h3d.shader.pbr.VolumeDecal.DecalOverlay);
				if( shader == null ) {
					shader = new h3d.shader.pbr.VolumeDecal.DecalOverlay();
					mesh.material.mainPass.addShader(shader);
				}
				mesh.material.mainPass.setPassName("beforeTonemappingDecal");
			case AfterTonemapping:
				var shader = mesh.material.mainPass.getShader(h3d.shader.pbr.VolumeDecal.DecalOverlay);
				if( shader == null ) {
					shader = new h3d.shader.pbr.VolumeDecal.DecalOverlay();
					mesh.material.mainPass.addShader(shader);
				}
				mesh.material.mainPass.setPassName("afterTonemappingDecal");
		}

		mesh.material.mainPass.depthWrite = false;
		mesh.material.mainPass.depthTest = GreaterEqual;
		mesh.material.mainPass.culling = Front;
		mesh.material.shadows = false;
		ctx.local3d = mesh;
		ctx.local3d.name = name;
		updateInstance(ctx);
		return ctx;
	}

	public function updateRenderParams(ctx) {
		var mesh = Std.downcast(ctx.local3d, h3d.scene.Mesh);
		mesh.material.mainPass.setBlendMode(blendMode);
		switch (renderMode) {
			case Default, Terrain:
				var shader = mesh.material.mainPass.getShader(h3d.shader.pbr.VolumeDecal.DecalPBR);
				if( shader != null ){
					shader.albedoTexture = albedoMap != null ? ctx.loadTexture(albedoMap) : null;
					shader.normalTexture = normalMap != null ? ctx.loadTexture(normalMap) : null;
					if(shader.albedoTexture != null) shader.albedoTexture.wrap = Repeat;
					if(shader.normalTexture != null) shader.normalTexture.wrap = Repeat;
					shader.albedoStrength = albedoStrength;
					shader.normalStrength = normalStrength;
					shader.pbrStrength = pbrStrength;
					shader.USE_ALBEDO = albedoStrength != 0&& shader.albedoTexture != null;
					shader.USE_NORMAL = normalStrength != 0 && shader.normalTexture != null;
					shader.CENTERED = centered;
					shader.fadePower = fadePower;
					shader.fadeStart = fadeStart;
					shader.fadeEnd = fadeEnd;
				}
				var pbrTexture = pbrMap != null ? ctx.loadTexture(pbrMap) : null;
				if( pbrTexture != null ) {
					var propsTexture = mesh.material.mainPass.getShader(h3d.shader.pbr.PropsTexture);
					if( propsTexture == null ) 
						propsTexture = mesh.material.mainPass.addShader(new h3d.shader.pbr.PropsTexture());
					propsTexture.texture = pbrTexture;
					propsTexture.texture.wrap = Repeat;
				}
				else {
					mesh.material.mainPass.removeShader(mesh.material.mainPass.getShader( h3d.shader.pbr.PropsTexture));
				}
			case BeforeTonemapping, AfterTonemapping:
				var shader = mesh.material.mainPass.getShader(h3d.shader.pbr.VolumeDecal.DecalOverlay);
				if( shader != null ){
					shader.colorTexture = albedoMap != null ? ctx.loadTexture(albedoMap) : null;
					if(shader.colorTexture != null) shader.colorTexture.wrap = Repeat;
					shader.CENTERED = centered;
					shader.GAMMA_CORRECT = renderMode == BeforeTonemapping;
					shader.AUTO_ALPHA = autoAlpha;
					shader.fadePower = fadePower;
					shader.fadeStart = fadeStart;
					shader.fadeEnd = fadeEnd;
					shader.emissive = emissive;
				}
		}
	}

	override function updateInstance( ctx : Context, ?propName : String ) {
		super.updateInstance(ctx,propName);
		updateRenderParams(ctx);
	}

	#if editor
	override function getHideProps() : HideProps {
		return { icon : "paint-brush", name : "Decal" };
	}

	override function setSelected( ctx : Context, b : Bool ) {
		if( b ) {
			var obj = ctx.shared.getSelfObject(this);
			if(obj != null) {
				var wire = new h3d.scene.Box(0xFFFFFFFF,obj);
				wire.name = "_highlight";
				wire.material.setDefaultProps("ui");
				wire.ignoreCollide = true;
				wire.material.shadows = false;
				var wireCenter = new h3d.scene.Box(0xFFFF00, obj);
				wireCenter.scaleZ = 0;
				wireCenter.name = "_highlight";
				wireCenter.material.setDefaultProps("ui");
				wireCenter.ignoreCollide = true;
				wireCenter.material.shadows = false;
				wireCenter.material.mainPass.depthTest = Always;
			}
		} else {
			clearSelection( ctx );
		}
		return true;
	}

	function clearSelection( ctx : Context ) {
		var obj = ctx.shared.getSelfObject(this);
		if(obj == null) return;
		var objs = obj.findAll( o -> if(o.name == "_highlight") o else null );
		for( o in objs )
			o.remove();
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		var pbrParams = '<dt>Albedo</dt><dd><input type="texturepath" field="albedoMap"/>
					<br/><input type="range" min="0" max="1" field="albedoStrength"/></dd>

					<dt>Normal</dt><dd><input type="texturepath" field="normalMap"/>
					<br/><input type="range" min="0" max="1" field="normalStrength"/></dd>

					<dt>PBR</dt><dd><input type="texturepath" field="pbrMap"/>
					<br/><input type="range" min="0" max="1" field="pbrStrength"/></dd>';

		var overlayParams = '<dt>Color</dt><dd><input type="texturepath" field="albedoMap"/></dd>
						<dt>Emissive</dt><dd> <input type="range" min="0" max="10" field="emissive"/></dd>
						<dt>AutoAlpha</dt><dd><input type="checkbox" field="autoAlpha"/></dd>';

		var params = switch (renderMode) {
			case Default, Terrain: pbrParams;
			case BeforeTonemapping: overlayParams;
			case AfterTonemapping: overlayParams;
		}

		function refreshProps() {
			var props = ctx.properties.add(new hide.Element('
			<div class="decal">
				<div class="group" name="Decal">
					<dl>
						<dt>Centered</dt><dd><input type="checkbox" field="centered"/></dd>'
						+ params +
						'<dt>Render Mode</dt>
						<dd><select field="renderMode">
							<option value="Default">Default</option>
							<option value="BeforeTonemapping">Before Tonemapping</option>
							<option value="AfterTonemapping">After Tonemapping</option>
							<option value="Terrain">Terrain</option>
						</select></dd>

						<dt>Blend Mode</dt>
						<dd><select field="blendMode">
							<option value="Alpha">Alpha</option>
							<option value="Add">Add</option>
							<option value="Multiply">Multiply</option>
						</select></dd>
					</dl>
				</div>
				<div class="group" name="Fade">
					<dt>FadePower</dt><dd> <input type="range" min="0" max="3" field="fadePower"/></dd>
					<dt>Start</dt><dd> <input type="range" min="0" max="1" field="fadeStart"/></dd>
					<dt>End</dt><dd> <input type="range" min="0" max="1" field="fadeEnd"/></dd>
				</div>
			</div>
			'),this, function(pname) {
				if( pname == "renderMode" ) {
					clearSelection( ctx.rootContext );
					ctx.rebuildPrefab(this);
					ctx.rebuildProperties();
				}
				else
					ctx.onChange(this, pname);
			});
		}

		refreshProps();
	}
	#end

	static var _ = Library.register("advancedDecal", Decal);

}