package hrt.prefab.l3d;

typedef Layer2DValue = {
	index	: Int,
	name 	: String,
	color	: Int
}

typedef Layer2D = {
	name	: String,
	values 	: Array<Layer2DValue>
}

class LayerView2DRFXShader extends h3d.shader.ScreenShader {

	static var SRC = {

		@param var layerAlpha : Float;
		@param var worldSize : Float;

		@param var collideMap : Sampler2D;
		@const var collideEnable : Bool;
		@param var collideMask : Vec4;
		@param var collideScale : Float;

		@const var layerEnable : Bool;
		@param var layerMap : Sampler2D;
		@param var layerScale : Float;

		@param var colors : Sampler2D;
		@param var nbColorsIndexes : Int;

		@param var curFrame : Sampler2D;
		@param var cameraInverseViewProj : Mat4;

		@const var PACKED_DEPTH : Bool;
		@param var depthChannel : Channel;
		@param var depthTexture : Sampler2D;

		@const var highlightNoPixels : Bool;
		@param var highlightColor : Vec4;

		var isSky : Bool;

		function getPixelPosition( uv : Vec2 ) : Vec3 {
			var d = PACKED_DEPTH ? unpack(depthTexture.get(uv)) : depthChannel.get(uv).r;
			var tmp = vec4(uvToScreen(uv), d, 1) * cameraInverseViewProj;
			tmp.xyz /= tmp.w;
			isSky = d == 1.0;
			return tmp.xyz;
		}

		function floatToInt( v : Float ) : Int {
			return int(v * 255);
		}

		function fragment() {
			var curColor = curFrame.get(calculatedUV);

			pixelColor = curColor;

			var curPos = getPixelPosition(calculatedUV).xy;

			var collide = false;

			if ( collideEnable ) {
				var tex = collideMap.get( floor( curPos / collideScale ) * collideScale / worldSize );
				if ( (tex.rgb-collideMask.rgb).length() < 1e-3 )
					collide = true;
			}

			if ( layerEnable ) {
				var layer = layerMap.get( floor( curPos / layerScale ) * layerScale / worldSize );
				var index = (floatToInt(layer.a) << 24) + (floatToInt(layer.r) << 16) + (floatToInt(layer.g) << 8) + (floatToInt(layer.b));
				if ( index > 0 )
					pixelColor.rgba = colors.get(vec2((index + 0.5) / nbColorsIndexes, 0.5));
				else if ( !collide && highlightNoPixels )
					pixelColor.rgba = highlightColor;
			}

			if ( collide )
				pixelColor = mix(mix(curColor, collideMask, 0.5), pixelColor, layerAlpha/2);
			else
				pixelColor = mix(curColor, pixelColor, layerAlpha);

		}

	}
}

class Layer2DRFX extends hrt.prefab.rfx.RendererFX {

	public var pass = new h3d.pass.ScreenFx(new LayerView2DRFXShader());

	var tmp = new h3d.Matrix();
	var curMatNoJitter = new h3d.Matrix();

	override function begin( r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step ) {
		if( step == MainDraw ) {
			var ctx = r.ctx;
			var s = pass.shader;

			curMatNoJitter.load(ctx.camera.m);
			s.cameraInverseViewProj.initInverse(curMatNoJitter);
		}
	}

	override function end( r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step ) {
		var ctx = r.ctx;
		if( step == AfterTonemapping ) {
			r.mark("Layers2D");
			var output : h3d.mat.Texture = ctx.engine.getCurrentTarget();
			var depthMap : Dynamic = ctx.getGlobal("depthMap");

			var curFrame = r.allocTarget("curFrame", false, 1.0, output.format);
			h3d.pass.Copy.run(output, curFrame);

			var s = pass.shader;
			s.curFrame = curFrame;

			s.PACKED_DEPTH = depthMap.packed != null && depthMap.packed == true;
			if( s.PACKED_DEPTH ) {
				s.depthTexture = depthMap.texture;
			}
			else {
				s.depthChannel = depthMap.texture;
				s.depthChannelChannel = depthMap.channel == null ? hxsl.Channel.R : depthMap.channel;
			}

			r.setTarget(output);
			pass.render();
		}
	}

}

