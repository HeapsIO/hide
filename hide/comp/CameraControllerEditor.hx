package hide.comp;
import hide.view.CameraController;

class CameraControllerEditor extends Popup {

    var form_div : Element = null;
    var editor : SceneEditor = null;

    var controllersClasses : Array<{name: String, cl : Class<CameraControllerBase>}> = [
        {name: "Legacy", cl: CamController},
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
        //form_div.find('[for="cam-speed"]').toggleClass("hide-grid", !controller.isFps);
        //form_div.find('#cam-speed').parent().toggleClass("hide-grid", !controller.isFps);
    }

    function create() {
        if (form_div == null)
            form_div = new Element("<div>").addClass("form-grid").appendTo(popup);
        form_div.empty();
    
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
                }
                refresh();
            });
        }

        {
            var dd = new Element("<label for='cam-speed'>").text("Fly Speed").appendTo(form_div);
            var range = new Range(form_div, new Element("<input id='cam-speed' type='range' min='1' max='8' step='1'>"));
            var scale = 5.0;
            range.value = Math.round(Math.log(editor.cameraController.camSpeed) / Math.log(scale)) + 3;
            range.onChange = function(_) {
                editor.cameraController.camSpeed = Math.pow(scale, range.value-3);
            };
        }
    }

}