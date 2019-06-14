/***

  Sdk to work with datapoints

 ***/

module sdk;

import std.stdio;
import std.bitmanip;
import std.range.primitives : empty;

import object_server;
import datapoints;
import baos;

// TODO: structs for converted datapoint value

const ushort MAX_DATAPOINT_NUM = 1000;

struct SdkDatapointValue {
  ushort id;
  string raw;
  DatapointType dpt;
  union {
    bool boolean;
    uint u_int;
    float floating;
  }
}

class DatapointSdk {
  private ushort SI_currentBufferSize;
  private OS_DatapointDescription[ushort] descriptions;
  private Baos baos;
  // TODO: methods to work with baos
  public ubyte[] getValue(ushort id) {
    ubyte[] res;
    auto val = baos.GetDatapointValueReq(id);
    writeln(val);
    if (val.success) {
      writeln("values: good");
      res = val.datapoint_values[0].value;
      /**foreach(OS_DatapointValue dv; val.datapoint_values) {
        writeln(dv);
        }**/
    } else {
      writeln("values: bad:: ", val.error.message);
    }

    return res;
  }

  public void processInd() {
    OS_Message ind = baos.processInd();
    if (ind.service == OS_Services.DatapointValueInd) {
      SdkDatapointValue[] result;
      result.length = ind.datapoint_values.length;
      // example
      auto count = 0;
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
        SdkDatapointValue _res;
        _res.id = dv.id;
        switch(descriptions[dv.id].type) {
          case OS_DatapointType.dpt1:
            _res.dpt = DatapointType.dpt1;
            _res.boolean = DPT1.toBoolean(dv.value);
            writeln("boo: ", _res.id, "=", _res.boolean);
            break;
          case OS_DatapointType.dpt9:
            _res.dpt = DatapointType.dpt9;
            _res.floating = DPT9.toFloat(dv.value);
            writeln("float: ", _res.id, "=", _res.floating);
            break;
          default:
            writeln("unknown yet dtp");
            break;
        }
        result[count] = _res;
        count++;
        // TODO: create ind object {id, value, raw} and return
      }
      result.length = count;
    }
  }
  this(string device = "/dev/ttyS1", string params = "19200:8E1") {

    baos = new Baos(device, params);

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
  }
}
