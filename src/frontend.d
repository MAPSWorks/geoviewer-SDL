module frontend;

import std.conv: text;
import std.concurrency: Tid, receiveTimeout, OwnerTerminated, Variant;
import std.datetime: dur, StopWatch;
import std.stdio: stderr, writeln, writefln;
import core.thread: Thread;

import derelict.sdl2.sdl;
import derelict.sdl2.image;
import derelict.opengl3.gl3;

import renderer;

// Frontend receives user input from OS and sends it to backend,
// receves from backend processed data and renders it
class FrontEnd
{
private:
	Renderer renderer_;
	SDL_Window* sdl_window_;
	SDL_GLContext gl_context_;

public:

	this(uint width, uint height)
	{
		DerelictSDL2.load();
		DerelictSDL2Image.load();
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
        
        //The frame rate regulator
        StopWatch fps;
        while(true)
		{
			//Start the frame timer
            fps.reset();
            fps.start();

            // process events from OS, if result is 
			// false then break loop
			if(!processEvents())
				break;
			// process messages from BackEnd
			receiveMsg();
			// draw result of processing events and 
			// receiving messages
			renderer_.draw();

        	SDL_GL_SwapWindow(sdl_window_);

            if( ( fps.peek.msecs < 1000 / FRAMES_PER_SECOND ) )
            {
                //Sleep the remaining frame time
                Thread.sleep(dur!"msecs"( (1000 / FRAMES_PER_SECOND) - fps.peek.msecs));
            }
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
	                break; 
	            case SDL_MOUSEBUTTONDOWN:
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
        do{     
            msg = receiveTimeout(dur!"usecs"(1),
            	(string str, uint amount)
            	{
            		if(str == "startTileSet")
            			renderer_.startTileset(amount);
            		else
            			stderr.writefln("Unknown message received by GUI thread: %s, %d", str, amount);
            	},
                (shared(Tile) shared_tile) {
                    auto tile = cast(Tile) shared_tile;
                    assert(tile !is null);
                    renderer_.setTile(tile);
                },
                (OwnerTerminated ot) {
                    writeln(__FILE__ ~ "\t" ~ text(__LINE__) ~ ": Owner terminated");
                },
                (Variant any) {
                    stderr.writeln("Unknown message received by GUI thread: " ~ any.type.text);
                }   
            );
        } while(msg);
    }
}
