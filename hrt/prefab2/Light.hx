package hrt.prefab2;

enum abstract LightKind(String) {
	var Point;
	var Directional;
	var Spot;
}

typedef LightShadows = {
	var mode : h3d.pass.Shadows.RenderMode;
	var size : Int;
	var bias : Float;
	var radius : Float;
	var quality : Float;
	var samplingMode : ShadowSamplingMode;
}

enum abstract ShadowSamplingKind(String) {
	var None;
	var PCF;
	var ESM;
}

typedef ShadowSamplingMode = {
	var kind : ShadowSamplingKind;
}

typedef ShadowSamplingESM = {> ShadowSamplingMode,
	var power : Float;
}

typedef ShadowSamplingPCF = {> ShadowSamplingMode,
	var quality : Int;
	var scale : Float;
}

class Light extends Object3D {

	@:s public var kind : LightKind = Point;
	@:s public var color : Int = 0xffffff;
	@:s public var power : Float = 1.0;
	@:s public var occlusionFactor = 1.0;
	@:s public var isMainLight : Bool = false;
	@:c public var shadows : LightShadows = getShadowsDefault();

	// Point/Spot
	@:s public var range : Float;

	// Point
	@:s public var size : Float = 1.0;
	@:s public var zNear : Float;

	// Spot
	@:s public var angle : Float = 90;
	@:s public var fallOff : Float = 80;
	@:s public var cookiePath : String = null;
	public var cookieTex : h3d.mat.Texture = null;

	// Dir
	@:s public var maxDist : Float = -1;
	@:s public var minDist : Float = -1;
	@:s public var autoShrink : Bool = true;
	@:s public var autoZPlanes : Bool = false;

	// Cascade
	@:s public var cascade : Bool = false;
	@:s public var cascadeNbr : Int = 1;
	@:s public var cascadePow : Float = 2;
	@:s public var firstCascadeSize : Float = 10;
	@:s public var castingMaxDist : Float = 0.0;
	@:s public var debugShader : Bool = false;

	// Debug
	@:s public var debugDisplay : Bool = true;

	static function getShadowsDefault() : LightShadows {
		return {
			mode : None,
			size : 256,
			radius : 0,
			quality : 1.0,
			bias : 0.1,
			samplingMode : {
				kind : None,
			}
		};
	}

	public function new(?parent) {
		super(parent);
		range = 10;
		zNear = 0.02;
	}

	override function save(to:Dynamic) : Dynamic {
		var obj : Dynamic = super.save(to);
		if( shadows.mode != None ) {
			obj.shadows = Reflect.copy(shadows);
			obj.shadows.mode = shadows.mode.getName();
		}
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		if( obj.shadows != null ) {
			var sh : Dynamic = Reflect.copy(obj.shadows);
			sh.mode = h3d.pass.Shadows.RenderMode.createByName(sh.mode);
			shadows = sh;
		} else
			shadows = getShadowsDefault();
	}

	override function applyTransform() {
		//super.applyTransform(o); // Disable scaling
		local3d.x = x;
		local3d.y = y;
		local3d.z = z;
		local3d.setRotation(hxd.Math.degToRad(rotationX), hxd.Math.degToRad(rotationY), hxd.Math.degToRad(rotationZ));
	}

	function initTexture( path : String, ?wrap : h3d.mat.Data.Wrap ) {
		if(path != null){
			var texture = hxd.res.Loader.currentInstance.load(path).toTexture();
			if(texture != null ) texture.wrap = wrap == null ? Repeat : wrap;
			return texture;
		}
		return null;
	}

	override function makeObject3d(parent3d:h3d.scene.Object) : h3d.scene.Object {
		var object : h3d.scene.Object = null;

		var isPbr = Std.isOfType(h3d.mat.MaterialSetup.current, h3d.mat.PbrMaterialSetup);
		if( !isPbr ) {
			switch( kind ) {
			case Point: object = new h3d.scene.fwd.PointLight(parent3d);
			case Directional: object = new h3d.scene.fwd.DirLight(parent3d);
			case Spot:
			}
		} else {
			switch( kind ) {
			case Point: object = new h3d.scene.pbr.PointLight(parent3d);
			case Directional: object = new h3d.scene.pbr.DirLight(parent3d, cascade);
			case Spot: object = new h3d.scene.pbr.SpotLight(parent3d);
			}
		}

		cookieTex = initTexture(cookiePath);

		return object;
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);

