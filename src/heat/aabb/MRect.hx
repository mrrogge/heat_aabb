package heat.aabb;

using tink.CoreApi;
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
    /**
        Sets the width. Position and offset are not altered.
    **/
    function set_width(width:Float):Float {
        dim.x = width;
        return width;
    }
    
    public var height(get, set):Float;
    inline function get_height():Float return dim.y;
    /**
        Sets the height. Position and offset are not altered.
    **/
    function set_height(height:Float):Float {
        dim.y = height;
        return height;
    }
    
    public var offsetX(get, set):Float;
    inline function get_offsetX():Float return offset.x;
    /**
        Sets the offset position. 
        
        Anchor position is not altered, so this can result in moving the MRect to a different position in space. For setting the offset without moving the MRect, see offsetTo().
    **/
    function set_offsetX(offsetX:Float):Float {
        offset.x = offsetX;
        return offsetX;
    }
    
    public var offsetY(get, set):Float;
    inline function get_offsetY():Float return offset.y;
    /**
        Sets the offset position. 
        
        Anchor position is not altered, so this can result in moving the MRect to a different position in space. For setting the offset without moving the MRect, see offsetTo().
    **/
    function set_offsetY(offsetY:Float):Float {
        offset.y = offsetY;
        return offsetY;
    }

    public var leftX(get, set):Float;
    inline function get_leftX():Float return x - offsetX;
    /**
        Sets the left edge position. Width is not altered.
    **/
    function set_leftX(leftX:Float):Float {
        x = leftX + offsetX;
        return leftX;
    }
    
    public var topY(get, set):Float;
    inline function get_topY():Float return y - offsetY;
    /**
        Sets the top edge position. Height is not altered.
    **/
    function set_topY(topY:Float):Float {
        y = topY + offsetY;
        return topY;
    }

    public var rightX(get, set):Float;
    inline function get_rightX():Float return leftX + width;
    /**
        Sets the right edge position. Width is not altered.
    **/
    function set_rightX(rightX:Float):Float {
        x = rightX - width + offsetX;
        return rightX;
    }

    public var bottomY(get, set):Float;
    inline function get_bottomY():Float return topY + height;
    /**
        Sets the bottom edge position. Height is not altered.
    **/
    function set_bottomY(bottomY:Float):Float {
        y = bottomY - height + offsetY;
        return bottomY;
    }

    public function topLeft(?dest:MVectorFloat2):MVectorFloat2 {
        if (dest == null) dest = new MVectorFloat2();
        return dest.init(leftX, topY);
    }

    public function topRight(?dest:MVectorFloat2):MVectorFloat2 {
        if (dest == null) dest = new MVectorFloat2();
        return dest.init(rightX, topY);
    }

    public inline function bottomLeft(?dest:MVectorFloat2):MVectorFloat2 {
        if (dest == null) dest = new MVectorFloat2();
        return dest.init(leftX, bottomY);
    }

    public inline function bottomRight(?dest:MVectorFloat2):MVectorFloat2 {
        if (dest == null) dest = new MVectorFloat2();
        return dest.init(rightX, bottomY);
    }
    
    public final pos = new MVectorFloat2();
    public final dim = new MVectorFloat2();
    public final offset = new MVectorFloat2();

    public function new(?pos:IVector2<Float>, ?dim:IVector2<Float>, ?offset:IVector2<Float>) {
        init(pos, dim, offset);
    }

    public inline function init(?pos:IVector2<Float>, ?dim:IVector2<Float>, ?offset:IVector2<Float>):MRect {
        return this.initPos(pos).initDim(dim).initOffset(offset);
    }

    public function initPos(?pos:IVector2<Float>):MRect {
        if (pos == null) {
            this.pos.init();
        }
        else {
            this.pos.initFrom(pos);
        }
        return this;
    }

    public function initDim(?dim:IVector2<Float>):MRect {
        if (dim == null) {
            this.dim.init();
        } 
        else {
            this.dim.initFrom(dim);
        }
        return this;
    }

    public function initOffset(?offset:IVector2<Float>):MRect {
        if (offset == null) {
            this.offset.init();
        } 
        else {
            this.offset.initFrom(offset);
        }
        return this;
    }
    
    public inline function clone():MRect {
        return new MRect(pos, dim, offset);
    }

    public function initFrom(other:IRect):MRect {
        pos.init(other.x, other.y);
        dim.init(other.width, other.height);
        offset.init(other.offsetX, other.offsetY);
        return this;
    }

    public inline function nearestCornerTo(point:IVector2<Float>, 
    ?dest:MVectorFloat2):MVectorFloat2 
    {
        if (dest == null) dest = new MVectorFloat2();
        return dest.init(
            Math.nearest(point.x, leftX, rightX), 
            Math.nearest(point.y, topY, bottomY)
        );
    }

    public static function diff(r1:IRect, r2:IRect, ?dest:MRect):MRect {
        if (dest == null) dest = new MRect();
        dest.pos.init(r2.leftX-r1.rightX, r2.topY-r1.bottomY);
        dest.dim.init(r1.width+r2.width, r1.height+r2.height);
        return dest;
    }

    public inline function diffWith(other:IRect, ?dest:MRect):MRect {
        return diff(this, other, dest);
    }


    public inline function offsetTo(offset:IVector2<Float>):MRect {
        return offsetToXY(offset.x, offset.y);
    }

    function offsetToXY(x:Float, y:Float):MRect {
        this.pos.init(leftX+x, topY+y);
        this.offset.init(x, y);
        return this;
    }

    public inline function normalize():MRect {
        return offsetTo(VectorFloat2.ORIGIN);
    }

    public inline function centerOffset():MRect {
        return offsetToXY(width/2, height/2);
    }

    public inline function containsPoint(point:IVector2<Float>):Bool {
        return point.x - leftX >= Math.FP_ERR()
            && point.y - topY >= Math.FP_ERR()
            && rightX - point.x >= Math.FP_ERR()
            && bottomY - point.y >= Math.FP_ERR();
    }

    public inline function intersectsWithRect(other:IRect):Bool {
        return leftX < other.rightX && other.leftX < rightX
            && topY < other.bottomY && other.topY < bottomY;
    }

    public inline function toImmutable():Rect {
        return new Rect(pos, dim, offset);
    }

    public static inline function fromImmutable(immutable:Rect):MRect {
        return new MRect(immutable.pos, immutable.dim, immutable.offset);
    }
}