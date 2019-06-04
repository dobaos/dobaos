module object_server;

import std.conv;
import std.stdio;


ubyte ObjServerMainService = 0xF0;
enum ObjServerServices {
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

enum ObjServerMessageDirection {
  request,
  response,
  indication
}

enum ObjServerDatapointValueFilter {
  all = 0x00,
  valid = 0x01,
  updated = 0x02
}

struct ObjServerDatapointValue  {
    int id;
    int state;
    int length;
    ubyte[] value;
}

struct ObjServerServerItem  {
    int id;
    int length;
    ubyte[] value;
}

// TODO:
// DPT as a different class for higher level - converting
// here is enough just enum
enum ObjServerDatapointType {
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

enum ObjServerDatapointPriority {
  system = 0b00,
  high = 0b01,
  alarm = 0b10,
  low = 0b11
};

struct ObjServerConfigFlags {
  ObjServerDatapointPriority priority;
  bool communication;
  bool read;
  bool write;
  bool read_on_init;
  bool transmit;
  bool update;
};

struct ObjServerDatapointDescription {
  int id;
  ObjServerDatapointType type;
  ObjServerConfigFlags flags;
}

struct ObjectServerMessage {
  ObjServerServices service;
  ObjServerMessageDirection direction;
  union {
    // TODO: union of possible service returned structs
    // DatapointDescriptions/DatapointValues/ServerItems/ParameterBytes
    ObjServerDatapointDescription[] datapoint_descriptions;
    ObjServerDatapointValue[] datapoint_values;
    ObjServerServerItem[] server_items;
  };
}

class ObjectServerProtocol {
  private static ObjServerServerItem[] _processServerItems(ubyte[] data) {
    // max size of baos message is 250 by default(ServerItems.MaxBufferSize)
    // 250 - 6[header] - ((2[id] + 1[state] + 1[length byte])[datapoint header] + <length>)*x > 0
    // (4 + length)*x < 244
    // min length of datapoint is 1byte,
    // so
    // 4*x < 244
    // x < 61; so, 64 is more than enough for default value.
    ObjServerServerItem[] result;
    result.length = 64;
    
    bool processed = false;
    // count of parsed values
    int count = 0;
    // current position in message
    int i = 0;
    while(i < data.length) {
      // TODO: readUInt16BE
      int id = data[i]*256 + data[i + 1];
      int value_length = data[i + 2];
    
      // TODO: think about safety
      i += 3;
      ubyte[] _value = data[i..i + value_length];
      writeln("server item value: ", _value);
      i += value_length;

      ObjServerServerItem _result;
      _result.id = id;
      _result.length = value_length;
      _result.value = _value;

      // push to result array
      result[count] = _result;
      count += 1;
    }

    // now, return array with only parsed datapoint values
    result.length = count;
    writeln(result);
    return result;
  }

  private static ObjServerDatapointDescription[] _processCommonDatapointDescriptions(ubyte[] data) {
    writeln("_processCommonDatapointDescriptions: ", data);
    ObjServerDatapointDescription[] result;
    result.length = 64;
    
    bool processed = false;
    // count of parsed values
    int count = 0;
    // current position in message
    int i = 0;
    while(i < data.length) {
      // TODO: readUInt16BE
      int id = data[i]*256 + data[i + 1];
      int value_type = data[i + 2];
      int config_flags = data[i + 3];
      int dpt = data[i + 4];
    
      i += 5;

      ObjServerDatapointDescription _result;
      _result.id = id;
      _result.flags.priority = to!ObjServerDatapointPriority(config_flags & 0x03);
      _result.flags.communication = cast(bool)(config_flags & 0x04);
      _result.flags.read = cast(bool)(config_flags & 0x08);
      _result.flags.write = cast(bool)(config_flags & 0x10);
      _result.flags.write = cast(bool)(config_flags & 0x20);
      _result.flags.read_on_init = cast(bool)(config_flags & 0x40);
      _result.flags.update = cast(bool)(config_flags & 0x80);
      _result.type = to!ObjServerDatapointType(dpt);

      // push to result array
      result[count] = _result;
      count += 1;
    }

    // now, return array with only parsed datapoint values
    result.length = count;
    writeln(result);
    return result;
  }