		var color = color | 0xff000000;
		var light = Std.downcast(local3d, h3d.scene.pbr.Light);
		if( light != null ) { // PBR
			light.isMainLight = isMainLight;
			light.occlusionFactor = occlusionFactor;

			switch( kind ) {
			case Directional:
				var dl = Std.downcast(light, h3d.scene.pbr.DirLight);
				if( dl.shadows != null ) {
					var s = Std.downcast(dl.shadows, h3d.pass.DirShadowMap);
					s.maxDist = maxDist;
					s.minDist = minDist;
					s.autoShrink = autoShrink;
					s.autoZPlanes = autoZPlanes;
					var cs = Std.downcast(s, h3d.pass.CascadeShadowMap);
					if ( cs != null ) {
						cs.cascade = cascadeNbr;
						cs.pow = cascadePow;
						cs.firstCascadeSize = firstCascadeSize;
						cs.debug = debugDisplay;
						cs.castingMaxDist = castingMaxDist;
						cs.debugShader = debugShader;
					}
				}
			case Spot:
				var sl = Std.downcast(light, h3d.scene.pbr.SpotLight);
				sl.range = range;
				sl.angle = angle;
				sl.fallOff = fallOff;
				sl.cookie = cookieTex;
			case Point:
				var pl = Std.downcast(light, h3d.scene.pbr.PointLight);
				pl.range = range;
				pl.size = size;
				pl.zNear = hxd.Math.max(0.02, zNear);
			default:
			}
			light.color.setColor(color);
			light.power = power;
			light.shadows.mode = shadows.mode;
			light.shadows.size = shadows.size;
			light.shadows.blur.radius = shadows.radius;
			light.shadows.blur.quality = shadows.quality;
			light.shadows.bias = shadows.bias * 0.1;

			switch (shadows.samplingMode.kind) {
				case None:
					light.shadows.samplingKind = None;
				case PCF:
					var sm : ShadowSamplingPCF = cast shadows.samplingMode;
					light.shadows.pcfQuality = sm.quality;
					light.shadows.pcfScale = sm.scale;
					light.shadows.samplingKind = PCF;
				case ESM:
					var sm : ShadowSamplingESM = cast shadows.samplingMode;
					light.shadows.power = sm.power;
					light.shadows.samplingKind = ESM;
			}
		}
		else if( light != null ) { // FWD
			light.color.setColor(color | 0xFF000000);
		}

		#if editor
		var debugPoint = local3d.find(c -> if(c.name == "_debugPoint") c else null);
		var debugDir = local3d.find(c -> if(c.name == "_debugDir") c else null);
		var debugSpot = local3d.find(c -> if(c.name == "_debugSpot") c else null);
		var mesh : h3d.scene.Mesh = null;
		var sel : h3d.scene.Object = null;

