package hide.comp;

class Scrollable extends Component {

    public function new(?parent,?el) {
        super(parent,el);
        element.addClass("hide-scroll");
    }

}