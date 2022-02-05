package heat.col;

/**
    Defines an area that an entity occupies in space. Note that this is distinct from the rendered size and can be different.
**/
class Collidable {
    public var rect:core.Rect;
    public var movable = true;

    public function new(x:Float, y:Float, w:Float, h:Float) {
        rect = new core.Rect(x, y, w, h);
    }
}
