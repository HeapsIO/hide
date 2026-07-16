package hrt.ui;

#if hui

class HuiSceneEvents extends hxd.SceneEvents {
	public var huiScene: HuiScene;

	override function selectCursor() {
		var cur : hxd.Cursor = defaultCursor;
		for ( o in overList ) {
			if ( o.cursor != null ) {
				cur = o.cursor;
				break;
			}
		}
		switch( cur ) {
			case Callback(f): f();
			default: huiScene.interactive.cursor = cur;
		}
	}
}

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
	public var sceneEvents : HuiSceneEvents;
	public var disableSceneRender : Bool = false;

	public var sceneWidth(get, never) : Int;
	function get_sceneWidth() : Int {return renderTexture.width;};
	public var sceneHeight(get, never) : Int;
	function get_sceneHeight() : Int {return renderTexture.height;};

	var renderTexture : h3d.mat.Texture;

	#if editor_hl
	public var showSceneInfos(default, set) : Bool = false;
	var sceneInfos : HuiSceneInfos;
	function set_showSceneInfos(v) { sceneInfos.visible = v; return showSceneInfos = v; }
	#end

	override function set_enableInteractive(b:Bool):Bool {
		if( enableInteractive == b )
			return b;
		if( b ) {
			if( interactive == null ) {
				var interactive = new Interactive2(0, 0);
				interactive.huiScene = this;
				addChildAt(interactive,0);
				this.interactive = interactive;
				interactive.cursor = null;
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


		sceneEvents = new HuiSceneEvents();
		sceneEvents.huiScene = this;
		@:privateAccess hxd.Window.getInstance().removeEventTarget(sceneEvents.onEvent);

		var base = uiBase;
		sceneEvents.addScene(s2d);
		sceneEvents.addScene(s3d);

		makeInteractive();
		propagateEvents = true;

		#if editor_hl
		sceneInfos = new HuiSceneInfos(this, this);
		showSceneInfos = showSceneInfos;
		#end

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
		s2d.scaleMode = Custom(innerWidth, innerHeight, scale, scale);
		var pos = this.getAbsPos().getPosition();
		@:privateAccess s2d.offsetX = 0;
		@:privateAccess s2d.offsetY = 0;

		var scenePosition = {
			offsetX : 0.0,
			offsetY : 0.0,
			width : Std.int(textureWidth),
			height : Std.int(textureHeight)
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
				if (!disableSceneRender) {
					s3d.render(ctx.engine);
					#if editor_hl
					if (sceneInfos.visible)
						sceneInfos.updateStats(ctx.engine);
					#end
					s2d.render(ctx.engine);
				}
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
		handleEvent2(e, true);
	}

	public var lastX: Int = 0;
	public var lastY: Int = 0;

	function handleEvent2(e: hxd.Event, fixPos: Bool) {
		super.handleEvent(e);

		if (!e.propagate)
			return;

		var newEvent = e;

		var clone = new hxd.Event(e.kind, e.relX, e.relY);
		clone.relZ = e.relZ;
		clone.propagate = e.propagate;
		clone.cancel = e.cancel;
		clone.button = e.button;
		clone.touchId = e.touchId;
		clone.keyCode = e.keyCode;
		clone.charCode = e.charCode;
		clone.wheelDelta = e.wheelDelta;
		newEvent = clone;

		var scene = huiScene.getScene();
		if (fixPos) {
			// replace global events in screenSpace
			clone.relX = scene.mouseX * scene.viewportScaleX;
			clone.relY = scene.mouseY * scene.viewportScaleY;
		}

		newEvent.relX -= huiScene.absX * scene.viewportScaleX;
		newEvent.relY -= huiScene.absY * scene.viewportScaleY;

		lastX = hxd.Math.round(newEvent.relX);
		lastY = hxd.Math.round(newEvent.relY);

		if (newEvent.kind == EPush) {
			capturing = true;
			var captureButton = e.button;

			@:privateAccess getScene().events.startCapture((e) -> {
					handleEvent2(e, false);
					if (!hxd.Key.isDown(captureButton))
						@:privateAccess getScene().events.stopCapture();
				}, () -> {
				capturing = false;
			});
		} else if (capturing && (newEvent.kind == ERelease || newEvent.kind == EReleaseOutside)) {
			@:privateAccess getScene().events.stopCapture();
		}



		@:privateAccess huiScene.sceneEvents.onEvent(newEvent);

		// stop propagaion for original event
		e.propagate = false;
	}
}

class HuiSceneInfos extends HuiElement {
	static var SRC = <hui-scene-infos class="vertical">
		<hui-text("Statistics") class="title"/>
		<hui-text("Scene") class="sub-title"/>
		<hui-element class="horizontal">
			<hui-text("FPS : ") class="label"/>
			<hui-text("78") id="fps"/>
		</hui-element>
		<hui-element class="horizontal">
			<hui-text("Scene objects : ") class="label"/>
			<hui-text("78") id="scene-obj-count"/>
		</hui-element>
		<hui-element class="horizontal">
			<hui-text("Interactives 3D : ") class="label"/>
			<hui-text("78") id="int-3d"/>
		</hui-element>
		<hui-element class="horizontal">
			<hui-text("Interactives 2D : ") class="label"/>
			<hui-text("78") id="int-2d"/>
		</hui-element>

		<hui-text("Graphics") class="sub-title"/>
		<hui-element class="horizontal">
			<hui-text("Triangles : ") class="label"/>
			<hui-text("78") id="triangles-count"/>
		</hui-element>
		<hui-element class="horizontal">
			<hui-text("Buffers : ") class="label"/>
			<hui-text("78") id="buffers-count"/>
		</hui-element>
		<hui-element class="horizontal">
			<hui-text("Textures : ") class="label"/>
			<hui-text("78") id="tex-count"/>
		</hui-element>
		<hui-element class="horizontal">
			<hui-text("Draw Calls : ") class="label"/>
			<hui-text("78") id="draw-calls-count"/>
		</hui-element>
		<hui-element class="horizontal">
			<hui-text("V Ram : ") class="label"/>
			<hui-text("78") id="vram-count"/>
		</hui-element>

		<hui-text("Debug") class="sub-title"/>
		// <hui-element class="horizontal">
		// 	<hui-text("Mouse : ") class="label"/>
		// 	<hui-text("X: 000 Y: 000") id="mousePos"/>
		// </hui-element>

		// <hui-element class="horizontal">
		// 	<hui-text("Event Mouse : ") class="label"/>
		// 	<hui-text("X: 000 Y: 000") id="eventMousePos"/>
		// </hui-element>

		<hui-element class="horizontal">
			<hui-text("Scene Size : ") class="label"/>
			<hui-text("W: 000 H: 000") id="sceneSize"/>
		</hui-element>
	</hui-scene-infos>

	var scene : HuiScene;

	public function new(scene : HuiScene, ?parent: h2d.Object) {
		super(parent);
		initComponent();
		this.scene = scene;
	}

	public function updateStats(engine: h3d.Engine) {
		function splitCentaines(v: Int) {
			var str = Std.string(v);
			var endStr = "";
			for (char in 0...str.length) {
				if (char % 3 == 0 && char > 0) {
					endStr = " " + endStr;
				}
				endStr = str.charAt(str.length - char - 1) + endStr;
			}
			return endStr;
		}

		var memStats = engine.mem.stats();

		// Scene stats
		fps.text = '${Math.round(@:privateAccess engine.realFps)}';
		sceneObjCount.text = '${splitCentaines(scene.s3d.getObjectsCount())}';

		// Graphics stats
		trianglesCount.text = '${splitCentaines(Std.int(engine.drawTriangles))}';
		buffersCount.text = '${splitCentaines(memStats.bufferCount)}';
		texCount.text = '${splitCentaines(memStats.textureCount)}';
		drawCallsCount.text = '${splitCentaines(engine.drawCalls)}';
		vramCount.text = '${Std.int(memStats.totalMemory / (1024 * 1024))} Mb';

		// mousePos.text = 'X: ${@:privateAccess scene.s3d.events.mouseX} Y: ${@:privateAccess scene.s3d.events.mouseY}';
		// var i2 : Interactive2 = cast scene.interactive;
		// eventMousePos.text = 'X: ${i2.lastX} Y: ${i2.lastY}';
		@:privateAccess sceneSize.text = 'W: ${scene.renderTexture.width} H: ${scene.renderTexture.height}';
	}
}

#end
