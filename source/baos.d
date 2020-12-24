module baos;
import std.stdio;
import core.thread;

import std.datetime.stopwatch;

import serialport;

// mi libs
import ft12;
import object_server;
import datapoints;
import errors;

class Baos {
  private SerialPortNonBlk com;

  // helper serves to parse/compose ft12 frames
  private FT12Helper ft12;
  private FT12FrameParity currentParity = FT12FrameParity.unknown;

  // var to store result for last response
  private OS_Message _response;
  // and indications. 
  private OS_Message[] _ind;
  private bool _resetInd;

  private bool _resetAckReceived = false;
  private bool _ackReceived = true;
  private bool _responseReceived = true;

  // timeout
  private int req_timeout;
  private bool _timeout = false;
  private StopWatch sw;

  private void onFT12Frame(FT12Frame frame) {
    OS_Message[] messagesToEmit = [];
    bool isAck = frame.isAckFrame();
    bool isResetInd = frame.isResetInd();
    bool isDataFrame = frame.isDataFrame();
    if (isAck) {
      if (!_resetAckReceived) {
        _resetAckReceived = true;
        writeln("Ack for reset request");
      } else {
        _ackReceived = true;
      }
    } else if (isResetInd) {
      currentParity = FT12FrameParity.unknown;
      // send acknowledge
      FT12Frame ackFrame;
      ackFrame.type = FT12FrameType.ackFrame;
      ubyte[] ackBuffer = FT12Helper.compose(ackFrame);
      com.write(ackBuffer);
      _resetInd = true;
    } else  if (isDataFrame) {
      OS_Message result = OS_Protocol.processIncomingMessage(frame.payload);
      // send reset request
      FT12Frame ackFrame;
      ackFrame.type = FT12FrameType.ackFrame;
      ubyte[] ackBuffer = FT12Helper.compose(ackFrame);
      com.write(ackBuffer);

      if (result.direction == OS_MessageDirection.indication) {
        // return message
        _ind.length++;
        _ind[$-1] = result;
      } else if(result.direction == OS_MessageDirection.response) {
        // if sometimes 0xe5 is not received
        _ackReceived = true;
        _responseReceived = true;
        // store response in global var
        // to resolve it from request method
        _response = result;
      }
    }
  }

  public ulong processIncomingData() {
    void[1024*4] data = void;
    void[] tmp;
    tmp = com.read(data);
    if(tmp.length > 0) {
      ubyte[] chunk = cast(ubyte[]) tmp;

      ft12.parse(chunk);
    }

    return tmp.length;
  }
  public void processResponseTimeout() {
    auto dur = sw.peek();
    _timeout = dur > msecs(req_timeout);
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

    OS_Message result;
    result.service = OS_Services.unknown;

    return  result;
  }
  public bool processResetInd() {
    bool res = _resetInd;
    _resetInd = false;

    return res;
  }

  private OS_Message commonRequest(ubyte[] message) {
    // reqs are syncronuous, so, no queue is required
    _ackReceived = false;
    _responseReceived = false;
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
    sw.reset();
    sw.start();
    // пока не получен ответ, либо индикатор сброса, либо таймаут
    while(!(_responseReceived || _resetInd || _timeout)) {
      try {
        processIncomingData();
        processResponseTimeout();
        if (_resetInd) {
          _response.success = false;
          _response.service = OS_Services.unknown;
          _response.error = Errors.interrupted;

          _responseReceived = true;
          _ackReceived = true;
        }
        if (_timeout) {
          _response.success = false;
          _response.service = OS_Services.unknown;
          _response.error = Errors.timeout;

          _responseReceived = true;
          _ackReceived = true;

          _timeout = false;
          sw.reset();
        }
      } catch(Exception e) {
        writeln(e);
      }
      Thread.sleep(2.msecs);
    }

    return _response;

    /***
      OS_Message result;
      result.success = false;
      result.error = Errors.unknown;
      result.service = OS_Services.unknown;

      return result;
     ***/
  }
  public ubyte[] rawRequest(ubyte[] message) {
    OS_Message res = commonRequest(message);
    return res.raw;
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
    return commonRequest(OS_Protocol.SetDatapointValueReq(values));
  }
  public OS_Message SetServerItemReq(OS_ServerItem[] items) {
    return commonRequest(OS_Protocol.SetServerItemReq(items));
  }

  public bool reset() {
    // send reset request
    FT12Frame resetFrame;
    resetFrame.type = FT12FrameType.resetReq;
    ubyte[] resetReqBuffer = ft12.compose(resetFrame);

    writeln("Sending reset request");
    com.write(resetReqBuffer);

    // init var
    _resetInd = false;
    _resetAckReceived = false;

    // reset timeout watcher
    _timeout = false;
    sw.reset();
    sw.start();

    int attempts = 0;
    int max = 5;
    // and wait until acknowledge is received
    while(!(_resetAckReceived || _resetInd ||
          _timeout || attempts > max)) {
      processIncomingData();
      processResponseTimeout();
      if (_timeout) {
        writeln(".....timeout");
        attempts += 1;
        _timeout = false;
        sw.reset();
        sw.start();
        // repeat
        com.write(resetReqBuffer);
      }
      if (attempts > max) {
        return false;
      }
      Thread.sleep(2.msecs);
    }

    writeln("Switching to BAOS mode.");
    ubyte[] switchFrame = [0xf6, 0x00, 0x08, 0x01, 0x34, 0x10, 0x01, 0xf0];
    commonRequest(switchFrame);

    return true;
  }
  public bool reset(string device, string params) {
    com.reopen(device, SPConfig.parse(params));
    return reset();
  }

  // constructor
  this(string device = "/dev/ttyS1", string params = "19200:8E1", int req_timeout = 300) {
    writeln("hello, baos");
    com = new SerialPortNonBlk(device, params);
    this.req_timeout = req_timeout;
    this.sw = StopWatch(AutoStart.no);
    // register listener for ft12 incoming frames
    ft12 = new FT12Helper(&onFT12Frame);
  }
}
