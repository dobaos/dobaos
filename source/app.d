module main;
import core.thread;
import std.stdio;
import std.bitmanip;
import std.range.primitives : empty;
import std.json;
import std.functional;

import std.datetime.stopwatch;

import clid;
import clid.validate;

import logo;
import baos;
import datapoints;
import object_server;
import dsm;
import sdk;
import errors;

// struct for commandline params
private struct Config
{
  @Parameter("device", 'd')
  @Description("UART device. Default: /dev/ttyS1")
  string device;

  @Parameter("params", 'p')
  @Description("Serialport parameters. Default: 19200:8E1")
  string params;

  @Parameter("req_channel", 'r')
  @Description("Pub/Sub channel for datapoint requests. Default: dobaos_req")
  string req_channel;

  @Parameter("service_channel", 's')
  @Description("Pub/sub channel for service requests. Default: dobaos_service")
  string service_channel;

  @Parameter("bcast_channel", 'b')
  @Description("Pub/sub channel for broadcasted values. Default: dobaos_cast")
  string bcast_channel;
}

void main()
{
  print_logo();

  // parse args
  auto config = parseArguments!Config();
  string device = config.device.length > 1 ? config.device : "/dev/ttyS1";
  string params = config.params.length > 1 ? config.params : "19200:8E1";
  string req_channel = config.req_channel.length > 1 ? config.req_channel : "dobaos_req";
  string service_channel = config.service_channel.length > 1 ? config.service_channel : "dobaos_service";
  string bcast_channel = config.bcast_channel.length > 1 ? config.bcast_channel : "dobaos_cast";
  string service_cast = "dobaos_cast";

  StopWatch sw;
  sw.start();

  auto sdk = new DatapointSdk(device, params);

  auto dsm = new Dsm("127.0.0.1", cast(ushort)6379, req_channel, bcast_channel);
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
      case "get server items":
        try {
          res["method"] = "success";
          res["payload"] = sdk.getServerItems();
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
  auto ssm = new Dsm("127.0.0.1", cast(ushort)6379, service_channel, service_cast);
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
          res["payload"] = "11_dec_2019";
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

    // calculate approximate sleep time depending on baudrate.
    // assuming default baud 19200 bits per second is used.
    // also that on each iteration app needs to get at least 4 bytes.
    // bytes_per_second = 19200/8 = 2400; bytes_per_ms = 2,4;
    // 4bytes can be received in 4/2.4 = 1.6 ~= 2 ms;
    // same applies to baos.d
    Thread.sleep(2.msecs);
  }
}
