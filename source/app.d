module main;
import core.thread;
import std.stdio;
import std.bitmanip;
import std.range.primitives : empty;
import std.json;
import std.functional;

import baos;
import datapoints;
import object_server;
import dsm;

const ushort MAX_DATAPOINT_NUM = 1000;
ushort SI_currentBufferSize;

void main()
{
  auto baos = new Baos();

  auto serverItemMessage = baos.GetServerItemReq(1, 17);

  // maximum buffer size
  SI_currentBufferSize = 0;
  writeln("Loading server items");
  if (serverItemMessage.service == OS_Services.GetServerItemRes) {
    foreach(OS_ServerItem si; serverItemMessage.server_items) {
      //writeln(si);
      // maximum buffer size
      if (si.id == 14) {
        SI_currentBufferSize = si.value.read!ushort();
        writefln("Current buffer size: %d bytes", SI_currentBufferSize);
      }
    }
  }
  writeln("Server items loaded");
  writeln("Loading datapoints");
  /***
    if (datapointValueMessage.service == OS_Services.GetDatapointValueRes) {
    writeln("values: good");
    foreach(OS_DatapointValue dv; datapointValueMessage.datapoint_values) {
    writeln(dv);
    }
    }
   ***/
  // TODO: calculate max num of dps

  OS_DatapointDescription[ushort] descriptions;
  // count for loaded datapoints
  auto count = 0;
  // GetDatapointDescriptionRes has a header(6b) and 5bytes each dp
  ushort number = cast(ushort)(SI_currentBufferSize - 6)/5;
  ushort start = 1;
  while(start < MAX_DATAPOINT_NUM ) {
    if (MAX_DATAPOINT_NUM - start <= number) {
      number = cast(ushort) (MAX_DATAPOINT_NUM - start + 1);
    }
    //writeln("start-number: ", start, "-", number);
    auto descr = baos.GetDatapointDescriptionReq(start, number);
    if (descr.success) {
      foreach(OS_DatapointDescription dd; descr.datapoint_descriptions) {
        //writeln("here comes description #", dd.id, "[", dd.type, "] ");
        // TODO: save in hash?
        descriptions[dd.id] = dd;
        count++;
      }
    } else {
      //writeln("here comes error:", start, "-", number,": ", descr.error.message);
    }
    start += number;
  }
  writefln("Datapoints[%d] loaded.", count);



  auto dsm = new Dsm("127.0.0.1", cast(ushort)6379, "hello", "friend");
  void handleRequest(JSONValue jreq, void delegate(JSONValue) sendResponse) {
    writeln("now handle request in main app");
    // example
    sendResponse(jreq);
  }
  dsm.subscribe(toDelegate(&handleRequest));
  writeln("IPC ready");

  // process incoming values
  while(true) {
    OS_Message ind = baos.processInd();
    if (ind.service != OS_Services.unknown) {
      // example
      foreach(OS_DatapointValue dv; ind.datapoint_values) {
        /****
          if (dv.id == 10) {
          OS_DatapointValue[] newVal;
          newVal.length = 1;
          newVal[0].id = 11;
          newVal[0].value.length = 1;
          newVal[0].value[0] = dv.value[0] == 0? 32: 8;
          writeln("new val: ", newVal[0].value[0]);
          Thread.sleep(1.msecs);
          baos.SetDatapointValueReq(cast(ushort) 10, newVal);
          } ****/

        // convert to base type
        switch(descriptions[dv.id].type) {
          case OS_DatapointType.dpt9:
            writeln("#d ", dv.id, "=", DPT9.toFloat(dv.value));
            break;
          default:
            writeln("unknown yet dtp");
            break;
        }
      }
    }
    // TODO: calculate approximate sleep time depending on baudrate
    Thread.sleep(2.msecs);
    // process redis messages here?
    // TODO: simple messages as a model; test
    dsm.processMessages();
  }
}

