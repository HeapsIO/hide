package hide.comp;

import hrt.impl.TextureType;
import hide.comp.GradientEditor.GradientBox;
import hrt.impl.Gradient;

// Allow the user to choose between picking a texture on disk,
// creating a gradient, and future other choices of texture generation
class TextureChoice extends Component {
    public var value(get, set) : Any;
    var innerValue : Any;

    public function new(?parent : Element,?root : Element) {
        var e = new Element("<div class='texture-choice'>");
        if (root != null) {
            JsTools.copyAttributes(e, root);
            root.replaceWith(e);
        }
        super(parent, e);

        rebuildUi();
    }

    public dynamic function onValueChange() {

    }

    public function rebuildUi() {
        element.empty();

        switch (Utils.getTextureType(innerValue)) {
            case TextureType.path: {
                // Small fix for the texture preview
                var wrapper = new Element("<div>").css({position: "relative"}).appendTo(element);

                var select = new hide.comp.TextureSelect(wrapper,null);
                select.element.width("auto");
                select.path = innerValue;
                select.onChange = function() {
                    set_value(select.path);
                    onChange(true);
                }
                onValueChange = function() {
                    select.path = innerValue;
                }
            }
            case TextureType.gradient: {
                var gradient = new GradientBox(element, null);
                gradient.onChange = function(isDragging:Bool) {
                    set_value({type:TextureType.gradient, data:gradient.value});
                    onChange(!isDragging);
                }
                onValueChange = function() {
                    gradient.value = Utils.getGradientData(innerValue);
                }
            }
            default : {
                new Element("<div>").text("Unhandled data (check log)").appendTo(element);
                trace("Unhandled data", innerValue);
                onValueChange = function() {};
            }
        }
        addChangeBtn();
    }

    function addChangeBtn() {
        var btn = new Element("<div class='hide-button change-button' title='Actions ...'>").appendTo(element);
        new Element("<div class='icon ico ico-ellipsis-h'>").appendTo(btn);
        btn.click(function(e) {
            ContextMenu2.createDropdown(btn.get(0), [
                { label : "Change to Texturepath", click : function() changeTextureType(TextureType.path), enabled: Utils.getTextureType(innerValue) != TextureType.path},
                { label : "Change to Gradient", click : function() changeTextureType(TextureType.gradient), enabled: Utils.getTextureType(innerValue) != TextureType.gradient},
            ]);
        });
    }

    function changeTextureType(newType : TextureType) {
        switch (newType) {
            case TextureType.path:
                set_value(null);
            case TextureType.gradient: {
                set_value({type:TextureType.gradient, data:Gradient.getDefaultGradientData()});
            }
            default :
                throw "unhandeld TextureType change";
        }

        onChange(true);
    }

    public function set_value(value : Any) {
        if (value == innerValue)
            return value;

        var prevValue = innerValue;
        innerValue = value;

        if (Type.typeof(value) != Type.typeof(prevValue)) {
            rebuildUi();
        }
        else if (Type.typeof(value) == TObject) {
            if ((value:Dynamic).type != (prevValue:Dynamic).type) {
                rebuildUi();
            }
        }

        onValueChange();

        return innerValue;
    }

    public function get_value() {
        return innerValue;
    }

    public dynamic function onChange(shouldUndo : Bool) {

    }


}