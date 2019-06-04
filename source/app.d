module main;
import core.thread;
import std.stdio;


import baos;
import object_server;

void main()
{
  auto baos = new Baos();

  auto serverItemMessage = baos.GetServerItemReq(1, 17);
  auto datapointDescriptionMessage = baos.GetDatapointDescriptionReq(1, 11);
  auto datapointValueMessage =  baos.GetDatapointValueReq(1, 11);
  if (serverItemMessage.service == ObjServerServices.GetServerItemRes) {
    writeln("server items: good");
    foreach(ObjServerServerItem si; serverItemMessage.server_items) {
      writeln(si);
    }
  }
  if (datapointDescriptionMessage.service == ObjServerServices.GetDatapointDescriptionRes) {
    writeln("descriptions: good");
    foreach(ObjServerDatapointDescription dd; datapointDescriptionMessage.datapoint_descriptions) {
      writeln(dd);
    }
  }
  if (datapointValueMessage.service == ObjServerServices.GetDatapointValueRes) {
    writeln("values: good");
    foreach(ObjServerDatapointValue dv; datapointValueMessage.datapoint_values) {
      writeln(dv);
    }
  }
  while(true) {
    ObjectServerMessage ind = baos.processInd();
    if (ind.service != ObjServerServices.unknown) {
      writeln("here comes message[ind]: ", ind);
      // example
      foreach(ObjServerDatapointValue dv; ind.datapoint_values) {
        if (dv.id == 10) {
          ObjServerDatapointValue[] newVal;
          newVal.length = 1;
          newVal[0].id = 11;
          newVal[0].value.length = 1;
          writeln("old val: ", dv.value[0]);
          newVal[0].value[0] = dv.value[0] == 0? 32: 8;
          writeln("new val: ", newVal[0].value[0]);
          Thread.sleep(1.msecs);
          baos.SetDatapointValueReq(cast(ushort) 10, newVal);
        }
      }
    }
    Thread.sleep(1.msecs);
    // process redis messages here?
    // TODO: simple messages as a model; test
  }
}
