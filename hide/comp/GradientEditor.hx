package hide.comp;

import hrt.impl.Gradient;
import hrt.impl.Gradient.GradientData;
import haxe.Int32;
import js.Browser;
import js.html.KeyboardEvent;
import js.html.MouseEvent;
import hide.comp.ColorPicker.ColorBox;
import js.html.SelectElement;
import js.html.PointerEvent;
import h3d.Vector;
import js.html.CanvasElement;

class GradientBox extends Component {
    public var value(get, set) : GradientData;
    var innerValue : GradientData;
    var gradientView : GradientView;

    var gradientEditor : GradientEditor;

    var prevHash : Int32 = 0;

    function set_value(value: GradientData) {
        // Cleanup previous gradient value from the cache
        /*var cache = Gradient.getCache();
        cache.remove(prevHash);*/

        innerValue = value;
        prevHash = Gradient.getDataHash(innerValue);

        gradientView.value = innerValue;
        if (gradientEditor != null)
            gradientEditor.value = innerValue;
        return innerValue;
    }

    function get_value() {
        return innerValue;
    }

    public dynamic function onChange(isDragging : Bool) {

    }

    public function new(?parent : Element, ?root : Element) {
        var e = new Element("<div class='gradient-box'>");
        if (root != null)
            root.replaceWith(e);
        super(parent, e);

        gradientView = new GradientView(element);

        element.click(function(e) {
            if (gradientEditor == null) {
                gradientEditor = new GradientEditor(null, element);
                gradientEditor.value = value;
                gradientEditor.onChange = function(isDragging : Bool) {
                    value = gradientEditor.value;
                    onChange(isDragging);
                }
                gradientEditor.onClose = function() {
                    gradientEditor = null;
                }
            } else {
                gradientEditor.close();
                gradientEditor = null;
            }
        });

        function contextMenu(e : js.jquery.Event) {
            e.preventDefault();
            new ContextMenu([
                {label: "Reset", click: function() {
                    value = Gradient.getDefaultGradientData();
                    onChange(false);
                }},
                {label:"sep", isSeparator: true},
                {label: "Copy", click: function() {
                    ide.setClipboard(haxe.Json.stringify(value));
                }},
                {
                    label: "Paste", click: function() {
                        try {
                            var data = haxe.Json.parse(ide.getClipboard());
                            value = data;
                            onChange(false);
                        } catch(_) {

                        }
                    }
                }
            ]);
        }

        element.contextmenu(contextMenu);
    }
}

class GradientEditor extends Popup {
    public var value(get, set) : GradientData;
    var innerValue : GradientData;

    var gradientView : GradientView;
    var stopsSvg : SVG;
    var linesSvg : SVG;

    var colorbox : ColorBox;

    var stopMarquers : Array<Element>;

    var selectedStop : Element;
    var stopEditor : Element;
    var stopLabel : Element;

    var resolutionInput : Element;
    var isVerticalCheckbox : Element;
    var interpolation : Element;
    var colorMode : Element;


    var keys : hide.ui.Keys;

    public dynamic function onChange(isDragging : Bool) {

    }

    function set_value(value: GradientData) {
        innerValue = value;
        gradientView.value = innerValue;
        repaint();
        return innerValue;
    }

    function get_value() {
        return innerValue;
    }

