#!/usr/bin/env python
import OSC
import serial
import time
import logging
import sys
import liblo

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
                while time.time() - t1 < 1.5:
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
    def __init__(self, *args, **kws):
        OSC.OSCServer.__init__(self, *args, **kws)
        self.timeout = 1
    def handle_timeout(self):
        self.timed_out = True
    def recv(self):
        self.timed_out = False
        self.handle_request()
        return not self.timed_out

class MidiLamp(object):
    def __init__(self, oscport=11111):
        self.conn = None
        self.connect_serial()
        self.oscport = oscport
        try:
            # self.server = MyOSCServer(("localhost", oscport))
            self.server = liblo.Server(11111)
        except:
            logging.debug("Could not create OSC server. Is it already open?")
            raise RuntimeError("osc error")
        self._running = False
        self._lastlum = -1
        self.add_handlers_liblo()
        
    def add_handlers_OSC(self):
        set_light = self.set_light
        def SET(path, tags, args, source):
            set_light(args[0])
        def STOP(path, tags, args, source):
            self._running = False
        self.server.addMsgHandler("/set", SET)
        self.server.addMsgHandler("/stop", STOP)

    def add_handlers_liblo(self):
        set_light = self.set_light
        def SET(path, args, types, src):
            brightness = args[0]
            if brightness > 1000:
                logging.debug("Brightness should be 0-1000")
            set_light(brightness)
            # logging.debug("brightness: %d" % brightness)
        def STOP(path, args, types, src):
            self._running = False
        def DEBUG(path, args, types, src):
            logging.debug("Got garbage! path={path}, args={args}, types={types}".format(**locals()))
        self.server.add_method("/set", None, SET)
        self.server.add_method("/stop", None, STOP)
        self.server.add_method(None, None, DEBUG)
        
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
            logging.debug("could not write to serial, reconnecting")
            self.connect_serial(60)

    def connect_serial(self, timeout=10, skip_detect=False):
        if self.conn:
            logging.debug("trying to reconnect to %s. closing serial connection" % self.devname)
            self.conn.close()
        if not skip_detect:
            self.devname = detect_arduino(timeout=timeout)
        if self.devname:
            try:
                self.conn = serial.Serial(self.devname, timeout=0.1)
                logging.debug("device found at port %s. Connected!" % self.devname) 
            except OSError:
                logging.error("could not open device %s" % self.devname)
                return False
        else:
            raise RuntimeError("device not found")
        return True
    
    def close(self):
        self._running = False
        self.conn.close()
        time.sleep(0.1)
        
    def run(self):
        self._running = True
        oscserver = self.server
        from time import sleep, time
        logging.info("Listening to OSC on port: %s" % self.oscport)
        last_incomming_serial = time()
        try:
            while self._running:
                now = time()
                # this will block until it receives a msg or it timesout
                if not oscserver.recv(50): 
                    incomming = self.conn.read(1)
                    if len(incomming):
                        last_incomming_serial = now
                        #self.conn.flushInput()
                    else:
                        if now - last_incomming_serial > 2:
                            for N in range(5):
                                logging.debug("lost connection! Will try to reconnect")
                                ok = self.connect_serial(skip_detect=True)
                                if ok: 
                                    break
                                else:
                                    sleep(0.5)
                            if not ok:
                                self._running = False
                                break
            self.close()
        except KeyboardInterrupt:
            print "exiting..."
            self.close()


if __name__ == '__main__':
    l = MidiLamp()
    print "Press CTRL-C to exit"
    l.run()

