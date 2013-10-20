module frontend;

import std.conv: text;
import std.concurrency: thisTid, Tid, send, prioritySend, receiveTimeout, OwnerTerminated, Variant;
import std.datetime: dur, StopWatch;
import std.stdio: stderr, writeln, writefln;
import std.exception: enforce;
import std.traits: isUnsigned;
import core.thread: Thread;

import sdlapp: SDLApp;
import renderer: Renderer;
import tile: Tile, world2tile, tile2geodetic, geodetic2tile, tile2world;
import backend: BackEnd;

// Frontend receives user input from OS and sends it to backend,
// receves from backend processed data and renders it
class FrontEnd : SDLApp
{
private:
	Renderer renderer_;

    BackEnd backend_;
    Tid backend_tid_;
    string url_, cache_path_;

    /// current requested tile batch id
    size_t batch_id_;
    static assert(isUnsigned!(typeof(batch_id_)), "batch_id_ shall have unsigned type!");

    void launchBackend()
    {
        static ubyte count;
        if(count > 2)
        {
            stderr.writefln("****************************************");
            stderr.writefln("Too many attemps to launch backend: %s.", count);
            stderr.writefln("No more attempts will be performed.");
            stderr.writefln("****************************************\n\n");
            throw new Exception("BackEnd launching failed.");
        }
        writeln("Backend launching...");
        backend_ = new BackEnd(url_, cache_path_);
        backend_tid_ = backend_.runAsync();
        backend_tid_.send(thisTid);
        count++;
    }

public:

    this(uint width, uint height, double lon, double lat, string url, string cache_path)
	{
		super("Geoviewer", width, height);

		renderer_ = new Renderer(width, height);
        renderer_.camera.eyes = geodetic2tile(lon, lat, 0).tile2world;

        url_ = url;
        cache_path_ = cache_path;

        launchBackend();

        mouseMotionHandler = (int x, int y, bool rbtn_pressed)
        {
            //auto t = renderer_.camera.mouse2world(x, y, 0).world2tile;
            //writefln("tile: %s", t);
            //writefln("geodetic: %s", t.tile2geodetic);

            if (rbtn_pressed) {
                renderer_.camera.scrollingEnabled = true;
            } else {
                renderer_.camera.scrollingEnabled = false;
            }

            if(renderer_.camera.doScrolling(x, y))
            {
                requestNewTileBatch();
            }
        };

        mouseWheelHandler = (int x, int y)
        {
            if(y)
            {
                if (y > 0)
                {
                    renderer_.camera.multiplyScale(1.025);
                    requestNewTileBatch();
                }
                else
                {
                    renderer_.camera.multiplyScale(.975);
                    requestNewTileBatch();
                }
            }
        };

        drawHandler = ()
        {
            // process messages from BackEnd
            receiveMsg();
            // draw result of processing events and
            // receiving messages
            renderer_.draw(mouse_x_, mouse_y_);
        };

	}

    override void close()
    {
        renderer_.close();
        super.close();
    }

	// run frontend in the current thread
	override void run()
	{
        enforce(backend_tid_ != Tid.init);

        // without delay messages can be missed by backend TODO: the reason isn't known
        Thread.sleep(dur!"msecs"(100));
        // init the first tile batch loading
        requestNewTileBatch();

        super.run();
	}

    /// using camera defines tiles that are in camera frustum and therefore should be loaded
    void requestNewTileBatch()
    {
        /// start loading new tile set using new camera view
        /// id of request lets us to recognize different requests and skip old request data
        /// if requests are generated too quickly (next before previous isn't finished)
        auto viewable_tile_set = renderer_.camera.getViewableTiles();

        renderer_.startTileset(viewable_tile_set.length);

        batch_id_++;  // intended integer overflow

        // send new tile batch id to let backend to skip old batches
        backend_tid_.prioritySend(batch_id_);
        foreach(tile; viewable_tile_set)
        {
            // request tile image from backend
            backend_tid_.send(batch_id_, tile.x, tile.y, tile.zoom);
        }
    }

    void receiveMsg()
    {
		// talk to logic thread
        bool msg;
        StopWatch timer;
        timer.start();
        do{
            msg = receiveTimeout(dur!"usecs"(1),
                // getting tiles from backend
                (size_t batch_id, shared(Tile) shared_tile)
                {
                    if(batch_id != batch_id_)  // ignore tile of other requests
                        return;

                    auto tile = cast(Tile) shared_tile;
                    assert(tile !is null);
                    renderer_.setTile(tile);
                },
                (BackEnd.Status status)
                {
                    if(status == BackEnd.Status.backendCrashed)
                    {
                        // back end crashed, restart it
                        launchBackend();
                        return;
                    }
                    stderr.writefln("Message unprocessed: %s", status);
                },
                (OwnerTerminated ot)
                {
                    writeln(__FILE__ ~ "\t" ~ text(__LINE__) ~ ": Owner terminated");
                },
                (Variant any)
                {
                    stderr.writeln("Unknown message received by frontend thread: " ~ any.type.text);
                }
            );
        } while(msg && (timer.peek.msecs < 5)); // do not process longer than 5 milliseconds at once
        timer.stop();
    }
}
