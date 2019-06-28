/*** 
  To compose/process OS_ requests/responses
  Following methods will be supported by this class:
  1. GetServerItemReq/Res; ServerItemInd
  2. SetServerItemReq/Res
  3. GetDatapointDescriptionReq/Res
  4. GetDatapointValueReq/Res; DatapointValueInd
  5. SetDatapointValueReq/Res
  6. GetParameterByteReq/Res
 ***/
module object_server;

import std.conv;
import std.stdio;
import std.string;
import std.bitmanip;
import std.range.primitives : empty;

ubyte OS_MainService = 0xF0;
enum OS_Services {
  unknown,
  GetServerItemReq = 0x01,
  GetServerItemRes = 0x81,
  SetServerItemReq = 0x02,
  SetServerItemRes = 0x82,
  GetDatapointDescriptionReq = 0x03,
  GetDatapointDescriptionRes = 0x83,
  GetDatapointValueReq = 0x05,
  GetDatapointValueRes = 0x85,
  SetDatapointValueReq = 0x06,
  SetDatapointValueRes =  0x86,
  GetParameterByteReq = 0x07,
  GetParameterByteRes = 0x87,
  ServerItemInd = 0xC2,
  DatapointValueInd = 0xC1,
}

// serves to indicate direction of message
enum OS_MessageDirection {
  request,
  response,
  indication
}

enum OS_DatapointValueFilter {
  all = 0x00,
  valid = 0x01,
  updated = 0x02
}
enum OS_DatapointValueCommand {
  unknown = 0x00,
  set = 0x01,
  send = 0x02,
  set_and_send = 0x03,
  read = 0x04,
  clear_transmission_state = 0x05
}

struct OS_DatapointValue  {
  ushort id;
  ubyte state;
  ubyte length;
  OS_DatapointValueCommand command;
  ubyte[] value;
}

struct OS_ServerItem  {
  ushort id;
  ubyte length;
  ubyte[] value;
}

enum OS_DatapointType {
  unknown,
  dpt1 = 1,
  dpt2 = 2,
  dpt3 = 3,
  dpt4 = 4,
  dpt5 = 5,
  dpt6 = 6,
  dpt7 = 7,
  dpt8 = 8,
  dpt9 = 9,
  dpt10 = 10,
  dpt11 = 11,
  dpt12 = 12,
  dpt13 = 13,
  dpt14 = 14,
  dpt15 = 15,
  dpt16 = 16,
  dpt17 = 17,
  dpt18 = 18
}

enum OS_DatapointPriority {
  system = 0b00,
  high = 0b01,
  alarm = 0b10,
  low = 0b11
};

struct OS_ConfigFlags {
  OS_DatapointPriority priority;
  bool communication;
  bool read;
  bool write;
  bool read_on_init;
  bool transmit;
  bool update;
};

struct OS_DatapointDescription {
  ushort id;
  ubyte length;
  OS_DatapointType type;
  OS_ConfigFlags flags;
}

struct OS_Message {
  OS_Services service;
  OS_MessageDirection direction;
  bool success;
  union {
    // TODO: union of possible service returned structs
    // DatapointDescriptions/DatapointValues/ServerItems/ParameterBytes
    OS_DatapointDescription[] datapoint_descriptions;
    OS_DatapointValue[] datapoint_values;
    OS_ServerItem[] server_items;
    Exception error;
  };
}

class OS_Protocol {
  private static OS_ServerItem[] _processServerItems(ubyte[] data) {
    // max size of baos message is 250 by default(ServerItems.MaxBufferSize)
    // 250 - 6[header] - ((2[id] + 1[state] + 1[length byte])[datapoint header] + <length>)*x > 0
    // (4 + length)*x < 244
    // min length of datapoint is 1byte,
    // so
    // 4*x < 244
    // x < 61; so, 64 is more than enough for default value.
    OS_ServerItem[] result;
    result.length = 64;

    bool processed = false;
    // count of parsed values
    int count = 0;
    // current position in message
    int i = 0;
    while(data.length > 0) {
      ushort id = data.read!ushort();
      ubyte value_length = data.read!ubyte();
      ubyte[] _value = data[0..value_length];

      // delete bytes from array
      if (data.length > value_length) {
        data = data[value_length..$];
      } else {
        data = [];
      }

      OS_ServerItem _result;
      _result.id = id;
      _result.length = value_length;
      _result.value = _value;

      // push to result array
      result[count] = _result;
      count += 1;
    }

    // now, return array with only parsed datapoint values
    result.length = count;
    return result;
  }

