package hide.comp;
import hide.view.CameraController;
import hide.comp.Popup;
import hide.comp.Range;
import hide.comp.ExpRange;



class CameraControllerEditor extends Popup {

    var form_div : Element = null;
    var editor : SceneEditor = null;


    static public var controllersClasses : Array<{name: String, cl : Class<CameraControllerBase>}> = [
        {name: "Classic", cl: CamController},
        {name: "Orthographic", cl: OrthoController},
        {name: "FPS", cl: FPSController},
        {name: "Fly/6DOF", cl: FlightController},
    ];

    public function new(editor: SceneEditor, ?parent : Element, ?root : Element) {
        super(parent, root);
        this.editor = editor;
        popup.addClass("settings-popup");
        popup.append(new Element("<p>").text("Camera settings"));
        /*popup.width("400px");*/

        create();
        refresh();
    }

    function refresh() {
        var ortho =
            Type.getClass(editor.cameraController) == OrthoController;

        var fly =
            Type.getClass(editor.cameraController) == FPSController ||
            Type.getClass(editor.cameraController) == FlightController;


        form_div.find('[for="cam-speed"]').toggleClass("hide-grid", !fly);
        form_div.find('#cam-speed').parent().toggleClass("hide-grid", !fly);
        form_div.find('[for="zNear"]').toggleClass("hide-grid", !fly);
        form_div.find('#zNear').parent().toggleClass("hide-grid", !fly);
        form_div.find('[for="zFar"]').toggleClass("hide-grid", !fly);
        form_div.find('#zFar').parent().toggleClass("hide-grid", !fly);

        form_div.find('[for="zBoundsScale"]').toggleClass("hide-grid", !ortho);
        form_div.find('#zBoundsScale').parent().toggleClass("hide-grid", !ortho);
    }

    function create() {
        if (form_div == null)
            form_div = new Element("<div>").addClass("form-grid").appendTo(popup);
        form_div.empty();

        {
            var dd = new Element("<label for='savePref'>").text("Global camera settings").appendTo(form_div);
            var checkBox = new Element('<input type="checkbox"/>').appendTo(form_div);
            var isGlobal = Ide.inst.currentConfig.get("sceneeditor.camera.isglobalsettings", false);
            checkBox.prop("checked", isGlobal);
            checkBox.on("change", function(_) {
                Ide.inst.currentConfig.set("sceneeditor.camera.isglobalsettings", checkBox.is(':checked'));
            });
        }

        {
            var dd = new Element("<label for='fov'>").text("FOV").appendTo(form_div);
            var range = new Range(form_div, new Element("<input id='fov' type='range' min='30' max='120'>"));
            range.value = editor.cameraController.wantedFOV;
            range.onChange = function(_) {
                editor.cameraController.wantedFOV = range.value;
            };
        }

        {
            var dd = new Element("<label for='control-mode'>").text("Cam Controls")
            .attr("title", "Choose how the camera is controlled :
            - Legacy : Middle mouse orbits, Right mouse pans.
            - FPS: Middle mouse pans, Right mouse look arround. Use the arrows/ZQSD keys while holding right mouse to fly around.")
            .appendTo(form_div);
            var select = new Element("<select id='control-mode'>").appendTo(form_div);
            var curId = 0;
            for (i in 0...controllersClasses.length) {
                var cl = controllersClasses[i];
                if (cl.cl == Type.getClass(editor.cameraController))
                    curId = i;
                new Element('<option value="$i">').text(cl.name).appendTo(select);
            }

            select.val(curId);

            select.on("change", function(_) {
                var id = Std.parseInt(select.val());
                var newClass = controllersClasses[id];
                if (Type.getClass(editor.cameraController) != newClass.cl) {
                    editor.switchCamController(newClass.cl);
                    refresh();
                }
                refresh();
            });
        }

        {
            var dd = new Element("<label for='cam-speed'>").text("Fly Speed").appendTo(form_div);
            var range = new Range(form_div, new Element("<input id='cam-speed' type='range' min='1' max='8' step='1'>"));
            var scale = 4.0;
            var pow_offset = 4;
            range.value = Math.round(Math.log(editor.cameraController.camSpeed) / Math.log(scale)) + pow_offset;
            range.onChange = function(_) {
                editor.cameraController.camSpeed = Math.pow(scale, range.value - pow_offset);
            };
        }

        {
            var dd = new Element("<label for='zNear'>").text("zNear").appendTo(form_div);
            var range = new ExpRange(form_div, new Element("<input id='zNear' type='range'>"));
            range.value = editor.cameraController.zNear;
            range.setMinMax(0.01,10000);
            range.onChange = function(_) {
                editor.cameraController.zNear = range.value;
            }
        }

        {
            var dd = new Element("<label for='zFar'>").text("zFar").appendTo(form_div);
            var range = new ExpRange(form_div, new Element("<input id='zFar' type='range'>"));
            range.value = editor.cameraController.zFar;
            range.setMinMax(0.01,10000);
            range.onChange = function(_) {
                editor.cameraController.zFar = range.value;
            }
        }

        {
            var dd = new Element("<label for='zBoundsScale'>").text("zBounds").appendTo(form_div);
            var range = new Range(form_div, new Element("<input id='zBoundsScale' type='range' min='0.01' max='10'>"));
            var ortho = Std.downcast(editor.cameraController, OrthoController);
            if (ortho != null) range.value = ortho.orthoZBounds;
            range.onChange = function(_) {
                var ortho = Std.downcast(editor.cameraController, OrthoController);
                if (ortho != null) ortho.orthoZBounds = range.value;
            };
        }
    }

}