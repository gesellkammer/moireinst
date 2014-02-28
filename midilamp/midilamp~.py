import OSC
import serial
import time
import logging

CHR0 = chr(0)

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

def detect_arduino():
	from serial.tools import list_ports
	device = None
	for portname, description, _ in list_ports.comports():
		logging.debug("probing port: %s" % portname)
		try:
			s = serial.Serial(portname, timeout=1)
			t = time.time()
			while time.time() - t < 3:
				l = _readline(s)
				if l and l == "HLMP":
					device = portname
					break
			if device:
				break
		except serial.SerialException:
			logging.debug("could not open %s, skipping" % portname)
	return device

class MidiLamp(object):
	def __init__(self, oscport=11111, autostart=True):
		self.oscport = oscport
		self.server = OSC.OSCServer(("localhost", oscport))
		self.devname = detect_arduino()
		if self.devname:
			logging.debug("device found at port %s" % self.devname)
			self.conn = serial.Serial(self.devname)
		else:
			raise RuntimeError("device not found")
		self._running = False
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

	def set_light(self, lum):
		lum = min(999, lum)
		connwrite = self.conn.write
		connwrite("S")
		connwrite(str(lum))
		connwrite(chr(0))

	def close(self):
		self._running = False
		self.conn.close()
		time.sleep(0.1)
		self.server.close()

	def run(self):
		self._running = True
		oscserver = self.server
		handle_request = oscserver.handle_request
		from time import sleep
		logging.info("Listening to port", self.oscport)
		conn = self.conn
		try:
			while self._running:
				handle_request()
				conn.flush()
				sleep(0.050)
			self.close()
		except KeyboardInterrupt:
			print "exiting..."
			self.close()


if __name__	== '__main__':
	l = MidiLamp(autostart=False)
	print "Press CTRL-C to exit"
	print "Listening to OSC on port %d" % l.oscport
	l.run()

