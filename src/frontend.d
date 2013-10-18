module frontend;

import std.conv: text, to;
import std.concurrency: thisTid, Tid, send, prioritySend, receiveTimeout, OwnerTerminated, Variant;
import std.datetime: dur, StopWatch;
import std.stdio: stderr, writeln, writefln;
import std.exception: enforce;
import std.traits: isUnsigned;
import core.thread: Thread;

import derelict.sdl2.sdl;
import derelict.opengl3.gl3;

import renderer: Renderer;
import tile: Tile, world2tile, tile2geodetic, geodetic2tile, tile2world;
import backend: BackEnd;

// Frontend receives user input from OS and sends it to backend,
// receves from backend processed data and renders it
class FrontEnd
{
private:
	Renderer renderer_;
	SDL_Window* sdl_window_;
	SDL_GLContext gl_context_;

    BackEnd backend_;
    Tid backend_tid_;
    string url_, cache_path_;

    uint mouse_x_, mouse_y_;

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
		DerelictSDL2.load();
	    DerelictGL3.load();

	    if (SDL_Init(SDL_INIT_VIDEO) < 0)
	        throw new Exception("Failed to initialize SDL: " ~ SDL_GetError().text);

	    scope(failure) SDL_Quit();

	    // Set OpenGL version
	    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
	    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 2);

	    // Set OpenGL attributes
	    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
	    SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);

	    sdl_window_ = SDL_CreateWindow("Geoviewer",
	        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
	        width, height, SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN);

	    if (!sdl_window_)
	    	throw new Exception("Failed to create a SDL window: " ~ SDL_GetError().text);
	    scope(failure) SDL_DestroyWindow(sdl_window_);

	    gl_context_ = SDL_GL_CreateContext(sdl_window_);
	    if (gl_context_ is null)
	    	throw new Exception("Failed to create a OpenGL context: " ~ SDL_GetError().text);
	    scope(failure) SDL_GL_DeleteContext(gl_context_);

	    DerelictGL3.reload();

		renderer_ = new Renderer(width, height);
        renderer_.camera.eyes = geodetic2tile(lon, lat, 0).tile2world;

        url_ = url;
        cache_path_ = cache_path;

        launchBackend();
	}

	void close()
	{
		renderer_.close();
		/* Delete our opengl context, destroy our window, and shutdown SDL */
	    SDL_GL_DeleteContext(gl_context_);
	    SDL_DestroyWindow(sdl_window_);
	    SDL_Quit();
	}

	// run frontend in the current thread
	void run()
	{
        enum FRAMES_PER_SECOND = 60;

        enforce(backend_tid_ != Tid.init);

        // without delay messages can be missed by backend TODO: the reason isn't known
        Thread.sleep(dur!"msecs"(100));
        // init the first tile batch loading
        requestNewTileBatch();

        //The frame rate regulator
        StopWatch fps;
        fps.start();
        while(true)
		{

            // process events from OS, if result is
			// false then break loop
			if(!processEvents())
				break;
			// process messages from BackEnd
			receiveMsg();
			// draw result of processing events and
			// receiving messages
			renderer_.draw(mouse_x_, mouse_y_);

        	SDL_GL_SwapWindow(sdl_window_);

            auto t = fps.peek.msecs;
            if(t < 1000 / FRAMES_PER_SECOND)
            {
                //Sleep the remaining frame time
                auto delay = (1000 / FRAMES_PER_SECOND) - t;
                Thread.sleep(dur!"msecs"(delay));
            }
            //reset the frame timer
            fps.reset();
		}
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

	bool processEvents()
	{
    	bool is_running = true;
        // handle all SDL events that we might've received in this loop iteration
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            switch(event.type){
                // user has clicked on the window's close button
                case SDL_QUIT:
	                is_running = false;
                    break;
                case SDL_KEYUP:
                	switch (event.key.keysym.sym) {
                		// if user presses ESCAPE key - stop running
                		case SDLK_ESCAPE:
                			is_running = false;
                			break;
                		default:{}
                	}
                	break;
                case SDL_KEYDOWN:
                	switch (event.key.keysym.sym) {
                		case SDLK_UP:
                			break;
                		case SDLK_DOWN:
                			break;
                		case SDLK_RIGHT:
                			break;
                		case SDLK_LEFT:
                			break;
                		default:{}
                	}
                	break;
	            case SDL_MOUSEMOTION:
                    mouse_x_ = event.motion.x;
                    mouse_y_ = event.motion.y;

                    //auto t = renderer_.camera.mouse2world(mouse_x_, mouse_y_, 0).world2tile;
                    //writefln("tile: %s", t);
                    //writefln("geodetic: %s", t.tile2geodetic);

                    if (event.motion.state & SDL_BUTTON_RMASK) {
                        renderer_.camera.scrollingEnabled = true;
                    } else {
                        renderer_.camera.scrollingEnabled = false;
                    }

                    if(renderer_.camera.doScrolling(mouse_x_, mouse_y_))
                    {
                        requestNewTileBatch();
                    }
                break;
	            case SDL_MOUSEBUTTONDOWN:
	                break;
                case SDL_MOUSEWHEEL:
                    if(event.wheel.y)
                    {
                        if (event.wheel.y > 0)
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
                    break;
                default:
                    break;
            }
        }
        return is_running;
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
