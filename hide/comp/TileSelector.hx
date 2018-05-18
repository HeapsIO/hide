package hide.comp;

class TileSelector extends Component {

    public var file(default,set) : String;
    public var size(default,set) : Int;
    public var value : Null<{ x : Int, y : Int, width : Int, height : Int }>;
    public var allowRectSelect(default,set) : Bool;
    public var allowSizeSelect(default,set) : Bool;

    public function new(file,size,?parent,?root) {
        super(parent,root);
        this.root.addClass("hide-tileselect");
        this.file = file;
        this.size = size;
    }

    function set_file(file) {
        this.file = file;
        rebuild();
        return file;
    }

    function set_size(size) {
        this.size = size;
        rebuild();
        return size;
    }

    function set_allowRectSelect(b) {
        allowRectSelect = b;
        rebuild();
        return b;
    }

    function set_allowSizeSelect(b) {
        allowSizeSelect = b;
        rebuild();
        return b;
    }

    function rebuild() {
        root.html('<div class="tile" style="background-image:url(\'file://${ide.getPath(file)}\')"></div>');
        root.click(function(e) e.stopPropagation());
    }

    public dynamic function onChange() {
    }

}