@:allow(hrt.prefab.l3d)
class Layers2D extends hrt.prefab.Object3D {

	@:s var layers : Array<Layer2D> = [];
	@:s var layerScale : Int = 1;
	@:s var collidePath : String;
	@:s var collideMask : Int = 0xff0000;
	@:s var worldSize : Int = 4096;
	var layerTextures : Map<String, hxd.Pixels> = [];

	@:s var highlightColor : Int = 0xff00ff;

	@:s public var keepVisible : Bool = false;

	#if editor
	var storedCtx : hrt.prefab.Context;

	var currentPixels : hxd.Pixels = null;
	var currentTexture : h3d.mat.Texture = null;
	var interactive : h2d.Interactive;
	var gBrushes : Array<h3d.scene.Mesh>;

	var brushRadius : Float = 20;
	var eraseRadius : Float = 10;
	var paintOverride : Bool = true;
	var layerAlpha : Float = 0.6;

	var collideEnable : Bool = true;
	var currentLayer : String;
	var currentLayerValue : Int;

	var collideMap : h3d.mat.Texture;
	var collidePixels : hxd.Pixels;
	var colorMap : h3d.mat.Texture;

	var highlightNotPaintedPixels : Bool = false;

	var rfx : Layer2DRFX;

	var sceneEditor : hide.comp.SceneEditor;
	var editorCtx : hide.prefab.EditContext;

	var undo(get, null):hide.ui.UndoHistory;
	function get_undo() { return sceneEditor.view.undo; }

	#end

	#if editor
	override function save() : {} {
		var o : Dynamic = super.save();

		for ( l in layers ) {
			var pixels = layerTextures.get(l.name);
			if ( pixels != null ) {
				var contextShared = storedCtx.shared;
				var path = new haxe.io.Path(contextShared.currentPath);
				path.ext = "dat";
				var fileName = "layer_" + l.name;
				contextShared.saveTexture(fileName, pixels.toPNG(), path.toString() + "/" + this.name, "png");
			}
		}

		return o;
	}
	#end

	override function makeInstance( ctx : hrt.prefab.Context ) : hrt.prefab.Context {
		ctx = super.makeInstance(ctx);
		#if editor
		storedCtx = ctx;
		#end

		for ( l in layers ) {
			var path = new haxe.io.Path(ctx.shared.currentPath);
			path.ext = "dat";
			var datDir = path.toString();
			var fileName = "layer_" + l.name + ".png";
			var pixels = loadPixels(datDir + "/" + this.name + "/" + fileName);
			if ( pixels != null )
				layerTextures.set(l.name, pixels);
		}
		return ctx;
	}

	function loadPixels(path : String) {
		return try hxd.res.Loader.currentInstance.load(path).toImage().getPixels() catch( e : hxd.res.NotFound )
			#if editor try hxd.res.Any.fromBytes(path, sys.io.File.getBytes(hide.Ide.inst.getPath(path))).toImage().getPixels() catch( e : Dynamic ) #end
			null;
	}

	public function getLayer( key : String ) {
		return layerTextures.get(key);
	}

	public function getLayerColor( layer : hxd.Pixels, x : Float, y : Float ) {
		if ( layer == null )
			return -1;
		var ix = Std.int(x / layerScale);
		var iy = Std.int(y / layerScale);
		if ( ix < 0 || ix > layer.width || iy < 0 || iy > layer.height )
			return -1;

		return layer.getPixel(ix, iy);
	}

	public function getLayerValue(key : String, x : Float, y : Float) {
		var color = getLayerColor(getLayer(key), x, y);
		if ( color == -1 ) return null;

		for ( layer in layers ) {
			if ( layer.name == key ) {
				for ( lv in layer.values ) {
					if ( lv.index == color ) {
						return lv.name;
					}
				}
			}
		}

		return null;
	}

	#if editor

	function removeInteractiveBrush() {
		if( interactive != null ) interactive.remove();
		clearBrushes();
	}

	function clearBrushes() {
		if( gBrushes != null ) {
			for (g in gBrushes) g.remove();
			gBrushes = null;
		}
	}

