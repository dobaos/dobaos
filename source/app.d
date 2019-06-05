module main;
import core.thread;
import std.stdio;
import std.bitmanip;
import std.range.primitives : empty;


import baos;
import object_server;

ushort SI_currentBufferSize;

void main()
{
  auto baos = new Baos();

  auto serverItemMessage = baos.GetServerItemReq(1, 17);
  auto datapointDescriptionMessage = baos.GetDatapointDescriptionReq(1, 11);
  auto datapointValueMessage =  baos.GetDatapointValueReq(1, 11);

  // maximum buffer size
  SI_currentBufferSize = 0;
  if (serverItemMessage.service == ObjServerServices.GetServerItemRes) {
    writeln("server items: good");
    foreach(ObjServerServerItem si; serverItemMessage.server_items) {
      writeln(si);
      // maximum buffer size
      if (si.id == 14) {
        SI_currentBufferSize = si.value.read!ushort();
      }
    }
  }
  if (datapointDescriptionMessage.service == ObjServerServices.GetDatapointDescriptionRes) {
    writeln("descriptions: good");
    foreach(ObjServerDatapointDescription dd; datapointDescriptionMessage.datapoint_descriptions) {
      writeln(dd.id, "[", dd.type, "] ");
    }
  }
  if (datapointValueMessage.service == ObjServerServices.GetDatapointValueRes) {
    writeln("values: good");
    foreach(ObjServerDatapointValue dv; datapointValueMessage.datapoint_values) {
      writeln(dv);
    }
  }
  writeln("Current buffer size: ", SI_currentBufferSize);
  while(true) {
    ObjectServerMessage ind = baos.processInd();
    if (ind.service != ObjServerServices.unknown) {
      writeln("here comes message[ind]: ");
      // example
      foreach(ObjServerDatapointValue dv; ind.datapoint_values) {
        /****
        if (dv.id == 10) {
          ObjServerDatapointValue[] newVal;
          newVal.length = 1;
          newVal[0].id = 11;
          newVal[0].value.length = 1;
          newVal[0].value[0] = dv.value[0] == 0? 32: 8;
          writeln("new val: ", newVal[0].value[0]);
          Thread.sleep(1.msecs);
          baos.SetDatapointValueReq(cast(ushort) 10, newVal);
        } ****/
          writeln("#d ", dv.id, "=", dv.value);
      }
    }
    Thread.sleep(1.msecs);
    // process redis messages here?
    // TODO: simple messages as a model; test
  }
}
