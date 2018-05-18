package hide.comp;

class Modal extends Component {

    public var content(default,null) : Element;

    public function new(?parent,?root) {
        super(parent,root);
        this.root.addClass('hide-modal');
        content = new Element("<div class='content'></div>").appendTo(this.root);
    }

}