	function setupRfx( ectx : hide.prefab.EditContext, b : Bool ) {
		if ( ectx == null )
			return;
		if ( b ) {
			if ( rfx == null ) {
				rfx = new Layer2DRFX();
				var renderer = Std.downcast(ectx.scene.s3d.renderer, h3d.scene.pbr.Renderer);
				renderer.effects.push(rfx);
			}
		} else if ( rfx != null ) {
			var renderer = Std.downcast(ectx.scene.s3d.renderer, h3d.scene.pbr.Renderer);
			renderer.effects.remove(rfx);
			rfx = null;
		}
	}

	function updateVisuals( ctx : hrt.prefab.Context ) {
		if ( rfx != null ) {
			var sh : LayerView2DRFXShader = cast rfx.pass.shader;
			if( collideMap == null || collideMap.isDisposed() ) {
				if ( collidePath != null ) {
					collideMap = ctx.loadTexture(collidePath);
					collideMap.filter = Nearest;
					collidePixels = loadPixels(collidePath);
				}
			}

			sh.layerAlpha = layerAlpha;
			sh.worldSize = worldSize;
			sh.collideScale = (collideMap != null) ? worldSize / collideMap.width : 1;
			sh.collideMap = collideMap;

			sh.collideEnable = collideEnable && collideMap != null;
			sh.collideMask = h3d.Vector.fromColor(collideMask);

			sh.layerEnable = currentTexture != null;
			sh.layerMap = currentTexture;
			sh.layerScale = layerScale;

			if ( sh.layerEnable ) {
				sh.colors = colorMap;
				sh.nbColorsIndexes = colorMap.width;
			}

			sh.highlightNoPixels = highlightNotPaintedPixels;
			sh.highlightColor = h3d.Vector.fromColor(highlightColor);
		}
	}

	var revertList : Array<{ pixels : hxd.Pixels, layer : String }> = [];
	var revertCurrentIdx : Int = 0;
	var currentRevertData : { pixels : hxd.Pixels, layer : String };
	function prepareUploadPixels() {
		if ( revertList.length == 0 ) {
			saveUploadPixels();
		}
	}

	function saveUploadPixels() {
		currentTexture.uploadPixels(currentPixels);

		if ( revertCurrentIdx < revertList.length )
			revertList.resize(revertCurrentIdx);

		revertList.push({ pixels : currentPixels.clone(), layer: currentLayer });

		revertCurrentIdx = revertList.length;

		undo.change(Custom(function(undo) {

			var revertDataToApply = if ( undo )
										revertList[--revertCurrentIdx];
									else
										revertList[revertCurrentIdx++];

			currentPixels = revertDataToApply.pixels;

			layerTextures.set(revertDataToApply.layer, currentPixels);

			if ( currentLayer == revertDataToApply.layer ) {
				currentTexture.uploadPixels(currentPixels);
				updateVisuals(editorCtx.getContext(this));
			}
		}));
	}

