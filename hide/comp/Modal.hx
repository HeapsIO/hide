package hide.comp;

class Modal extends Component {

    public var content(default,null) : Element;

    public function new(?parent,?el) {
        super(parent,el);
        element.addClass('hide-modal');
        element.on("click dblclick keydown keyup keypressed mousedown mouseup mousewheel",function(e) e.stopPropagation());
        content = new Element("<div class='content'></div>").appendTo(element);
    }

}