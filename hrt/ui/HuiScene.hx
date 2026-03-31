package hrt.ui;

#if hui

class HuiScene extends HuiElement {
	static var SRC =
	<hui-scene>
		<bitmap public id="display"/>
		<hui-error-display id="error"/>
	</hui-scene>

	/**Clear color of the 3d scene. Must include the alpha component in order to be visible**/
	@:p var backgroundColor : Int = 0;

	public var s2d : h2d.Scene;
	public var s3d : h3d.scene.Scene;
	public var sceneEvents : hxd.SceneEvents;

	var renderTexture : h3d.mat.Texture;

	override function set_enableInteractive(b:Bool):Bool {
		if( enableInteractive == b )
			return b;
		if( b ) {
			if( interactive == null ) {
				var interactive = new Interactive2(0, 0);
				interactive.huiScene = this;
				addChildAt(interactive,0);
				this.interactive = interactive;
				interactive.cursor = Default;
				getProperties(interactive).isAbsolute = true;
				if( !needReflow ) {
					interactive.width = calculatedWidth;
					interactive.height = calculatedHeight;
				}
				interactive.onWheel = onMouseWheel;
			}
		} else {
			if( interactive != null ) {
				interactive.remove();
				interactive = null;
			}
		}
		return enableInteractive = b;
	}


	public function new(?parent: h2d.Object) {
		super(parent);
		initComponent();

		s2d = new h2d.Scene();
		s3d = new h3d.scene.Scene(false, false);

		if (renderTexture == null) {
			renderTexture = new h3d.mat.Texture(1,1, [Target]);
			renderTexture.depthBuffer = new h3d.mat.Texture(1,1, hxd.PixelFormat.Depth24Stencil8);
			renderTexture.clear(0x000000);
			display.tile = h2d.Tile.fromTexture(renderTexture);
		}


		sceneEvents = new hxd.SceneEvents();
		@:privateAccess hxd.Window.getInstance().removeEventTarget(sceneEvents.onEvent);

		var base = uiBase;
		sceneEvents.addScene(s2d);
		sceneEvents.addScene(s3d);

		makeInteractive();
		propagateEvents = true;

		// new h3d.scene.Box(0x000000, s3d);
		// var t = new h2d.Text(hxd.res.DefaultFont.get(), s2d);
		// t.text = "Hello scene";

		// enableInteractive = true;
		// (cast interactive:Interactive2).huiScene = this;

		// new h3d.scene.CameraController(s3d);
		// @:privateAccess new hrt.ui.HuiButtonMenu(() -> [], base);
	}

	var wasVisible = false;
	override function sync(ctx) {
		var currentVisible = true;
		var current : h2d.Object = this;
		while(current != null) {
			if (!current.visible) {
				currentVisible = false;
				break;
			}
			current = current.parent;
		}

		if (currentVisible != wasVisible) {
			wasVisible = currentVisible;
			var base = uiBase;
		}

		if (currentVisible) {
			var scene = getScene();
			var scale = getScene().viewportScaleX;

			s3d.scenePosition = s3d.scenePosition ?? {offsetX: 0, offsetY: 0, width: 0, height: 0};
			s3d.scenePosition.offsetX = 0;//display.absX;
			s3d.scenePosition.offsetY = 0;//display.absY;
			s3d.scenePosition.width = Std.int(display.width);
			s3d.scenePosition.height = Std.int(display.height);

			sceneEvents.checkEvents();

			s3d.setElapsedTime(hxd.Timer.dt);
			s2d.setElapsedTime(hxd.Timer.dt);



		}


		super.sync(ctx);
	}

	override function onAfterReflow() {
		var scale = getScene().viewportScaleX;

		var textureWidth = hxd.Math.iclamp(hxd.Math.round(innerWidth * scale) , 1, 4096);
		var textureHeight = hxd.Math.iclamp(hxd.Math.round(innerHeight * scale) , 1, 4096);

		if(renderTexture.width != textureWidth || renderTexture.height != textureHeight) {
			renderTexture.resize(textureWidth, textureHeight);
			renderTexture.depthBuffer.resize(textureWidth, textureHeight);
			display.tile = h2d.Tile.fromTexture(renderTexture);
		}

		display.width = innerWidth;
		display.height = innerHeight;

		s2d.scaleMode = Stretch(innerWidth, innerHeight);
		var pos = this.getAbsPos().getPosition();
		@:privateAccess s2d.offsetX = pos.x;
		@:privateAccess s2d.offsetY = pos.y;

		var scenePosition = {
			offsetX : pos.x,
			offsetY : pos.y,
			width : Std.int(innerWidth),
			height : Std.int(innerHeight)
		};
		s3d.scenePosition = scenePosition;
	}

	override function onRemove() {
		super.onRemove();

		s3d.dispose();
		s2d.dispose();

		var base = uiBase;
		base.app.sevents.removeScene(s2d);

		if (renderTexture != null) {
			renderTexture.dispose();
			renderTexture = null;
		}
	}

	override function draw(ctx:h2d.RenderContext) {
		if (renderTexture != null) {

			var prevRZ = ctx.getCurrentRenderZone();
			@:privateAccess ctx.clearRZ();

			var engine = ctx.engine;

			s3d.setOutputTarget(ctx.engine, renderTexture);
			engine.clear(backgroundColor, 1.0);

			var anyError = false;
			try {
				s3d.render(ctx.engine);
				s2d.render(ctx.engine);
			} catch(e) {
				anyError = true;
				error.setError("Scene render failed", e);
			}

			if (!anyError) {
				error.clearError();
			}

			s3d.setOutputTarget();

			if( prevRZ != null )
				@:privateAccess ctx.setRZ(prevRZ.x, prevRZ.y, prevRZ.width, prevRZ.height);

			@:privateAccess ctx.initShaders(ctx.baseShaderList);
			ctx.setCurrent();
		}
	}
}

class Interactive2 extends h2d.Interactive {
	public var huiScene: HuiScene;
	var capturing = false;
	override function handleEvent( e : hxd.Event ) {
		super.handleEvent(e);

		if (!e.propagate)
			return;


		if (e.kind == EPush) {
			capturing = true;
			@:privateAccess getScene().events.startCapture((e) -> {
					var scale = huiScene.getScene().viewportScaleX;
					var oldX = e.relX;
					var oldY = e.relY;

					e.relX -= huiScene.absX * scale;
					e.relY -= huiScene.absY * scale;
					e.relX /= scale;
					e.relY /= scale;

					handleEvent(e);

					e.relX = scale;
					e.relY = scale;
				}, () -> {
				capturing = false;
			});
		} else if (capturing && (e.kind == ERelease || e.kind == EReleaseOutside)) {
			@:privateAccess getScene().events.stopCapture();
		}

		var clone = new hxd.Event(e.kind, e.relX, e.relY);

		clone.relZ = e.relZ;
		clone.propagate = e.propagate;
		clone.cancel = e.cancel;
		clone.button = e.button;
		clone.touchId = e.touchId;
		clone.keyCode = e.keyCode;
		clone.charCode = e.charCode;
		clone.wheelDelta = e.wheelDelta;

		@:privateAccess huiScene.sceneEvents.onEvent(clone);
		e.propagate = false;
	}
}

#end
