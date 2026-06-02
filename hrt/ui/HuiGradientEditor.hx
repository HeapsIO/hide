package hrt.ui;

#if hui

class HuiGradientEditor extends HuiPopup {
	static var SRC =
		<hui-gradient-editor>

			<hui-element id="gradient-container">
				<bitmap id="gradient-display"/>
			</hui-element>


			<hui-element id="stop-editor">
				<hui-text id="stop-number"/>

				<hui-element id="h-layout">
					<hui-color-box id="color-picker"/>

					<hui-element id="v-layout">
						<hui-element class="edit-line">
							<hui-element class="label"><hui-text("Position") /></hui-element>
							<hui-slider min={0.0} max={1.0} decimals={3} id="stop-position"/>
						</hui-element>


						<hui-element class="edit-toolbar">
							<hui-button-menu(editMenu)>
								<hui-text("Edit")/>
								<hui-icon("dropDown")/>
							</hui-button-menu>
							<hui-button-menu(settingsMenu)>
								<hui-text("Texture settings")/>
								<hui-icon("dropDown")/>
							</hui-button-menu>
						</hui-element>
					</hui-element>

				</hui-element>

			</hui-element>



		</hui-gradient-editor>

	public function new(?parent) {
		super(parent);
		initComponent();

		stopGraphics = new h2d.Graphics(gradientContainer);
		gradientContainer.getProperties(stopGraphics).isAbsolute = true;
		gradientContainer.onAfterReflow = gradientContainerReflow;

		gradientContainer.onMove = gradientMouseMove;
		gradientContainer.onPush = gradientMousePush;

		var previewAlpha = new hrt.shader.PreviewShaderAlpha();
		gradientDisplay.addShader(previewAlpha);
		previewAlpha.split.y = 0.05;
		previewAlpha.split.w = 0.95;

		colorPicker.useAlpha = true;
		colorPicker.onValueChanged = colorPickerColorChanged;
		colorPicker.getPopupAnchor = () -> { object: Element(this), directionX: StartOutside, directionY: EndInside };

		stopPosition.onValueChanged = stopPositionChanged;

		registerCommand(hrt.ui.HuiCommands.delete, ElementAndChildren, () -> {
			if (selectedStop != -1 && value.stops.length > 1) {
				sortStops(() -> value.stops.splice(selectedStop, 1));
				onValueChanged(false);
			}
		});

		refreshSelectedStop();
	}

	public var value(default, set): hrt.impl.Gradient.GradientData;

	var stopGraphics: h2d.Graphics;

	function gradientMouseMove(e: hxd.Event) {
		updateHover(e);
		e.propagate = false;
	}

	function updateHover(e: hxd.Event) {
		var y = gradientContainer.calculatedHeight * 0.5;
		var prevHoveredStop = hoveredStop;
		hoveredStop = -1;
		var closestDist = stopSize;
		for (i => stop in value.stops) {
			var x = gradientContainer.calculatedWidth * stop.position;

			// manhattan distance for diamond collision detection
			var dist = hxd.Math.abs(e.relX - x) + hxd.Math.abs(e.relY - y);
			if (dist < closestDist) {
				hoveredStop = i;
				closestDist = dist;
			}
		}

		if (hoveredStop != prevHoveredStop) {
			refreshStops();
		}
	}

	function editMenu() : Array<hrt.ui.HuiMenu.MenuItem> {
		return [
			{label: "Flip", click: flip, stayOpen: true},
			{label: "Reset", click: reset, stayOpen: true},
		];
	}

	function reset() {
		value = hrt.impl.Gradient.getDefaultGradientData();
		refreshGradient();
		refreshSelectedStop();
		onValueChanged(false);
	}

	function flip() {
		sortStops(() -> {
			for (stop in value.stops) {
				stop.position = 1.0 - stop.position;
			}
		});

		refreshGradient();
		refreshSelectedStop();
		onValueChanged(false);
	};

