#!/usr/bin/env python
import serial
import time
import logging
import sys
import liblo
import threading
import Tkinter
import ttk
import tkFont

SEARCH_TIMEOUT = 1 # listen to each connection for this ammount of time

GUI = "tk"

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

# class MyOSCServer(OSC.OSCServer):
#     def __init__(self, *args, **kws):
#         OSC.OSCServer.__init__(self, *args, **kws)
#         self.timeout = 1
#     def handle_timeout(self):
#         self.timed_out = True
#     def recv(self):
#         self.timed_out = False
#         self.handle_request()
#         return not self.timed_out

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
        self.thread = None
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
        except serial.SerialException:
            logging.debug("SerialException. could not write to serial, skipping")

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
        time.sleep(0.2)
        self.conn.close()
        
    def run(self, async=True):
        if async:
            self.thread = t = threading.Thread(target=self.run, args=(False,))
            t.start()
            return
        self._running = True
        oscserver = self.server
        from time import sleep, time
        logging.info("Listening to OSC on port: %s" % self.oscport)
        last_incomming_serial = time()
        while self._running:
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
                            if now - last_incomming_serial > 5:
                                last_incomming_serial = now
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
            except serial.SerialException:
                # the serial connection broke
                while True:
                    ok = self.connect_serial(skip_detect=True)
                    if ok:
                        last_incomming_serial = time()
                        break
                    else:
                        sleep(1)


class TkGui(object):
    def __init__(self):
        self.win = window = Tkinter.Tk()
        window.title('moirelamp')
        window.resizable(0, 0)
        window.tk.call('ttk::setTheme', "clam")
        
        bg = '#2095F0'
        fg = '#FFFFFF'
        active = '#00FF4b'
        disabled = '#A4DCFF'
        
        def defstyle(stylename, *args, **kws):
            style = ttk.Style()
            style.configure(stylename, *args, **kws)
            return style
        
        btn_style = defstyle('flat.TButton',
                font = tkFont.Font(family='Helvetica', size=72),
                relief = 'flat',
                background = bg,
                foreground = fg
        )
        
        btn_style.map('flat.TButton',
            background=[('pressed', '!disabled', fg), ('active', bg), ('disabled', disabled)],
            foreground=[('pressed', bg), ('active', fg)]
        )

        def click_quit():
            l.close()
            time.sleep(0.5)
            window.quit()

        self.btn_quit = btn_quit = ttk.Button(window, text='QUIT', padding=6, style='flat.TButton', command=click_quit)
        btn_quit.grid(column=0, row=1, columnspan=2, padx=10, pady=10, ipadx=10, ipady=10, sticky="nswe")

    def run(self):
        self.win.lift()
        self.win.call('wm', 'attributes', '.', '-topmost', True)
        self.win.after_idle(self.win.call, 'wm', 'attributes', '.', '-topmost', False)
        self.win.mainloop()

if __name__ == '__main__':
    l = MidiLamp()
    print "Press CTRL-C to exit"
    async = GUI is not None
    l.run(async=async)
    if GUI == 'tk':
        gui = TkGui()
        gui.run()
        

    elif GUI == 'qt':
        print "Not Supported"
        sys.exit(0)



