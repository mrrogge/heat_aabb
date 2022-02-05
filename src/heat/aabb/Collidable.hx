package heat.aabb;

/**
    Defines an area that an entity occupies in space. Note that this is distinct from the rendered size and can be different.
    
    The rect position should be the absolute position of its entity.
**/
class Collidable {
    public var rect(default, null):MRect;
    public var offset(default, null):heat.vector.MVector2<Float>;
    public var movable = true;

    public function new() {
        rect = new MRect();
        offset = new heat.vector.MVector2<Float>();
    }

    public function setPos(x:Float, y:Float):Collidable {
        this.rect.x = x;
        this.rect.y = y;
        return this;
    }

    public function setDim(w:Float, h:Float):Collidable {
        this.rect.w = w;
        this.rect.h = h;
        return this;
    }

    public function setOffset(x:Float, y:Float):Collidable {
        this.offset.x = x;
        this.offset.y = y;
        return this;
    }
}