		switch(kind){

			case Point:

				if(debugDir != null) debugDir.remove();
				if(debugSpot != null) debugSpot.remove();

				var rangeSphere : h3d.scene.Sphere;

				if(debugPoint == null) {
					debugPoint = new h3d.scene.Object(local3d);
					debugPoint.name = "_debugPoint";

					mesh = new h3d.scene.Mesh(h3d.prim.Sphere.defaultUnitSphere(), debugPoint);
					mesh.ignoreBounds = true;
					mesh.setScale(0.2);

					rangeSphere = new h3d.scene.Sphere(0xffffff, 1, true, debugPoint);
					rangeSphere.visible = false;
					rangeSphere.ignoreBounds = true;
					rangeSphere.ignoreCollide = true;
					rangeSphere.material.mainPass.setPassName("overlay");
					rangeSphere.material.shadows = false;
				}
				else {
					mesh = cast debugPoint.getChildAt(0);
					rangeSphere = cast debugPoint.getChildAt(1);
				}

				mesh.setScale(0.2/range);
				rangeSphere.material.color.setColor(color);
				sel = rangeSphere;

			case Directional :

				if(debugPoint != null) debugPoint.remove();
				if(debugSpot != null) debugSpot.remove();

				if(debugDir == null) {
					debugDir = new h3d.scene.Object(local3d);
					debugDir.name = "_debugDir";

					mesh = new h3d.scene.Mesh(h3d.prim.Sphere.defaultUnitSphere(), debugDir);
					mesh.ignoreBounds = true;
					mesh.setScale(0.2);
					mesh.ignoreParentTransform = true;

					var g = new h3d.scene.Graphics(debugDir);
					g.lineStyle(1, 0xffffff);
					g.moveTo(0,0,0);
					g.lineTo(10,0,0);
					g.ignoreBounds = true;
					g.ignoreCollide = true;
					g.visible = false;
					g.material.mainPass.setPassName("overlay");
					sel = g;
				}
				else {
					mesh = cast debugDir.getChildAt(0);
					sel = debugDir.getChildAt(1);
				}

				mesh.setPosition(debugDir.getAbsPos().tx, debugDir.getAbsPos().ty, debugDir.getAbsPos().tz);

			case Spot:

				if(debugDir != null) debugDir.remove();
				if(debugPoint != null) debugPoint.remove();

				if(debugSpot == null) {
					debugSpot = new h3d.scene.Object(local3d);
					debugSpot.name = "_debugSpot";

					mesh = new h3d.scene.Mesh(h3d.prim.Sphere.defaultUnitSphere(), debugSpot);
					mesh.ignoreBounds = true;
					mesh.setScale(0.2);

					var g = new h3d.scene.Graphics(debugSpot);
					g.lineStyle(1, this.color);
					g.moveTo(0,0,0); g.lineTo(1, 1, 1);
					g.moveTo(0,0,0); g.lineTo(1, -1, 1);
					g.moveTo(0,0,0); g.lineTo(1, 1, -1);
					g.moveTo(0,0,0); g.lineTo(1, -1, -1);
					g.lineTo(1, 1, -1);
					g.lineTo(1, 1, 1);
					g.lineTo(1, -1, 1);
					g.lineTo(1, -1, -1);

					g.ignoreBounds = true;
					g.ignoreCollide = true;
					g.visible = false;
					g.material.mainPass.setPassName("overlay");
					sel = g;
				}
				else{
					var g : h3d.scene.Graphics = Std.downcast(debugSpot.getChildAt(1), h3d.scene.Graphics);
					g.clear();
					g.lineStyle(1, this.color);
					g.moveTo(0,0,0); g.lineTo(1, 1, 1);
					g.moveTo(0,0,0); g.lineTo(1, -1, 1);
					g.moveTo(0,0,0); g.lineTo(1, 1, -1);
					g.moveTo(0,0,0); g.lineTo(1, -1, -1);
					g.lineTo(1, 1, -1);
					g.lineTo(1, 1, 1);
					g.lineTo(1, -1, 1);
					g.lineTo(1, -1, -1);

					mesh = cast debugSpot.getChildAt(0);
					sel = g;
				}

				mesh.setScale(0.2/range);
		}

		if(mesh != null){
			var mat = mesh.material;
			mat.mainPass.setPassName("overlay");
			mat.color.setColor(color);
			mat.shadows = false;
		}

		var isSelected = false;
		if(sel != null){
			isSelected = sel.visible;
			if( debugPoint != null ) debugPoint.visible = (isSelected) && debugDisplay;
			if( debugDir != null ) debugDir.visible = (isSelected) && debugDisplay;
			if( debugSpot != null ) debugSpot.visible = (isSelected) && debugDisplay;
			sel.name = "__selection";
		}

		// no "Mixed" in editor
		if( light != null && light.shadows.mode == Mixed ) light.shadows.mode = Dynamic;

