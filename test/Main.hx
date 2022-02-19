import heat.aabb.*;
import heat.ecs.*;
import heat.event.*;

using buddy.Should;

class Main extends buddy.SingleSuite {
    public function new() {
        describe("basic tests:", {
            it("basic collision", {
                var coms = new ComMap<Collidable>();
                var sys = new CollisionSys(coms);
                coms[1] = new Collidable().setPos(0, 0).setDim(50, 50);
                coms[2] = new Collidable().setPos(25, 25).setDim(50, 50);
                var collided = false;
                var colSlot = new Slot((arg:ECollision)->collided = true);
                sys.collisionSignal.connect(colSlot);
                sys.update(1);
                collided.should.be(true);
            });
        });
    }
}