    public function new(?parent : Element, ?root : Element) {
        super(parent, root);

        popup.addClass("gradient-editor");

        // Allows the popup to become focusable,
        // allowing the handling of keyboard events
        popup.attr("tabindex","-1");
        popup.focus();

		popup.on("keydown", function (e : KeyboardEvent) {
            if (e.key == "Delete" || e.key =="Backspace") {
                if (selectedStop != null) {
                    removeStop(selectedStop);
                }
                e.preventDefault();
                e.stopPropagation();
            }
            if (e.key == "Escape") {
                if (selectedStop != null) {
                    selectStop(null);
                }
                else {
                    close();
                }
                e.preventDefault();
                e.stopPropagation();
            }
        });

        gradientView = new GradientView(popup);
        gradientView.element.height(90).width(256);

        var elem = gradientView.element.get(0);

        elem.onclick = function (e : js.html.MouseEvent) {
            var pos = e.offsetX / gradientView.element.width();
            addStop(pos);
        }

        stopMarquers = new Array<Element>();

        linesSvg = new SVG(gradientView.element);
        linesSvg.element.addClass("lines");
        linesSvg.element.attr({viewBox: '0.0 0.0 1.0 1.0'});
        linesSvg.element.attr({preserveAspectRatio:"xMidYMid slice"});

        linesSvg.line(linesSvg.element, 0.0,0.5,1.0,0.5).attr("vector-effect","non-scaling-stroke");

        stopsSvg = new SVG(gradientView.element);
        stopsSvg.element.attr({viewBox: '0.0 0.0 1.0 1.0'});
        stopsSvg.element.attr({preserveAspectRatio:"xMidYMid slice"});

        stopsSvg.element.html('
        <defs>
        <pattern id="checkboard-bg" width="0.5" height="0.5" patternContentUnits="objectBoundingBox">
        <rect x="0" y="0" width="1" height="1" fill="#777"/>
        <rect x="0" y="0" width=".25" height=".25" fill="#aaa"/>
        <rect x="0.25" y="0.25" width=".25" height=".25" fill="#aaa"/>
        </pattern>

        <filter id="shadow" color-interpolation-filters="sRGB" y="-40%" x="-40%" height="180%" width="180%">
        <feDropShadow dx="0.005" dy="0.005" stdDeviation="0.007" flood-opacity="0.5"/>
        </filter>
        </defs>');

        var editor = new Element("<div>").addClass("editor").appendTo(popup);
        stopEditor = new Element("<div>").addClass("stop-editor").appendTo(editor);

        stopLabel = new Element("<p>").appendTo(stopEditor);

        colorbox = new ColorBox(stopEditor, null, true, true);
        colorbox.element.width(64);
        colorbox.element.height(64);

        colorbox.onChange =
        function(isDragging : Bool) {
            if (selectedStop != null) {
                var id = stopMarquers.indexOf(selectedStop);
                innerValue.stops[id].color = colorbox.value;
                onChange(isDragging);
            }
        }

        // Prevent color picker from closing if we clicked the gradient
        colorbox.onPickerOpen = function() {
            colorbox.picker.onShouldCloseOnClick = function (clickEvent : js.html.Event) {
                var e = new Element(clickEvent.target);
                return e.closest(gradientView.element).length == 0;
            }
        }

        var detailsSection = new Element("<details>").appendTo(editor);
        new Element("<summary>").text("Generated texture settings").appendTo(detailsSection);

        var detailsDiv = new Element("<div>").css("padding", "4px").appendTo(detailsSection);

        resolutionInput = new Element("<select id='resolution' name='resolution'>");

        new Element("<div>").appendTo(detailsDiv)
            .append( new Element("<label for='resolution'>").text("Resolution"))
            .append(resolutionInput);
        for (i in 1...12) {
            var val = Math.pow(2, i);
            new Element('<option value="$val">').text('$val px').appendTo(resolutionInput);
        }

        resolutionInput.on("change", function(e : js.jquery.Event) {
            var val : Int = Std.parseInt(resolutionInput.val());
            innerValue.resolution = val;
            onChange(false);
        });


        isVerticalCheckbox = new Element("<select id='isVertical'>");

        new Element('<option value="0">').text('Horizontal').appendTo(isVerticalCheckbox);
        new Element('<option value="1">').text('Vertical').appendTo(isVerticalCheckbox);

        isVerticalCheckbox.on("change", function(e : js.jquery.Event) {
            var val : Bool = isVerticalCheckbox.val() == 1 ? true : false;
            innerValue.isVertical = val;
            trace(val);
            onChange(false);
        });

        new Element("<div>").appendTo(detailsDiv)
            .append(new Element("<label for='isVertical'>").text("Orientation").attr("title", "Change the orientation of the generated texture. This don't have any effect on gradients that are used only on the cpu"))
            .append(isVerticalCheckbox);


        interpolation = new Element("<select id='interpolation'>");
        new Element('<option value="Linear">').text('Linear').appendTo(interpolation);
        new Element('<option value="Constant">').text('Constant').appendTo(interpolation);
        new Element('<option value="Cubic">').text('Cubic').appendTo(interpolation);


        interpolation.on("change", function(e : js.jquery.Event) {
            var val : String = interpolation.val();
            innerValue.interpolation = val;
            trace(val);
            onChange(false);
        });

        new Element("<div>").appendTo(detailsDiv)
        .append(new Element("<label for='interpolation'>").text("Interpolation").attr("title", "Change how the colors stops in the gradient are interpolated between them."))
        .append(interpolation);

        colorMode = new Element("<select id='colorMode'>");
        var idx = 0;
        for (mode in hrt.impl.ColorSpace.colorModes) {
            new Element('<option value="$idx">').text(mode.name).appendTo(colorMode);
            idx ++;
        }

        colorMode.on("change", function(e : js.jquery.Event) {
            var val : Int = Std.parseInt(colorMode.val());
            innerValue.colorMode = val;
            trace(val);
            onChange(false);
        });

        new Element("<div>").appendTo(detailsDiv)
        .append(new Element("<label for='colorMode'>").text("Color Space").attr("title", "Change the color space to use when interpolating the stops of the gradient."))
        .append(colorMode);

        reflow();
        fixInputSelect();
    }

    public override function close() {
        if(colorbox.isPickerOpen()) {
            colorbox.picker.close();
        }
        super.close();
    }

    public override function canCloseOnClickOutside() : Bool {
        return !colorbox.isPickerOpen();
    }

    public function selectStop(stop:Element) {
        if (selectedStop != null) {
            selectedStop.removeClass("selected");
        }
        selectedStop = stop;
        if (selectedStop != null) {
            selectedStop.addClass("selected");
        }
        repaint();
    }

    public function repaint() {
        for (i in innerValue.stops.length...stopMarquers.length) {
            var elem = stopMarquers.pop();
            elem.remove();
        }

        for (i in stopMarquers.length...innerValue.stops.length) {
            var group = stopsSvg.group(stopsSvg.element).addClass("gradient-stop");
            stopsSvg.circle(group, 0, 0, 0.05, {}).addClass("outline");
            stopsSvg.circle(group, 0, 0, 0.05, {}).addClass("checkboard");
            stopsSvg.circle(group, 0, 0, 0.05, {}).addClass("fill");

            stopMarquers.push(group);

            var elem = group.get(0);
            var isDragging = false;
            elem.onclick = function (e : MouseEvent) {
                e.stopPropagation();
            }

            elem.oncontextmenu = function (e : MouseEvent) {
                e.preventDefault();
                removeStop(group);
            }

            var updateStopMouse = function (e : PointerEvent, isDrag : Bool) {
                var pos = e.offsetX / stopsSvg.element.width();
                pos = hxd.Math.clamp(pos, 0.0, 1.0);

                setStopPos(stopMarquers.indexOf(group), pos);
                onChange(isDrag);
            }

            elem.onpointerdown = function (e : PointerEvent) {
                isDragging = true;
                elem.setPointerCapture(e.pointerId);
                selectStop(group);
            }

            elem.onpointermove = function (e : PointerEvent) {
                if (isDragging) {
                    updateStopMouse(e, true);
                }
            }

            elem.onpointerup = function (e : PointerEvent) {
                isDragging = false;
                onChange(false);
                elem.releasePointerCapture(e.pointerId);
            }
        }

        var vector = new h3d.Vector4();
        for (i in 0...stopMarquers.length) {
            var marquer = stopMarquers[i];
            var stop = innerValue.stops[i];

            var x : Float = stop.position;
            var y : Float = 0.5;
            marquer.attr("transform", 'translate(${x}, ${y})');

            Gradient.evalData(innerValue, stop.position, vector);
            marquer.children(".fill").attr({fill: 'rgba(${vector.r*255.0}, ${vector.g*255.0}, ${vector.b*255.0}, ${vector.a})'});
        }

        if (selectedStop != null) {
            var id = stopMarquers.indexOf(selectedStop);
            colorbox.value = innerValue.stops[id].color;
            stopEditor.removeClass("disabled");
            stopLabel.text('Stop ${id+1} / ${stopMarquers.length}');
            colorbox.isPickerEnabled = true;
        } else {
            stopEditor.addClass("disabled");
            stopLabel.text('Stop');
            colorbox.value = 0x77777777;
            colorbox.isPickerEnabled = false;
        }

        resolutionInput.val('${innerValue.resolution}');
        isVerticalCheckbox.val('${innerValue.isVertical ? 1 : 0}');
        interpolation.val(innerValue.interpolation);
        colorMode.val('${innerValue.colorMode}');
    }

    function removeStop(element : Element) {
        if (stopMarquers.length <= 1)
            return;

        var idx = stopMarquers.indexOf(element);
        innerValue.stops.splice(idx, 1);

        if (selectedStop == element)
            selectStop(null);
        onChange(false);
    }

    function addStop(pos : Float) {
        var color = Gradient.evalData(innerValue, pos);
        innerValue.stops.push({position: pos, color:color.toColor()});
        innerValue.stops.sort((a, b) -> return if (a.position < b.position) -1
                                else if (a.position > b.position) 1
                                else 0);
        onChange(false);
    }

    function setStopPos(stopId : Int, pos : Float) {
        var arr = new Array<{stop:ColorStop, marquer:Element}>();
        arr.resize(stopMarquers.length);

        for (i in 0...stopMarquers.length) {
            var marquer = stopMarquers[i];
            var stop = innerValue.stops[i];
            arr[i] = {stop:stop, marquer:marquer};
        }

        arr[stopId].stop.position = pos;
        arr.sort((a, b) -> return if (a.stop.position < b.stop.position) -1
                                else if (a.stop.position > b.stop.position) 1
                                else 0);

        var prevPos = 0.0;

        for (i in 0...stopMarquers.length) {
            innerValue.stops[i] = arr[i].stop;
            stopMarquers[i] = arr[i].marquer;
        }
    }
}

// Displays a GradientData inside a canvas
class GradientView extends Component {
    public var value(get, set) : GradientData;
    var innerValue : GradientData;

    public var canvas : CanvasElement;

    function set_value(value: GradientData) {
        innerValue = value;
        repaint();
        return innerValue;
    }

    function get_value() {
        return innerValue;
    }

    function repaint() {
        canvas.width = innerValue.resolution;
        var c2d = canvas.getContext("2d");

        var image_data = c2d.getImageData(0,0,innerValue.resolution,1);
		var color = new h3d.Vector4();

        for (x in 0...innerValue.resolution) {
            var index = x * 4;
            Gradient.evalData(innerValue, x / (innerValue.resolution-1), color);
            image_data.data[index] = Std.int(color.r * 255.0);
            image_data.data[index+1] = Std.int(color.g * 255.0);
            image_data.data[index+2] = Std.int(color.b * 255.0);
            image_data.data[index+3] = Std.int(color.a * 255.0);
        }

		c2d.putImageData(image_data,0,0);
    }

    public function new(?parent : Element) {
        var e = new Element("<div class='gradient-container checkerboard-bg'>");
        super(parent, e);

        var canvasElement = new Element("<canvas class='gradient-preview'>").css({display:"block"}).appendTo(element);
        canvas = cast(canvasElement.get(0),CanvasElement);
        canvas.height = 1;
    }
}