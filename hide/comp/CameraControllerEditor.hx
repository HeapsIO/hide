package hide.comp;
import hide.view.CameraController.CamController as CamController;

class CameraControllerEditor extends Popup {

    var form_div : Element = null;
    var controller : CamController = null;

    public function new(controller: CamController, ?parent : Element, ?root : Element) {
        super(parent, root);
        this.controller = controller;
        popup.addClass("settings-popup");
        popup.append(new Element("<p>").text("Camera settings"));
        /*popup.width("400px");*/

        create();
        refresh();
    }

    function refresh() {
        form_div.find('[for="cam-speed"]').toggleClass("hide-grid", controller.isFps);
        form_div.find('#cam-speed').parent().toggleClass("hide-grid", controller.isFps);
    }

    function create() {
        if (form_div == null)
            form_div = new Element("<div>").addClass("form-grid").appendTo(popup);
        form_div.empty();

        {
            var dd = new Element("<label for='fov'>").text("FOV").appendTo(form_div);
            var range = new Range(form_div, new Element("<input id='fov' type='range' min='30' max='120'>"));
            range.value = controller.wantedFOV;
            range.onChange = function(_) {
                controller.wantedFOV = range.value;
            };
        }

        {
            var dd = new Element("<label for='control-mode'>").text("Cam Controls")
            .attr("title", "Choose how the camera is controlled :
            - Legacy : Middle mouse orbits, Right mouse pans.
            - FPS: Middle mouse pans, Right mouse look arround. Use the arrows/ZQSD keys while holding right mouse to fly around.")
            .appendTo(form_div);
            var select = new Element("<select id='control-mode'>").appendTo(form_div);
            new Element('<option value="Legacy">').text("Legacy").appendTo(select);
            new Element('<option value="FPS">').text("FPS").appendTo(select);
            select.val(controller.isFps ? "FPS" : "Legacy");
            select.on("change", function(_) {
                controller.isFps = select.val() == "FPS";
                refresh();
            });
        }

        {
            var dd = new Element("<label for='cam-speed'>").text("Fly Speed").appendTo(form_div);
            var range = new Range(form_div, new Element("<input id='cam-speed' type='range' min='1' max='8' step='1'>"));
            var scale = 5.0;
            range.value = Math.round(Math.log(controller.camSpeed) / Math.log(scale)) + 3;
            range.onChange = function(_) {
                controller.camSpeed = Math.pow(scale, range.value-3);
            };
        }
    }

}