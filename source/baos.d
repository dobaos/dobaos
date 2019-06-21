module baos;
import std.stdio;
import core.thread;

import serialport;

// mi libs
import ft12;
import object_server;
import datapoints;

class Baos {
  private SerialPortNonBlk com;

  // helper serves to parse/compose ft12 frames
  private FT12Helper ft12;
  private FT12FrameParity currentParity = FT12FrameParity.unknown;

  // var to store result for last response
  private OS_Message _res;
  // and indications. 
  private OS_Message[] _ind;

  private bool resetAckReceived = false;
  private bool ackReceived = true;
  private bool responseReceived = true;

  private void onFT12Frame(FT12Frame frame) {
    OS_Message[] messagesToEmit = [];
    bool isAck = frame.isAckFrame();
    bool isResetInd = frame.isResetInd();
    bool isDataFrame = frame.isDataFrame();
    if (isAck) {
      if (!resetAckReceived) {
        resetAckReceived = true;
        writeln("frame received: ack for reset request");
      } else {
        ackReceived = true;
      }
    } else if (isResetInd) {
      writeln("frame received: resetInd");
      currentParity = FT12FrameParity.unknown;
      // send acknowledge
      FT12Frame ackFrame;
      ackFrame.type = FT12FrameType.ackFrame;
      ubyte[] ackBuffer = FT12Helper.compose(ackFrame);
      com.write(ackBuffer);
    } else  if (isDataFrame) {
      OS_Message result = OS_Protocol.processIncomingMessage(frame.payload);
      // send reset request
      FT12Frame ackFrame;
      ackFrame.type = FT12FrameType.ackFrame;
      ubyte[] ackBuffer = FT12Helper.compose(ackFrame);
      com.write(ackBuffer);

      if (result.direction == OS_MessageDirection.indication) {
        //writeln("is indication");
        // return message
        _ind.length++;
        _ind[$-1] = result;
      } else if(result.direction == OS_MessageDirection.response) {
        //writeln("is response");
        // if sometimes 0xe5 is not received
        ackReceived = true;
        responseReceived = true;
        // store response in global var
        // to resolve it from request method
        _res = result;
      }
    }
  }

  public ulong processIncomingData() {
    void[1024*4] data = void;
    void[] tmp;
    tmp = com.read(data);
    if(tmp.length > 0)
    {
      ubyte[] chunk = cast(ubyte[]) tmp;

      ft12.parse(chunk);
    }

    return tmp.length;
  }

  public OS_Message processInd() {
    processIncomingData();
    if (_ind.length > 0) {
      auto result = _ind[0];
      if (_ind.length > 1) {
        _ind = _ind[1..$];
      } else {
        _ind = [];
      }
      return result;
    }

    // TODO: return null?
    OS_Message result;
    result.service = OS_Services.unknown;

    return  result;
  }

  private OS_Message commonRequest(ubyte[] message) {
    // reqs are syncronuous, so, no queue is required
    if (resetAckReceived && ackReceived && responseReceived) {
      ackReceived = false;
      responseReceived = false;
      if (currentParity == FT12FrameParity.unknown || currentParity == FT12FrameParity.even) {
        currentParity = FT12FrameParity.odd;
      } else {
        currentParity = FT12FrameParity.even;
      }

      FT12Frame request;
      request.type = FT12FrameType.dataFrame;
      request.parity = currentParity;
      request.payload = message[0..$];
      ubyte[] buffer = ft12.compose(request);
      com.write(buffer);
      while(!responseReceived) {
        processIncomingData();
        Thread.sleep(2.msecs);
      }
      return _res;
    }

    OS_Message result;
    result.service = OS_Services.unknown;
    return result;
  }
  public OS_Message GetDatapointDescriptionReq(ushort start, ushort number = 1) {
    return commonRequest(OS_Protocol.GetDatapointDescriptionReq(start, number));
  }
  public OS_Message GetServerItemReq(ushort start, ushort number = 1) {
    return commonRequest(OS_Protocol.GetServerItemReq(start, number));
  }
  public OS_Message GetDatapointValueReq(ushort start, ushort number = 1) {
    return commonRequest(OS_Protocol.GetDatapointValueReq(start, number));
  }
  public OS_Message SetDatapointValueReq(OS_DatapointValue[] values) {
    // TODO: get rid of start, sort values array by id, then values[0].id is start.
    writeln("baos.SetDatapointValueReq");
    return commonRequest(OS_Protocol.SetDatapointValueReq(values));
  }
  // constructor
  this(string device = "/dev/ttyS1", string params = "19200:8E1") {
    com = new SerialPortNonBlk(device, params);

    // register listener for ft12 incoming frames
    ft12 = new FT12Helper(&onFT12Frame);

    // send reset request
    FT12Frame resetFrame;
    resetFrame.type = FT12FrameType.resetReq;
    ubyte[] resetReqBuffer = ft12.compose(resetFrame);
    com.write(resetReqBuffer);
    // and wait until it is received
    while(!resetAckReceived) {
      processIncomingData();
    }
  }
}
