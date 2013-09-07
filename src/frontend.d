module frontend;

import std.conv: text;

import derelict.sdl2.sdl;
import derelict.opengl3.gl3;

import renderer;

// фронтэнд получает от ОС ввод и отправляет его бекенду,
// получает от бекенда подготовленные данные и отображает их
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
	    DerelictGL3.load();

	    if (SDL_Init(SDL_INIT_VIDEO) < 0)
	        throw new Exception("Failed to initialize SDL: " ~ SDL_GetError().text);
	    
	    scope(failure)
	    	SDL_Quit();

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
	    scope(failure) 
	    	SDL_DestroyWindow(sdl_window_);

	    gl_context_ = SDL_GL_CreateContext(sdl_window_);
	    if (gl_context_ is null) 
	    	throw new Exception("Failed to create a OpenGL context: " ~ SDL_GetError().text);
	    scope(failure)
	    	SDL_GL_DeleteContext(gl_context_);

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
			renderer_.draw();

        	SDL_GL_SwapWindow(sdl_window_);
		}
	}

	bool processEvents()
	{
    	bool is_running = true;
        SDL_Event event;
        // handle all SDL events that we might've received in this loop iteration
        if (SDL_WaitEvent(&event)) {
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

    }
}