  private static OS_DatapointDescription[] _processCommonDatapointDescriptions(ubyte[] data) {
    OS_DatapointDescription[] result;
    result.length = 64;

    bool processed = false;
    // count of parsed values
    int count = 0;
    // current position in message
    while(data.length > 0) {
      ushort id = data.read!ushort();
      ubyte value_type = data.read!ubyte();
      ubyte config_flags = data.read!ubyte();
      ubyte dpt = data.read!ubyte();

      OS_DatapointDescription _result;
      _result.id = id;
      _result.flags.priority = to!OS_DatapointPriority(config_flags & 0x03);
      _result.flags.communication = (config_flags & 0x04) != 0;
      _result.flags.read = (config_flags & 0x08) != 0;
      _result.flags.write = (config_flags & 0x10) != 0;
      _result.flags.read_on_init = (config_flags & 0x20) != 0;
      _result.flags.transmit = (config_flags & 0x40) != 0;
      _result.flags.update = (config_flags & 0x80) != 0;
      _result.type = to!OS_DatapointType(dpt);

      // TODO: value_type =>> length table
      _result.length = 1;
      switch(value_type) {
        case 0, 1, 2, 3, 4, 5, 6, 7:
          _result.length = 1;
          break;
        case 8:
          _result.length = 2;
          break;
        case 9:
          _result.length = 3;
          break;
        case 10:
          _result.length = 4;
          break;
        case 11:
          _result.length = 6;
          break;
        case 12:
          _result.length = 8;
          break;
        case 13:
          _result.length = 10;
          break;
        case 14:
          _result.length = 16;
          break;
        default:
          break;
      }

      // push to result array
      result[count] = _result;
      count += 1;
    }

    // now, return array with only parsed datapoint values
    result.length = count;
    return result;
  }

  private static OS_DatapointValue[] _processCommonDatapointValues(ubyte[] data) {
    // max size of baos message is 250 by default(ServerItems.MaxBufferSize)
    // 250 - 6[header] - ((2[id] + 1[state] + 1[length byte])[datapoint header] + <length>)*x > 0
    // (4 + length)*x < 244
    // min length of datapoint is 1byte,
    // so
    // 4*x < 244
    // x < 61; so, 64 is more than enough for default value.
    OS_DatapointValue[] result;
    result.length = 64;

    bool processed = false;
    // count of parsed values
    int count = 0;
    // current position in message
    int i = 0;
    while(data.length > 0) {
      ushort id = data.read!ushort();
      ubyte value_state = data.read!ubyte();
      ubyte value_length = data.read!ubyte();

      ubyte[] _value = data[0..value_length];

      if (data.length > value_length) {
        data = data[value_length..$];
      } else {
        data = [];
      }

      OS_DatapointValue _result;
      _result.id = id;
      _result.state = value_state;
      _result.length = value_length;
      _result.value = _value;

      // push to result array
      result[count] = _result;
      count += 1;
    }

    // now, return array with only parsed datapoint values
    result.length = count;
    return result;
  }

  private static OS_ServerItem[] _processServerItemRes(ubyte[] data) {
    // start dp[2], number of dp[2], (err[1]/value[~varies])
    ushort start = data.read!ushort();
    ushort number = data.read!ushort();
    if (number == 0) {
      // TODO: error handling
      throw new Exception(format("%d", data[0]));
    }

    return _processServerItems(data);
  }

  private static OS_DatapointValue[] _processDatapointValueRes(ubyte[] data) {
    // start dp[2], number of dp[2], (err[1]/value[~varies])
    ushort start = data.read!ushort();
    ushort number = data.read!ushort();
    if (number == 0) {
      // TODO: error handling
      throw new Exception(format("%d", data[0]));
    }

    return _processCommonDatapointValues(data);
  }

  private static OS_DatapointDescription[] _processDatapointDescriptionRes(ubyte[] data) {
    // start dp[2], number of dp[2], (err[1]/value[~varies])
    int start = data.read!ushort();
    int number = data.read!ushort();
    if (number == 0) {
      throw new Exception(format("%d", data[0]));
    }

    return _processCommonDatapointDescriptions(data);
  }

  static OS_Message processIncomingMessage(ubyte[] data) {
    OS_Message result;
    ubyte mainService = data.read!ubyte();
    ubyte subService = data.read!ubyte();
    try {
      if (mainService == OS_MainService) {
        switch(subService) {
          case OS_Services.GetServerItemRes:
            //writeln("GetServerItemRes");
            result.direction = OS_MessageDirection.response;
            result.service= OS_Services.GetServerItemRes;
            result.success = true;
            result.server_items = _processServerItemRes(data);
            break;
          case OS_Services.ServerItemInd:
            //writeln("ServerItemInd");
            result.direction = OS_MessageDirection.indication;
            result.service= OS_Services.ServerItemInd;
            result.server_items = _processServerItemRes(data);
            break;
          case OS_Services.GetDatapointDescriptionRes:
            //writeln("GetDatapointDescriptionRes");
            result.direction = OS_MessageDirection.response;
            result.service= OS_Services.GetDatapointDescriptionRes;
            result.success = true;
            result.datapoint_descriptions = _processDatapointDescriptionRes(data);
            break;
          case OS_Services.GetDatapointValueRes:
            //writeln("GetDatapointValueRes");
            result.direction = OS_MessageDirection.response;
            result.service= OS_Services.GetDatapointValueRes;
            result.success = true;
            result.datapoint_values = _processDatapointValueRes(data);
            break;
          case OS_Services.SetDatapointValueRes:
            //writeln("SetDatapointValueRes:", data);
            result.direction = OS_MessageDirection.response;
            result.service= OS_Services.SetDatapointValueRes;
            result.success = true;
            // TODO: parse response
            break;
          case OS_Services.SetServerItemRes:
            writeln("SetServerItemRes:", data);
            result.direction = OS_MessageDirection.response;
            result.service= OS_Services.SetServerItemRes;
            result.success = true;
            // TODO: parse response
            break;
          case OS_Services.DatapointValueInd:
            //writeln("DatapointValueInd");
            result.service= OS_Services.DatapointValueInd;
            result.direction = OS_MessageDirection.indication;
            result.datapoint_values = _processDatapointValueRes(data);
            break;
          default:
            break;
        }
      }
    } catch(Exception e) {
      result.service = OS_Services.unknown;
      result.success = false;
      result.error = e;
    }

    return result;
  }

