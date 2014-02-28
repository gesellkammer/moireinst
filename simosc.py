#!/usr/bin/env python
import rtmidi2
from rtmidi2 import splitchannel, CC
import liblo
import atexit
import time

ccmap = [None] * 128
ccmap[81] = ('/strain', lambda ch, cc, value: value/127.0)

CSOUND_ADDR = liblo.Address('localhost', 30018)

s = liblo.Server()

def callback(msg, t):
	msgtype, ch = splitchannel(msg[0])
	if msgtype == CC:
		mapping = ccmap[msg[1]]
		if mapping:
			path, func = mapping
			value = func(ch, msg[1], msg[2])
			s.send(CSOUND_ADDR, path, value)

def exitfunc():
	s.close()

m = rtmidi2.MidiIn()
m.open_port("BCF*")
m.callback = callback

atexit.register(exitfunc)

try:
	while True:
		time.sleep(36000)
except KeyboardInterrupt:
	pass



