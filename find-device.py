#!/usr/bin/env python
import sys
import os
import serial
import glob

if sys.platform == "darwin":
    arduino = glob.glob("/dev/tty*usb*")
    if arduino:
        print arduino[0]
elif sys.platform == 'linux':
    arduino = glob.glob("/dev/*arduino*")
    if arduino:
        print arduino[0]
    else:
        arduino = glob.glob("/dev/tty*ACM*")
        if arduino:
            print arduino[0]