	function settingsMenu() : Array<hrt.ui.HuiMenu.MenuItem> {

		var resolutionMenu : Array<hrt.ui.HuiMenu.MenuItem> = [];
		for (i in 3...9) {
			var val = 1 << i;
			resolutionMenu.push({label: '$val px', radio: () -> value.resolution == val, click: () -> {value.resolution = val; refreshGradient(); onValueChanged(false);}, stayOpen: true});
		}

		return [
			{label: "Resolution", menu: resolutionMenu},
			{label: "Orientation", menu: [
				{label: "Vertical", radio: () -> value.isVertical, click: () -> {value.isVertical = true; onValueChanged(false);}, stayOpen: true},
				{label: "Horizontal", radio: () -> !value.isVertical, click: () -> {value.isVertical = false; onValueChanged(false);}, stayOpen: true},
			]},
			{label: "Interpolation", menu: [
				{label: "Linear", radio: () -> value.interpolation == Linear, click: () -> {value.interpolation = Linear; refreshGradient(); onValueChanged(false);}, stayOpen: true},
				{label: "Cubic", radio: () -> value.interpolation == Cubic, click: () -> {value.interpolation = Cubic; refreshGradient(); onValueChanged(false);}, stayOpen: true},
				{label: "Constant", radio: () -> value.interpolation == Constant, click: () -> {value.interpolation = Constant; refreshGradient(); onValueChanged(false);}, stayOpen: true},
			]},
		];
	}


	function gradientMousePush(e: hxd.Event) {
		if (e.button == 0) {
			if (selectedStop != hoveredStop) {
				selectedStop = hoveredStop;
				refreshStops();
			} else if (selectedStop == -1) {
				// Add new stop

				var x = hxd.Math.clamp(e.relX / gradientContainer.calculatedWidth);

				var newStop : hrt.impl.Gradient.ColorStop = {
					position: x,
					color: hrt.impl.Gradient.evalData(value, x).toColor(),
				};

				sortStops(() -> value.stops.push(newStop));

				selectedStop = value.stops.indexOf(newStop);
				onValueChanged(false);
			}
			e.propagate = false;

			if (selectedStop != -1) {
				gradientContainer.interactive.startCapture(gradientMouseDrag, () -> {
					onValueChanged(false);
				});
			}

			updateHover(e);
			return;
		}
		else if (e.button == 1) {
			selectedStop = hoveredStop;
			execCommand(hrt.ui.HuiCommands.delete);
		}
	}

	function gradientMouseDrag(e: hxd.Event) {
		switch(e.kind) {
			case ERelease | EReleaseOutside:
				gradientContainer.interactive.stopCapture();
			case EMove:
				var x = hxd.Math.clamp(e.relX / gradientContainer.calculatedWidth);

				sortStops(() -> value.stops[selectedStop].position = x);

				refreshGradient();
				refreshSelectedStop();
			default:
		}
		e.propagate = false;
	}

	/** Allow to modify the order / number of points in the stop array without loosing reference to selected/hovered stops,
		and maintain the correct order of the stops in the array
		The cb function should contains the modifications of the array you wanna perform
	**/
	function sortStops(cb: Void -> Void) {
		var oldSelected = value.stops[selectedStop];
		var oldHovered = value.stops[hoveredStop];

		cb();
		value.stops.sort((a, b) -> Reflect.compare(a.position, b.position));

		selectedStop = value.stops.indexOf(oldSelected);
		hoveredStop = value.stops.indexOf(oldHovered);
	}

	function colorPickerColorChanged(tempChange: Bool) {
		if (selectedStop == -1)
			return;
		value.stops[selectedStop].color = colorPicker.value;
		refreshGradient();
		onValueChanged(tempChange);
	}

	function stopPositionChanged(tempChange: Bool) {
		if (selectedStop == -1)
			return;

		sortStops(() -> value.stops[selectedStop].position = stopPosition.value);
		refreshGradient();
		onValueChanged(tempChange);
	}

	function set_value(v: hrt.impl.Gradient.GradientData) : hrt.impl.Gradient.GradientData {
		value = v ?? hrt.impl.Gradient.getDefaultGradientData(); // ensure we allways have a valid data for the editor
		selectedStop = hxd.Math.imin(selectedStop, value.stops.length);
		hoveredStop = hxd.Math.imin(hoveredStop, value.stops.length);
		refreshGradient();
		refreshSelectedStop();
		refreshStops();
		return value;
	}

