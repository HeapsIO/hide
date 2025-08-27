package hrt.prefab;

enum abstract LightKind(String) {
	var Point;
	var Directional;
	var Spot;
	var Capsule;
	var Rectangle;
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

typedef CascadeParams = {
	var depthBias : Float;
	var slopeBias : Float;
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

	// Capsule
	@:s public var length : Float = 1.0;

	// Rectangle
	@:s public var width : Float = 1.0;
	@:s public var height : Float = 1.0;
	@:s public var verticalAngle : Float = 1.0;
	@:s public var horizontalAngle : Float = 1.0;

	// Cascade
	@:s public var cascade : Bool = false;
	@:s public var cascadeNbr : Int = 1;
	@:s public var cascadePow : Float = 2;
	@:s public var firstCascadeSize : Float = 10;
	@:s public var minPixelSize : Int = 1;
	@:s public var castingMaxDist : Float = 0.0;
	@:s public var transitionFraction : Float = 0.15;
	@:s public var params : Array<CascadeParams> = [];
	@:s public var debugShader : Bool = false;
	@:s public var highPrecision : Bool = false;

	// Debug
	@:s public var debugDisplay : Bool = true;

	#if editor
	var icon : hrt.impl.EditorTools.EditorIcon = null;
	#end

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

	public function new(parent, shared: ContextShared) {
		super(parent, shared);
		range = 10;
		zNear = 0.02;
	}

	override function save() : Dynamic {
		var obj : Dynamic = super.save();
		if( shadows.mode != None ) {
			obj.shadows = Reflect.copy(shadows);
			obj.shadows.mode = shadows.mode.getName();
		}
		if ( !cascade )
			Reflect.deleteField(obj, "params");
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		if( obj.shadows != null ) {
			var sh : Dynamic = Reflect.copy(obj.shadows);
			shadows = sh;
			shadows.mode = h3d.pass.Shadows.RenderMode.createByName(sh.mode);
		} else
			shadows = getShadowsDefault();
	}

	override function copy(prefab: Prefab) {
		super.copy(prefab);
	}

	override function applyTransform() {
		//super.applyTransform(o); // Disable scaling

		if (local3d != null)
			applyTransformToObject(local3d);
	}

	public function applyTransformToObject( o : h3d.scene.Object ) {
		o.x = x;
		o.y = y;
		o.z = z;
		o.setRotation(hxd.Math.degToRad(rotationX), hxd.Math.degToRad(rotationY), hxd.Math.degToRad(rotationZ));
	}

	function initTexture( path : String, ?wrap : h3d.mat.Data.Wrap ) {
		if(path != null){
			var texture = hxd.res.Loader.currentInstance.load(path).toTexture();
			if(texture != null ) texture.wrap = wrap == null ? Repeat : wrap;
			return texture;
		}
		return null;
	}

	override function makeObject(parent3d:h3d.scene.Object) : h3d.scene.Object {
		var object : h3d.scene.Object = null;

		var isPbr = Std.isOfType(h3d.mat.MaterialSetup.current, h3d.mat.PbrMaterialSetup);
		if( !isPbr ) {
			switch( kind ) {
			case Point: object = new h3d.scene.fwd.PointLight(parent3d);
			case Directional: object = new h3d.scene.fwd.DirLight(parent3d);
			case Spot:
			case Capsule:
			case Rectangle:
			}
		} else {
			switch( kind ) {
			case Point: object = new h3d.scene.pbr.PointLight(parent3d);
			case Directional: object = new h3d.scene.pbr.DirLight(parent3d, cascade);
			case Spot: object = new h3d.scene.pbr.SpotLight(parent3d);
			case Capsule: object = new h3d.scene.pbr.CapsuleLight(parent3d);
			case Rectangle: object = new h3d.scene.pbr.RectangleLight(parent3d);
			}
		}

		#if editor
		if (shared.parentPrefab == null || (Std.downcast(shared.parentPrefab, Reference)?.editMode != None && shared.parentPrefab != shared.editor?.renderPropsRoot)) {
			icon = hrt.impl.EditorTools.create3DIcon(object, hide.Ide.inst.getHideResPath("icons/PointLight.png"), 0.5, Light);
		}
		#end

		cookieTex = initTexture(cookiePath);

		return object;
	}

	override function updateInstance(?propName : String ) {
		super.updateInstance(propName);

		if (local3d == null)
			return;

		var color = color | 0xff000000;
		var light = Std.downcast(local3d, h3d.scene.pbr.Light);

		if( light != null ) { // PBR
			light.isMainLight = isMainLight;
			light.occlusionFactor = occlusionFactor;
			light.color.setColor(color);
			light.power = power;
			light.shadows.mode = shadows.mode;
			light.shadows.size = shadows.size;
			light.shadows.blur.radius = shadows.radius;
			light.shadows.blur.quality = shadows.quality;
			light.shadows.bias = shadows.bias * 0.1;

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
						cs.ditributionPower = cascadePow;
						cs.firstCascadeSize = firstCascadeSize;
						cs.minPixelSize = minPixelSize;
						cs.debug = debugDisplay;
						cs.castingMaxDist = castingMaxDist;
						cs.transitionFraction = transitionFraction;
						cs.debugShader = debugShader;
						cs.blur.radius = 0.0;
						cs.mode = Dynamic;
						params.resize(cascadeNbr);
						for ( i in 0...params.length )
							if ( params[i] == null )
								params[i] = { depthBias : 1.0, slopeBias : 3.0 };
						cs.params = params;
						cs.highPrecision = highPrecision;
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
			case Capsule:
				var cl = Std.downcast(light, h3d.scene.pbr.CapsuleLight);
				cl.range = range;
				cl.length = length;
				cl.radius = size;
				cl.zNear = hxd.Math.max(0.02, zNear);
			case Rectangle:
				var rec = Std.downcast(light, h3d.scene.pbr.RectangleLight);
				rec.range = range;
				rec.height = height;
				rec.width = width;
				rec.verticalAngle = verticalAngle;
				rec.horizontalAngle = horizontalAngle;
				rec.fallOff = fallOff;
			default:
			}

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

		if (icon != null) {
			icon.color = h3d.Vector4.fromColor(color);

			var ide = hide.Ide.inst;
			switch(kind) {
				case Directional:
					icon.texture = ide.getTexture(ide.getHideResPath("icons/DirLight.png"));
				case Point:
					icon.texture = ide.getTexture(ide.getHideResPath("icons/PointLight.png"));
				case Spot:
					icon.texture = ide.getTexture(ide.getHideResPath("icons/SpotLight.png"));
				case Capsule:
					icon.texture = ide.getTexture(ide.getHideResPath("icons/CapsuleLight.png"));
				case Rectangle:
					icon.texture = ide.getTexture(ide.getHideResPath("icons/RectangleLight.png"));
			}
		}

		refreshDebug();

		// no "Mixed" in editor
		if( light != null && light.shadows.mode == Mixed ) light.shadows.mode = Dynamic;
		#end
	}

	#if editor

	function refreshDebug() {
		if ( local3d == null )
			return;
		var debugPoint = local3d.find(c -> if(c.name == "_debugPoint") c else null);
		var debugDir = local3d.find(c -> if(c.name == "_debugDir") c else null);
		var debugSpot = local3d.find(c -> if(c.name == "_debugSpot") c else null);
		var debugCapsule = local3d.find(c -> if(c.name == "_debugCapsule") c else null);
		var debugRectangle = local3d.find(c -> if(c.name == "_debugRectangle") c else null);
		var sel : h3d.scene.Object = null;

		switch(kind){
		case Point:
			if(debugDir != null) debugDir.remove();
			if(debugSpot != null) debugSpot.remove();
			if(debugCapsule != null) debugCapsule.remove();
			if(debugRectangle != null) debugRectangle.remove();

			var rangeSphere : h3d.scene.Sphere;

			if(debugPoint == null) {
				debugPoint = new h3d.scene.Object(local3d);
				debugPoint.name = "_debugPoint";

				rangeSphere = new h3d.scene.Sphere(0xffffff, 1, true, debugPoint);
				rangeSphere.visible = false;
				rangeSphere.ignoreBounds = true;
				rangeSphere.ignoreCollide = true;
				rangeSphere.material.mainPass.setPassName("overlay");
				rangeSphere.material.shadows = false;

				var sizeSphere = new h3d.scene.Sphere(0xffff00, 1, true, rangeSphere);
				sizeSphere.visible = true;
				sizeSphere.ignoreBounds = true;
				sizeSphere.ignoreCollide = true;
				sizeSphere.material.mainPass.setPassName("overlay");
				sizeSphere.material.shadows = false;
			}
			else {
				rangeSphere = cast debugPoint.getChildAt(0);
			}

			rangeSphere.material.color.setColor(color);
			cast(rangeSphere.getChildAt(0), h3d.scene.Sphere).setScale(size / range);
			sel = rangeSphere;

		case Directional :
			if(debugPoint != null) debugPoint.remove();
			if(debugSpot != null) debugSpot.remove();
			if(debugCapsule != null) debugCapsule.remove();
			if(debugRectangle != null) debugRectangle.remove();

			if(debugDir == null) {
				debugDir = new h3d.scene.Object(local3d);
				debugDir.name = "_debugDir";



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
				sel = debugDir.getChildAt(0);
			}

		case Spot:
			if(debugDir != null) debugDir.remove();
			if(debugPoint != null) debugPoint.remove();
			if(debugCapsule != null) debugCapsule.remove();
			if(debugRectangle != null) debugRectangle.remove();

			if(debugSpot == null) {
				debugSpot = new h3d.scene.Object(local3d);
				debugSpot.name = "_debugSpot";

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
				var g : h3d.scene.Graphics = Std.downcast(debugSpot.getChildAt(0), h3d.scene.Graphics);
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

				sel = g;
			}

		case Capsule:
			if(debugDir != null) debugDir.remove();
			if(debugPoint != null) debugPoint.remove();
			if(debugSpot != null) debugSpot.remove();
			if(debugRectangle != null) debugRectangle.remove();

			var rangeCapsule : h3d.scene.Capsule;

			if(debugCapsule == null) {
				debugCapsule = new h3d.scene.Object(local3d);
				debugCapsule.name = "_debugCapsule";

				rangeCapsule = new h3d.scene.Capsule(0xffffff, 1, true, debugCapsule);
				rangeCapsule.visible = false;
				rangeCapsule.ignoreBounds = true;
				rangeCapsule.ignoreCollide = true;
				rangeCapsule.material.mainPass.setPassName("overlay");
				rangeCapsule.material.shadows = false;

				var sizeCapsule = new h3d.scene.Capsule(0xffff00, 1, true, rangeCapsule);
				sizeCapsule.visible = true;
				sizeCapsule.ignoreBounds = true;
				sizeCapsule.ignoreCollide = true;
				sizeCapsule.material.mainPass.setPassName("overlay");
				sizeCapsule.material.shadows = false;
			}
			else {
				rangeCapsule = cast(debugCapsule.getChildAt(0));
			}

			rangeCapsule.length = length / range;
			var sizeCapsule = cast(rangeCapsule.getChildAt(0), h3d.scene.Capsule);
			sizeCapsule.radius = size / range;
			sizeCapsule.length = length / range;
			sel = rangeCapsule;

		case Rectangle:
			if(debugDir != null) debugDir.remove();
			if(debugPoint != null) debugPoint.remove();
			if(debugSpot != null) debugSpot.remove();
			if(debugCapsule != null) debugCapsule.remove();

			function drawRec(g : h3d.scene.Graphics) {
				g.lineStyle(1, this.color);
				var p1 = new h3d.col.Point(0,-width / 2,-height / 2);
				var p2 = new h3d.col.Point(0, width / 2, -height / 2);
				var p3 = new h3d.col.Point(0,-width / 2,height / 2);
				var p4 = new h3d.col.Point(0, width / 2, height / 2);

				var p5 = p1 + new h3d.col.Point(range,-hxd.Math.sin(hxd.Math.degToRad(horizontalAngle) / 2) * range,-hxd.Math.sin(hxd.Math.degToRad(verticalAngle) / 2) * range);
				var p6 =  p2 + new h3d.col.Point(range,hxd.Math.sin(hxd.Math.degToRad(horizontalAngle) / 2) * range,-hxd.Math.sin(hxd.Math.degToRad(verticalAngle) / 2) * range);
				var p7 =  p3 + new h3d.col.Point(range,-hxd.Math.sin(hxd.Math.degToRad(horizontalAngle) / 2) * range,hxd.Math.sin(hxd.Math.degToRad(verticalAngle) / 2) * range);
				var p8 =  p4 + new h3d.col.Point(range,hxd.Math.sin(hxd.Math.degToRad(horizontalAngle) / 2) * range,hxd.Math.sin(hxd.Math.degToRad(verticalAngle) / 2) * range);

				function drawLine(point1 : h3d.col.Point, point2 : h3d.col.Point) {
					g.moveTo(point1.x, point1.y, point1.z); g.lineTo(point2.x, point2.y, point2.z);
				}

				// Front
				drawLine(p1, p2);
				drawLine(p3, p4);
				drawLine(p1, p3);
				drawLine(p2, p4);

				// Back
				drawLine(p5, p6);
				drawLine(p7, p8);
				drawLine(p5, p7);
				drawLine(p6, p8);

				// Sides
				drawLine(p1, p5);
				drawLine(p2, p6);
				drawLine(p3, p7);
				drawLine(p4, p8);
			}

			if(debugRectangle == null) {
				debugRectangle = new h3d.scene.Object(local3d);
				debugRectangle.name = "_debugRectangle";

				var g = new h3d.scene.Graphics(debugRectangle);
				drawRec(g);
				g.ignoreBounds = true;
				g.ignoreCollide = true;
				g.visible = false;
				g.material.mainPass.setPassName("overlay");
				sel = g;
			}
			else {
				var g : h3d.scene.Graphics = Std.downcast(debugRectangle.getChildAt(0), h3d.scene.Graphics);
				g.clear();
				drawRec(g);
				sel = g;
			}
		}

		var isSelected = false;
		if(sel != null){
			isSelected = sel.visible;
			if( debugPoint != null ) debugPoint.visible = (isSelected || shared.editorDisplay);
			if( debugDir != null ) debugDir.visible = (isSelected || shared.editorDisplay);
			if( debugSpot != null ) debugSpot.visible = (isSelected || shared.editorDisplay);
			if( debugCapsule != null ) debugCapsule.visible = (isSelected || shared.editorDisplay);
			sel.name = "__selection";
		}
	}

	override function setSelected(b : Bool ) {
		var sel = local3d?.getObjectByName("__selection");
		if( sel != null ) sel.visible = b;
		refreshDebug();
		if (!b && local3d != null)
			local3d.visible = this.visible && !shared.editor.isHidden(this);
		return true;
	}

	override function editorRemoveInstanceObjects() : Void {
		if (icon != null) {
			icon.remove();
		}
		super.editorRemoveInstanceObjects();
	}

	override function edit( ctx : hide.prefab.EditContext ) {
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
							<option value="Capsule">Capsule</option>
							<option value="Rectangle">Rectangle</option>
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
		case Capsule:
			group.append(hide.comp.PropsEditor.makePropsList([
				{ name: "size", t: PFloat(0, 5), def: 0 },
				{ name: "length", t: PFloat(0, 5), def: 0 },
				{ name: "range", t: PFloat(1, 20), def: 10 },
				{ name: "zNear", t: PFloat(0.02, 5), def: 0.02 },
			]));
		case Rectangle:
			group.append(hide.comp.PropsEditor.makePropsList([
				{ name: "width", t: PFloat(0, 5), def: 0 },
				{ name: "height", t: PFloat(0, 5), def: 0 },
				{ name: "horizontalAngle", t: PFloat(1, 90), def: 0 },
				{ name: "verticalAngle", t: PFloat(1, 90), def: 0 },
				{ name: "fallOff", t: PFloat(1, 90), def: 80 },
				{ name: "range", t: PFloat(1, 20), def: 10 }
			]));
		default:
		}

		ctx.properties.add(group, this, function(pname) {
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
					<div class="nonCascadeParams">
						<dt>Mode</dt>
						<dd>
							<select field="mode">
								<option value="None">None</option>
								<option value="Static">Static</option>
								<option value="Mixed">Mixed</option>
								<option value="Dynamic">Dynamic (Moving light)</option>
							</select>
						</dd>
						<dt>Blur Radius</dt><dd><input type="range" field="radius" min="0" max="20"/></dd>
						<dt>Blur Quality</dt><dd><input type="range" field="quality" min="0" max="1"/></dd>
						<dt>Bias</dt><dd><input type="range" field="bias" min="0" max="1"/></dd>
					</div>
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

		var nonCascadeParamsEl = shadowGroup.find(".nonCascadeParams");
		if ( cascade )
			nonCascadeParamsEl.hide();
		else
			nonCascadeParamsEl.show();

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

		var cascadeGroup = new hide.Element(
			'<div class="group" name="Cascades">
				<dl>
					<dt>Number</dt><dd><input type="range" field="cascadeNbr" step="1" min="1" max="4"/></dd>
					<dt>Min pixel size</dt><dd><input type="range" step="1" field="minPixelSize" min="0" max="100"/></dd>
					<dt>First cascade size</dt><dd><input type="range" field="firstCascadeSize" min="5" max="100"/></dd>
					<dt>Distribution power</dt><dd><input type="range" field="cascadePow" min="0.1" max="10"/></dd>
					<dt>Casting max dist</dt><dd><input type="range" field="castingMaxDist" min="-1" max="1000"/></dd>
					<dt>Transition fraction</dt><dd><input type="range" field="transitionFraction" min="0.0" max="0.3"/></dd>
					<dl>
						<ul id="params"></ul>
					</dl>
					<dt>Debug shader</dt><dd><input type="checkbox" field="debugShader"/></dd>
					<dt>High precision</dt><dd><input type="checkbox" field="highPrecision"/></dd>
				</dl>
			</div>'
		);

		if ( cascade && shadows.mode != None ) {
			ctx.properties.add(cascadeGroup,this,function(pname) {
				ctx.onChange(this,pname);
				params.resize(cascadeNbr);
				if( pname == "cascadeNbr" ) ctx.rebuildProperties();
			});
		}

		var list = cascadeGroup.find("ul#params");

		for ( param in params ) {
			var e = new hide.Element('
			<div class="group" name="Params">
				<dl>
					<dt>DepthBias</dt><dd><input type="range" min="0" max="10" step="0.1" field="depthBias"/></dd>
					<dt>SlopeBias</dt><dd><input type="range" min="0" max="10" step="0.1" field="slopeBias"/></dd>
				</dl>
			</div>
			');
			e.appendTo(list);
			ctx.properties.build(e, param, (pname) -> {
				ctx.onChange(this, "params");
			});
		}
	}

	function loadTextureCustom(propsName : String, texture : h3d.mat.Texture, ?wrap : h3d.mat.Data.Wrap){
		if(texture != null) texture.dispose();
		if(propsName == null) return null;
		texture = shared.loadTexture(propsName);
		texture.wrap = wrap == null ? Repeat : wrap;
		return texture;
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "sun-o", name : "Light" };
	}
	#end

	static var _ = Prefab.register("light", Light);
}