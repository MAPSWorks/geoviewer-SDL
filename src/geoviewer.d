module geoviewer;

import std.concurrency: Tid, thisTid, send;

import frontend: FrontEnd;
import backend: BackEnd;

class Geoviewer {
private:
	FrontEnd frontend_;
	BackEnd backend_;
public:

	this(uint width, uint height, double lon, double lat, string url, string cache_path)
	{
		backend_ = new BackEnd(lon, lat, url, cache_path);
		frontend_ = new FrontEnd(width, height);
	}

	void run()
	{
		auto tid = backend_.runAsync();
		// notify backend what thread id the frontend has
		tid.send(thisTid);
		frontend_.backend = tid;
		frontend_.run();
	}

	void close() {
		frontend_.close();
		backend_.close();
	}
}
