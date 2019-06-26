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
  StopWatch mainSw;
  mainSw.start();
  auto sdk = new DatapointSdk();
  auto dsm = new Dsm("127.0.0.1", cast(ushort)6379, "hello", "friend");
  void handleRequest(JSONValue jreq, void delegate(JSONValue) sendResponse) {
    writeln("now handle request in main app");

    JSONValue res;

    auto jmethod = ("method" in jreq);
    if (jmethod is null) {
      writeln("there is no method field in json req");
      res["success"] = false;
      return;
    }
    auto jpayload = ("payload" in jreq);
    if (jpayload is null) {
      writeln("there is no payload field in json req");
      return;
    }

    string method = ("method" in jreq).str;
    switch(method) {
      case "get description":
        try {
          StopWatch sw;
          sw.start();
          res["method"] = "success";
          res["payload"] = sdk.getDescription(jreq["payload"]);
          sendResponse(res);
          writeln("is time: ", sw.peek());
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case "get value":
        try {
          res["method"] = "success";
          StopWatch sw;
          sw.start();
          res["payload"] = sdk.getValue(jreq["payload"]);
          writeln("is time: ", sw.peek());
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case "set value":
        try {
          res["method"] = "success";
          StopWatch sw;
          sw.start();
          res["payload"] = sdk.setValue(jreq["payload"]);
          writeln("is time: ", sw.peek());
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      default:
        res["method"] = "error";
        res["payload"] = "Unknown API method";
        StopWatch sw;
        sw.start();
        sendResponse(res);
        break;
    }
  }
  dsm.subscribe(toDelegate(&handleRequest));
  writeln("IPC ready");
  writeln("started in: ", mainSw.peek());

  // process incoming values
  while(true) {
    // TODO: now, there is a problem
    // TODO: when reset ind is received
    // TODO: blocking method may be trying to run
    // TODO: e.g. when bus was disconnected
    // TODO: and in this time was req from redis
    // TODO: of course, that req was not successfull
    // TODO: but he is blocking everything
    // TODO: resolve this problem
    sdk.processResetInd();

    JSONValue ind = sdk.processInd();
    if (ind.type() != JSONType.null_) {
      dsm.broadcast(ind);
    }
    dsm.processMessages();

    // TODO: calculate approximate sleep time depending on baudrate
    Thread.sleep(2.msecs);
  }
}
