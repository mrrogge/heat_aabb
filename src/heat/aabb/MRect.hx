package heat.aabb;

using heat.AllCore;

class MRect implements IRect {
    public var x(get, set):Float;
    inline function get_x():Float return pos.x;
    function set_x(x:Float):Float {
        pos.x = x;
        return x;
    }

    public var y(get, set):Float;
    inline function get_y():Float return pos.y;
    function set_y(y:Float):Float {
        pos.y = y;
        return y;
    }
    
    public var width(get, set):Float;
    inline function get_width():Float return dim.x;
    function set_width(width:Float):Float {
        dim.x = width;
        return width;
    }
    
    public var height(get, set):Float;
    inline function get_height():Float return dim.y;
    function set_height(height:Float):Float {
        dim.y = height;
        return height;
    }
    
    public var offsetX(get, set):Float;
    inline function get_offsetX():Float return offset.x;
    function set_offsetX(offsetX:Float):Float {
        offset.x = offsetX;
        return offsetX;
    }
    
    public var offsetY(get, set):Float;
    inline function get_offsetY():Float return offset.y;
    function set_offsetY(offsetY:Float):Float {
        offset.y = offsetY;
        return offsetY;
    }

    public var leftX(get, set):Float;
    inline function get_leftX():Float return x - offsetX;
    function set_leftX(leftX:Float):Float {
        x = leftX + offsetX;
        return leftX;
    }
    
    public var topY(get, set):Float;
    inline function get_topY():Float return y - offsetY;
    function set_topY(topY:Float):Float {
        y = topY + offsetY;
        return topY;
    }

    public var rightX(get, set):Float;
    inline function get_rightX():Float return leftX + width;
    function set_rightX(rightX:Float):Float {
        x = rightX - width + offsetX;
        return rightX;
    }

    public var bottomY(get, set):Float;
    inline function get_bottomY():Float return topY + height;
    function set_bottomY(bottomY:Float):Float {
        y = bottomY - height + offsetY;
        return bottomY;
    }

    public inline function topLeft():MVectorFloat2 {
        return new MVectorFloat2(leftX, topY);
    }

    public inline function topRight():MVectorFloat2 {
        return new MVectorFloat2(rightX, topY);
    }

    public inline function bottomLeft():MVectorFloat2 {
        return new MVectorFloat2(leftX, bottomY);
    }

    public inline function bottomRight():MVectorFloat2 {
        return new MVectorFloat2(rightX, bottomY);
    }
    
    final pos:MVectorFloat2;
    final dim:MVectorFloat2;
    final offset:MVectorFloat2;

    public function new(x=0., y=0., width=0., height=0., offsetX=0., offsetY=0.) {
        pos = new MVectorFloat2(x, y);
        dim = new MVectorFloat2(width, height);
        offset = new MVectorFloat2(offsetX, offsetY);
    }

    public static inline function fromXYWH(x=0., y=0., w=0., h=0.):MRect {
        return new MRect(x, y, w, h, 0, 0);
    }
    
    public inline function clone():MRect {
        return new MRect(x, y, width, height, offsetX, offsetY);
    }

    public inline function nearestCornerTo(x:Float, y:Float):MVectorFloat2 {
        return new MVectorFloat2(Math.nearest(x, leftX, rightX), 
            Math.nearest(y, topY, bottomY));
    }

    public static inline function diff(r1:IRect, r2:IRect):MRect {
        return new MRect(r2.leftX - r1.rightX,
            r2.topY - r1.bottomY,
            r1.width + r2.width,
            r1.height + r2.height,
            0, 0);
    }

    public inline function diffWith(other:IRect):MRect {

        return diff(this, other);
    }

    public inline function offsetTo(offsetX:Float, offsetY:Float):Rect {
        return new Rect(leftX + offsetX, topY + offsetY, width, height, offsetX, offsetY);
    }

    public inline function normalize():Rect {
        return offsetTo(0, 0);
    }

    public inline function centerOffset():Rect {
        return offsetTo(width/2, height/2);
    }

    public inline function containsPoint(x:Float, y:Float):Bool {
        return x - leftX >= Math.FP_ERR() && y - topY >= Math.FP_ERR()
            && rightX - x >= Math.FP_ERR() && bottomY - y >= Math.FP_ERR();
    }

    public inline function intersectsWithRect(other:IRect):Bool {
        return leftX < other.rightX && other.leftX < rightX
            && topY < other.bottomY && other.topY < bottomY;
    }
}