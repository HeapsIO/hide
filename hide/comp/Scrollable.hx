package hide.comp;

class Scrollable extends Component {

    public function new(?parent,?root) {
        super(parent,root);
        this.root.addClass("hide-scrollable");
    }

}