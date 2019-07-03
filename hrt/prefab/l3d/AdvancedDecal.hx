package hrt.prefab.l3d;

class AdvancedDecal extends Object3D {

	var albedoMap : String;
	var normalMap : String;
	var pbrMap : String;
	var albedoStrength : Float = 1.0;
	var normalStrength: Float = 1.0;
	var pbrStrength: Float = 1.0;
	var fadePower : Float = 1.0;
	var fadeStart : Float = 0;
	var fadeEnd : Float = 1.0;
	var emissive : Float = 0.0;
	var blendMode : h2d.BlendMode = Alpha;
	var renderMode : h3d.mat.PbrMaterial.PbrMode = Decal;
	var centered : Bool = true;

	override function save() {
		var obj : Dynamic = super.save();
		if(albedoMap != null) obj.albedoMap = albedoMap;
		if(normalMap != null) obj.normalMap = normalMap;
		if(pbrMap != null) obj.pbrMap = pbrMap;
		if(albedoStrength != 1) obj.albedoStrength = albedoStrength;
		if(normalStrength != 1) obj.normalStrength = normalStrength;
		if(pbrStrength != 1) obj.pbrStrength = pbrStrength;
		if(blendMode != Alpha) obj.blendMode = blendMode.getIndex();
		if(centered != true) obj.centered = centered;
		if(fadePower != 1) obj.fadePower = fadePower;
		if(fadeStart != 0) obj.fadeStart = fadeStart;
		if(fadeEnd != 1) obj.fadeEnd = fadeEnd;
		if(renderMode != Decal) obj.renderMode = renderMode;
		if(emissive != 0.0) obj.emissive = emissive;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		albedoMap = obj.albedoMap;
		normalMap = obj.normalMap;
		pbrMap = obj.pbrMap;
		albedoStrength = obj.albedoStrength != null ? obj.albedoStrength : 1;
		normalStrength = obj.normalStrength != null ? obj.normalStrength : 1;
		pbrStrength = obj.pbrStrength != null ? obj.pbrStrength : 1;
		blendMode = obj.blendMode != null ? h2d.BlendMode.createByIndex(obj.blendMode) : Alpha;
		centered = obj.centered != null ? obj.centered : true;
		fadePower = obj.fadePower != null ? obj.fadePower : 1;
		fadeStart = obj.fadeStart != null ? obj.fadeStart : 0;
		fadeEnd = obj.fadeEnd != null ? obj.fadeEnd : 1;
		renderMode = obj.renderMode != null ? obj.renderMode : Decal;
		emissive = obj.emissive != null ? obj.emissive : 0.0;
	}

	override function makeInstance(ctx:Context) : Context {
		ctx = ctx.clone(this);
		var mesh = new h3d.scene.pbr.Decal(h3d.prim.Cube.defaultUnitCube(), ctx.local3d);

		switch (renderMode) {
			case Decal:
				var shader = mesh.material.mainPass.getShader(h3d.shader.pbr.VolumeDecal.DecalPBR);
				if( shader == null ) {
					shader = new h3d.shader.pbr.VolumeDecal.DecalPBR();
					//mesh.material.mainPass.colorMask
					mesh.material.mainPass.addShader(shader);
				}
				mesh.material.mainPass.setPassName("decal");
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
			default:
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
		mesh.material.blendMode = blendMode;
		switch (renderMode) {
			case Decal:
				var shader = mesh.material.mainPass.getShader(h3d.shader.pbr.VolumeDecal.DecalPBR);
				if( shader != null ){
					shader.albedoTexture = albedoMap != null ? ctx.loadTexture(albedoMap) : null;
					shader.normalTexture = normalMap != null ? ctx.loadTexture(normalMap) : null;
					shader.pbrTexture = pbrMap != null ? ctx.loadTexture(pbrMap) : null;
					if(shader.albedoTexture != null) shader.albedoTexture.wrap = Repeat;
					if(shader.normalTexture != null) shader.normalTexture.wrap = Repeat;
					if(shader.pbrTexture != null) shader.pbrTexture.wrap = Repeat;
					shader.albedoStrength = albedoStrength;
					shader.normalStrength = normalStrength;
					shader.pbrStrength = pbrStrength;
					shader.USE_ALBEDO = albedoStrength != 0;
					shader.USE_NORMAL = normalStrength != 0;
					shader.USE_PBR = pbrStrength != 0;
					shader.CENTERED = centered;
					shader.fadePower = fadePower;
					shader.fadeStart = fadeStart;
					shader.fadeEnd = fadeEnd;
				}
			case BeforeTonemapping, AfterTonemapping:
				var shader = mesh.material.mainPass.getShader(h3d.shader.pbr.VolumeDecal.DecalOverlay);
				if( shader != null ){
					shader.colorTexture = albedoMap != null ? ctx.loadTexture(albedoMap) : null;
					if(shader.colorTexture != null) shader.colorTexture.wrap = Repeat;
					shader.CENTERED = centered;
					shader.fadePower = fadePower;
					shader.fadeStart = fadeStart;
					shader.fadeEnd = fadeEnd;
					shader.emissive = emissive;
				}
			default:
		}
	}

	override function updateInstance( ctx : Context, ?propName : String ) {
		super.updateInstance(ctx,propName);
		updateRenderParams(ctx);
	}

	#if editor
	override function getHideProps() : HideProps {
		return { icon : "paint-brush", name : "AdvancedDecal" };
	}

	override function setSelected( ctx : Context, b : Bool ) {
		if( b ) {
			var obj = ctx.shared.contexts.get(this).local3d;
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
		} else {
			clearSelection( ctx );
		}
	}

	function clearSelection( ctx : Context ) {

		var obj = ctx.shared.contexts.get(this).local3d;
		var objs = obj.findAll( o -> if(o.name == "_highlight") o else null );
		for( o in objs )
			o.remove();
	}

	var pbrParams = '<dt>Albedo</dt><dd><input type="texturepath" field="albedoMap"/>
					<br/><input type="range" min="0" max="1" field="albedoStrength"/></dd>

					<dt>Normal</dt><dd><input type="texturepath" field="normalMap"/>
					<br/><input type="range" min="0" max="1" field="normalStrength"/></dd>

					<dt>PBR</dt><dd><input type="texturepath" field="pbrMap"/>
					<br/><input type="range" min="0" max="1" field="pbrStrength"/></dd>';

	var overlayParams = '<dt>Color</dt><dd><input type="texturepath" field="albedoMap"/>
						<dt>Emissive</dt><dd> <input type="range" min="0" max="10" field="emissive"/></dd>';

	override function edit( ctx : EditContext ) {
		super.edit(ctx);

		var params = switch (renderMode) {
			case Decal: pbrParams;
			case BeforeTonemapping: overlayParams;
			default: null;
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
							<option value="Decal">PBR</option>
							<option value="BeforeTonemapping">Before Tonemapping</option>
							<option value="AfterTonemapping">After Tonemapping</option>
						</select></dd>

						<dt>Blend Mode</dt>
						<dd><select field="blendMode">
							<option value="Alpha">Alpha</option>
							<option value="Add">Add</option>
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

	static var _ = Library.register("advancedDecal", AdvancedDecal);

}