  private static ObjServerDatapointValue[] _processCommonDatapointValues(ubyte[] data) {
    // max size of baos message is 250 by default(ServerItems.MaxBufferSize)
    // 250 - 6[header] - ((2[id] + 1[state] + 1[length byte])[datapoint header] + <length>)*x > 0
    // (4 + length)*x < 244
    // min length of datapoint is 1byte,
    // so
    // 4*x < 244
    // x < 61; so, 64 is more than enough for default value.
    ObjServerDatapointValue[] result;
    result.length = 64;
    
    bool processed = false;
    // count of parsed values
    int count = 0;
    // current position in message
    int i = 0;
    while(i < data.length) {
      // TODO: readUInt16BE
      int id = data[i]*256 + data[i + 1];
      int value_state = data[i + 2];
      int value_length = data[i + 3];
    
      // TODO: think about safety
      i += 4;
      ubyte[] _value = data[i..i + value_length];
      writeln("_value: ", _value);
      i += value_length;

      ObjServerDatapointValue _result;
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
    writeln(result);
    return result;
  }

  private static ObjServerServerItem[] _processServerItemRes(ubyte[] data) {
    // start dp[2], number of dp[2], (err[1]/value[~varies])
    int start = data[0]*256 + data[1];
    int number = data[2]*256 + data[3];
    if (number == 0) {
      // TODO: error handling
      writeln("number field has null value. error code: ", data[4]);
      throw new Exception("Number of items is 0. Error code: ..not yet");
    }

    return _processServerItems(data[4..$]);
  }

  private static ObjServerDatapointValue[] _processDatapointValueRes(ubyte[] data) {
    // start dp[2], number of dp[2], (err[1]/value[~varies])
    int start = data[0]*256 + data[1];
    int number = data[2]*256 + data[3];
    if (number == 0) {
      // TODO: error handling
      writeln("datapoint number field has null value. error code: ", data[4]);
      throw new Exception("Datapoint number is 0. Error code: ..not yet");
    }

    return _processCommonDatapointValues(data[4..$]);
  }

  private static ObjServerDatapointDescription[] _processDatapointDescriptionRes(ubyte[] data) {
    // start dp[2], number of dp[2], (err[1]/value[~varies])
    int start = data[0]*256 + data[1];
    int number = data[2]*256 + data[3];
    if (number == 0) {
      // TODO: error handling
      writeln("datapoint number field has null value. error code: ", data[4]);
      throw new Exception("Datapoint number is 0. Error code: ..not yet");
    }

    return _processCommonDatapointDescriptions(data[4..$]);
  }

  static ObjectServerMessage processIncomingMessage(ubyte[] data) {
    ObjectServerMessage result;
    int mainService = data[0];
    int subService = data[1];
    if (mainService == ObjServerMainService) {
      switch(subService) {
        case ObjServerServices.GetServerItemRes:
          writeln("GetServerItemRes");
          result.service= ObjServerServices.GetServerItemRes;
          result.server_items = _processServerItemRes(data[2..$]);
          break;
        case ObjServerServices.ServerItemInd:
          writeln("ServerItemInd");
          result.service= ObjServerServices.ServerItemInd;
          result.server_items = _processServerItemRes(data[2..$]);
          break;
        case ObjServerServices.GetDatapointDescriptionRes:
          writeln("GetDatapointDescriptionRes");
          result.service= ObjServerServices.GetDatapointDescriptionRes;
          result.datapoint_descriptions = _processDatapointDescriptionRes(data[2..$]);
          break;
        case ObjServerServices.GetDatapointValueRes:
          writeln("GetDatapointValueRes");
          result.service= ObjServerServices.GetDatapointValueRes;
          result.datapoint_values = _processDatapointValueRes(data[2..$]);
          break;
        case ObjServerServices.DatapointValueInd:
          writeln("DatapointValueInd");
          result.service= ObjServerServices.DatapointValueInd;
          result.datapoint_values = _processDatapointValueRes(data[2..$]);
          break;
        default:
          break;
      }
    }
    return result;
  }

  static ubyte[] GetDatapointDescriptionReq(int start, int number = 1) {
    ubyte[] result;
    // max len
    result.length = 6;
    ubyte main = ObjServerMainService;
    ubyte service = ObjServerServices.GetDatapointDescriptionReq;
    result[0] = main;
    result[1] = service;
    // start BE
    result[2] = cast(ubyte) (start/256);
    result[3] = cast(ubyte) start%256;
    // number BE
    result[4] = cast(ubyte) (number/256);
    result[5] = cast(ubyte) number%256;

    return result;
  }

  static ubyte[] GetDatapointValueReq(int start, int number = 1, ObjServerDatapointValueFilter filter = ObjServerDatapointValueFilter.all) {
    ubyte[] result;
    // max len
    result.length = 7;
    ubyte main = ObjServerMainService;
    ubyte service = ObjServerServices.GetDatapointValueReq;
    result[0] = main;
    result[1] = service;
    // start BE
    result[2] = cast(ubyte) (start/256);
    result[3] = cast(ubyte) start%256;
    // number BE
    result[4] = cast(ubyte) (number/256);
    result[5] = cast(ubyte) number%256;
    result[6] = cast(ubyte) filter;

    return result;
  }

  static ubyte[] GetServerItemReq(int start, int number = 1) {
    ubyte[] result;
    // max len
    result.length = 6;
    ubyte main = ObjServerMainService;
    ubyte service = ObjServerServices.GetServerItemReq;
    result[0] = main;
    result[1] = service;
    // start BE
    result[2] = cast(ubyte) (start/256);
    result[3] = cast(ubyte) start%256;
    // number BE
    result[4] = cast(ubyte) (number/256);
    result[5] = cast(ubyte) number%256;

    return result;
  }

}
