module main;
import core.thread;
import std.stdio;


import baos;
import object_server;


void main()
{
  auto baos = new Baos();
  
  void onObjServerService(ObjectServerMessage message) {
    writeln("here comes message[ind]: ", message);
    Thread.sleep(1000.msecs);
    writeln("descr?", baos.GetDatapointDescriptionReq(1, 11));
  }
  baos.onObjServerService(&onObjServerService);
  while(true) {
    baos.processIncomingData();
    Thread.sleep(1.msecs);
    // process redis messages here?
  }
}