	function createInteractiveBrush(ectx : hide.prefab.EditContext) {
		if (!enabled) return;
		editorCtx = ectx;
		var ctx = ectx.getContext(this);
		var s2d = ctx.shared.root2d.getScene();
		interactive = new h2d.Interactive(10000, 10000, s2d);
		interactive.propagateEvents = true;
		interactive.cancelEvents = false;

		var modified = false;

		var layer = layers.filter(l -> l.name == currentLayer)[0];

		var layerValue = layer.values.filter( vl -> vl.index == currentLayerValue )[0];

		function drawBrush() {
			var worldPos = ectx.screenToGround(s2d.mouseX, s2d.mouseY);

			if( worldPos == null ) {
				clearBrushes();
				return;
			}

			var radius = brushRadius;
			var color = layerValue.color;
			if ( hxd.Key.isDown(hxd.Key.SHIFT) ) {
				radius = eraseRadius;
				color = 0xff0000;
			}

			drawCircle(ctx, worldPos.x, worldPos.y, worldPos.z, radius, 5, color);
		}

		interactive.onWheel = function(e) {
			if ( hxd.Key.isDown(hxd.Key.CTRL) ) {
				if ( hxd.Key.isDown(hxd.Key.SHIFT) ) {
					eraseRadius += e.wheelDelta * 2;
					if ( eraseRadius < 1 )
						eraseRadius = 1;
					@:privateAccess ectx.properties.fields.filter( f -> f.fname == "eraseRadius")[0].range.value = eraseRadius;
				} else {
					brushRadius += e.wheelDelta * 2;
					if ( brushRadius < 1 )
						brushRadius = 1;
					@:privateAccess ectx.properties.fields.filter( f -> f.fname == "brushRadius")[0].range.value = brushRadius;
				}
				e.propagate = false;
				drawBrush();
			}
		};

		function paint() {
			var clean = hxd.Key.isDown( hxd.Key.SHIFT);
			var worldPos = ectx.screenToGround(s2d.mouseX, s2d.mouseY);

			var MAX_X = Math.floor(currentPixels.width * layerScale) - 1;
			var MAX_Y = Math.floor(currentPixels.height * layerScale) - 1;

			var collideScale = collidePixels.width / worldSize;

			if ( worldPos != null ) {
				var startX = worldPos.x;
				var startY = worldPos.y;

				var brRadius = ( clean ) ? eraseRadius : brushRadius;
				var radiusSq = brRadius * brRadius;

				var minX = hxd.Math.iclamp(Math.floor(startX - brRadius), 0, MAX_X);
				var maxX = hxd.Math.iclamp(Math.ceil(startX + brRadius), 0, MAX_X);
				var minY = hxd.Math.iclamp(Math.floor(startY - brRadius), 0, MAX_Y);
				var maxY = hxd.Math.iclamp(Math.ceil(startY + brRadius), 0, MAX_Y);

				if ( clean ) {
					for ( iy in minY...maxY ) {
						for ( ix in minX...maxX ) {
							var vec = new h2d.col.Point(ix - startX, iy - startY);
							var distSq = vec.x*vec.x + vec.y*vec.y;
							var tx = Math.floor(ix / layerScale);
							var ty = Math.floor(iy / layerScale);
							if ( distSq <= radiusSq && currentPixels.getPixel(tx, ty) != 0 ) {
								currentPixels.setPixel(tx, ty, 0x00000000);
								modified = true;
							}
						}
					}
				} else {
					var distances : Array<Int> = [];
					var queue : Array<Int> = [];

					inline function isCollide( ix : Int, iy : Int ) {
						return collideEnable && collidePixels.getPixel(Math.floor(ix * collideScale), Math.floor(iy * collideScale)) & collideMask == collideMask;
					}

					function add( ix : Int, iy : Int, d : Int ) {
						var flagIdx = (iy - minY) * (maxX - minX) + ix;
						var dist = distances[ flagIdx ];
						if ( dist != null && dist <= d )
							return;

						distances[ flagIdx ] = d;

						queue.push(ix);
						queue.push(iy);
						queue.push(d);
					}

					function process( ix : Int, iy : Int, d : Int ) {
						if( ix < 0 || ix > MAX_X )
							return;
						if( iy < 0 || iy > MAX_Y )
							return;

						var dx = Math.abs(ix - startX);
						var dy = Math.abs(iy - startY);

						var distSq = dx * dx + dy * dy;

						if ( distSq > radiusSq )
							return;

						var collide = isCollide(ix, iy);

						if ( d == 0 && collide )
							return;

						if ( d > brushRadius * 1.414 )
							return;

						var tx = Math.floor(ix / layerScale);
						var ty = Math.floor(iy / layerScale);
						var currentColor = currentPixels.getPixel(tx, ty);
						if ( (paintOverride || currentColor == 0) && currentColor != currentLayerValue ) {
							currentPixels.setPixel(tx, ty, currentLayerValue);
							modified = true;
						}

						if ( collide )
							return;

						var newD = d + 1;

						add(ix-layerScale, iy, newD);
						add(ix+layerScale, iy, newD);
						add(ix, iy-layerScale, newD);
						add(ix, iy+layerScale, newD);
					}

					add(Math.round(startX), Math.round(startY), 0);

					while ( queue.length > 0 ) {
						process(queue.shift(), queue.shift(), queue.shift());
					}

				}

				currentTexture.uploadPixels(currentPixels);
			}
		}

		interactive.onPush = function(e) {
			e.propagate = false;

			modified = false;

			prepareUploadPixels();

			drawBrush();
			paint();
		};

		interactive.onRelease = function(e) {
			e.propagate = false;
			drawBrush();
			if ( modified )
				saveUploadPixels();
		};

		var layerChanged = false;
		interactive.onKeyDown = function(e) {
			if ( layerChanged )
				return;
			var NB_KEYS = layer.values.length+1;
			for ( k in hxd.Key.NUMBER_0...hxd.Key.NUMBER_0+NB_KEYS ) {
				if ( hxd.Key.isPressed(k) ) {
					layerChanged = true;
					currentLayerValue = layer.values[(((k-hxd.Key.NUMBER_0)-1+NB_KEYS)%NB_KEYS)].index;
				}
			}

			drawBrush();

			if ( layerChanged ) {
				haxe.Timer.delay(function() ectx.rebuildProperties(), 0);
			}
		}

		interactive.onMove = function(e) {
			drawBrush();

			if( hxd.Key.isDown( hxd.Key.MOUSE_LEFT) ) {
				e.propagate = false;

				paint();
			}
		};
		updateVisuals(ctx);

	}

