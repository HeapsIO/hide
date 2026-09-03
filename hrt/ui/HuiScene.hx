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
	var delayedMove : hxd.Event = null;

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

		sceneEvents.addScene(s2d);
		sceneEvents.addScene(s3d);

		makeInteractive();
		propagateEvents = true;

		#if editor_hl
		sceneInfos = new HuiSceneInfos(this, this);
		showSceneInfos = showSceneInfos;
		#end
	}

	var wasVisible = false;
	override function sync(ctx) {
		#if editor_hl
		if (sceneInfos.visible)
			sceneInfos.begin(ctx.engine);
		#end
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
			if (delayedMove != null) {
				@:privateAccess sceneEvents.onEvent(delayedMove);
				delayedMove = null;
			}

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
		@:privateAccess s2d.offsetX = absX;
		@:privateAccess s2d.offsetY = absY;

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

			#if editor_hl
			if (sceneInfos.visible)
				sceneInfos.end(ctx.engine);
			#end
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

		if (newEvent.kind == EMove) {
			// delay move event to have only one per frame to avoid too many raycasts
			@:privateAccess huiScene.delayedMove = newEvent;
		} else {
			@:privateAccess huiScene.sceneEvents.onEvent(newEvent);
		}

		// stop propagaion for original event
		e.propagate = false;
	}
}

class HuiSceneInfos extends HuiElement {
	static var SRC = <hui-scene-infos class="vertical">
		<hui-text("Statistics") class="title"/>
		<hui-element class="horizontal">
			<hui-text("FPS : ") class="label"/>
			<hui-text("X") id="fps"/>
		</hui-element>
		<hui-element class="horizontal">
			<hui-text("CPU ms : ") class="label"/>
			<hui-text("X") id="cpu-ms-el"/>
		</hui-element>
		<hui-element class="horizontal">
			<hui-text("GPU ms : ") class="label"/>
			<hui-text("X") id="gpu-ms-el"/>
		</hui-element>


		<hui-element class="horizontal">
			<hui-text("Triangles : ") class="label"/>
			<hui-text("X") id="triangles-count"/>
		</hui-element>
		<hui-element class="horizontal">
			<hui-text("Post Process : ") class="label"/>
			<hui-text("X") id="post-process-count"/>
		</hui-element>
		<hui-element class="horizontal">
			<hui-text("V Ram : ") class="label"/>
			<hui-text("X") id="vram-count"/>
		</hui-element>

		<hui-text("Debug") class="sub-title"/>
		<hui-element class="horizontal">
			<hui-text("Mouse : ") class="label"/>
			<hui-text("X: 000 Y: 000") id="mousePos"/>
		</hui-element>

		<hui-element class="horizontal">
			<hui-text("Event Mouse : ") class="label"/>
			<hui-text("X: 000 Y: 000") id="eventMousePos"/>
		</hui-element>

		<hui-element class="horizontal">
			<hui-text("Scene Size : ") class="label"/>
			<hui-text("W: 000 H: 000") id="sceneSize"/>
		</hui-element>
	</hui-scene-infos>

	var scene : HuiScene;

	var cpuMs : Float = 0;
	var gpuMs : Float = 0;
	var postProcess : Int = 0;
	var triangles : Int = 0;

	var driver : h3d.impl.Driver;
	var gpuFreeQueryPool : Array<h3d.impl.Driver.Query> = [];
	var gpuPendingQueries : Array<h3d.impl.Driver.Query> = [];

	public function new(scene : HuiScene, ?parent: h2d.Object) {
		super(parent);
		initComponent();
		this.scene = scene;
		driver = h3d.Engine.getCurrent().driver;
	}

	public function begin(engine: h3d.Engine) {
		triangles = Std.int(engine.drawTriangles);
		cpuMs = haxe.Timer.stamp() * 1000;

		while (gpuPendingQueries.length >= 2) {
			var gpuStartQuery = gpuPendingQueries[0];
			var gpuEndQuery = gpuPendingQueries[1];
			if( !driver.queryResultAvailable(gpuStartQuery) || !driver.queryResultAvailable(gpuEndQuery) )
				break;
			gpuPendingQueries.shift();
			gpuPendingQueries.shift();
			var gpuDtNs = driver.queryResult(gpuEndQuery) - driver.queryResult(gpuStartQuery);
			gpuMs = roundFloat(gpuDtNs / 1e6);
			gpuFreeQueryPool.push(gpuStartQuery);
			gpuFreeQueryPool.push(gpuEndQuery);
		}
		if( gpuFreeQueryPool.length < 2 ) {
			gpuFreeQueryPool.push(driver.allocQuery(TimeStamp));
			gpuFreeQueryPool.push(driver.allocQuery(TimeStamp));
		}
		var query = gpuFreeQueryPool.pop();
		driver.endQuery(query);
		gpuPendingQueries.push(query);
	}

	public function end(engine: h3d.Engine) {
		if (gpuPendingQueries.length <= 0)
			return;

		triangles = Std.int(engine.drawTriangles) - triangles;
		cpuMs = (haxe.Timer.stamp() * 1000) - cpuMs;

		var query = gpuFreeQueryPool.pop();
		driver.endQuery(query);
		gpuPendingQueries.push(query);

		updateStats(engine);
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

		fps.text = '${Std.int(@:privateAccess engine.realFps)}';
		cpuMsEl.text = '${roundFloat(cpuMs)} ms';
		gpuMsEl.text = '${roundFloat(gpuMs)} ms';
		trianglesCount.text = '${splitCentaines(triangles)}';
		postProcessCount.text = '${@:privateAccess scene.s3d.renderer.effects.length}';
		var memStats = engine.mem.stats();
		vramCount.text = '${Std.int(memStats.totalMemory / (1024 * 1024))} Mb';

		// Debug
		mousePos.text = 'X: ${@:privateAccess scene.s3d.events.mouseX} Y: ${@:privateAccess scene.s3d.events.mouseY}';
		var i2 : Interactive2 = cast scene.interactive;
		eventMousePos.text = 'X: ${i2.lastX} Y: ${i2.lastY}';
		@:privateAccess sceneSize.text = 'W: ${scene.renderTexture.width} H: ${scene.renderTexture.height}';
	}

	function roundFloat(v : Float) {
		return Math.ceil(v * 100) / 100;
	}
}

#end
