import core.time;

import std.algorithm : remove;
import std.conv : to;
import std.socket : InternetAddress, Socket, SocketException, SocketSet, TcpSocket;
import std.stdio : writeln, writefln;


enum BUFF_SIZE = 32768;

class SocketServer {
  ushort port;
  ushort max_connections;
  TcpSocket listener;
  SocketSet socketSet;
  Socket[] reads;
  string[] addrs;

  this(ushort port, ushort max_connections = 50) {
    listener = new TcpSocket();
    assert(listener.isAlive);
    listener.blocking(false);
    listener.bind(new InternetAddress(port));
    listener.listen(10);
    // Room for listener.
    this.port = port;
    this.max_connections = max_connections;
    socketSet = new SocketSet(max_connections + 1);
  }

  public void delegate(Socket, string) onOpen;
  public void delegate(Socket, string) onClose;
  public void delegate(Socket, string, ubyte[]) onMessage;

  void broadcast(ubyte[] data) {
    foreach(sock; reads) {
      sock.send(data);
    }
  }

  void stop() {
    foreach(sock; reads) {
      sock.close();
    }
    socketSet.reset();
  }

  void loop(Duration timeout = 1.msecs) {
    socketSet.add(listener);
    foreach (sock; reads) {
      socketSet.add(sock);
    }

    // with timeout, so, won't block
    Socket.select(socketSet, null, null, timeout);

    for (size_t i = 0; i < reads.length; i++) {
      if (socketSet.isSet(reads[i])) {
        ubyte[BUFF_SIZE] buf;
        auto datLength = reads[i].receive(buf[]);

        if (datLength == Socket.ERROR) {
          if (onClose !is null)
            onClose(reads[i], addrs[i]);
        } else if (datLength != 0) {
          if (onMessage !is null)
            onMessage(reads[i], addrs[i], buf[0..datLength]);
          continue;
        } else {
          if (onClose !is null)
            onClose(reads[i], addrs[i]);
        }

        // release socket resources now
        reads[i].close();

        reads = reads.remove(i);
        addrs = addrs.remove(i);
        // i will be incremented by the for, we don't want it to be.
        i--;
      }
    }

    // connection request
    if (socketSet.isSet(listener)) {
      Socket sn = null;
      scope (failure) {
        if (sn) {
          sn.close();
        }
      }
      sn = listener.accept();
      assert(sn.isAlive);
      assert(listener.isAlive);

      if (reads.length < max_connections) {
        reads ~= sn;
        auto addr = sn.remoteAddress().toString();
        addrs ~= addr;
        if (onOpen !is null)
          onOpen(sn, addr);
      } else {
        sn.close();
        assert(!sn.isAlive);
        assert(listener.isAlive);
      }
    }

    socketSet.reset();
  }
}
