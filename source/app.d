module main;

import std.stdio;
import core.thread;


import serialport;

// mi libs
import ft12;
import object_server;

// global: first reset
bool resetAckReceived = false;

void main()
{
  //ObjectServerProtocol.processIncomingMessage([0xf0, 0x05, 0x00]);
  writeln("trying to open sp");
  // serialport
  auto com = new SerialPortNonBlk("/dev/ttyS1", "19200:8E1");

  void onFrame(FT12Frame frame) {
    bool isAck = frame.isAckFrame();
    bool isResetInd = frame.isResetInd();
    bool isDataFrame = frame.isDataFrame();
    if (isAck) {
      if (!resetAckReceived) {
        resetAckReceived = true;
        writeln("frame received: ack for reset request");
      }
    } else if (isResetInd) {
      writeln("frame received: resetInd");
      // send reset request
      FT12Frame ackFrame;
      ackFrame.type = FT12FrameType.ackFrame;
      ubyte[] ackBuffer = FT12Helper.compose(ackFrame);
      com.write(ackBuffer);
    } else  if (isDataFrame) {
      writeln("frame received: data ", frame.payload);
      ObjectServerProtocol.processIncomingMessage(frame.payload);
      // send reset request
      FT12Frame ackFrame;
      ackFrame.type = FT12FrameType.ackFrame;
      ubyte[] ackBuffer = FT12Helper.compose(ackFrame);
      com.write(ackBuffer);
    }
  }
  FT12Helper ft12 = new FT12Helper(&onFrame);

  // send reset request
  FT12Frame resetFrame;
  resetFrame.type = FT12FrameType.resetReq;
  ubyte[] resetReqBuffer = ft12.compose(resetFrame);
  com.write(resetReqBuffer);


  bool flag1 = false;
  // receive data
  void[1024*4] data = void;
  while (true)
  {
    void[] tmp;
    tmp = com.read(data);
    Thread.sleep(1.msecs);
    if(tmp.length > 0)
    {
      ubyte[] chunk = cast(ubyte[]) tmp;
      writeln(chunk);

      ft12.parse(chunk);
      // TODO: readData as a separate method, without while loop

    } else {
      // TODO: do something else
      if (resetAckReceived && !flag1) {
        writeln("get server item req");

        FT12Frame getDescrFrame;
        getDescrFrame.type = FT12FrameType.dataFrame;
        getDescrFrame.parity = FT12FrameParity.odd;
        getDescrFrame.payload = ObjectServerProtocol.GetDatapointDescriptionReq(1, 42);
        
        ubyte[] getDescrBuffer = ft12.compose(getDescrFrame);
        writeln("sending: ", getDescrBuffer);
        com.write(getDescrBuffer);
        flag1 = true;
      }
    }
  }
}
