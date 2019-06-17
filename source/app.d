module main;
import core.thread;
import std.stdio;
import std.bitmanip;
import std.range.primitives : empty;
import std.json;
import std.functional;

import std.datetime.stopwatch;

import baos;
import datapoints;
import object_server;
import dsm;
import sdk;

void main()
{
  auto sdk = new DatapointSdk();
  auto dsm = new Dsm("127.0.0.1", cast(ushort)6379, "hello", "friend");
  void handleRequest(JSONValue jreq, void delegate(JSONValue) sendResponse) {
    writeln("now handle request in main app");

    JSONValue res;

    // TODO: switch(method) ..... send response; default: unknown method
    string method = ("method" in jreq).str;
    switch(method) {
      case "get value":
        res["success"] = true;
        StopWatch sw;
        sw.start();
        res["payload"] = sdk.getValue(jreq["payload"]);
        writeln("is time: ", sw.peek());
        sendResponse(res);
        break;
      default:
        res["success"] = false;
        StopWatch sw;
        sw.start();
        writeln("some other stuff");
        sendResponse(res);
        writeln("is time: ", sw.peek());
        break;
    }
  }
  dsm.subscribe(toDelegate(&handleRequest));
  writeln("IPC ready");

  // process incoming values
  while(true) {
    sdk.processInd();
    dsm.processMessages();

    // TODO: calculate approximate sleep time depending on baudrate
    // process redis messages here?
    // TODO: simple messages as a model; test
    Thread.sleep(1.msecs);
  }
}