	function gradientContainerReflow() {
		gradientDisplay.width = gradientContainer.calculatedWidth;
		gradientDisplay.height = gradientContainer.calculatedHeight;

		refreshStops();
	}

	function refreshSelectedStop() {

		stopPosition.enable = selectedStop != -1;
		colorPicker.enable = selectedStop != -1;

		if (selectedStop == -1) {
			colorPicker.value = 0x77777777;
			stopNumber.text = 'No stop selected';
			stopPosition.value = 0;
		} else {
			colorPicker.value = value.stops[selectedStop].color;
			stopNumber.text = 'Stop ${selectedStop + 1} / ${value.stops.length}';
			stopPosition.value = value.stops[selectedStop].position;
		}
	}

	function refreshGradient() {
		var tex = hrt.impl.Gradient.textureFromData(value, false);
		gradientDisplay.tile = h2d.Tile.fromTexture(tex);

		refreshStops();
	}

	var stopSize = 0.0;
	var hoveredStop = -1;
	var selectedStop(default, set) = -1;

	function set_selectedStop(v: Int) {
		if(v != selectedStop) {
			selectedStop = v;
			refreshSelectedStop();
		}
		return v;
	}

	static var tmpVector = new h3d.Vector();
	function refreshStops() {
		stopGraphics.clear();

		var y = gradientContainer.calculatedHeight * 0.5;

		stopGraphics.beginFill(0, 1.0);
		stopGraphics.drawRect(0, y - 1, gradientContainer.calculatedWidth, 3);
		stopGraphics.endFill();

		stopGraphics.beginFill(0xFFFFFF, 1.0);
		stopGraphics.drawRect(0, y, gradientContainer.calculatedWidth, 1);
		stopGraphics.endFill();


		function drawStop(i: Int) {
			var stop = value.stops[i];
			var x = gradientContainer.calculatedWidth * stop.position;
			var y = gradientContainer.calculatedHeight * 0.5;
			stopSize = gradientContainer.calculatedHeight * 0.1;

			function drawDiamond(color: Int, size: Float) {
				stopGraphics.beginFill(color, 1.0);
				// circles are very aliased ...
				// stopGraphics.drawCircle(x, y, size, 16);
				stopGraphics.moveTo(x, y - size);
				stopGraphics.lineTo(x + size, y);
				stopGraphics.lineTo(x, y + size);
				stopGraphics.lineTo(x - size, y);
				stopGraphics.lineTo(x, y - size);
				stopGraphics.endFill();

				tmpVector = h3d.Vector.fromColor(color);
				var lineColor = 0xFFFFFF;
				if (tmpVector.length() > 0.5) {
					lineColor = 0;
				}

				stopGraphics.lineStyle(1, lineColor, 1.0);
				stopGraphics.moveTo(x, 0);
				stopGraphics.lineTo(x, 10);

				stopGraphics.moveTo(x, gradientContainer.calculatedHeight - 10);
				stopGraphics.lineTo(x, gradientContainer.calculatedHeight);
				stopGraphics.lineStyle();

			}

			var expandOutline = 0;
			if (hoveredStop == i)
				expandOutline += 2;
			if (selectedStop == i)
				expandOutline += 3;

			stopGraphics.lineStyle(1, 0, 0.5); // pseudo shadow
			drawDiamond(selectedStop == i ? 0xFFFFFF : 0xAAAAAA, stopSize + 4 + expandOutline);
			stopGraphics.lineStyle();

			drawDiamond(0, stopSize + 2);
			drawDiamond(stop.color, stopSize);
		}

		for (i => stop in value.stops) {
			if (i == selectedStop)
				continue;
			if (i == hoveredStop)
				continue;

			drawStop(i);
		}

		if (selectedStop > -1)
			drawStop(selectedStop);

		if (hoveredStop > -1)
			drawStop(hoveredStop);

	}

	public dynamic function onValueChanged(tempChange: Bool) {

	}
}

#end