	public function drawCircle(ctx : hrt.prefab.Context, originX : Float, originY : Float, originZ : Float, radius: Float, thickness: Float, color) {
		var newColor = h3d.Vector.fromColor(color);
		if (gBrushes == null || gBrushes.length == 0 || gBrushes[0].scaleX != radius || gBrushes[0].material.color != newColor) {
			clearBrushes();
			gBrushes = [];
			var gBrush = new h3d.scene.Mesh(hrt.prefab.l3d.Spray.makePrimCircle(64, 0.95), ctx.local3d);
			gBrush.scaleX = gBrush.scaleY = radius;
			gBrush.ignoreParentTransform = true;
			var pass = gBrush.material.mainPass;
			pass.setPassName("outline");
			pass.depthTest = Always;
			pass.depthWrite = false;
			gBrush.material.shadows = false;
			gBrush.material.color = newColor;
			gBrushes.push(gBrush);
			gBrush = new h3d.scene.Mesh(new h3d.prim.Sphere(Math.min(radius*0.05, 0.35)), ctx.local3d);
			gBrush.ignoreParentTransform = true;
			var pass = gBrush.material.mainPass;
			pass.setPassName("outline");
			pass.depthTest = Always;
			pass.depthWrite = false;
			gBrush.material.shadows = false;
			gBrush.material.color = newColor;
			gBrushes.push(gBrush);
		}
		for (g in gBrushes) g.visible = true;
		for (g in gBrushes) {
			g.x = originX;
			g.y = originY;
			g.z = originZ + 0.025;
		}
	}

	override function setSelected( ctx : hrt.prefab.Context, b : Bool ) {
		if( !b ) {
			removeInteractiveBrush();
		}
		setupRfx(editorCtx, keepVisible || b);
		updateVisuals(ctx);
		return false;
	}

	function updateColors() {

		var layer = layers.filter(l -> l.name == currentLayer)[0];

		var maxIndex = 0;
		for ( v in layer.values ) {
			if ( maxIndex < v.index )
				maxIndex = v.index;
		}
		var pixels = hxd.Pixels.alloc(maxIndex+1, 1, RGBA);
		for ( v in layer.values ) {
			pixels.setPixel(v.index, 0, v.color);
		}

		if ( colorMap != null )
			colorMap.dispose();

		colorMap = h3d.mat.Texture.fromPixels(pixels);
		colorMap.filter = Nearest;
	}

