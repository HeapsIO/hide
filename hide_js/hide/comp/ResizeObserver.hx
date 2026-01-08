package hide.comp;

@:native("ResizeObserver")
extern class ResizeObserver {
    function new(callback: (entries : Array<Dynamic>, self: ResizeObserver) -> Void);

    /**
        Unobserves all observed Element targets of a particular observer.
    **/
    function disconnect() : Void;

    /**
        Initiates the observing of a specified Element.
    **/
    function observe(element: js.html.Element) : Void;

    /**
        Ends the observing of a specified Element.
    **/
    function unobserve(target: js.html.Element) : Void;
}