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
import errors;

void main()
{
  StopWatch sw;
  sw.start();

  auto sdk = new DatapointSdk("/dev/ttyS1", "19200:8E1");

  auto dsm = new Dsm("127.0.0.1", cast(ushort)6379, "dobaos_req", "dobaos_cast");
  void handleRequest(JSONValue jreq, void delegate(JSONValue) sendResponse) {
    JSONValue res;

    auto jmethod = ("method" in jreq);
    if (jmethod is null) {
      res["success"] = false;
      res["payload"] = Errors.no_method_field.message;
      sendResponse(res);
      return;
    }
    auto jpayload = ("payload" in jreq);
    if (jpayload is null) {
      res["success"] = false;
      res["payload"] = Errors.no_payload_field.message;
      sendResponse(res);
      return;
    }

    string method = ("method" in jreq).str;
    switch(method) {
      case "get description":
        try {
          res["method"] = "success";
          res["payload"] = sdk.getDescription(jreq["payload"]);
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case "get value":
        try {
          res["method"] = "success";
          res["payload"] = sdk.getValue(jreq["payload"]);
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
          res["payload"] = sdk.setValue(jreq["payload"]);
          sendResponse(res);
          // broadcast values
          auto jcast = parseJSON("{}");
          jcast["method"] = "datapoint value";
          if (res["payload"].type() == JSONType.array) {
            jcast["payload"] = parseJSON("[]");
            jcast["payload"].array.length = res["payload"].array.length;
            auto count = 0;
            foreach(value; res["payload"].array) {
              if (value["success"].type() == JSONType.true_) {
                auto _jvalue = parseJSON("{}");
                _jvalue["id"] = value["id"];
                _jvalue["raw"] = value["raw"];
                _jvalue["value"] = value["value"];
                jcast["payload"].array[count] = _jvalue;
                count += 1;
              }
            }
            if (count > 0) {
              dsm.broadcast(jcast);
            }
          } else if (res["payload"].type() == JSONType.object) {
            auto value = res["payload"];
            if (value["success"].type() == JSONType.true_) {
              auto _jvalue = parseJSON("{}");
              _jvalue["id"] = value["id"];
              _jvalue["raw"] = value["raw"];
              _jvalue["value"] = value["value"];
              jcast["payload"] = _jvalue;
              dsm.broadcast(jcast);
            }
          }
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case "read value":
        try {
          res["method"] = "success";
          res["payload"] = sdk.readValue(jreq["payload"]);
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case "get programming mode":
        try {
          res["method"] = "success";
          res["payload"] = sdk.getProgrammingMode();
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case "set programming mode":
        try {
          res["method"] = "success";
          res["payload"] = sdk.setProgrammingMode(jreq["payload"]);
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      default:
        res["method"] = "error";
        res["payload"] = Errors.unknown_method.message;
        sendResponse(res);
        break;
    }
  }
  dsm.subscribe(toDelegate(&handleRequest));

  // service messages
  auto ssm = new Dsm("127.0.0.1", cast(ushort)6379, "dobaos_service", "dobaos_scast");
  void handleService(JSONValue jreq, void delegate(JSONValue) sendResponse) {
    JSONValue res;

    auto jmethod = ("method" in jreq);
    if (jmethod is null) {
      res["success"] = false;
      res["payload"] = Errors.no_method_field.message;
      sendResponse(res);
      return;
    }
    auto jpayload = ("payload" in jreq);
    if (jpayload is null) {
      res["success"] = false;
      res["payload"] = Errors.no_payload_field.message;
      sendResponse(res);
      return;
    }

    string method = ("method" in jreq).str;
    switch(method) {
      case "reset":
        try {
          sdk.interrupt();
          res["method"] = "success";
          res["payload"] = null;
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      case "version":
        try {
          res["method"] = "success";
          res["payload"] = "0.4.2";
          sendResponse(res);
        } catch(Exception e) {
          res["method"] = "error";
          res["payload"] = e.message;
          sendResponse(res);
        }
        break;
      default:
        res["method"] = "error";
        res["payload"] = Errors.unknown_method.message;
        sendResponse(res);
        break;
    }
  }
  ssm.subscribe(toDelegate(&handleService));

  writeln("IPC ready");

  sdk.setInterruptsDelegate(toDelegate(&ssm.processMessages));
  sdk.resetBaos();
  sdk.init();

  writeln("SDK ready");
  writefln("Started in %dms", sw.peek.total!"msecs");
  sw.stop();

  // process incoming values
  while(true) {
    sdk.processResetInd();
    sdk.processInterrupts();

    JSONValue ind = sdk.processInd();
    if (ind.type() != JSONType.null_) {
      dsm.broadcast(ind);
    }
    dsm.processMessages();
    ssm.processMessages();

    // TODO: calculate approximate sleep time depending on baudrate
    Thread.sleep(2.msecs);
  }
}