	override function edit( ectx : hide.prefab.EditContext ) {
		super.edit(ectx);
		var ctx = ectx.getContext(this);

		sceneEditor = ectx.scene.editor;

		var props = new hide.Element('<div>
					<div class="group" name="Layers">
						<dl>
							<dt>World Size</dt><dd><input type="text" value="$worldSize" style="width:110px" disabled /><button id="changeWorldSize" >Change</button></dd>
							<dt>Layer Scale</dt><dd><input type="text" value="$layerScale" style="width:110px" disabled /><button id="changeLayerScale" >Change</button></dd>
						</dl>
						<dl>
							<dt>Collide</dt>
							<dd>
								<input type="checkbox" field="collideEnable"/>
								<input type="texturepath" style="width:125px" field="collidePath"/>
								<input type="color" field="collideMask"/>
							</dd>
							<dt>Highlight Unpainted</dt>
							<dd>
								<input type="checkbox" field="highlightNotPaintedPixels"/>
								<input type="color" field="highlightColor"/>
							</dd>
							<dt>Brush Radius</dt><dd><input type="range" min="1" max="100" field="brushRadius"/></dd>
							<dt>Erase Radius</dt><dd><input type="range" min="1" max="100" field="eraseRadius"/></dd>
							<dt>Layer Alpha</dt><dd><input type="range" min="0" max="1" field="layerAlpha"/></dd>
						</dl>
						<dl>
							<dt>Paint override</dt><dd><input type="checkbox" field="paintOverride" /></dd>
						</dl>
						<dl>
							<dt>Keep Visible</dt><dd><input type="checkbox" field="keepVisible"/></dd>
						</dl>
						<p>
							<b><i>
							Hold down SHIFT to erase<br />
							Hold down CTRL + Wheel to adjust brush radius
						</p>
						<ul id="layers"></ul>
					</div>
				</div>');

		props.find("#changeLayerScale").click(function(_) {
			var input = hide.Ide.inst.ask("New layer scale: ");
			if( input == null || input.length == 0 )  return;
			var value = Std.parseInt(input);
			if( Std.string(value) != input ) return;
			if( value <= 0 ) return;
			if( value == layerScale ) return;
			var oldSize = Math.floor(worldSize / layerScale);
			layerScale = value;
			var newSize = Math.floor(worldSize / layerScale);
			var difSize = oldSize / newSize;
			for( key => layerTexture in layerTextures ) {
				var newLayerTexture = hxd.Pixels.alloc(newSize, newSize, RGBA);
				for( y in 0...newSize ) {
					for( x in 0...newSize ) {
						var ox = Math.floor(x * difSize); 
						var oy = Math.floor(y * difSize);
						var c = layerTexture.getPixel(ox, oy);
						newLayerTexture.setPixel(x, y, c);
					}
				}
				layerTextures.set(key, newLayerTexture);
			}
			ectx.rebuildProperties();
		});
		props.find("#changeWorldSize").click(function(_) {
			var input = hide.Ide.inst.ask("New world size: ", "" + worldSize);
			if( input == null || input.length == 0 )  return;
			var value = Std.parseInt(input);
			if( Std.string(value) != input ) return;
			if( value == worldSize ) return;
			var oldSize = Math.floor(worldSize / layerScale);
			worldSize = value;
			var newSize = Math.floor(worldSize / layerScale);
			var copySize = hxd.Math.imin(oldSize, newSize);
			for( key => layerTexture in layerTextures ) {
				var newLayerTexture = hxd.Pixels.alloc(newSize, newSize, RGBA);
				newLayerTexture.blit(0, 0, layerTexture, 0, 0, copySize, copySize);
				layerTextures.set(key, newLayerTexture);
			}
			ectx.rebuildProperties();
		});
		var list = props.find("ul#layers");
		ectx.properties.add(props,this, (pname) -> {
			if ( pname == "collidePath" ) {
				if ( collideMap != null ) {
					collideMap.dispose();
					collideMap = null;
				}
			}
			updateVisuals(ctx);
		});

		function selectLayer( name : String ) {
			if ( currentLayer != name ) {
				currentLayer = name;

				currentPixels = layerTextures.get(currentLayer);
				if ( currentPixels == null ) {
					currentPixels = hxd.Pixels.alloc(Math.floor(worldSize / layerScale), Math.floor(worldSize / layerScale), RGBA);
					layerTextures.set(currentLayer, currentPixels);
				}
				currentTexture = h3d.mat.Texture.fromPixels(currentPixels, RGBA);
				currentTexture.filter = Nearest;
				updateColors();

				currentLayerValue = null;
			} else {
				currentLayer = null;
				currentLayerValue = null;
			}
			ectx.rebuildProperties();
		}

		for( layer in layers ) {
			var borderColor = currentLayer == layer.name ? "green" : "darkgrey";
			var e = new hide.Element('<div style="margin-top: 5px; border: 1px solid $borderColor; padding: 6px;">
				<input type="text" style="width:100px" field="name"/> <button id="selectLayer">Select</button>
				<div class="layerValues" style="margin-top: 5px; vspacing:" />
			</div>
			');
			ectx.properties.build(e, layer, (pname) -> { });

			if ( currentLayer == layer.name ) {
				var layerValues = e.find(".layerValues");
				for ( vLayer in layer.values ) {
					var rowStyle = (currentLayerValue == vLayer.index) ? "border: 2px solid green; background: #001d00;" : "border: 2px solid #111111;";
					var lValueContent = new hide.Element('<div style="margin: 3px; padding: 2px; $rowStyle" >
						<input type="color" field="color"/>
						<input type="text" style="width:110px" field="name"/>
						<button id="paintVLayer">Paint</button>
						<button id="delVLayer">Del.</button>
					</div>');
					lValueContent.appendTo(layerValues);
					ectx.properties.build(lValueContent, vLayer, (pname) -> {
						if (pname == "color") {
							updateColors();
							updateVisuals(ctx);
						}
					});

					lValueContent.find("#paintVLayer").click(function(_) {
						if ( currentLayerValue == vLayer.index )
							currentLayerValue = null;
						else {
							currentLayerValue = vLayer.index;
						}
						ectx.rebuildProperties();
					});

					lValueContent.find("#delVLayer").click(function(_) {
						if ( hide.Ide.inst.confirm('Delete value "${vLayer.name}" ?') ) {
							layer.values.remove(vLayer);
							prepareUploadPixels();
							for ( iy in 0...currentPixels.height ) {
								for ( ix in 0...currentPixels.width ) {
									if ( currentPixels.getPixel(ix, iy) & vLayer.index == vLayer.index )
										currentPixels.setPixel(ix, iy, 0);
								}
							}
							saveUploadPixels();
							currentTexture.uploadPixels(currentPixels);
							if ( currentLayerValue == vLayer.index )
								currentLayerValue = null;

							ectx.rebuildProperties();
						}
					});
				}

				var vLayerAction = new hide.Element('<div class="btn-list" align="center">
					<input type="button" value="Add value" id="addVLayer" />
					<input type="button" value="Delete layer" id="delLayer" />
				</div>').appendTo(layerValues);

				vLayerAction.find("#addVLayer").click(function(_) {
					var name = hide.Ide.inst.ask("Layer value name:");
					if (name == null || name.length == 0) return;
					var maxIndex = 0;
					for ( v in layer.values ) {
						if ( maxIndex < v.index )
							maxIndex = v.index;
					}
					var validIdx = maxIndex+1;
					for ( i in 1...maxIndex ) {
						if ( layer.values.filter( v -> v.index == i ).length == 0 ) {
							validIdx = i;
							break;
						}
					}
					layer.values.push({
						index	: validIdx,
						name 	: name,
						color	: 0x00ff00
					});
					updateColors();
					ectx.rebuildProperties();
				});

				vLayerAction.find("#delLayer").click(function(_) {
					if ( hide.Ide.inst.confirm('Delete layer "${layer.name}" ?') ) {
						layers.remove(layer);
						currentLayer = null;
						currentLayerValue = null;
						ectx.rebuildProperties();
					}
				});
			}
			e.find("#selectLayer").click(function(_) {
				selectLayer(layer.name);
			});
			e.appendTo(list);
		}

		if ( currentLayerValue != null ) {
			createInteractiveBrush(ectx);
		} else {
			removeInteractiveBrush();
		}

		setupRfx(ectx, true);
		updateVisuals(ctx);

		var actions = new hide.Element('<div class="btn-list" align="center" style="margin-top: 5px;" ></div>').appendTo(list);
		var addLayer = new hide.Element('<input type="button" value="Create a new layer" />').appendTo(actions);
		addLayer.click(function(_) {
			var name = hide.Ide.inst.ask("Layer name:");
			if (name == null || name.length == 0) return;
			for ( l in layers ) {
				if ( l.name == name ) {
					hide.Ide.inst.message("Another layer already has this name");
					return;
				}
			}
			layers.push({
				name 	: name,
				values	: []
			});
			selectLayer(name);
			ectx.rebuildProperties();
		});
	}

	override function getHideProps() : hide.prefab.HideProps {
		return { icon : "industry", name : "Layers 2D", isGround : true };
	}

	#end

	static var _ = hrt.prefab.Library.register("layers2D", Layers2D);

}
