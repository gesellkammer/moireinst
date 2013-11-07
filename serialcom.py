#!/usr/bin/env python
import liblo
import serial
import glob
import sys
import select
import os

CSOUNDPORT = 30018

def detect_arduino():
        if sys.platform == 'darwin':
		arduino = glob.glob("/dev/tty*usb*")
		if arduino:
			return arduino[0]
		return None
	elif sys.platform == 'linux2':
		arduino = glob.glob("/dev/arduino*")
		if arduino:
			return arduino[0]
		arduino = glob.glob("/dev/*ACM*")
		if arduino:
			return arduino[0]
		return None
	else:
		return None

arduino = detect_arduino()
if not arduino:
	print "USB device not found. Is it plugged?"
	sys.exit(0)

s = serial.Serial(arduino, baudrate=115200)
osc = liblo.Server()
addr = liblo.Address('127.0.0.1', CSOUNDPORT)

def listen(s):
	counter = 0
	from time import time, sleep
	lasttime = time()
	_osc, _addr = osc, addr
	_ord = ord
	samplerate = -1
	s_read = s.read
	send = _osc.send
	fd = s.fd
	fdl = [fd]
	_select = select.select
	os_read = os.read
	#k = select.kqueue()
	#ev = [select.kevent(s.fd, select.KQ_FILTER_READ)]
	#k.control(ev, 1, None)
	while True:
		ready, _, _ = _select(fdl, (), (), 1/1000.)
		#k.control(None, 4, 1/1000.)
		if not ready:
			continue
		ch = _ord(os_read(fd, 1))

		if ch < 128:
			continue
		if ch < 140:
			#evs = k.control(ev, 4, None)
			V = map(ord, os_read(fd, 4))
			L = V[0] * 128 + V[1]
			R = V[2]*128 + V[3]
			counter += 1
			send(_addr, '/data', L, R)
		elif ch == 140:
			V = map(_ord, os_read(fd, 4))
			fader1 = V[0] * 128 + V[1]
			pedal1 = V[2] * 128 + V[3]
			now = time()
			if now - lasttime > 1:
				samplerate = counter / (now - lasttime)
				counter = 0
				lasttime = now
			send(_addr, '/ctrl', fader1, pedal1, samplerate)

if __name__ == '__main__':
        print "listening to arduino:     ", arduino
        print "sending data to OSC port: ", CSOUNDPORT
	listen(s)