  static ubyte[] GetDatapointDescriptionReq(ushort start, ushort number = 1) {
    ubyte[] result;
    // max len
    result.length = 6;
    // service header
    result.write!ubyte(OS_MainService, 0);
    result.write!ubyte(OS_Services.GetDatapointDescriptionReq, 1);
    // start BE
    result.write!ushort(start, 2);
    // number BE
    result.write!ushort(number, 4);

    return result;
  }

  static ubyte[] GetDatapointValueReq(ushort start, ushort number = 1, OS_DatapointValueFilter filter = OS_DatapointValueFilter.all) {
    ubyte[] result;
    // max len
    result.length = 7;
    // service header
    result.write!ubyte(OS_MainService, 0);
    result.write!ubyte(OS_Services.GetDatapointValueReq, 1);
    // start BE
    result.write!ushort(start, 2);
    // number BE
    result.write!ushort(number, 4);
    result.write!ubyte(cast(ubyte)filter, 6);

    return result;
  }

  static ubyte[] GetServerItemReq(ushort start, ushort number = 1) {
    ubyte[] result;
    // max len
    result.length = 6;
    // service header
    result.write!ubyte(OS_MainService, 0);
    result.write!ubyte(OS_Services.GetServerItemReq, 1);
    // start BE
    result.write!ushort(start, 2);
    // number BE
    result.write!ushort(number, 4);

    return result;
  }
  static ubyte[] SetDatapointValueReq(OS_DatapointValue[] values) {
    //writeln("object_server.SetDatapointValueReq: ", values);
    ubyte[] result;
    // max len
    ubyte header_length = 6;
    ubyte value_length = 0;
    // as max as possible. anyway, max datapoint id is 1000;
    ushort start = 65535;
    foreach(OS_DatapointValue value; values) {
      // id, cmd, len, value
      value_length += ushort.sizeof + ubyte.sizeof + ubyte.sizeof+ value.value.length;
      // get min from values
      if (value.id < start) {
        start = value.id;
      }
    }
    result.length = header_length + value_length;

    // service header
    result.write!ubyte(OS_MainService, 0);
    result.write!ubyte(OS_Services.SetDatapointValueReq, 1);
    // start BE
    result.write!ushort(start, 2);
    // number BE
    ushort number = cast(ushort) values.length;
    result.write!ushort(number, 4);

    // current position
    int c = header_length; 
    foreach(OS_DatapointValue value; values) {
      result.write!ushort(value.id, c);
      // command: set and send
      // TODO: command in params
      ubyte command = cast(ubyte) value.command;
      result.write!ubyte(command, c + 2);

      result.write!ubyte(cast(ubyte) value.value.length, c + 3);

      // end position of value chunk
      int end = c+4 + cast(int) value.value.length;
      result[c+4..end] = value.value[0..$];
      c = end;
    }

    return result;
  }
  static ubyte[] SetServerItemReq(OS_ServerItem[] items) {
    //writeln("object_server.SetServerItemReq: ", items);
    ubyte[] result;
    // max len
    ubyte header_length = 6;
    ubyte value_length = 0;
    // as max as possible
    ushort start = 65535;
    foreach(item; items) {
      // id, len, value
      value_length += ushort.sizeof + ubyte.sizeof+ item.value.length;
      // get min from values
      if (item.id < start) {
        start = item.id;
      }
    }
    result.length = header_length + value_length;

    // service header
    result.write!ubyte(OS_MainService, 0);
    result.write!ubyte(OS_Services.SetServerItemReq, 1);
    // start BE
    result.write!ushort(start, 2);
    // number BE
    ushort number = cast(ushort) items.length;
    result.write!ushort(number, 4);

    // current position
    int c = header_length; 
    foreach(item; items) {
      result.write!ushort(item.id, c);
      result.write!ubyte(cast(ubyte) item.value.length, c + 2);

      // end position of value chunk
      int end = c+3 + cast(int) item.value.length;
      result[c+3..end] = item.value[0..$];
      c = end;
    }

    writeln(result);
    return result;
  }
}