		#end
	}

	#if editor

	override function setSelected(b : Bool ) {
		var sel = local3d.getObjectByName("__selection");
		if( sel != null ) sel.visible = b;
		updateInstance();
		return true;
	}

	override function edit( ctx : hide.prefab2.EditContext ) {
		super.edit(ctx);

		var group = new hide.Element('
			<div class="group" name="Light">
				<dl>
					<dt>Debug Display</dt><dd><input type="checkbox" field="debugDisplay"/></dd>
					<dt>Main Light</dt><dd><input type="checkbox" field="isMainLight"/></dd>
					<dt>Kind</dt><dd>
						<select field="kind">
							<option value="Point">Point</option>
							<option value="Directional">Directional</option>
							<option value="Spot">Spot</option>
						</select></dd>
					<dt>Color</dt><dd><input type="color" field="color"/></dd>
					<dt>Power</dt><dd><input type="range" min="0" max="10" field="power"/></dd>
					<dt>Occlusion Factor</dt><dd><input type="range" min="0" max="1" field="occlusionFactor"/></dd>
				</dl>
			</div>
		');

		switch( kind ) {
		case Directional:
			group.append(hide.comp.PropsEditor.makePropsList([
				{ name: "maxDist", t: PFloat(0, 1000), def: -1 },
				{ name: "minDist", t: PFloat(0, 50), def: -1 },
				{ name: "autoShrink", t: PBool, def: true }
			]));

			if ( autoShrink ) {
				group.append(hide.comp.PropsEditor.makePropsList([
					{ name: "autoZPlanes", t: PBool, def: false }
				]));
			}

			group.append(hide.comp.PropsEditor.makePropsList([
				{ name: "cascade", t: PBool, def: false }
			]));
		case Spot:
			group.append(hide.comp.PropsEditor.makePropsList([
				{ name: "range", t: PFloat(1, 20), def: 10 },
				{ name: "angle", t: PFloat(1, 90), def: 90 },
				{ name: "fallOff", t: PFloat(1, 90), def: 80 },
				{ name: "cookiePath", t: PTexturePath },
			]));
		case Point:
			group.append(hide.comp.PropsEditor.makePropsList([
				{ name: "size", t: PFloat(0, 5), def: 0 },
				{ name: "range", t: PFloat(1, 20), def: 10 },
				{ name: "zNear", t: PFloat(0.02, 5), def: 0.02 },
			]));
		default:
		}
		if ( cascade )
			group.append(hide.comp.PropsEditor.makePropsList([
				{ name: "cascadeNbr", t: PInt(1, 5), def: 1},
				{ name: "cascadePow", t: PFloat(0, 4), def: 2},
				{ name: "firstCascadeSize", t: PFloat(0, 1), def: 0.2},
				{ name: "castingMaxDist", t: PFloat(0, 100), def: 0.0},
				{ name: "debugShader", t: PBool, def: false},
			]));

		var props = ctx.properties.add(group, this, function(pname) {
			if( pname == "kind" || pname == "cascade" || pname == "autoShrink" ){
				ctx.rebuildPrefab(this);
				ctx.rebuildProperties();
			}
			else{
				if( pname == "cookiePath") cookieTex = loadTextureCustom(this.cookiePath, cookieTex, Clamp);
				ctx.onChange(this, pname);
			}
		});

		var shadowModeESM =
		'<div class="group" name="ESM">
			<dl>
				<dt>Power</dt><dd><input type="range" field="samplingMode.power" min="0" max="50"/></dd>
			</dl>
		</div>';

		var shadowModePCF =
		'<div class="group" name="PCF">
			<dl>
				<dt>Quality</dt>
					<dd>
						<select field="samplingMode.quality" type="number">
							<option value="1">Low</option>
							<option value="2">High</option>
							<option value="3">Very High</option>
						</select>
					</dd>
				<dt>Scale</dt><dd><input type="range" field="samplingMode.scale" min="0" max="10" /></dd>
			</dl>
		</div>';

		var shadowGroup = new hide.Element('
			<div class="group" name="Shadows">
				<dl>
					<dt>Mode</dt><dd><select field="mode"></select></dd>
					<dt>Size</dt>
					<dd>
						<select field="size" type="number">
							<option value="64">64</option>
							<option value="128">128</option>
							<option value="256">256</option>
							<option value="512">512</option>
							<option value="1024">1024</option>
							<option value="2048">2048</option>
							<option value="4096">4096</option>
						</select>
					</dd>
					<dt>Blur Radius</dt><dd><input type="range" field="radius" min="0" max="20"/></dd>
					<dt>Blur Quality</dt><dd><input type="range" field="quality" min="0" max="1"/></dd>
					<dt>Bias</dt><dd><input type="range" field="bias" min="0" max="1"/></dd>
					<dt>Sampling Mode</dt>
					<dd>
						<select field="samplingMode.kind">
							<option value="None">None</option>
							<option value="ESM">ESM</option>
							<option value="PCF">PCF</option>
						</select>
					</dd>
				</dl>
			</div>
		');

		switch (shadows.samplingMode.kind) {
			case None:
			case PCF: shadowGroup.append(shadowModePCF);
			case ESM: shadowGroup.append(shadowModeESM);
		}

		var e = ctx.properties.add(shadowGroup,shadows,function(pname) {
			ctx.onChange(this,pname);
			if( pname == "mode" ) ctx.rebuildProperties();
			if( pname == "samplingMode.kind" ) {
				switch (shadows.samplingMode.kind) {
					case None: shadows.samplingMode = cast { kind : None };
					case PCF: shadows.samplingMode = cast { kind : PCF, quality : 1, scale : 1.0, bias : 0.1 };
					case ESM: shadows.samplingMode = cast { kind : ESM, power : 30, bias : 0.1 };
				}
				ctx.rebuildProperties();
			}
		});

		if( shadows.mode == None ) {
			e.find("dd").not(":first").remove();
			e.find("dt").not(":first").remove();
		}
	}

	function loadTextureCustom(propsName : String, texture : h3d.mat.Texture, ?wrap : h3d.mat.Data.Wrap){
		if(texture != null) texture.dispose();
		if(propsName == null) return null;
		texture = shared.loadTexture(propsName);
		texture.wrap = wrap == null ? Repeat : wrap;
		return texture;
	}

	override function getHideProps() : hide.prefab2.HideProps {
		return { icon : "sun-o", name : "Light" };
	}
	#end

	static var _ = Prefab.register("light", Light);
}