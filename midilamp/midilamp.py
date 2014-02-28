#!/usr/bin/env python
import OSC
import serial
import time
import logging
import sys

SEARCH_TIMEOUT = 1 # listen to each connection for this ammount of time

CHR0 = chr(0)

root = logging.getLogger()

ch = logging.StreamHandler(sys.stdout)
ch.setLevel(logging.DEBUG)
root.addHandler(ch)
root.setLevel(logging.DEBUG)

def _readline(conn, sep=CHR0):
    chrs = []
    timeout = conn.timeout
    t = time.time()
    while time.time() - t < timeout:
        c = conn.read(1)
        if len(c) > 0:
            if c == sep:
                return ''.join(chrs)
            chrs.append(c)
    logging.debug("timed out")
    return None

def detect_arduino(timeout=10):
    from serial.tools import list_ports
    device = None
    t0 = time.time()
    while time.time() - t0 < timeout:   
        comports = list_ports.comports()
        possible_ports = [port for port in comports if "arduino" in port[1].lower()]
        if not possible_ports:
            logging.error("did not found any port that could be an arduino. found these ports: %s" % str(comports))
        for portname, description, _ in possible_ports:
            logging.debug("probing port: %s" % portname)
            try:
                s = serial.Serial(portname, timeout=SEARCH_TIMEOUT)
                t1 = time.time()
                while time.time() - t1 < 3:
                    l = _readline(s)
                    if l and l == "HLMP":
                        device = portname
                        break
                if device:
                    break
            except serial.SerialException:
                logging.debug("could not open %s, skipping" % portname)
            except OSError:
                logging.debug("oserror: could not open %s, skipping" % portname)
        if device:
            break
        time.sleep(1)
    return device

class MyOSCServer(OSC.OSCServer):
    def handle_timeout(self):
        self.timed_out = True
    def recv(self):
        self.timed_out = False
        self.handle_request()
        return not self.timed_out

class MidiLamp(object):
    def __init__(self, oscport=11111, autostart=True):
        self.conn = None
        self.connect_serial()
        self.oscport = oscport
        try:
            self.server = MyOSCServer(("localhost", oscport))
        except:
            print "Could not create OSC server. Is it already open?"
            raise RuntimeError("osc error")
        self.server.timeout = 1
        self._running = False
        self._lastlum = -1
        self.add_handlers()
        if autostart:
            self.run()

    def add_handlers(self):
        set_light = self.set_light
        def SET(path, tags, args, source):
            set_light(args[0])
        def STOP(path, tags, args, source):
            self._running = False
        self.server.addMsgHandler("/set", SET)
        self.server.addMsgHandler("/stop", STOP)
        
    def set_light(self, lum, smooth=False):
        lum = min(999, lum)
        if lum == self._lastlum:
            return
        connwrite = self.conn.write
        try:
            if smooth:
                lum = lum * 0.5 + self._lastlum * 0.5
            connwrite("S")
            connwrite(str(int(lum)))
            connwrite(chr(0))
            self._lastlum = lum
        except serial.SerialTimeoutException:
            print "could not write to serial, reconnecting"
            self.connect_serial(60)

    def connect_serial(self, timeout=10):
        if self.conn:
            self.conn.close()
        self.devname = detect_arduino(timeout=timeout)
        if self.devname:
            self.conn = serial.Serial(self.devname)
            logging.debug("device found at port %s. Connected!" % self.devname) 
        else:
            raise RuntimeError("device not found")
    
    def close(self):
        self._running = False
        self.conn.close()
        time.sleep(0.1)
        self.server.close()

    def run(self):
        self._running = True
        oscserver = self.server
        from time import sleep
        logging.info("Listening to OSC on port: %s" % self.oscport)
        try:
            while self._running:
                if not oscserver.recv(): # this will block until it receives a msg or it timesout
                    # flush any incomming serial info each time we time out
                    self.conn.flushInput()
            self.close()
        except KeyboardInterrupt:
            print "exiting..."
            self.close()


if __name__ == '__main__':
    l = MidiLamp(autostart=False)
    print "Press CTRL-C to exit"
    l.run()

